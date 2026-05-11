//
//  LLMBridgeServer.swift
//  dria
//
//  Tiny HTTP server bound to 127.0.0.1 so external apps (Excel add-in,
//  Raycast extensions, browser bookmarklets) can call dria's AI providers
//  through one local endpoint. Disabled by default; enabled via Settings.
//
//  Auth: Bearer token persisted at
//  ~/Library/Application Support/dria/bridge-token (generated on first enable).
//
//  Endpoints (all under /v1):
//    GET  /ping           — health
//    GET  /modes          — list available study modes
//    POST /ask            — { prompt, mode?, useKnowledgeBase? } → { answer }
//    POST /classify       — { text, categories: [String] } → { label }
//    POST /extract        — { text, instruction } → { value }
//

import Foundation
import Network

@MainActor
final class LLMBridgeServer {
    static let defaultPort: UInt16 = 7842
    private let port: NWEndpoint.Port

    private var listener: NWListener?
    private var connections: Set<ObjectIdentifier> = []
    private var connectionStore: [ObjectIdentifier: NWConnection] = [:]

    /// Bearer token loaded from disk (or generated on first start).
    private(set) var token: String = ""

    /// Callback into AppState — set after init, called per /ask request.
    var onAsk: ((_ prompt: String, _ modeName: String?, _ useKB: Bool) async -> Result<String, Error>)?
    var onListModes: (() -> [String])?

    var isRunning: Bool { listener != nil }

