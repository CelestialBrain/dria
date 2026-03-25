//
//  GeminiService.swift
//  dria
//
//  Vertex AI REST API + Google AI SDK dual provider
//

import AppKit
import Foundation
import GoogleGenerativeAI

// MARK: - Token Cache Actor (Bug 2 fix)

private actor TokenCache {
    private var cachedToken: String?
    private var tokenExpiry: Date?

    func getToken(generator: @Sendable () async throws -> String) async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        let token = try await generator()
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(50 * 60) // Cache for 50 min (JWT valid for 60)
        return token
    }

    func invalidate() {
        cachedToken = nil
        tokenExpiry = nil
    }
}

// MARK: - Vertex AI REST Provider

final class VertexAIProvider: Sendable {
    let project: String
    let location: String
    let modelName: String
    private let accessTokenProvider: @Sendable () async throws -> String
    private let tokenCache = TokenCache()

    init(serviceAccountKeyPath: String, project: String?, location: String = "global", modelName: String) throws {
        self.modelName = modelName
        self.location = location

        // Parse service account key (Bug 1 fix: safe unwraps)
        let keyData = try Data(contentsOf: URL(fileURLWithPath: serviceAccountKeyPath))
        guard let keyJSON = try JSONSerialization.jsonObject(with: keyData) as? [String: Any] else {
            throw GeminiError.apiError("Service account key file is not a valid JSON object")
        }
        guard let clientEmail = keyJSON["client_email"] as? String else {
            throw GeminiError.apiError("Service account key missing 'client_email' field")
        }
        guard let privateKeyPEM = keyJSON["private_key"] as? String else {
            throw GeminiError.apiError("Service account key missing 'private_key' field")
        }

        // Bug 4 fix: no hardcoded sisia-2 fallback — require project
        guard let resolvedProject = project ?? (keyJSON["project_id"] as? String), !resolvedProject.isEmpty else {
            throw GeminiError.apiError("No GCP project specified and service account key has no 'project_id'. Set your Vertex AI project in Settings.")
        }
        self.project = resolvedProject

        // Store for token generation
        self.accessTokenProvider = {
            try await VertexAIProvider.getAccessToken(clientEmail: clientEmail, privateKeyPEM: privateKeyPEM)
        }
    }

    private var endpoint: String {
        let base = location == "global"
            ? "https://aiplatform.googleapis.com"
            : "https://\(location)-aiplatform.googleapis.com"
        return "\(base)/v1beta1/projects/\(project)/locations/\(location)/publishers/google/models/\(modelName):streamGenerateContent"
    }

    func streamGenerate(systemPrompt: String, userContent: [[String: Any]]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Bug 5 fix: retry logic (max 2 retries, 1s delay, no retry on auth/quota)
                var lastError: Error?
                let maxAttempts = 3

                for attempt in 1...maxAttempts {
                    do {
                        // Bug 2 fix: use cached token
                        let token = try await tokenCache.getToken(generator: accessTokenProvider)

                        guard let url = URL(string: endpoint) else {
                            continuation.finish(throwing: GeminiError.apiError("Invalid endpoint URL"))
                            return
                        }

                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                        let body: [String: Any] = [
                            "contents": userContent,
                            "systemInstruction": [
                                "parts": [["text": systemPrompt]]
                            ],
                            "generationConfig": [
                                "temperature": 0.7,
                                "topP": 0.95,
                                "maxOutputTokens": 4096
                            ]
                        ]
                        request.httpBody = try JSONSerialization.data(withJSONObject: body)

                        let (bytes, response) = try await URLSession.shared.bytes(for: request)

                        // Bug 1 fix: safe cast for HTTPURLResponse
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.finish(throwing: GeminiError.apiError("Invalid HTTP response"))
                            return
                        }

                        // Bug 5: don't retry on auth or quota errors
                        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                            // Invalidate cached token on auth errors so next request gets fresh token
                            await tokenCache.invalidate()
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }
                            continuation.finish(throwing: GeminiError.apiError("Vertex AI \(httpResponse.statusCode): \(errorBody.prefix(200))"))
                            return
                        }

