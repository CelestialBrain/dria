//
//  InputView.swift
//  dria
//

import SwiftUI

struct InputView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { Task { await appState.captureScreen() } }) {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { appState.toggleClipboardMonitoring() }) {
                    Label(
                        appState.autoMonitorClipboard ? "Watching" : "Auto",
                        systemImage: appState.autoMonitorClipboard ? "eye.fill" : "eye"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(appState.autoMonitorClipboard ? .green : nil)

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 8) {
                let placeholder = appState.activeMode.id == StudyMode.general.id
                    ? "Ask anything..."
                    : "Ask about \(appState.activeMode.name)..."

                TextField(placeholder, text: $state.currentQuestion)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task { await appState.submitQuestion() }
                    }

                Button(action: {
                    Task { await appState.submitQuestion() }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(appState.currentQuestion.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty || appState.isStreaming)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func pasteFromClipboard() {
        let (text, image) = appState.clipboard.readCurrentClipboard()
        if let text {
            appState.currentQuestion = text
        } else if let image {
            Task {
                do {
                    let recognized = try await appState.ocr.recognizeText(from: image)
                    appState.currentQuestion = recognized
                } catch {
                    appState.errorMessage = "OCR failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