    init(port: UInt16 = defaultPort) {
        self.port = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(rawValue: 7842)!
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        token = BridgeTokenStore.loadOrCreate()

        // Defense in depth — three layers force loopback-only binding:
        //  1. acceptLocalOnly: NWParameters constraint to the local host
        //  2. requiredInterfaceType = .loopback: bind only to lo0, never to a
        //     physical interface, VPN utun*, or Docker bridge
        //  3. accept-handler check: reject any remote endpoint that isn't
        //     127.0.0.1 / ::1 / fe80::1
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true
        params.requiredInterfaceType = .loopback
        params.includePeerToPeer = false

        do {
            let l = try NWListener(using: params, on: port)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.handleConnection(conn)
                }
            }
            l.stateUpdateHandler = { state in
                if case .failed(let err) = state {
                    NSLog("[dria-bridge] listener failed: \(err)")
                }
            }
            l.start(queue: .main)
            listener = l
            NSLog("[dria-bridge] listening on 127.0.0.1:\(port.rawValue) (loopback only)")
        } catch {
            NSLog("[dria-bridge] start failed: \(error)")
        }
    }

    /// Whitelist of remote addresses we'll service. Rejects everything else
    /// even if the OS happened to accept the connection.
    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let ip):
                return ip == .loopback || ip.rawValue.first == 127
            case .ipv6(let ip):
                return ip == .loopback // ::1
            case .name(let n, _):
                let lower = n.lowercased()
                return lower == "localhost" || lower == "localhost." || lower == "ip6-localhost"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    func stop() {
        for (_, c) in connectionStore { c.cancel() }
        connectionStore.removeAll()
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - Token

    func currentToken() -> String {
        if !token.isEmpty { return token }
        return BridgeTokenStore.loadOrCreate()
    }

    /// Generate a new token, invalidating any client that cached the old one.
    /// UI should re-display the token after this completes.
    func rotateToken() {
        token = BridgeTokenStore.rotate()
    }

    // MARK: - Connection handling

    private func handleConnection(_ conn: NWConnection) {
        // Belt-and-braces remote-endpoint check. Should be unreachable given
        // `acceptLocalOnly = true` + `requiredInterfaceType = .loopback`, but
        // an OS bug or future API change shouldn't expose the bridge LAN-wide.
        if !isLoopback(conn.endpoint) {
            NSLog("[dria-bridge] rejecting non-loopback connection from \(conn.endpoint)")
            conn.cancel()
            return
        }

        let key = ObjectIdentifier(conn)
        connectionStore[key] = conn
        connections.insert(key)

        conn.start(queue: .main)
        receiveRequest(on: conn)
    }

    private func closeConnection(_ conn: NWConnection) {
        conn.cancel()
        let key = ObjectIdentifier(conn)
        connectionStore.removeValue(forKey: key)
        connections.remove(key)
    }

    private func receiveRequest(on conn: NWConnection, accumulated: Data = Data()) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                var buf = accumulated
                if let data { buf.append(data) }

                // Check if we have full headers + body
                if let req = HTTPRequest.parse(buf) {
                    await self.route(req, on: conn)
                } else if isComplete || error != nil {
                    self.closeConnection(conn)
                } else {
                    // Keep reading
                    self.receiveRequest(on: conn, accumulated: buf)
                }
            }
        }
    }

    // MARK: - Routing

    private func route(_ req: HTTPRequest, on conn: NWConnection) async {
        // CORS preflight for Office origins
        if req.method == "OPTIONS" {
            sendCORS(on: conn, request: req)
            return
        }

        // Token check (except /ping which is unauthenticated)
        if req.path != "/v1/ping" {
            let auth = req.headers["authorization"] ?? ""
            let expected = "Bearer \(token)"
            guard auth == expected else {
                send(status: 401, json: ["error": "unauthorized"], on: conn, request: req)
                return
            }
        }

        switch (req.method, req.path) {
        case ("GET", "/v1/ping"):
            send(status: 200, json: ["ok": true, "version": "1"], on: conn, request: req)

        case ("GET", "/v1/modes"):
            let modes = onListModes?() ?? []
            send(status: 200, json: ["modes": modes], on: conn, request: req)

        case ("POST", "/v1/ask"):
            await handleAsk(req: req, on: conn)

        case ("POST", "/v1/classify"):
            await handleClassify(req: req, on: conn)

        case ("POST", "/v1/extract"):
            await handleExtract(req: req, on: conn)

        default:
            send(status: 404, json: ["error": "not found"], on: conn, request: req)
        }
    }

    // MARK: - Handlers

    private func handleAsk(req: HTTPRequest, on conn: NWConnection) async {
        guard let body = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let prompt = body["prompt"] as? String, !prompt.isEmpty else {
            send(status: 400, json: ["error": "missing 'prompt'"], on: conn, request: req)
            return
        }
        let modeName = body["mode"] as? String
        let useKB = (body["useKnowledgeBase"] as? Bool) ?? true

        guard let handler = onAsk else {
            send(status: 503, json: ["error": "bridge not wired"], on: conn, request: req)
            return
        }
        switch await handler(prompt, modeName, useKB) {
        case .success(let answer):
            send(status: 200, json: ["answer": answer], on: conn, request: req)
        case .failure(let err):
            send(status: 500, json: ["error": err.localizedDescription], on: conn, request: req)
        }
    }

    private func handleClassify(req: HTTPRequest, on conn: NWConnection) async {
        guard let body = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let text = body["text"] as? String,
              let categories = body["categories"] as? [String], !categories.isEmpty else {
            send(status: 400, json: ["error": "missing 'text' or 'categories'"], on: conn, request: req)
            return
        }
        let prompt = """
        Classify the following text into exactly ONE of these categories: \(categories.joined(separator: ", ")).
        Return ONLY the category name, nothing else.

        Text: \(text)
        """
        guard let handler = onAsk else {
            send(status: 503, json: ["error": "bridge not wired"], on: conn, request: req)
            return
        }
        switch await handler(prompt, nil, false) {
        case .success(let answer):
            let label = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            send(status: 200, json: ["label": label], on: conn, request: req)
        case .failure(let err):
            send(status: 500, json: ["error": err.localizedDescription], on: conn, request: req)
        }
    }

    private func handleExtract(req: HTTPRequest, on conn: NWConnection) async {
        guard let body = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let text = body["text"] as? String,
              let instruction = body["instruction"] as? String else {
            send(status: 400, json: ["error": "missing 'text' or 'instruction'"], on: conn, request: req)
            return
        }
        let prompt = """
        From the text below, extract: \(instruction).
        Return ONLY the extracted value, nothing else. If not found, return an empty string.

        Text: \(text)
        """
        guard let handler = onAsk else {
            send(status: 503, json: ["error": "bridge not wired"], on: conn, request: req)
            return
        }
        switch await handler(prompt, nil, false) {
        case .success(let answer):
            send(status: 200, json: ["value": answer.trimmingCharacters(in: .whitespacesAndNewlines)], on: conn, request: req)
        case .failure(let err):
            send(status: 500, json: ["error": err.localizedDescription], on: conn, request: req)
        }
    }

    // MARK: - Response helpers

    /// Origins we'll service. Office desktop add-ins send no Origin header —
    /// requests with absent Origin are allowed (handled below). Browser-style
    /// requests are echoed back only when matching, never wildcarded.
    private static let originAllowlist: [NSRegularExpression] = {
        let patterns = [
            #"^https://localhost(?::\d+)?$"#,            // local dev (npx http-server -S)
            #"^https://127\.0\.0\.1(?::\d+)?$"#,
            #"^https://[A-Za-z0-9-]+\.officeapps\.live\.com$"#, // Excel for Web runtime
            #"^https://[A-Za-z0-9-]+\.office\.com$"#,            // Excel taskpane host
            #"^https://outlook\.office\.com$"#,
            #"^https://outlook\.office365\.com$"#,
            #"^https://[A-Za-z0-9-]+\.officeusercontent\.com$"#, // sandboxed add-in content
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    private func allowedOrigin(_ origin: String?) -> String? {
        guard let origin, !origin.isEmpty else {
            // Absent Origin means Office desktop add-in or same-origin curl — no CORS needed.
            return nil
        }
        let range = NSRange(origin.startIndex..<origin.endIndex, in: origin)
        for rx in Self.originAllowlist where rx.firstMatch(in: origin, options: [], range: range) != nil {
            return origin
        }
        return nil
    }

    private func corsHeaders(for request: HTTPRequest?) -> String {
        let origin = request?.headers["origin"]
        guard let echo = allowedOrigin(origin) else {
            // No CORS headers — browser will refuse the response.
            // Always set Vary so any caching proxy doesn't poison this.
            return "Vary: Origin\r\n"
        }
        return """
        Access-Control-Allow-Origin: \(echo)\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Authorization, Content-Type\r
        Access-Control-Max-Age: 86400\r
        Vary: Origin\r

        """
    }

    private func sendCORS(on conn: NWConnection, request: HTTPRequest? = nil) {
        let resp = "HTTP/1.1 204 No Content\r\n\(corsHeaders(for: request))Content-Length: 0\r\n\r\n"
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            self?.closeConnection(conn)
        })
    }

    private func send(status: Int, json: [String: Any], on conn: NWConnection, request: HTTPRequest? = nil) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let head = """
        HTTP/1.1 \(status) \(statusText(status))\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.count)\r
        \(corsHeaders(for: request))Connection: close\r
        \r

        """
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeConnection(conn)
            }
        })
    }

    private func statusText(_ s: Int) -> String {
        switch s {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

// MARK: - Minimal HTTP request parser

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        // Split headers/body at \r\n\r\n
        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = data.range(of: sep) else { return nil }
        let headerData = data.subdata(in: 0..<range.lowerBound)
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = range.upperBound
        let availableBody = data.subdata(in: bodyStart..<data.count)

        // Honor Content-Length to avoid premature parsing
        if let lenStr = headers["content-length"], let len = Int(lenStr) {
            guard availableBody.count >= len else { return nil }
            return HTTPRequest(method: method, path: path, headers: headers, body: availableBody.prefix(len))
        }
        return HTTPRequest(method: method, path: path, headers: headers, body: availableBody)
    }
}

private extension Data {
    func prefix(_ n: Int) -> Data {
        subdata(in: 0..<Swift.min(n, count))
    }
}
