//
//  AppState.swift
//  dria
//

import SwiftUI

extension NSImage {
    func jpegData(maxWidth: CGFloat = 800) -> Data? {
        let scale = min(1.0, maxWidth / size.width)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}

private func stripMarkdown(_ text: String) -> String {
    var s = text
    s = s.replacingOccurrences(of: "***", with: "")
    s = s.replacingOccurrences(of: "**", with: "")
    s = s.replacingOccurrences(of: "__", with: "")
    s = s.replacingOccurrences(of: "### ", with: "")
    s = s.replacingOccurrences(of: "## ", with: "")
    s = s.replacingOccurrences(of: "# ", with: "")
    s = s.replacingOccurrences(of: "\n- ", with: "\n• ")
    s = s.replacingOccurrences(of: "\n* ", with: "\n• ")
    s = s.replacingOccurrences(of: "```", with: "")
    s = s.replacingOccurrences(of: "`", with: "")
    return s
}

@Observable
@MainActor
final class AppState {
    // MARK: - UI State
    var currentQuestion: String = ""
    var currentResponse: String = ""
    var isStreaming: Bool = false
    var chatHistory: [ChatMessage] = []
    var errorMessage: String?

    // MARK: - Stealth Mode
    var capturedImage: NSImage?
    var stealthResponse: String = ""
    var isProcessing: Bool = false

    // MARK: - Modes
    var modes: [StudyMode] = []
    var activeModeId: UUID = StudyMode.general.id {
        didSet {
            UserDefaults.standard.set(activeModeId.uuidString, forKey: "activeModeId")
        }
    }

    var activeMode: StudyMode {
        modes.first(where: { $0.id == activeModeId }) ?? .general
    }

    // MARK: - Settings
    var selectedModel: String = "gemini-2.5-flash" {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
            geminiService = nil // force recreate with new model
        }
    }

    var captureWorkflow: String = "twoStep" {
        didSet { UserDefaults.standard.set(captureWorkflow, forKey: "captureWorkflow") }
    }

    var autoDetectMode: Bool = false {
        didSet { UserDefaults.standard.set(autoDetectMode, forKey: "autoDetectMode") }
    }

    var autoMonitorClipboard: Bool = false {
        didSet { UserDefaults.standard.set(autoMonitorClipboard, forKey: "autoMonitorClipboard") }
    }

    /// Marquee width in characters (how much menu bar space the answer takes)
    var marqueeWidth: Int = 20 {
        didSet { UserDefaults.standard.set(marqueeWidth, forKey: "marqueeWidth") }
    }

    /// Marquee text opacity: 0.0 = invisible (chameleon), 0.3 = faint, 0.6 = subtle, 1.0 = full
    var marqueeOpacity: Double = 1.0 {
        didSet { UserDefaults.standard.set(marqueeOpacity, forKey: "marqueeOpacity") }
    }

    /// Lock popover — prevent accidental clicks from opening the chat window
    var lockPopover: Bool = false {
        didSet { UserDefaults.standard.set(lockPopover, forKey: "lockPopover") }
    }

    // MARK: - Services
    let modeManager = ModeManager()
    let keychain = KeychainService()
    let clipboard = ClipboardService()
    let screenCapture = ScreenCaptureService()
    let ocr = OCRService()
    let hotkey = HotkeyService()
    let focusDetector = FocusDetector()
    let updateChecker = UpdateChecker()
    private var knowledgeBase: KnowledgeBaseService?
    private var geminiService: GeminiService?
    private var knowledgeBaseTask: Task<Void, Never>?

    // MARK: - Callbacks
    var onMarqueeUpdate: ((String?) -> Void)?
    var onModeChanged: ((StudyMode) -> Void)?
    var onAbort: (() -> Void)?
    var onAITaskStarted: ((Task<Void, Never>) -> Void)?

    // MARK: - Computed
    var hasAPIKey: Bool {
        (try? keychain.getAPIKey()) != nil
    }

