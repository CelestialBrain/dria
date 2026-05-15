//
//  ExcelAgentService.swift
//  dria
//
//  Iterative Excel agent: lets the AI call read_cell / read_range / write_cell
//  / list_sheets / get_selection on demand instead of receiving one pre-packed
//  TSV snapshot. Closer to a true Excel MCP than v1.7.12's one-shot context.
//
//  Talks to the Gemini REST API directly (Google AI key path). Vertex AI uses
//  the same payload shape — left as a follow-up. Other providers fall back to
//  one-shot in AppState.handleAskExcelCell.
//
//  Each ⌘⌥E invocation that goes through here is logged to
//  ~/Library/Logs/dria/excel-agent-<ts>.log with every tool call + result.
//

import Foundation

final class ExcelAgentService: @unchecked Sendable {
    enum AgentError: LocalizedError {
        case noAPIKey
        case http(Int, String)
        case invalidResponse(String)
        case maxTurnsExceeded

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No Google AI key set."
            case .http(let code, let body): return "Gemini HTTP \(code): \(body.prefix(200))"
            case .invalidResponse(let s): return "Gemini response invalid: \(s)"
            case .maxTurnsExceeded: return "Agent exceeded 8 turns without producing an answer."
            }
        }
    }

    /// Cap on tool-use round-trips. Each turn = one model call + zero or more
    /// tool executions. 8 is empirically generous for "answer one cell question".
    private let maxTurns = 8

    private let apiKey: String
    private let modelName: String
    /// Optional sheet name to scope tool calls to. nil means "active sheet".
    private let sheetName: String?
    private let logURL: URL?

    init(apiKey: String, modelName: String, sheetName: String?) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.sheetName = sheetName
        let dir = NSHomeDirectory() + "/Library/Logs/dria"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        self.logURL = URL(fileURLWithPath: "\(dir)/excel-agent-\(CrashReporter.timestamp()).log")
    }

    /// Run the loop. Returns the final text answer the AI converged on.
    /// Calls `onTrace(stage)` for each turn so the UI can show progress.
    func run(
        systemPrompt: String,
        userQuestion: String,
        seedContext: String,
        onTrace: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // Conversation history mirrors Gemini's "contents" array. We rebuild
        // the whole array each turn since /generateContent is stateless.
        var contents: [[String: Any]] = []
        // Combine seed context (the snapshot we always send so the AI has
        // immediate situational awareness) + the question.
        let seeded = seedContext.isEmpty
            ? userQuestion
            : "Initial sheet context (always-available snapshot):\n\(seedContext)\n\n---\n\n\(userQuestion)"
        contents.append(["role": "user", "parts": [["text": seeded]]])

        appendLog("=== ExcelAgent run ===\nModel: \(modelName)\nSystem prompt (first 500): \(systemPrompt.prefix(500))\nUser question: \(userQuestion)\nSeed context: \(seedContext.count) chars\n")

        for turn in 1...maxTurns {
            onTrace?("turn \(turn)")
            appendLog("\n--- turn \(turn) ---\n")

            let response = try await call(systemPrompt: systemPrompt, contents: contents)

            // Inspect the first candidate's parts. A part is either text or functionCall.
            guard let candidate = (response["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                appendLog("Unexpected response shape: \(response)\n")
                throw AgentError.invalidResponse("missing candidates/content/parts")
            }

            // Separate function calls from text.
            var textOut = ""
            var toolCalls: [(name: String, args: [String: Any])] = []
            for part in parts {
                if let t = part["text"] as? String, !t.isEmpty {
                    textOut += t
                }
                if let fc = part["functionCall"] as? [String: Any],
                   let name = fc["name"] as? String {
                    let args = (fc["args"] as? [String: Any]) ?? [:]
                    toolCalls.append((name: name, args: args))
                }
            }

            if !toolCalls.isEmpty {
                // Echo the model's tool-call message back into history exactly.
                contents.append(["role": "model", "parts": parts])
                appendLog("Model requested \(toolCalls.count) tool call(s):\n")
                // Execute each tool and append a functionResponse part.
                var responseParts: [[String: Any]] = []
                for tc in toolCalls {
                    onTrace?("\(tc.name)")
                    let result = await dispatch(tool: tc.name, args: tc.args)
                    appendLog("  → \(tc.name)(\(tc.args)) = \(result.prefix(500))\n")
                    responseParts.append([
                        "functionResponse": [
                            "name": tc.name,
                            "response": ["result": result]
                        ]
                    ])
                }
                contents.append(["role": "user", "parts": responseParts])
                continue
            }

            if !textOut.isEmpty {
                appendLog("Final text answer (\(textOut.count) chars): \(textOut.prefix(500))\n")
                return textOut.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // No text, no tool calls — bail.
            appendLog("Empty turn (no text, no tool calls). Bailing.\n")
            throw AgentError.invalidResponse("empty turn")
        }

        appendLog("Max turns (\(maxTurns)) exceeded.\n")
        throw AgentError.maxTurnsExceeded
    }

    // MARK: - Tool dispatch

    private func dispatch(tool: String, args: [String: Any]) async -> String {
        switch tool {
        case "get_selection":
            guard let ctx = ExcelScript.workbookContext(maxRows: 1, maxCols: 1) else { return "(no Excel)" }
            return "address=\(ctx.selectionAddress); value=\(ctx.selectionValue.isEmpty ? "(empty)" : ctx.selectionValue)"

        case "list_sheets":
            return ExcelScript.listSheets()?.joined(separator: ", ") ?? "(failed)"

        case "read_cell":
            let address = (args["address"] as? String) ?? ""
            guard !address.isEmpty else { return "error: missing 'address'" }
            let sheet = (args["sheet"] as? String) ?? sheetName
            return ExcelScript.readCell(address: address, sheet: sheet) ?? "error: read failed"

        case "read_range":
            let range = (args["range"] as? String) ?? ""
            guard !range.isEmpty else { return "error: missing 'range'" }
            let sheet = (args["sheet"] as? String) ?? sheetName
            return ExcelScript.readRange(range: range, sheet: sheet) ?? "error: read failed"

        case "write_cell":
            let address = (args["address"] as? String) ?? ""
            let value = (args["value"] as? String) ?? ""
            guard !address.isEmpty else { return "error: missing 'address'" }
            let sheet = (args["sheet"] as? String) ?? sheetName
            let ok = ExcelScript.writeCell(address: address, value: value, sheet: sheet)
            return ok ? "ok" : "error: write failed (TCC denied?)"

        case "compute_formula":
            let formula = (args["formula"] as? String) ?? ""
            guard !formula.isEmpty else { return "error: missing 'formula'" }
            let sheet = (args["sheet"] as? String) ?? sheetName
            return ExcelScript.computeFormula(formula, sheet: sheet) ?? "error: compute failed"

        default:
            return "error: unknown tool '\(tool)'"
        }
    }

    // MARK: - Gemini REST call

    private static let toolDeclarations: [[String: Any]] = [
        [
            "name": "get_selection",
            "description": "Return the currently selected cell's A1 address and value.",
            "parameters": ["type": "object", "properties": [:]]
        ],
        [
            "name": "list_sheets",
            "description": "Return the names of all worksheets in the active workbook.",
            "parameters": ["type": "object", "properties": [:]]
        ],
        [
            "name": "read_cell",
            "description": "Read a single cell by A1 address (e.g. 'H16'). Returns the cell's value as text, or '(empty)'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "address": ["type": "string", "description": "A1 address like 'H16'."],
                    "sheet": ["type": "string", "description": "Optional sheet name. Defaults to the active sheet."]
                ],
                "required": ["address"]
            ]
        ],
        [
            "name": "read_range",
            "description": "Read a range by A1 reference (e.g. 'A1:Z50'). Returns TSV with column-letter and row-number headers so the model can resolve any cell address.",
            "parameters": [
                "type": "object",
                "properties": [
                    "range": ["type": "string", "description": "A1 range like 'A1:F20'."],
                    "sheet": ["type": "string", "description": "Optional sheet name."]
                ],
                "required": ["range"]
            ]
        ],
        [
            "name": "write_cell",
            "description": "Write a value (or formula starting with '=') to a specific A1 address. Use this ONLY for the final answer that resolves the user's question. Prefer formulas over computed values when the answer must remain dynamic.",
            "parameters": [
                "type": "object",
                "properties": [
                    "address": ["type": "string"],
                    "value": ["type": "string"],
                    "sheet": ["type": "string"]
                ],
                "required": ["address", "value"]
            ]
        ],
        [
            "name": "compute_formula",
            "description": "Evaluate an Excel formula AS IF you typed it into a cell, and return its computed result. Use this for ALL arithmetic — sums, averages, counts, max/min, lookups, comparisons. NEVER compute math in your head; always go through this tool. The formula must start with '='. Examples: '=MAX(C13:J26)', '=AVERAGE(C13:C26)', '=INDEX(C12:J12,MATCH(MAX(K3:K10),K3:K10,0))', '=COUNTIF(C14:J14,\">0\")'.",
            "parameters": [
                "type": "object",
                "properties": [
                    "formula": ["type": "string", "description": "Excel formula starting with '='."],
                    "sheet": ["type": "string", "description": "Optional sheet name."]
                ],
                "required": ["formula"]
            ]
        ]
    ]

    private func call(systemPrompt: String, contents: [[String: Any]]) async throws -> [String: Any] {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw AgentError.invalidResponse("bad url") }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
            "tools": [["functionDeclarations": Self.toolDeclarations]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 1024
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        req.timeoutInterval = 90

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AgentError.invalidResponse("no HTTPURLResponse") }
        guard 200..<300 ~= http.statusCode else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            appendLog("HTTP \(http.statusCode) body: \(bodyText.prefix(2000))\n")
            throw AgentError.http(http.statusCode, bodyText)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentError.invalidResponse("non-JSON body")
        }
        return json
    }

    // MARK: - Logging

    private func appendLog(_ s: String) {
        guard let logURL else { return }
        if let data = s.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}