                        if httpResponse.statusCode == 429 {
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }
                            continuation.finish(throwing: GeminiError.apiError("Vertex AI rate limited (429): \(errorBody.prefix(200))"))
                            return
                        }

                        guard httpResponse.statusCode == 200 else {
                            var errorBody = ""
                            for try await line in bytes.lines { errorBody += line }
                            let err = GeminiError.apiError("Vertex AI \(httpResponse.statusCode): \(errorBody.prefix(200))")
                            // Retry on 5xx server errors
                            if httpResponse.statusCode >= 500 && attempt < maxAttempts {
                                lastError = err
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            continuation.finish(throwing: err)
                            return
                        }

                        // Parse streaming JSON array response
                        // Vertex AI returns a JSON array: [{...}, {...}, ...]
                        // We accumulate the entire response and parse chunks
                        var buffer = ""
                        for try await line in bytes.lines {
                            buffer += line
                        }

                        // Try parsing as JSON array
                        let cleanBuffer = buffer.trimmingCharacters(in: CharacterSet.whitespaces)
                        if let data = cleanBuffer.data(using: .utf8) {
                            // Could be a JSON array or single object
                            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                                for json in array {
                                    if let candidates = json["candidates"] as? [[String: Any]],
                                       let content = candidates.first?["content"] as? [String: Any],
                                       let parts = content["parts"] as? [[String: Any]],
                                       let text = parts.first?["text"] as? String {
                                        continuation.yield(text)
                                    }
                                }
                            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                // Single object response
                                if let candidates = json["candidates"] as? [[String: Any]],
                                   let content = candidates.first?["content"] as? [String: Any],
                                   let parts = content["parts"] as? [[String: Any]],
                                   let text = parts.first?["text"] as? String {
                                    continuation.yield(text)
                                } else if let error = json["error"] as? [String: Any],
                                          let message = error["message"] as? String {
                                    continuation.finish(throwing: GeminiError.apiError("Vertex AI: \(message)"))
                                    return
                                } else {
                                    continuation.finish(throwing: GeminiError.apiError("Vertex AI: unexpected response: \(String(cleanBuffer.prefix(300)))"))
                                    return
                                }
                            } else {
                                continuation.finish(throwing: GeminiError.apiError("Vertex AI: could not parse response: \(String(cleanBuffer.prefix(300)))"))
                                return
                            }
                        }
                        continuation.finish()
                        return // Success — exit retry loop

                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch let error as GeminiError {
                        // GeminiError means we already handled it (auth, quota, parse) — don't retry
                        continuation.finish(throwing: error)
                        return
                    } catch {
                        // Network / transient errors — retry
                        lastError = error
                        if attempt < maxAttempts {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            continue
                        }
                        continuation.finish(throwing: error)
                        return
                    }
                }

                // Should not reach here, but just in case
                if let err = lastError {
                    continuation.finish(throwing: err)
                } else {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - JWT / OAuth Token

    private static func getAccessToken(clientEmail: String, privateKeyPEM: String) async throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": clientEmail,
            "scope": "https://www.googleapis.com/auth/cloud-platform",
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600
        ]

        let headerB64 = try base64url(JSONSerialization.data(withJSONObject: header))
        let claimsB64 = try base64url(JSONSerialization.data(withJSONObject: claims))
        let signingInput = "\(headerB64).\(claimsB64)"

        // Sign with RSA private key
        guard let signingData = signingInput.data(using: .utf8) else {
            throw GeminiError.apiError("Failed to encode JWT signing input")
        }
        let signature = try signRS256(data: signingData, privateKeyPEM: privateKeyPEM)
        let signatureB64 = base64url(signature)
        let jwt = "\(signingInput).\(signatureB64)"

        // Exchange JWT for access token
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GeminiError.apiError("Invalid OAuth token URL")
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        // Bug 1 fix: safe cast for token JSON
        guard let tokenJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.apiError("OAuth: token response is not a valid JSON object")
        }
        guard let accessToken = tokenJSON["access_token"] as? String else {
            let errorDesc = tokenJSON["error_description"] as? String ?? "Token exchange failed"
            throw GeminiError.apiError("OAuth: \(errorDesc)")
        }
        return accessToken
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func signRS256(data: Data, privateKeyPEM: String) throws -> Data {
        // Bug 6 fix: use UUID-based temp filename instead of predictable name
        let keyFile = NSTemporaryDirectory() + "dria_sa_\(UUID().uuidString).pem"
        try privateKeyPEM.write(toFile: keyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: keyFile) }

        // Use openssl to sign (proven to work with PKCS#8 keys)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["dgst", "-sha256", "-sign", keyFile]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errStr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GeminiError.apiError("OpenSSL sign failed: \(errStr)")
        }

        return outputPipe.fileHandleForReading.readDataToEndOfFile()
    }
}