    var hasServiceAccount: Bool {
        let path = serviceAccountKeyPath
        return !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    var claudeApiKey: String {
        get { UserDefaults.standard.string(forKey: "claudeApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "claudeApiKey"); geminiService = nil }
    }

    /// OpenAI-compatible provider API key
    var openAIApiKey: String {
        get { UserDefaults.standard.string(forKey: "openAIApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIApiKey"); geminiService = nil }
    }

    /// OpenAI-compatible base URL
    var openAIBaseURL: String {
        get { UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIBaseURL"); geminiService = nil }
    }

    /// OpenAI-compatible provider name (for display)
    var openAIProviderName: String {
        get { UserDefaults.standard.string(forKey: "openAIProviderName") ?? "OpenAI" }
        set { UserDefaults.standard.set(newValue, forKey: "openAIProviderName") }
    }

    var availableModels: [String] {
        switch aiProvider {
        case "claude":
            return ["claude-sonnet-4-20250514", "claude-haiku-4-20250414"]
        case "openai-compatible":
            // Try to find preset models
            if let preset = OpenAICompatibleProvider.presets.first(where: { openAIBaseURL.contains($0.baseURL) || openAIProviderName == $0.name }) {
                return preset.models
            }
            return [selectedModel] // user's custom model
        default:
            return ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-2.5-pro", "gemini-3-flash-preview"]
        }
    }

    var serviceAccountKeyPath: String {
        get {
            let path = UserDefaults.standard.string(forKey: "serviceAccountKeyPath") ?? ""
            if path.isEmpty {
                // Try known SA key locations (prefer App Support — always accessible)
                let candidates = [
                    NSHomeDirectory() + "/Library/Application Support/dria/sa-key.json",
                    NSHomeDirectory() + "/Library/Application Support/dria/google-sa-key.json"
                ]
                for candidate in candidates {
                    if FileManager.default.fileExists(atPath: candidate) { return candidate }
                }
            }
            return path
        }
        set { UserDefaults.standard.set(newValue, forKey: "serviceAccountKeyPath"); geminiService = nil }
    }

    var vertexProject: String {
        get { UserDefaults.standard.string(forKey: "vertexProject") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "vertexProject"); geminiService = nil }
    }

    /// "vertexai", "googleai", or "claude"
    var aiProvider: String = "googleai" {
        didSet {
            UserDefaults.standard.set(aiProvider, forKey: "aiProvider")
            geminiService = nil
            syncModelToProvider()
        }
    }

    func syncModelToProvider() {
        let models = availableModels
        if !models.contains(selectedModel), let first = models.first {
            selectedModel = first
        }
    }

    // MARK: - Smart Detection Settings
    var autoAnswerOnCopy: Bool = false {
        didSet { UserDefaults.standard.set(autoAnswerOnCopy, forKey: "autoAnswerOnCopy") }
    }

    var smartDetectionEnabled: Bool = true {
        didSet { UserDefaults.standard.set(smartDetectionEnabled, forKey: "smartDetectionEnabled") }
    }

    var detectionSensitivity: String = "normal" {
        didSet {
            UserDefaults.standard.set(detectionSensitivity, forKey: "detectionSensitivity")
            clipboard.detector.sensitivity = DetectionSensitivity(rawValue: detectionSensitivity) ?? .normal
        }
    }

    /// Last detected question from clipboard — NOT @Published to avoid re-render
    private(set) var lastDetectedQuestion: DetectedQuestion?

    let questionDetector = QuestionDetector()

    // MARK: - Init

    init() {
        // Load saved settings
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "gemini-2.5-flash"
        captureWorkflow = UserDefaults.standard.string(forKey: "captureWorkflow") ?? "twoStep"
        autoDetectMode = UserDefaults.standard.bool(forKey: "autoDetectMode")
        autoMonitorClipboard = UserDefaults.standard.bool(forKey: "autoMonitorClipboard")
        autoAnswerOnCopy = UserDefaults.standard.bool(forKey: "autoAnswerOnCopy")
        smartDetectionEnabled = UserDefaults.standard.object(forKey: "smartDetectionEnabled") as? Bool ?? true
        detectionSensitivity = UserDefaults.standard.string(forKey: "detectionSensitivity") ?? "normal"
        marqueeWidth = UserDefaults.standard.object(forKey: "marqueeWidth") as? Int ?? 30
        marqueeOpacity = UserDefaults.standard.object(forKey: "marqueeOpacity") as? Double ?? 1.0
        lockPopover = UserDefaults.standard.bool(forKey: "lockPopover")

        aiProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "googleai"

        modes = modeManager.loadModes()
        activeModeId = UUID(uuidString: UserDefaults.standard.string(forKey: "activeModeId") ?? "") ?? StudyMode.general.id

        loadKnowledgeBase()
        chatHistory = Self.loadChatHistory()
        setupHotkeys()
        setupClipboardDetection()
    }

    private func setupClipboardDetection() {
        clipboard.onQuestionDetected = { [weak self] question, rawText in
            guard let self, self.smartDetectionEnabled else { return }
            self.lastDetectedQuestion = question
            self.onMarqueeUpdate?("📋 \(question.type.label)")

            // Auto-detect mode from focus
            if self.autoDetectMode {
                let focus = self.focusDetector.currentFocus()
                if let suggested = self.focusDetector.suggestMode(from: focus, availableModes: self.modes),
                   suggested.id != self.activeModeId {
                    self.switchMode(to: suggested)
                }
            }

            // Auto-answer if enabled
            if self.autoAnswerOnCopy {
                Task { await self.answerDetectedQuestion(question, rawText: rawText) }
            }
        }

        clipboard.detector.sensitivity = DetectionSensitivity(rawValue: detectionSensitivity) ?? .normal
        if autoMonitorClipboard {
            clipboard.startMonitoring()
        }
    }

    /// Auto-answer a detected question from clipboard
    func answerDetectedQuestion(_ question: DetectedQuestion, rawText: String) async {
        guard !isProcessing else { return } // Prevent overlap with manual send
        AnalyticsService.shared.track(.autoAnswer)
        AnalyticsService.shared.track(.clipboardDetection(question.type))
        guard let gemini = getOrCreateGemini() else { return }

        isProcessing = true
        onMarqueeUpdate?("🔄 Answering \(question.type.label)...")

        let context = knowledgeBase?.buildContext(for: rawText).contextString ?? ""

        var prompt: String
        switch question.type {
        case .multipleChoice:
            prompt = "Answer this multiple choice question. State ONLY the correct option first, then explain briefly.\n\nQuestion: \(question.stem)\nOptions:\n\(question.options.joined(separator: "\n"))"
        case .trueFalse:
            prompt = "Answer TRUE or FALSE first, then explain briefly.\n\nQuestion: \(question.stem)"
        case .identification:
            prompt = "Give the answer (the term/concept) first, then explain briefly.\n\nQuestion: \(question.stem)"
        case .essay:
            prompt = "Answer this essay question using IRAC method (Issue, Rule, Application, Conclusion).\n\n\(question.stem)"
        case .unknown:
            prompt = "Answer this question directly and concisely.\n\n\(rawText)"
        }

        let userMsg = ChatMessage(role: .user, content: rawText)
        AttachmentCache.shared.store(messageId: userMsg.id, clipboardText: rawText)
        chatHistory.append(userMsg)

        do {
            var response = ""
            let stream = gemini.ask(question: prompt, context: context, history: chatHistory)
            for try await chunk in stream { response += chunk }
            response = stripMarkdown(response)

            let clean = response
                .replacingOccurrences(of: "\n", with: " · ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onMarqueeUpdate?(clean.isEmpty ? "⚠️ Empty response" : "\(question.type.label): \(clean)")

            chatHistory.append(ChatMessage(role: .assistant, content: response))
            AnalyticsService.shared.track(.responseReceived(charCount: response.count))
        } catch {
            onMarqueeUpdate?("⚠️ \(error.localizedDescription)")
            AnalyticsService.shared.track(.aiError)
        }

        isProcessing = false
        persistChatHistory()
    }

    // MARK: - Chat Persistence (Bug 3 fix)

    private static let chatHistoryKey = "chatHistory"
    private static let maxPersistedMessages = 100

    private func persistChatHistory() {
        let toSave = Array(chatHistory.suffix(Self.maxPersistedMessages))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: Self.chatHistoryKey)
        }
    }

    private static func loadChatHistory() -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: chatHistoryKey),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return Array(messages.suffix(maxPersistedMessages))
    }

