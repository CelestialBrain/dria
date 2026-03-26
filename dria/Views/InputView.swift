//
//  InputView.swift
//  dria
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat Input Field (Enter = send, Shift+Enter = newline)

struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityPlaceholderValue(placeholder)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            // Prevent coordinator from fighting this update
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.updateHeight(textView)
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField
        var isUpdating = false
        private var lastHeight: CGFloat = 18

        init(_ parent: ChatInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(textView)
        }

        func updateHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let lineHeight: CGFloat = 18
            let visualLines = max(1, Int(ceil(usedRect.height / lineHeight)))
            let newHeight = min(54, CGFloat(visualLines) * lineHeight)
            // Only update if actually changed — prevents loop
            guard abs(newHeight - lastHeight) > 1 else { return }
            lastHeight = newHeight
            DispatchQueue.main.async {
                self.parent.height = newHeight
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift is held
                if NSEvent.modifierFlags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Enter without shift = submit
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

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
    @State private var inputHeight: CGFloat = 18
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

                ChatInputField(text: $state.currentQuestion, height: $inputHeight, placeholder: placeholder) {
                    Task { await appState.submitQuestion() }
                }
                .frame(height: inputHeight)

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
