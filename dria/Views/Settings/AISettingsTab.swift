//
//  AISettingsTab.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

struct AISettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var saved: Bool = false
    @State private var saKeyPath: String = ""
    @State private var projectId: String = ""
    @State private var claudeKeyInput: String = ""
    @State private var showClaudeKey: Bool = false
    @State private var claudeSaved: Bool = false
    @State private var openAIKeyInput: String = ""
    @State private var openAISaved: Bool = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Provider") {
                Picker("AI Provider", selection: $state.aiProvider) {
                    Text("Google AI (API Key) — Free").tag("googleai")
                    Text("Vertex AI (Service Account)").tag("vertexai")
                    Text("Claude (Anthropic)").tag("claude")
                    Text("OpenAI / Groq / Mistral / Ollama / OpenRouter / xAI").tag("openai-compatible")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.aiProvider) {
                    appState.syncModelToProvider()
                }
            }

            if appState.aiProvider == "vertexai" {
                Section("Vertex AI Configuration") {
                    HStack {
                        TextField("Service Account Key Path", text: $saKeyPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.json]
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                let dest = NSHomeDirectory() + "/Library/Application Support/dria/sa-key.json"
                                try? FileManager.default.createDirectory(
                                    atPath: NSHomeDirectory() + "/Library/Application Support/dria",
                                    withIntermediateDirectories: true)
                                try? FileManager.default.removeItem(atPath: dest)
                                try? FileManager.default.copyItem(atPath: url.path, toPath: dest)
                                saKeyPath = dest
                                appState.serviceAccountKeyPath = dest
                            }
                        }
                    }

                    TextField("Project ID", text: $projectId)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: projectId) { _, val in
                            appState.vertexProject = val
                        }

                    if appState.hasServiceAccount {
                        Label("Service account found", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else if !saKeyPath.isEmpty {
                        Label("Key file not found", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            } else if appState.aiProvider == "openai-compatible" {
                Section("Provider Preset") {
                    Picker("Provider", selection: Binding(
                        get: { appState.openAIProviderName },
                        set: { name in
                            appState.openAIProviderName = name
                            if let preset = OpenAICompatibleProvider.presets.first(where: { $0.name == name }) {
                                appState.openAIBaseURL = preset.baseURL
                                appState.selectedModel = preset.defaultModel
                            }
                        }
                    )) {
                        ForEach(OpenAICompatibleProvider.presets, id: \.id) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        Text("Custom").tag("Custom")
                    }
                }
                Section("\(appState.openAIProviderName) Configuration") {
                    if appState.openAIProviderName == "Custom" || !OpenAICompatibleProvider.presets.contains(where: { $0.name == appState.openAIProviderName }) {
                        TextField("Base URL", text: Binding(
                            get: { appState.openAIBaseURL },
                            set: { appState.openAIBaseURL = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        SecureField("API Key", text: $openAIKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            appState.openAIApiKey = openAIKeyInput
                            openAISaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openAISaved = false }
                        }
                        .disabled(openAIKeyInput.isEmpty && !appState.openAIBaseURL.contains("localhost"))
                    }
                    if openAISaved {
                        Text("Key saved!").foregroundStyle(.green).font(.caption)
                    }
                    if appState.openAIBaseURL.contains("localhost") {
                        Text("Ollama detected — no API key needed for local models.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if appState.aiProvider == "claude" {
                Section("Claude API Key") {
                    HStack {
                        if showClaudeKey {
                            TextField("API Key", text: $claudeKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $claudeKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showClaudeKey.toggle() }) {
                            Image(systemName: showClaudeKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button("Save") {
                            appState.claudeApiKey = claudeKeyInput
                            claudeSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { claudeSaved = false }
                        }
                        .disabled(claudeKeyInput.isEmpty)
                    }
                    if claudeSaved {
                        Text("Key saved!").foregroundStyle(.green).font(.caption)
                    }
                    Text("Get your key at [console.anthropic.com](https://console.anthropic.com/settings/keys)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section("Google AI API Key") {
                    HStack {
                        if showKey {
                            TextField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button("Save") {
                            try? appState.keychain.saveAPIKey(apiKeyInput)
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }
                    if saved {
                        Text("Key saved!").foregroundStyle(.green).font(.caption)
                    }
                    Text("Get your key at [aistudio.google.com](https://aistudio.google.com/apikey)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Model") {
                Picker("Model", selection: $state.selectedModel) {
                    ForEach(appState.availableModels, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if let key = try? appState.keychain.getAPIKey() { apiKeyInput = key }
            saKeyPath = appState.serviceAccountKeyPath
            projectId = appState.vertexProject
            claudeKeyInput = appState.claudeApiKey
        }
    }
}
