//
//  SettingsView.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            ModesTab()
                .environment(appState)
                .tabItem { Label("Modes", systemImage: "square.stack.3d.up") }

            AISettingsTab()
                .environment(appState)
                .tabItem { Label("AI Model", systemImage: "cpu") }

            CustomizationTab()
                .environment(appState)
                .tabItem { Label("Stealth", systemImage: "eye.slash") }

            GeneralSettingsTab()
                .environment(appState)
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - Modes Tab

private struct ModesTab: View {
    @Environment(AppState.self) private var appState
    @State private var selectedModeId: UUID?
    @State private var showingNewMode = false

    var body: some View {
        HSplitView {
            // Mode list
            VStack(spacing: 0) {
                List(appState.modes, selection: $selectedModeId) { mode in
                    Label { Text(mode.name) } icon: { ModeIcon(iconName: mode.iconName) }
                        .tag(mode.id)
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: { showingNewMode = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedModeId == StudyMode.general.id || selectedModeId == nil)

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Mode detail
            if let mode = selectedMode {
                ModeEditorView(modeId: mode.id)
                    .id(mode.id)
                    .environment(appState)
            } else {
                VStack {
                    Text("Select a mode")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingNewMode) {
            NewModeSheet(onAdd: { name, icon, color, keywords in
                appState.addMode(name: name, iconName: icon, colorHex: color, keywords: keywords)
            })
        }
        .onAppear {
            if selectedModeId == nil { selectedModeId = appState.activeModeId }
        }
    }

    private var selectedMode: StudyMode? {
        appState.modes.first(where: { $0.id == selectedModeId })
    }

    private func deleteSelected() {
        guard let mode = selectedMode else { return }
        appState.deleteMode(mode)
        selectedModeId = appState.modes.first?.id
    }
}

// MARK: - New Mode Sheet

private struct NewModeSheet: View {
    var onAdd: (String, String, String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var iconName = "book.closed"
    @State private var colorHex = "5E5CE6"
    @State private var keywordsText = ""

    private let icons = ["book.closed", "leaf", "atom", "function", "globe.americas",
                         "heart.text.clipboard", "building.columns", "cpu", "music.note",
                         "paintpalette", "camera", "hammer", "chart.bar", "person.3"]

    var body: some View {
        VStack(spacing: 16) {
            Text("New Study Mode").font(.headline)

            TextField("Mode name (e.g., ENVI SCI)", text: $name)
                .textFieldStyle(.roundedBorder)

            // Icon picker
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 7), spacing: 8) {
                // Custom DRIA icon first
                Image(nsImage: {
                    let img = NSImage(named: "MenuBarIcon") ?? NSImage()
                    img.isTemplate = true
                    return img
                }())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                    .background(iconName == "sparkles" ? Color.accentColor.opacity(0.2) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { iconName = "sparkles" }

                // SF Symbol icons
                ForEach(icons, id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(iconName == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture { iconName = icon }
                }
            }

            TextField("Auto-detect keywords (comma-separated)", text: $keywordsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    let keywords = keywordsText.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased() }
                    onAdd(name, iconName, colorHex, keywords)
                    dismiss()
                }
                .disabled(name.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

// MARK: - Mode Editor

struct ModeEditorView: View {
    let modeId: UUID
    @Environment(AppState.self) private var appState

    private var mode: StudyMode {
        appState.modes.first(where: { $0.id == modeId }) ?? .general
    }
    @State private var editedName: String = ""
    @State private var editedPrompt: String = ""
    @State private var editedKeywords: String = ""
    @State private var isImporting = false
    @State private var importProgress: String?

    var body: some View {
        Form {
            Section("Mode") {
                TextField("Name", text: $editedName)
                    .onChange(of: editedName) { _, val in
                        var m = mode; m.name = val; appState.updateMode(m)
                    }

                TextField("Keywords (comma-separated)", text: $editedKeywords)
                    .onChange(of: editedKeywords) { _, val in
                        var m = mode
                        m.keywords = val.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces).lowercased() }
                        appState.updateMode(m)
                    }
            }

            Section("Custom AI Prompt (optional)") {
                TextEditor(text: $editedPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 80)
                    .onChange(of: editedPrompt) { _, val in
                        var m = mode; m.systemPrompt = val.isEmpty ? nil : val; appState.updateMode(m)
                    }
            }

            Section("Knowledge Base Files (\(mode.files.count))") {
                if mode.files.isEmpty {
                    Text("No files added. Click + to upload documents.")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                } else {
                    ForEach(mode.files) { file in
                        HStack {
                            Image(systemName: file.iconName)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(file.displayName)
                                    .font(.caption)
                                Text("\(file.chunkCount) chunks")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !mode.isBuiltIn {
                                Button(role: .destructive) {
                                    appState.removeFile(file, from: mode)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let progress = importProgress {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: openFilePicker) {
                    Label("Add Files", systemImage: "plus.circle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            editedName = mode.name
            editedPrompt = mode.systemPrompt ?? ""
            editedKeywords = mode.keywords.joined(separator: ", ")
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf, .plainText, .html, .rtf, .rtfd,
            .init(filenameExtension: "md")!, .init(filenameExtension: "docx")!,
            .init(filenameExtension: "doc")!, .init(filenameExtension: "pptx")!,
            .init(filenameExtension: "ppt")!, .init(filenameExtension: "xlsx")!,
            .init(filenameExtension: "xls")!,
            .jpeg, .png, .tiff, .heic,
        ]
        panel.allowsOtherFileTypes = true
        panel.message = "Select files to add to \(mode.name) knowledge base"

        guard panel.runModal() == .OK else { return }

        Task {
            for url in panel.urls {
                importProgress = "Importing \(url.lastPathComponent)..."
                let success = await appState.addFile(to: mode, from: url)
                if !success {
                    importProgress = "Failed: \(url.lastPathComponent)"
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
            }
            importProgress = nil
        }
    }
}

// MARK: - AI Settings

private struct AISettingsTab: View {
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
                                // Copy to App Support so it's always accessible
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

// MARK: - Customization Tab

private struct CustomizationTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Stealth Presets") {
                HStack(spacing: 12) {
                    StealthPresetButton(label: "Full", icon: "eye", opacity: 1.0, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 1.0
                    }
                    StealthPresetButton(label: "Subtle", icon: "eye.slash", opacity: 0.5, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.5
                    }
                    StealthPresetButton(label: "Faint", icon: "cloud", opacity: 0.25, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.25
                    }
                    StealthPresetButton(label: "Ghost", icon: "eye.slash.fill", opacity: 0.1, current: state.marqueeOpacity) {
                        state.marqueeOpacity = 0.1
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Text Visibility") {
                HStack {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                    Slider(value: $state.marqueeOpacity, in: 0.05...1.0, step: 0.05)
                    Image(systemName: "eye")
                        .foregroundStyle(.secondary)
                }
                Text("Opacity: \(Int(state.marqueeOpacity * 100))% — \(opacityLabel(state.marqueeOpacity))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Marquee") {
                HStack {
                    Text("Text width")
                    Slider(value: .init(
                        get: { Double(state.marqueeWidth) },
                        set: { state.marqueeWidth = Int($0) }
                    ), in: 10...50, step: 5)
                    Text("\(state.marqueeWidth)")
                        .font(.caption).monospacedDigit()
                        .frame(width: 25)
                }
                Text("Characters visible in menu bar. Smaller = more discreet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Safety") {
                Toggle("Lock chat window", isOn: $state.lockPopover)
                Text("Prevents accidental popover. Use ⌘⌥3 for inline chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func opacityLabel(_ v: Double) -> String {
        if v < 0.15 { return "Ghost mode — nearly invisible" }
        if v < 0.3 { return "Faint — very hard to read" }
        if v < 0.5 { return "Subtle — blends with dark menus" }
        if v < 0.8 { return "Visible — readable but understated" }
        return "Full — normal text brightness"
    }
}

private struct StealthPresetButton: View {
    let label: String
    let icon: String
    let opacity: Double
    let current: Double
    let action: () -> Void

    private var isSelected: Bool {
        abs(current - opacity) < 0.06
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Settings

private struct ShortcutRow: View {
    let label: String
    @Binding var binding: HotkeyBinding

    var body: some View {
        Picker(label, selection: $binding) {
            ForEach(HotkeyBinding.allOptions, id: \.keyCode) { option in
                Text(option.displayName).tag(option)
            }
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @State private var updateChecker = UpdateChecker()
    @State private var hotkeyConfig = HotkeyConfig.load()
    @State private var initialConfig = HotkeyConfig.load()

    private var shortcutsChanged: Bool {
        hotkeyConfig.capture != initialConfig.capture ||
        hotkeyConfig.sendToAI != initialConfig.sendToAI ||
        hotkeyConfig.inlineChat != initialConfig.inlineChat ||
        hotkeyConfig.cycleMode != initialConfig.cycleMode ||
        hotkeyConfig.abort != initialConfig.abort
    }

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("About") {
                HStack {
                    Text("DRIA")
                        .font(.headline)
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
                Button("Check for Updates") {
                    updateChecker.checkForUpdates()
                }
                .disabled(!updateChecker.canCheckForUpdates)
            }

            Section("Capture Workflow") {
                Picker("Mode", selection: $state.captureWorkflow) {
                    Text("Two-step: ⌘⌥1 capture, ⌘⌥2 send").tag("twoStep")
                    Text("One-step: ⌘⌥1 capture + send").tag("oneStep")
                }
                .pickerStyle(.radioGroup)
            }

            Section("Auto-detect") {
                Toggle("Auto-detect mode from window title", isOn: $state.autoDetectMode)
                Text("Matches window titles against each mode's keywords.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Smart Detection") {
                Toggle("Monitor clipboard for questions", isOn: $state.autoMonitorClipboard)
                Text("Detects MC, T/F, Identification, Essay questions when you copy text.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Smart question detection", isOn: $state.smartDetectionEnabled)
                Text("Classifies question type and shows detection in marquee.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Auto-answer on copy", isOn: $state.autoAnswerOnCopy)
                Text("Automatically sends detected questions to AI. Works best on Canvas/GForms.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shortcuts (⌘⌥ + key)") {
                ShortcutRow(label: "Capture screen", binding: $hotkeyConfig.capture)
                ShortcutRow(label: "Send to AI", binding: $hotkeyConfig.sendToAI)
                ShortcutRow(label: "Inline chat", binding: $hotkeyConfig.inlineChat)
                ShortcutRow(label: "Cycle mode", binding: $hotkeyConfig.cycleMode)
                ShortcutRow(label: "Cancel", binding: $hotkeyConfig.abort)

                Button("Apply Changes") {
                    hotkeyConfig.save()
                    appState.hotkey.reloadBindings()
                }
                .disabled(!shortcutsChanged)

                Text("All shortcuts use ⌘⌥ (Command+Option) as modifier.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text("Screen capture requires Screen Recording permission. If capture fails with a TCC error, fix it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reset Screen Recording Permission") {
                    // Reset TCC for this app, then open System Settings
                    Task.detached {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                        process.arguments = ["reset", "ScreenCapture", "com.dev.dria"]
                        try? process.run()
                        process.waitUntilExit()
                    }

                    // Open Screen Recording settings
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Open Screen Recording Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Text("After enabling, you may need to quit and relaunch DRIA.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Analytics (Local Only)") {
                Toggle("Enable usage analytics", isOn: Binding(
                    get: { AnalyticsService.shared.isEnabled },
                    set: { AnalyticsService.shared.isEnabled = $0 }
                ))
                Text("All data stays on this device. Nothing is sent to any server.")
                    .font(.caption).foregroundStyle(.secondary)

                if AnalyticsService.shared.isEnabled {
                    let s = AnalyticsService.shared.stats
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Queries: \(s.totalQueries)")
                            Spacer()
                            Text("Screenshots: \(s.screenshotCaptures)")
                        }
                        HStack {
                            Text("Auto-answers: \(s.autoAnswers)")
                            Spacer()
                            Text("Sessions: \(s.sessionsCount)")
                        }
                        HStack {
                            Text("Files imported: \(s.filesImported)")
                            Spacer()
                            Text("Errors: \(s.aiErrors)")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                    HStack {
                        Button("Export Summary") {
                            let summary = AnalyticsService.shared.exportSummary()
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(summary, forType: .string)
                        }
                        Button("Reset Stats", role: .destructive) {
                            AnalyticsService.shared.reset()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