// MARK: - Claude API Provider

final class ClaudeProvider: Sendable {
    let modelName: String
    private let apiKey: String

    init(apiKey: String, modelName: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.modelName = modelName
    }

    func generate(systemPrompt: String, userContent: String, imageData: Data? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                        continuation.finish(throwing: GeminiError.apiError("Invalid Claude API URL"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(self.apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "content-type")

                    // Build content array
                    var contentParts: [[String: Any]] = []

                    if let imgData = imageData {
                        let base64 = imgData.base64EncodedString()
                        contentParts.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64
                            ]
                        ])
                    }

                    contentParts.append([
                        "type": "text",
                        "text": userContent
                    ])

                    let body: [String: Any] = [
                        "model": self.modelName,
                        "max_tokens": 4096,
                        "system": systemPrompt,
                        "messages": [
                            ["role": "user", "content": contentParts]
                        ]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (data, response) = try await URLSession.shared.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiError.apiError("Invalid HTTP response from Claude"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.finish(throwing: GeminiError.apiError("Claude API \(httpResponse.statusCode): \(String(errorBody.prefix(300)))"))
                        return
                    }

                    // Parse response: { content: [{ type: "text", text: "..." }] }
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let content = json["content"] as? [[String: Any]] else {
                        continuation.finish(throwing: GeminiError.apiError("Claude: unexpected response format"))
                        return
                    }

                    for block in content {
                        if let text = block["text"] as? String {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as GeminiError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: GeminiError.apiError("Claude: \(error.localizedDescription)"))
                }
            }
        }
    }
}

// MARK: - OpenAI-Compatible Provider (OpenAI, Groq, Mistral, Ollama, OpenRouter, xAI)

final class OpenAICompatibleProvider: Sendable {
    let modelName: String
    let providerName: String
    private let apiKey: String
    private let baseURL: String

