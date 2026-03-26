//
//  InputView.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Voice Wave Animation

struct VoiceWaveView: View {
    @State private var animating = false
    let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 2, height: animating ? CGFloat.random(in: 4...20) : 4)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.15...0.4))
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.03),
                        value: animating
                    )
            }
        }
        .frame(height: 24)
        .onAppear { animating = true }
    }
}

// MARK: - Input View

struct InputView: View {
    @Environment(AppState.self) private var appState
    @State private var showFlashcards = false
    @State private var flashcards: [(front: String, back: String)] = []
    @State private var flashcardIndex = 0
    @State private var showingBack = false

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 8) {
            // Voice wave bar — shows when listening
            if appState.voice.isListening {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    VoiceWaveView()
                    Spacer()
                    Text("Listening...")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button(action: { appState.stopVoiceInput() }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Tool buttons row
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

                // Tools menu
                Menu {
                    Button(action: { Task { await appState.generatePracticeQuestion() } }) {
                        Label("Practice Question", systemImage: "questionmark.bubble")
                    }
                    Button(action: { showFlashcards = true }) {
                        Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                    }
                    Button(action: exportPDF) {
                        Label("Export to PDF", systemImage: "arrow.down.doc")
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            // Text field + mic + send
            HStack(alignment: .center, spacing: 6) {
                let placeholder = appState.voice.isListening
                    ? "Listening..."
                    : (appState.activeMode.id == StudyMode.general.id
                        ? "Ask anything..."
                        : "Ask about \(appState.activeMode.name)...")

                ScrollView(.vertical, showsIndicators: false) {
                    TextField(placeholder, text: $state.currentQuestion, axis: .vertical)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            Task { await appState.submitQuestion() }
                        }
                }
                .frame(minHeight: 20, maxHeight: appState.currentQuestion.isEmpty ? 20 : 54)

                // Mic button
                Button(action: {
                    if appState.voice.isListening {
                        appState.stopVoiceInput()
                    } else {
                        appState.startVoiceInput()
                    }
                }) {
                    Image(systemName: appState.voice.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 16))
                        .foregroundStyle(appState.voice.isListening ? .red : .secondary)
                }
                .buttonStyle(.plain)

                // Send button
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
        .sheet(isPresented: $showFlashcards) {
            VStack(spacing: 16) {
                Text("Flashcards — \(appState.activeMode.name)")
                    .font(.headline)

                if flashcards.isEmpty {
                    ProgressView("Generating flashcards...")
                        .task {
                            flashcards = await appState.generateFlashcards()
                            flashcardIndex = 0
                            showingBack = false
                        }
                } else {
                    let card = flashcards[flashcardIndex]
                    VStack(spacing: 12) {
                        Text(showingBack ? card.back : card.front)
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .padding()
                            .background(showingBack ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { showingBack.toggle() }

                        Text("\(flashcardIndex + 1)/\(flashcards.count) — tap to flip")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("← Prev") {
                                flashcardIndex = max(0, flashcardIndex - 1)
                                showingBack = false
                            }.disabled(flashcardIndex == 0)

                            Spacer()

                            Button("Next →") {
                                flashcardIndex = min(flashcards.count - 1, flashcardIndex + 1)
                                showingBack = false
                            }.disabled(flashcardIndex >= flashcards.count - 1)
                        }
                    }
                }

                Button("Done") {
                    showFlashcards = false
                    flashcards = []
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .frame(width: 350, height: 300)
        }
    }

    private func exportPDF() {
        guard let url = appState.exportChatToPDF() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dria-chat-\(appState.activeMode.name).pdf"
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: url, to: dest)
        }
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
