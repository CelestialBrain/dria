//
//  AIProviderFactory.swift
//  dria
//
//  Builds the GeminiService for the currently selected AI provider.
//  Caches the last-built service so repeated calls return the same instance
//  unless model/mode/provider config changes.
//

import Foundation

@MainActor
final class AIProviderFactory {
    struct Config {
        var provider: String
        var modelName: String
        var modeId: UUID
        var mode: StudyMode
        var language: String
        var keychain: KeychainService
        var serviceAccountKeyPath: String
        var vertexProject: String
        var claudeApiKey: String
        var openAIApiKey: String
        var openAIBaseURL: String
        var openAIProviderName: String
    }

    enum FactoryError: LocalizedError {
        case noAPIKey(provider: String)
        case vertexFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey(let p): return "No API key set for \(p). Go to Settings → AI Model."
            case .vertexFailed(let msg): return "Vertex AI: \(msg)"
            }
        }
    }

    private var cached: GeminiService?

    /// Invalidate the cache — call when config changes.
    func invalidate() {
        cached = nil
    }

    func makeService(_ config: Config) -> Result<GeminiService, FactoryError> {
        if let existing = cached,
           existing.modelName == config.modelName,
           existing.modeId == config.modeId {
            return .success(existing)
        }

        let prompt = GeminiService.buildSystemPrompt(for: config.mode, language: config.language)

        switch config.provider {
        case "vertexai":
            let saPath = config.serviceAccountKeyPath
            if !saPath.isEmpty && FileManager.default.fileExists(atPath: saPath) {
                do {
                    let proj = config.vertexProject.isEmpty ? nil : config.vertexProject
                    let svc = try GeminiService(
                        serviceAccountKeyPath: saPath,
                        project: proj,
                        modelName: config.modelName,
                        modeId: config.modeId,
                        systemPrompt: prompt
                    )
                    cached = svc
                    return .success(svc)
                } catch {
                    return .failure(.vertexFailed("\(error)"))
                }
            }
            // No SA key — fall back to Google AI if API key exists
            if let apiKey = try? config.keychain.getAPIKey(), !apiKey.isEmpty {
                let svc = GeminiService(apiKey: apiKey, modelName: config.modelName, modeId: config.modeId, systemPrompt: prompt)
                cached = svc
                return .success(svc)
            }
            return .failure(.noAPIKey(provider: "any"))

        case "claude":
            let key = config.claudeApiKey
            guard !key.isEmpty else { return .failure(.noAPIKey(provider: "Claude")) }
            let svc = GeminiService(claudeApiKey: key, modelName: config.modelName, modeId: config.modeId, systemPrompt: prompt)
            cached = svc
            return .success(svc)

        case "openai-compatible":
            let key = config.openAIApiKey
            let base = config.openAIBaseURL
            guard !key.isEmpty || base.contains("localhost") else {
                return .failure(.noAPIKey(provider: config.openAIProviderName))
            }
            let svc = GeminiService(
                openAIKey: key, baseURL: base, modelName: config.modelName,
                providerName: config.openAIProviderName, modeId: config.modeId, systemPrompt: prompt
            )
            cached = svc
            return .success(svc)

        default:
            guard let apiKey = try? config.keychain.getAPIKey(), !apiKey.isEmpty else {
                return .failure(.noAPIKey(provider: "Google AI"))
            }
            let svc = GeminiService(apiKey: apiKey, modelName: config.modelName, modeId: config.modeId, systemPrompt: prompt)
            cached = svc
            return .success(svc)
        }
    }
}