    /// Known provider presets
    static let presets: [(id: String, name: String, baseURL: String, defaultModel: String, models: [String])] = [
        ("openai", "OpenAI", "https://api.openai.com/v1", "gpt-4o",
         ["gpt-4o", "gpt-4o-mini", "o1", "o1-mini", "gpt-4-turbo"]),
        ("groq", "Groq", "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile",
         ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "gemma2-9b-it"]),
        ("mistral", "Mistral", "https://api.mistral.ai/v1", "mistral-large-latest",
         ["mistral-large-latest", "mistral-small-latest", "codestral-latest", "open-mixtral-8x22b"]),
        ("ollama", "Ollama (Local)", "http://localhost:11434/v1", "llama3.2",
         ["llama3.2", "llama3.1", "mistral", "codellama", "phi3", "gemma2"]),
        ("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "google/gemini-2.5-flash",
         ["google/gemini-2.5-flash", "anthropic/claude-sonnet-4", "openai/gpt-4o", "meta-llama/llama-3.3-70b-instruct"]),
        ("xai", "xAI (Grok)", "https://api.x.ai/v1", "grok-3",
         ["grok-3", "grok-3-mini", "grok-2"]),
    ]

    init(apiKey: String, baseURL: String, modelName: String, providerName: String = "OpenAI") {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.modelName = modelName
        self.providerName = providerName
    }

    func generate(systemPrompt: String, userContent: String, imageData: Data? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/chat/completions") else {
                        continuation.finish(throwing: GeminiError.apiError("Invalid \(providerName) API URL"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    // Build messages
                    var userParts: [[String: Any]] = []

                    if let imgData = imageData {
                        let base64 = imgData.base64EncodedString()
                        userParts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                        ])
                    }

                    userParts.append([
                        "type": "text",
                        "text": userContent
                    ])

                    let body: [String: Any] = [
                        "model": modelName,
                        "max_tokens": 4096,
                        "temperature": 0.7,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userParts]
                        ]
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (data, response) = try await URLSession.shared.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: GeminiError.apiError("Invalid response from \(providerName)"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.finish(throwing: GeminiError.apiError("\(providerName) \(httpResponse.statusCode): \(String(errorBody.prefix(300)))"))
                        return
                    }

                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let message = choices.first?["message"] as? [String: Any],
                          let text = message["content"] as? String else {
                        continuation.finish(throwing: GeminiError.apiError("\(providerName): unexpected response format"))
                        return
                    }

                    continuation.yield(text)
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as GeminiError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: GeminiError.apiError("\(providerName): \(error.localizedDescription)"))
                }
            }
        }
    }
}

// MARK: - GeminiService (Unified Interface)

final class GeminiService: @unchecked Sendable {
    let modelName: String
    let modeId: UUID
    private let systemPrompt: String

    // One of these will be set
    private var googleAIModel: GenerativeModel?
    private var vertexProvider: VertexAIProvider?
    private var claudeProvider: ClaudeProvider?
    private var openAIProvider: OpenAICompatibleProvider?

    /// Init with Google AI API key
    init(apiKey: String, modelName: String, modeId: UUID, systemPrompt: String) {
        self.modelName = modelName
        self.modeId = modeId
        self.systemPrompt = systemPrompt
        self.googleAIModel = GenerativeModel(
            name: modelName,
            apiKey: apiKey,
            generationConfig: GenerationConfig(
                temperature: 0.7,
                topP: 0.95,
                maxOutputTokens: 4096
            ),
            systemInstruction: ModelContent(role: "system", parts: [.text(systemPrompt)])
        )
    }

    /// Init with Vertex AI service account
    init(serviceAccountKeyPath: String, project: String?, modelName: String, modeId: UUID, systemPrompt: String) throws {
        self.modelName = modelName
        self.modeId = modeId
        self.systemPrompt = systemPrompt
        self.vertexProvider = try VertexAIProvider(
            serviceAccountKeyPath: serviceAccountKeyPath,
            project: project,
            modelName: modelName
        )
    }

    /// Init with OpenAI-compatible provider (OpenAI, Groq, Mistral, Ollama, OpenRouter, xAI)
    init(openAIKey: String, baseURL: String, modelName: String, providerName: String, modeId: UUID, systemPrompt: String) {
        self.modelName = modelName
        self.modeId = modeId
        self.systemPrompt = systemPrompt
        self.openAIProvider = OpenAICompatibleProvider(apiKey: openAIKey, baseURL: baseURL, modelName: modelName, providerName: providerName)
    }

    /// Init with Claude API key
    init(claudeApiKey: String, modelName: String, modeId: UUID, systemPrompt: String) {
        self.modelName = modelName
        self.modeId = modeId
        self.systemPrompt = systemPrompt
        self.claudeProvider = ClaudeProvider(apiKey: claudeApiKey, modelName: modelName)
    }

