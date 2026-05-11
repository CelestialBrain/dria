//
//  GeneralSettingsTab.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
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
                    Text("dria")
                        .font(.headline)
                    Spacer()
                    Text("v\(appState.updateChecker.currentVersion)")
                        .foregroundStyle(.secondary)
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { appState.updateChecker.launchAtLogin },
                    set: { appState.updateChecker.launchAtLogin = $0 }
                ))

                HStack {
                    if !appState.updateChecker.canCheckForUpdates {
                        ProgressView().controlSize(.small)
                        Text("Checking...").font(.caption)
                    } else if appState.updateChecker.updateAvailable {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text("v\(appState.updateChecker.latestVersion) available")
                            .font(.caption)
                        Spacer()
                        Button("Download Update") {
                            appState.updateChecker.downloadUpdate()
                        }
                        .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Up to date")
                            .font(.caption)
                    }
                    Spacer()
                    Button("Check for Updates") {
                        appState.updateChecker.checkForUpdates()
                    }
                    .controlSize(.small)
                    .disabled(!appState.updateChecker.canCheckForUpdates)
                }
            }

            Section("Capture Workflow") {
                Picker("Mode", selection: $state.captureWorkflow) {
                    Text("Two-step: ⌘⌥1 full screen, ⌘⌥2 send").tag("twoStep")
                    Text("Select area: ⌘⌥1 pick region, ⌘⌥2 send").tag("selectArea")
                    Text("One-step: ⌘⌥1 capture + send").tag("oneStep")
                }
                .pickerStyle(.radioGroup)
                Text("Select area lets you highlight just the question — like ⌘⇧4.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hover Capture (⌘⌥4)") {
                Text("Captures area around your cursor and sends to AI instantly. No visible UI.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Text("Width")
                    Slider(value: $state.hoverCaptureWidth, in: 400...1600, step: 100)
                    Text("\(Int(state.hoverCaptureWidth))px")
                        .monospacedDigit().frame(width: 50)
                }
                HStack {
                    Text("Height")
                    Slider(value: $state.hoverCaptureHeight, in: 300...1200, step: 100)
                    Text("\(Int(state.hoverCaptureHeight))px")
                        .monospacedDigit().frame(width: 50)
                }

                HoverCapturePreview(
                    width: state.hoverCaptureWidth,
                    height: state.hoverCaptureHeight
                )
                .frame(height: 120)
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

                Picker("Sensitivity", selection: $state.detectionSensitivity) {
                    Text("Normal — balanced").tag("normal")
                    Text("Sensitive — catches more").tag("sensitive")
                    Text("Catch All — everything you copy").tag("catchAll")
                }
                Text(DetectionSensitivity(rawValue: state.detectionSensitivity)?.description ?? "")
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
                    Task.detached {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                        process.arguments = ["reset", "ScreenCapture", "com.dev.dria"]
                        try? process.run()
                        process.waitUntilExit()
                    }

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
                            appState.clipboard.skipNextChange = true
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

            Section("Excel / External Integrations") {
                Toggle("Enable local bridge server", isOn: $state.bridgeEnabled)
                Text("Lets Excel add-ins (and other local tools) call dria via http://127.0.0.1:7842 — uses your current provider + mode + knowledge base.")
                    .font(.caption).foregroundStyle(.secondary)

                if appState.bridgeEnabled {
                    HStack {
                        Text("Auth token")
                            .font(.caption.monospaced())
                        Spacer()
                        Button("Copy") {
                            appState.clipboard.skipNextChange = true
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.bridgeServer.currentToken(), forType: .string)
                        }
                        .controlSize(.small)
                    }
                    Text("Paste this into your Excel add-in settings. Stored at ~/Library/Application Support/dria/bridge-token.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section("Recent Issues") {
                RecentIssuesView()
            }

            Section("Troubleshooting") {
                Button("Export Debug Logs") {
                    exportDebugLogs()
                }
                Button("Report Bug on GitHub") {
                    if let url = URL(string: "https://github.com/CelestialBrain/dria/issues/new?template=bug_report.md&title=Bug:+") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("Export logs first, then attach to the GitHub issue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportDebugLogs() {
        var log = "=== dria Debug Log ===\n"
        log += "Date: \(Date())\n"
        log += "Version: \(appState.updateChecker.currentVersion)\n"
        log += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"

        log += "=== Settings ===\n"
        log += "Provider: \(appState.aiProvider)\n"
        log += "Model: \(appState.selectedModel)\n"
        log += "Has API Key: \(appState.hasAPIKey)\n"
        log += "Has Service Account: \(appState.hasServiceAccount)\n"
        log += "Active Mode: \(appState.activeMode.name)\n"
        log += "Modes: \(appState.modes.map { "\($0.name) (\($0.files.count) files)" }.joined(separator: ", "))\n"
        log += "Messages: \(appState.chatHistory.count)\n\n"

        log += "=== Analytics ===\n"
        log += AnalyticsService.shared.exportSummary()
        log += "\n\n"

        log += "=== Recent Crashes ===\n"
        let reportsDir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
        if let files = try? FileManager.default.contentsOfDirectory(atPath: reportsDir) {
            let driaFiles = files.filter { $0.lowercased().contains("dria") }.sorted().suffix(3)
            for file in driaFiles { log += "- \(file)\n" }
            if driaFiles.isEmpty { log += "None\n" }
        }

        log += "\n=== Last Error ===\n"
        log += appState.errorMessage ?? "None\n"

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dria-debug.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let dest = panel.url {
            try? log.write(to: dest, atomically: true, encoding: .utf8)
        }
    }
}

private struct RecentIssuesView: View {
    @State private var logs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if logs.isEmpty {
                Text("No recent crashes or hangs recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(logs, id: \.path) { url in
                    HStack {
                        Image(systemName: iconFor(url))
                            .foregroundStyle(colorFor(url))
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                                .font(.caption.monospaced())
                            Text(date(for: url))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("View") { NSWorkspace.shared.open(url) }
                            .controlSize(.small)
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .controlSize(.small)
                    }
                }
            }

            HStack {
                Button("Refresh") { logs = CrashReporter.recentLogs() }
                    .controlSize(.small)
                Spacer()
                if !logs.isEmpty {
                    Button("Clear all", role: .destructive) {
                        for url in logs { try? FileManager.default.removeItem(at: url) }
                        logs = []
                    }
                    .controlSize(.small)
                }
            }

            Text("Logs at ~/Library/Logs/dria/. Crash logs come from uncaught exceptions or fatal signals; hang logs come from the main-thread watchdog.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear { logs = CrashReporter.recentLogs() }
    }

    private func iconFor(_ url: URL) -> String {
        url.lastPathComponent.hasPrefix("crash") ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark.fill"
    }
    private func colorFor(_ url: URL) -> Color {
        url.lastPathComponent.hasPrefix("crash") ? .red : .orange
    }
    private func date(for url: URL) -> String {
        let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .medium
        return f.string(from: d)
    }
}

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

private struct HoverCapturePreview: View {
    let width: Double
    let height: Double

    var body: some View {
        GeometryReader { geo in
            let screenW: CGFloat = 1440
            let screenH: CGFloat = 900
            let previewScale = min(geo.size.width / screenW, geo.size.height / screenH)
            let pw = screenW * previewScale
            let ph = screenH * previewScale
            let cw = width * previewScale
            let ch = height * previewScale

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: pw, height: ph)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<8) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: pw * (i % 3 == 0 ? 0.6 : 0.8), height: 3)
                    }
                }

                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(width: cw, height: ch)

                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)

                VStack {
                    Spacer()
                    Text("\(Int(width)) × \(Int(height))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
                .frame(width: cw, height: ch)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