    // MARK: - Mode Management

    func switchMode(to mode: StudyMode) {
        activeModeId = mode.id
        geminiService = nil
        loadKnowledgeBase()
        onModeChanged?(mode)
        onMarqueeUpdate?("📚 \(mode.name)")
        AnalyticsService.shared.track(.modeSwitch)
    }

    func cycleMode() {
        guard modes.count > 1 else { return }
        let currentIndex = modes.firstIndex(where: { $0.id == activeModeId }) ?? 0
        let nextIndex = (currentIndex + 1) % modes.count
        switchMode(to: modes[nextIndex])
    }

    func addMode(name: String, iconName: String, colorHex: String, keywords: [String]) {
        let mode = modeManager.createMode(name: name, iconName: iconName, colorHex: colorHex, keywords: keywords)
        modes.append(mode)
        modeManager.saveModes(modes)
    }

    func updateMode(_ mode: StudyMode) {
        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[idx] = mode
            modeManager.saveModes(modes)
            if mode.id == activeModeId {
                geminiService = nil
                loadKnowledgeBase()
            }
        }
    }

    func deleteMode(_ mode: StudyMode) {
        guard mode.id != StudyMode.general.id else { return }
        modeManager.deleteMode(mode)
        modes.removeAll { $0.id == mode.id }
        modeManager.saveModes(modes)
        if activeModeId == mode.id {
            switchMode(to: .general)
        }
    }

    func addFile(to mode: StudyMode, from url: URL) async -> Bool {
        guard let result = await modeManager.addFile(to: mode, from: url) else { return false }
        AnalyticsService.shared.track(.fileImport)
        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[idx].files.append(result.file)
            modeManager.saveModes(modes)
            if mode.id == activeModeId {
                loadKnowledgeBase()
            }
        }
        return true
    }

    func removeFile(_ file: ModeFile, from mode: StudyMode) {
        modeManager.removeFile(file, from: mode)
        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[idx].files.removeAll { $0.id == file.id }
            modeManager.saveModes(modes)
            if mode.id == activeModeId {
                loadKnowledgeBase()
            }
        }
    }

    private func loadKnowledgeBase() {
        knowledgeBaseTask?.cancel()
        let mode = activeMode
        let manager = modeManager
        knowledgeBaseTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let chunks = manager.loadChunks(for: mode)
            guard !Task.isCancelled else { return }
            let kb = KnowledgeBaseService(chunks: chunks)
            await MainActor.run {
                self.knowledgeBase = kb
            }
        }
    }

    private func getOrCreateGemini() -> GeminiService? {
        if geminiService != nil && geminiService?.modelName == selectedModel && geminiService?.modeId == activeModeId {
            return geminiService
        }

        let prompt = GeminiService.buildSystemPrompt(for: activeMode)

        if aiProvider == "vertexai" {
            let saPath = serviceAccountKeyPath
            guard !saPath.isEmpty && FileManager.default.fileExists(atPath: saPath) else {
                // No SA key — try falling back to Google AI if API key exists
                if let apiKey = try? keychain.getAPIKey(), !apiKey.isEmpty {
                    geminiService = GeminiService(apiKey: apiKey, modelName: selectedModel, modeId: activeModeId, systemPrompt: prompt)
                    return geminiService
                }
                errorMessage = "No AI provider configured. Go to Settings → AI Model."
                return nil
            }
            do {
                let proj = vertexProject.isEmpty ? nil : vertexProject
                geminiService = try GeminiService(
                    serviceAccountKeyPath: saPath,
                    project: proj,
                    modelName: selectedModel,
                    modeId: activeModeId,
                    systemPrompt: prompt
                )
                return geminiService
            } catch {
                let err = "Vertex AI: \(error)"
                errorMessage = err
                onMarqueeUpdate?("⚠️ \(err)")
                return nil
            }
        } else if aiProvider == "claude" {
            let key = claudeApiKey
            guard !key.isEmpty else {
                errorMessage = "No Claude API key set. Go to Settings → AI Model."
                return nil
            }
            geminiService = GeminiService(claudeApiKey: key, modelName: selectedModel, modeId: activeModeId, systemPrompt: prompt)
            return geminiService
        } else if aiProvider == "openai-compatible" {
            let key = openAIApiKey
            let base = openAIBaseURL
            guard !key.isEmpty || base.contains("localhost") else {
                errorMessage = "No API key set for \(openAIProviderName). Go to Settings → AI Model."
                return nil
            }
            geminiService = GeminiService(
                openAIKey: key, baseURL: base, modelName: selectedModel,
                providerName: openAIProviderName, modeId: activeModeId, systemPrompt: prompt
            )
            return geminiService
        } else {
            // Google AI API key
            guard let apiKey = try? keychain.getAPIKey(), !apiKey.isEmpty else {
                errorMessage = "No API key set. Go to Settings → AI Model."
                return nil
            }
            geminiService = GeminiService(apiKey: apiKey, modelName: selectedModel, modeId: activeModeId, systemPrompt: prompt)
            return geminiService
        }
    }

    // MARK: - Hotkeys

    // Callback for ⌘⌥3 — set by AppDelegate to toggle popover
    var onOpenPopover: (() -> Void)?

    private func setupHotkeys() {
        hotkey.onScreenshot = { [weak self] in
            self?.handleCapture()
        }
        hotkey.onSendToAI = { [weak self] in
            Task { [weak self] in
                await self?.sendCapturedToAI()
            }
        }
        hotkey.onOpenPopover = { [weak self] in
            self?.onOpenPopover?()
        }
        hotkey.onToggleMode = { [weak self] in
            self?.cycleMode()
        }
        hotkey.onAbort = { [weak self] in
            self?.onAbort?()
        }
        hotkey.register()
    }

    // MARK: - Stealth Actions

    func handleCapture() {
        AnalyticsService.shared.track(.screenshot)
        if captureWorkflow == "oneStep" {
            // One step: capture + auto-detect + send
            Task {
                let result = await screenCapture.captureSilent()
                capturedImage = result.image
                if capturedImage != nil {
                    await autoDetectAndSend()
                } else {
                    onMarqueeUpdate?("⚠️ \(result.error ?? "Capture failed")")
                }
            }
        } else {
            // Two step: just capture
            Task {
                let result = await screenCapture.captureSilent()
                capturedImage = result.image
                if capturedImage != nil {
                    onMarqueeUpdate?("📸 ⌘⌥2 to send")
                } else {
                    onMarqueeUpdate?("⚠️ \(result.error ?? "Capture failed")")
                }
            }
        }
    }

    private func autoDetectAndSend() async {
        // Auto-detect mode from focused window
        if autoDetectMode {
            let focus = focusDetector.currentFocus()
            if let suggested = focusDetector.suggestMode(from: focus, availableModes: modes),
               suggested.id != activeModeId {
                switchMode(to: suggested)
            }
        }
        await sendCapturedToAI()
    }

    func sendCapturedToAI() async {
        guard !isProcessing else { return } // Prevent double-send
        AnalyticsService.shared.track(.query(provider: aiProvider))
        if chatHistory.count > 100 { chatHistory.removeFirst(chatHistory.count - 80) }

        // Gather all available context: screenshot and/or clipboard
        let (clipText, clipImage) = clipboard.readCurrentClipboard()
        let image = capturedImage ?? clipImage

        guard image != nil || (clipText != nil && !clipText!.isEmpty) else {
            onMarqueeUpdate?("⚠️ Nothing to send — ⌘⌥1 to capture or copy text first")
            return
        }

        guard let gemini = getOrCreateGemini() else {
            onMarqueeUpdate?("⚠️ \(errorMessage ?? "Configure AI in Settings")")
            return
        }

        isProcessing = true
        stealthResponse = ""
        onMarqueeUpdate?("🔄 \(activeMode.name)...")

        // Build context from all available inputs
        var ocrText: String? = nil
        if let image { ocrText = try? await ocr.recognizeText(from: image) }

        var queryHint = ocrText ?? ""
        if let clipText { queryHint += " \(clipText)" }
        if queryHint.isEmpty { queryHint = "screenshot question" }

        let context = knowledgeBase?.buildContext(for: queryHint).contextString ?? ""

        let focus = focusDetector.currentFocus()
        let focusContext = "User is viewing: \(focus.appName)" + (focus.windowTitle.map { " — \($0)" } ?? "")

        var fullContext = "\(focusContext)\n\n\(context)"
        if let clipText, !clipText.isEmpty {
            fullContext += "\n\n=== CLIPBOARD TEXT ===\n\(clipText)"
        }

        // Add a user message with attachments cached separately
        var userDesc = ocrText?.prefix(200).description ?? ""
        if userDesc.isEmpty && clipText != nil { userDesc = String(clipText!.prefix(200)) }
        if userDesc.isEmpty { userDesc = "[captured]" }
        let msg = ChatMessage(role: .user, content: userDesc)
        AttachmentCache.shared.store(messageId: msg.id, imageData: image?.jpegData(maxWidth: 400), clipboardText: clipText)
        chatHistory.append(msg)

        do {
            var rawResponse = ""

            if let image {
                // Has image — use cursor marking + image analysis
                let markedImage = screenCapture.markCursorPosition(on: image)
                let stream1 = gemini.askWithImage(image: markedImage, ocrText: ocrText, context: fullContext, cursorMarked: true)
                for try await chunk in stream1 { rawResponse += chunk }

                // Retry with fullscreen if empty
                if rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
                    onMarqueeUpdate?("🔄 Scanning full screen...")
                    rawResponse = ""
                    let stream2 = gemini.askWithImageFullscreen(image: image, ocrText: ocrText, context: fullContext)
                    for try await chunk in stream2 { rawResponse += chunk }
                }
            } else {
                // Text only from clipboard — use regular ask
                let prompt = clipText ?? ""
                let stream = gemini.ask(question: prompt, context: fullContext, history: chatHistory)
                for try await chunk in stream { rawResponse += chunk }
            }

            stealthResponse = stripMarkdown(rawResponse)
            let clean = stealthResponse
                .replacingOccurrences(of: "\n", with: " · ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onMarqueeUpdate?(clean.isEmpty ? "⚠️ Empty response" : clean)

            chatHistory.append(ChatMessage(role: .assistant, content: stealthResponse))
        } catch {
            onMarqueeUpdate?("⚠️ \(error.localizedDescription)")
        }

        isProcessing = false
        persistChatHistory()
        capturedImage = nil
    }

    /// Send screenshot/clipboard + typed question together (⌘⌥1 → ⌘⌥3 flow or clipboard → ⌘⌥3 flow)
    func sendCapturedWithQuestion(_ question: String) async {
        if chatHistory.count > 100 { chatHistory.removeFirst(chatHistory.count - 80) }
        let (clipText, clipImage) = clipboard.readCurrentClipboard()
        let image = capturedImage ?? clipImage
        guard let gemini = getOrCreateGemini() else {
            onMarqueeUpdate?("⚠️ \(errorMessage ?? "Configure AI in Settings")")
            return
        }

        isProcessing = true
        stealthResponse = ""
        onMarqueeUpdate?("🔄 \(activeMode.name)...")

        var ocrText: String? = nil
        if let image { ocrText = try? await ocr.recognizeText(from: image) }

        var queryHint = "\(question) \(ocrText ?? "")"
        if let clipText, !clipText.isEmpty { queryHint += " \(clipText)" }

        let context = knowledgeBase?.buildContext(for: queryHint).contextString ?? ""

        let focus = focusDetector.currentFocus()
        let focusContext = "User is viewing: \(focus.appName)" + (focus.windowTitle.map { " — \($0)" } ?? "")

        var fullContext = "\(focusContext)\n\n\(context)"
        if let clipText, !clipText.isEmpty {
            fullContext += "\n\n=== CLIPBOARD TEXT ===\n\(clipText)"
        }
        if !chatHistory.isEmpty {
            fullContext += "\n\n=== CONVERSATION HISTORY ===\n"
            for msg in chatHistory.suffix(10) {
                let role = msg.role == .user ? "Student" : "DRIA"
                fullContext += "\(role): \(msg.content)\n\n"
            }
        }
        fullContext += "\n\n=== STUDENT'S QUESTION ===\n\(question)"

        let sendMsg = ChatMessage(role: .user, content: question)
        AttachmentCache.shared.store(messageId: sendMsg.id, imageData: image?.jpegData(maxWidth: 400), clipboardText: clipText)
        chatHistory.append(sendMsg)

        do {
            if let image {
                let stream = gemini.askWithImage(image: image, ocrText: ocrText, context: fullContext)
                for try await chunk in stream { stealthResponse += chunk }
            } else {
                let stream = gemini.ask(question: question, context: fullContext, history: chatHistory)
                for try await chunk in stream { stealthResponse += chunk }
            }
            stealthResponse = stripMarkdown(stealthResponse)
            let clean = stealthResponse
                .replacingOccurrences(of: "\n", with: " · ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            onMarqueeUpdate?(clean.isEmpty ? "⚠️ Empty response" : clean)

            chatHistory.append(ChatMessage(role: .assistant, content: stealthResponse))
        } catch {
            onMarqueeUpdate?("⚠️ \(error.localizedDescription)")
        }

        isProcessing = false
        persistChatHistory()
        capturedImage = nil
    }

    // MARK: - Regular Chat

    func submitQuestion() async {
        guard !isStreaming else { return } // Prevent double-submit
        if chatHistory.count > 100 { chatHistory.removeFirst(chatHistory.count - 80) }
        let question = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        guard let gemini = getOrCreateGemini() else {
            let err = errorMessage ?? "Configure AI in Settings → AI Model"
            errorMessage = err
            onMarqueeUpdate?("⚠️ \(err)")
            // Add user message so they can see what they typed
            chatHistory.append(ChatMessage(role: .user, content: question))
            chatHistory.append(ChatMessage(role: .assistant, content: "Error: \(err)"))
            currentQuestion = ""
            return
        }

        let userMessage = ChatMessage(role: .user, content: question)
        chatHistory.append(userMessage)
        currentQuestion = ""

        // Include clipboard text as extra context if available
        let (clipText, _) = clipboard.readCurrentClipboard()
        var contextString = knowledgeBase?.buildContext(for: question).contextString ?? ""
        let sourceFiles = knowledgeBase?.buildContext(for: question).sourceFiles ?? []
        if let clipText, !clipText.isEmpty {
            contextString += "\n\n=== CLIPBOARD TEXT ===\n\(clipText)"
        }

        isStreaming = true
        currentResponse = ""
        errorMessage = nil

        var assistantMessage = ChatMessage(role: .assistant, content: "", referencedSources: sourceFiles)

        do {
            let stream = gemini.ask(question: question, context: contextString, history: chatHistory)
            for try await chunk in stream {
                currentResponse += chunk
            }
            currentResponse = stripMarkdown(currentResponse)
            assistantMessage.content = currentResponse
        } catch {
            let errMsg = error.localizedDescription
            errorMessage = errMsg
            onMarqueeUpdate?("⚠️ \(errMsg)")
            assistantMessage.content = "Error: \(errMsg)"
        }

        chatHistory.append(assistantMessage)
        isStreaming = false
        persistChatHistory()
    }

    func clearChat() {
        chatHistory.removeAll()
        AttachmentCache.shared.clear()
        UserDefaults.standard.removeObject(forKey: Self.chatHistoryKey)
        currentResponse = ""
        currentQuestion = ""
        errorMessage = nil
        stealthResponse = ""
        capturedImage = nil
        onMarqueeUpdate?(nil)
    }

    func captureScreen() async {
        if let image = await screenCapture.captureInteractive() {
            do {
                let text = try await ocr.recognizeText(from: image)
                if !text.isEmpty {
                    currentQuestion = text
                } else {
                    errorMessage = "No text detected in screenshot."
                }
            } catch {
                errorMessage = "OCR failed: \(error.localizedDescription)"
            }
        }
    }

    func toggleClipboardMonitoring() {
        autoMonitorClipboard.toggle()
        if autoMonitorClipboard {
            setupClipboardDetection()
        } else {
            clipboard.stopMonitoring()
        }
    }

    /// Call on app termination to clean up resources
    func cleanup() {
        knowledgeBaseTask?.cancel()
        clipboard.stopMonitoring()
        hotkey.unregister()
    }
}