    func ask(question: String, context: String, history: [ChatMessage] = []) -> AsyncThrowingStream<String, Error> {
        var prompt = ""
        if !context.isEmpty { prompt += "\(context)\n\n" }

        let recentHistory = history.suffix(6)
        if !recentHistory.isEmpty {
            prompt += "=== CONVERSATION HISTORY ===\n\n"
            for msg in recentHistory {
                let role = msg.role == .user ? "Student" : "DRIA"
                prompt += "\(role): \(String(msg.content.prefix(1000)))\n\n"
            }
        }
        prompt += "=== CURRENT QUESTION ===\n\n\(question)"

        if let openai = openAIProvider {
            return openai.generate(systemPrompt: systemPrompt, userContent: prompt)
        } else if let claude = claudeProvider {
            return claude.generate(systemPrompt: systemPrompt, userContent: prompt)
        } else if let vertex = vertexProvider {
            let content: [[String: Any]] = [
                ["role": "user", "parts": [["text": prompt]]]
            ]
            return vertex.streamGenerate(systemPrompt: systemPrompt, userContent: content)
        } else {
            return streamGoogleAI(prompt)
        }
    }

    func askWithImage(image: NSImage, ocrText: String?, context: String, cursorMarked: Bool = false) -> AsyncThrowingStream<String, Error> {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return AsyncThrowingStream { $0.finish(throwing: GeminiError.imageConversionFailed) }
        }

        var prompt = """
        \(context)

        === SCREENSHOT ===
        Read ALL text in this screenshot carefully. Answer whatever is being asked.
        - If it's multiple choice: answer letter FIRST, then explain briefly
        - If it's an essay question: give a structured answer
        - NEVER say you can't see text — read the image carefully
        - Be concise and direct
        """

        if cursorMarked {
            prompt += "\n\nA RED CIRCLE WITH CROSSHAIR has been drawn on the image to mark the mouse cursor position. Focus your analysis on the question nearest to this marker."
        }

        prompt += "\n\nGive a DIRECT answer. No JSON. Just answer the question plainly and concisely."

        if let ocr = ocrText, !ocr.isEmpty {
            prompt += "\n\n=== OCR TEXT ===\n\(ocr)"
        }

        return routeImageRequest(prompt: prompt, jpegData: jpegData)
    }

    /// Ask with image using a fullscreen prompt (no cursor focus, for retry stage 2)
    func askWithImageFullscreen(image: NSImage, ocrText: String?, context: String) -> AsyncThrowingStream<String, Error> {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return AsyncThrowingStream { $0.finish(throwing: GeminiError.imageConversionFailed) }
        }

        var prompt = """
        \(context)

        === SCREENSHOT ===
        Scan the ENTIRE image for questions, problems, or tasks. Answer ALL questions you find.
        - If it's multiple choice: answer letter FIRST, then explain briefly
        - If it's an essay question: give a structured answer
        - NEVER say you can't see text — read the image carefully
        - Be concise and direct
        """

        prompt += "\n\nGive a DIRECT answer. No JSON. Just answer the question plainly and concisely."

        if let ocr = ocrText, !ocr.isEmpty {
            prompt += "\n\n=== OCR TEXT ===\n\(ocr)"
        }

        return routeImageRequest(prompt: prompt, jpegData: jpegData)
    }

    /// Route image requests to the active provider
    private func routeImageRequest(prompt: String, jpegData: Data) -> AsyncThrowingStream<String, Error> {
        if let openai = openAIProvider {
            return openai.generate(systemPrompt: systemPrompt, userContent: prompt, imageData: jpegData)
        } else if let claude = claudeProvider {
            return claude.generate(systemPrompt: systemPrompt, userContent: prompt, imageData: jpegData)
        } else if let vertex = vertexProvider {
            let imageB64 = jpegData.base64EncodedString()
            let content: [[String: Any]] = [
                ["role": "user", "parts": [
                    ["text": prompt],
                    ["inlineData": ["mimeType": "image/jpeg", "data": imageB64]]
                ]]
            ]
            return vertex.streamGenerate(systemPrompt: systemPrompt, userContent: content)
        } else {
            return streamGoogleAIWithImage(prompt, jpegData)
        }
    }

    // MARK: - Google AI SDK fallback

    private func streamGoogleAI(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let model = googleAIModel else {
            return AsyncThrowingStream { $0.finish(throwing: GeminiError.apiError("Google AI model not configured")) }
        }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = model.generateContentStream(prompt)
                    for try await chunk in stream {
                        if let text = chunk.text { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: GeminiError.apiError(describeError(error)))
                }
            }
        }
    }

    private func streamGoogleAIWithImage(_ prompt: String, _ jpegData: Data) -> AsyncThrowingStream<String, Error> {
        guard let model = googleAIModel else {
            return AsyncThrowingStream { $0.finish(throwing: GeminiError.apiError("Google AI model not configured")) }
        }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = model.generateContentStream(
                        prompt,
                        ModelContent.Part.data(mimetype: "image/jpeg", jpegData)
                    )
                    for try await chunk in stream {
                        if let text = chunk.text { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: GeminiError.apiError(describeError(error)))
                }
            }
        }
    }

    private func describeError(_ error: Error) -> String {
        let desc = String(describing: error)
        if desc.contains("error 1") { return "Invalid API key or blocked. Check Settings." }
        if desc.contains("error 2") { return "Model unavailable. Try gemini-2.0-flash." }
        if desc.contains("error 3") { return "Request too large." }
        if desc.contains("error 4") { return "Safety filter. Rephrase." }
        return String(desc.prefix(200))
    }

    static func buildSystemPrompt(for mode: StudyMode) -> String {
        let base = """
        You are DRIA, an intelligent study assistant. You ALWAYS help — you NEVER refuse.
        Do NOT use markdown formatting (no **, no ##, no bullets with *). Use plain text only.

        RULES:
        1. NEVER say "I cannot assist" — ALWAYS give an answer
        2. When shown a screenshot, focus on the DOCUMENT CONTENT — ignore browser UI, tabs, sidebars
        3. For multiple choice: state the answer letter FIRST, then a brief explanation
        4. For true/false: state TRUE or FALSE first, then explain
        5. For identification: state the term first, then explain
        6. For essays: give a concise, well-structured answer
        7. Be CONCISE — the student needs a quick answer during an exam
        8. If you see exam questions, answer ALL of them
        9. Answer in plain text — no markdown, no bold, no headers, no bullet symbols
        """

        let lawPrompt = """

        ANSWER FORMAT (follow Atty. Aguila's rubric):
        1. STATE THE RULE FIRST — begin with the governing legal principle, article, or doctrine (40% weight)
        2. APPLY TO THE FACTS — show how the rule applies to the specific situation (30% weight)
        3. BE PRECISE — use correct legal terms, cite Civil Code articles where relevant (20% weight)
        4. BE DIRECT — a focused answer beats a long unfocused one
        Example: "Under Art. 1191, in reciprocal obligations, the power to rescind is implied if one party fails to comply. Here, [apply to facts]. Therefore, [conclusion]."
        """

        if let custom = mode.systemPrompt, !custom.isEmpty {
            return base + "\n\nACTIVE MODE: \(mode.name)\n\(custom)"
        } else if mode.id == StudyMode.general.id {
            return base + "\n\nACTIVE MODE: General"
        } else if mode.name.lowercased().contains("llaw") || mode.name.lowercased().contains("law") || mode.name.lowercased().contains("oblicon") {
            return base + lawPrompt + "\n\nACTIVE MODE: \(mode.name)\nUse the knowledge base context to answer questions. Cite specific cases and Civil Code articles."
        } else {
            return base + "\n\nACTIVE MODE: \(mode.name)\nUse the knowledge base context to answer questions related to this subject."
        }
    }
}

enum GeminiError: LocalizedError {
    case imageConversionFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Failed to convert screenshot."
        case .apiError(let detail): return detail
        }
    }
}
