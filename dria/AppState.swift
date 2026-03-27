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

/// Extract the short direct answer (before "---") for the marquee
private func extractShortAnswer(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    // Find the "---" separator
    if let sepIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
        let shortPart = lines[..<sepIdx].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !shortPart.isEmpty { return shortPart }
    }
    // No separator — take first line or first 80 chars
    let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
    return String(first.prefix(80))
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
    @ObservationIgnored
    var currentResponse: String = ""
    @ObservationIgnored
    var isStreaming: Bool = false
    var isVoiceListening: Bool = false
    @ObservationIgnored
    var chatHistory: [ChatMessage] = []
    @ObservationIgnored
    var errorMessage: String?

    /// Notify views that chat changed — uses NotificationCenter to avoid observation loops
    @ObservationIgnored
    private var chatNotifyScheduled = false
    static let chatDidChange = Notification.Name("driaChat")
    func notifyChatChanged() {
        guard !chatNotifyScheduled else { return }
        chatNotifyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.chatNotifyScheduled = false
            NotificationCenter.default.post(name: AppState.chatDidChange, object: nil)
        }
    }

    // MARK: - Stealth Mode
    @ObservationIgnored
    var capturedImage: NSImage?
    @ObservationIgnored
    var stealthResponse: String = ""
    @ObservationIgnored
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

    /// Hover capture dimensions
    var hoverCaptureWidth: Double = 800 {
        didSet { UserDefaults.standard.set(hoverCaptureWidth, forKey: "hoverCaptureWidth") }
    }
    var hoverCaptureHeight: Double = 600 {
        didSet { UserDefaults.standard.set(hoverCaptureHeight, forKey: "hoverCaptureHeight") }
    }

    /// Audio source for voice input
    var audioSource: AudioSource = .mic {
        didSet {
            UserDefaults.standard.set(audioSource.rawValue, forKey: "audioSource")
            voice.audioSource = audioSource
            // Restart if currently listening with the new source
            if voice.isListening {
                voice.prefixText = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                voice.stopListening()
                voice.startListening()
            }
        }
    }

    /// Lock popover — prevent accidental clicks from opening the chat window
    var lockPopover: Bool = false {
        didSet { UserDefaults.standard.set(lockPopover, forKey: "lockPopover") }
    }

    /// What to copy when clicking the icon: "short" (direct answer), "full" (full explanation), "marquee" (what's scrolling)
    var copyMode: String = "short" {
        didSet { UserDefaults.standard.set(copyMode, forKey: "copyMode") }
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
    let voice = VoiceInputService()
    private var knowledgeBase: KnowledgeBaseService?
    private var geminiService: GeminiService?
    private var knowledgeBaseTask: Task<Void, Never>?

    // MARK: - Callbacks
    var onMarqueeUpdate: ((String?) -> Void)?
    var onIconColorChange: ((String) -> Void)? // "red", "yellow", "blue", "green", "reset"
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

    /// Language for voice input and AI responses
    var responseLanguage: String = "en-US" {
        didSet {
            UserDefaults.standard.set(responseLanguage, forKey: "responseLanguage")
            voice.setLanguage(responseLanguage)
            geminiService = nil // rebuild with new language in system prompt
        }
    }

    /// Ollama auto-fallback when offline
    var ollamaFallback: Bool = false {
        didSet { UserDefaults.standard.set(ollamaFallback, forKey: "ollamaFallback") }
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
        responseLanguage = UserDefaults.standard.string(forKey: "responseLanguage") ?? "en-US"
        ollamaFallback = UserDefaults.standard.bool(forKey: "ollamaFallback")
        marqueeWidth = UserDefaults.standard.object(forKey: "marqueeWidth") as? Int ?? 30
        marqueeOpacity = UserDefaults.standard.object(forKey: "marqueeOpacity") as? Double ?? 1.0
        lockPopover = UserDefaults.standard.bool(forKey: "lockPopover")
        hoverCaptureWidth = UserDefaults.standard.object(forKey: "hoverCaptureWidth") as? Double ?? 800
        hoverCaptureHeight = UserDefaults.standard.object(forKey: "hoverCaptureHeight") as? Double ?? 600
        audioSource = AudioSource(rawValue: UserDefaults.standard.string(forKey: "audioSource") ?? "Microphone") ?? .mic
        voice.audioSource = audioSource
        copyMode = UserDefaults.standard.string(forKey: "copyMode") ?? "short"

        aiProvider = UserDefaults.standard.string(forKey: "aiProvider") ?? "googleai"

        modes = modeManager.loadModes()
        activeModeId = UUID(uuidString: UserDefaults.standard.string(forKey: "activeModeId") ?? "") ?? StudyMode.general.id

        loadKnowledgeBase()
        migrateOldChatHistory()
        chatHistory = loadChatHistory(for: activeModeId)
        setupHotkeys()

        // Setup clipboard callbacks but DON'T start monitoring automatically
        // User must toggle "Watching" button to start — avoids TCC crash
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

        // Start monitoring after 5s delay if user had it enabled — avoids TCC crash at startup
        if autoMonitorClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.clipboard.startMonitoring()
            }
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

            let marqueeText = extractShortAnswer(response)
            onMarqueeUpdate?(marqueeText.isEmpty ? "⚠️ Empty response" : "\(question.type.label): \(marqueeText)")

            chatHistory.append(ChatMessage(role: .assistant, content: response))
            AnalyticsService.shared.track(.responseReceived(charCount: response.count))
        } catch {
            onMarqueeUpdate?("⚠️ \(error.localizedDescription)")
            AnalyticsService.shared.track(.aiError)
        }

        isProcessing = false
        persistChatHistory()
    }

    // MARK: - Per-Mode Chat Persistence

    private static let maxPersistedMessages = 50

    /// Migrate old shared chatHistory to the General mode (one-time)
    private func migrateOldChatHistory() {
        let oldKey = "chatHistory"
        let newKey = chatKey(for: StudyMode.general.id)
        // Only migrate if old key exists and new key doesn't
        guard UserDefaults.standard.data(forKey: oldKey) != nil,
              UserDefaults.standard.data(forKey: newKey) == nil else { return }
        // Copy old data to General mode
        if let data = UserDefaults.standard.data(forKey: oldKey) {
            UserDefaults.standard.set(data, forKey: newKey)
        }
        // Remove old key
        UserDefaults.standard.removeObject(forKey: oldKey)
    }

    private func chatKey(for modeId: UUID) -> String {
        "chatHistory_\(modeId.uuidString)"
    }

    private func persistChatHistory() {
        let key = chatKey(for: activeModeId)
        let toSave = Array(chatHistory.suffix(Self.maxPersistedMessages))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: key)
        }
        notifyChatChanged()
    }

    private func loadChatHistory(for modeId: UUID) -> [ChatMessage] {
        let key = chatKey(for: modeId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return Array(messages.suffix(Self.maxPersistedMessages))
    }

    // MARK: - Mode Management

    func switchMode(to mode: StudyMode) {
        // Save current mode's chat before switching
        persistChatHistory()

        activeModeId = mode.id
        geminiService = nil
        loadKnowledgeBase()

        // Load the new mode's chat
        chatHistory = loadChatHistory(for: mode.id)
        currentResponse = ""
        isStreaming = false

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

        let prompt = GeminiService.buildSystemPrompt(for: activeMode, language: responseLanguage)

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
        hotkey.onHoverCapture = { [weak self] in
            Task { [weak self] in
                await self?.handleHoverCapture()
            }
        }
        hotkey.register()
    }

    // MARK: - Hover Capture (⌘⌥4)

    /// Captures 800x600 region around cursor, sends to AI immediately — completely invisible
    func handleHoverCapture() async {
        guard !isProcessing else { return }
        AnalyticsService.shared.track(.screenshot)
        onIconColorChange?("blue")

        let result = await screenCapture.captureAroundCursor(width: hoverCaptureWidth, height: hoverCaptureHeight)
        guard let image = result.image else {
            onMarqueeUpdate?(result.error ?? "Hover capture failed")
            onIconColorChange?("red")
            return
        }

        // Mark cursor position on the captured region
        capturedImage = screenCapture.markCursorPosition(on: image)

        // Send immediately — no second hotkey needed
        await sendCapturedToAI()
    }

    // MARK: - Stealth Actions

    func handleCapture() {
        AnalyticsService.shared.track(.screenshot)
        if captureWorkflow == "oneStep" {
            Task {
                let result = await screenCapture.captureSilent()
                capturedImage = result.image
                if capturedImage != nil {
                    await autoDetectAndSend()
                } else {
                    onMarqueeUpdate?("⚠️ \(result.error ?? "Capture failed")")
                }
            }
        } else if captureWorkflow == "selectArea" {
            // Interactive area selection (like ⌘⇧4)
            Task {
                if let image = await screenCapture.captureInteractive() {
                    capturedImage = image
                    onMarqueeUpdate?("📸 ⌘⌥2 to send")
                }
            }
        } else {
            // Two step: full screen capture
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
            let marqueeText = extractShortAnswer(stealthResponse)
            onMarqueeUpdate?(marqueeText.isEmpty ? "⚠️ Empty response" : marqueeText)

            chatHistory.append(ChatMessage(role: .assistant, content: stealthResponse))
        } catch {
            onMarqueeUpdate?("⚠️ \(error.localizedDescription)")
            AnalyticsService.shared.track(.aiError)
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
            let marqueeText = extractShortAnswer(stealthResponse)
            onMarqueeUpdate?(marqueeText.isEmpty ? "⚠️ Empty response" : marqueeText)

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

        // Stop voice if active — must happen before any other work
        if voice.isListening {
            stopVoiceInput()
        }

        if chatHistory.count > 100 { chatHistory.removeFirst(chatHistory.count - 80) }
        var question = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        // Cap message length to prevent SwiftUI render hang
        if question.count > 2000 { question = String(question.prefix(2000)) + "..." }

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
        notifyChatChanged()
        currentQuestion = ""

        // Include clipboard text as extra context — skip NSImage read to avoid TCC crash
        let clipText = NSPasteboard.general.string(forType: .string)
        let kbContext = knowledgeBase?.buildContext(for: question)
        var contextString = kbContext?.contextString ?? ""
        let sourceFiles = kbContext?.sourceFiles ?? []
        if let clipText, !clipText.isEmpty {
            contextString += "\n\n=== CLIPBOARD TEXT ===\n\(clipText)"
        }

        isStreaming = true
        currentResponse = ""
        notifyChatChanged()
        errorMessage = nil

        var assistantMessage = ChatMessage(role: .assistant, content: "", referencedSources: sourceFiles)

        do {
            var buffer = ""
            var lastUIUpdate = Date()
            let stream = gemini.ask(question: question, context: contextString, history: chatHistory)
            for try await chunk in stream {
                buffer += chunk
                // Throttle UI updates to 5x per second max
                let now = Date()
                if now.timeIntervalSince(lastUIUpdate) > 0.2 {
                    currentResponse = buffer
                    notifyChatChanged()
                    lastUIUpdate = now
                }
            }
            currentResponse = stripMarkdown(buffer)
            assistantMessage.content = currentResponse
        } catch {
            let errMsg = error.localizedDescription
            errorMessage = errMsg
            onMarqueeUpdate?("⚠️ \(errMsg)")
            assistantMessage.content = "Error: \(errMsg)"
        }

        chatHistory.append(assistantMessage)
        isStreaming = false
        notifyChatChanged()
        persistChatHistory()
    }

    func clearChat() {
        chatHistory.removeAll()
        AttachmentCache.shared.clear()
        UserDefaults.standard.removeObject(forKey: chatKey(for: activeModeId))
        notifyChatChanged()
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

    // MARK: - Voice Input

    @ObservationIgnored
    private var lastVoiceText: String = ""

    func startVoiceInput() {
        onIconColorChange?("red")
        isVoiceListening = true
        lastVoiceText = ""

        // 2. Save existing text
        voice.prefixText = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        // 3. Callbacks — throttled to avoid SwiftUI render storm with long text
        let savedPrefix = voice.prefixText
        var lastUpdateTime: Date = .distantPast
        voice.onPartialTranscript = { [weak self] voiceText in
            guard let self else { return }
            self.lastVoiceText = voiceText
            // Throttle: update at most every 0.3s
            let now = Date()
            guard now.timeIntervalSince(lastUpdateTime) > 0.3 else { return }
            lastUpdateTime = now
            let newText = savedPrefix.isEmpty ? voiceText : savedPrefix + " " + voiceText
            self.currentQuestion = newText
        }
        voice.onTranscriptReady = { [weak self] voiceText in
            guard let self, !voiceText.isEmpty else { return }
            let newText = savedPrefix.isEmpty ? voiceText : savedPrefix + " " + voiceText
            self.currentQuestion = newText
        }

        // 4. Just start — don't request permissions (TCC crashes the app on macOS 26)
        //    If mic isn't authorized, the engine will fail silently
        voice.permissionGranted = true  // Skip permission check in startListening
        voice.startListening()

        // If it didn't actually start (no permission), reset UI
        if !voice.isListening {
            isVoiceListening = false
            onIconColorChange?("reset")
        }
    }

    func stopVoiceInput() {
        // Save what's in the text field BEFORE stopping — this is the truth
        let savedText = currentQuestion
        isVoiceListening = false
        onIconColorChange?("reset")
        voice.stopListening()
        // Always restore — stopListening might have cleared it
        currentQuestion = savedText
    }

    // MARK: - Practice Mode

    func generatePracticeQuestion() async {
        guard let gemini = getOrCreateGemini() else { return }
        var context = knowledgeBase?.buildContext(for: "practice question exam").contextString ?? ""
        if context.count > 3000 { context = String(context.prefix(3000)) }
        let prompt = "Generate ONE practice exam question based on the study materials. Vary the type (MC, T/F, essay, identification). Give ONLY the question, not the answer."

        isStreaming = true
        currentResponse = ""
        notifyChatChanged()
        let msg = ChatMessage(role: .user, content: "Generate a practice question")
        chatHistory.append(msg)

        do {
            var buffer = ""
            var lastUI = Date()
            let stream = gemini.ask(question: prompt, context: context, history: [])
            for try await chunk in stream {
                buffer += chunk
                let now = Date()
                if now.timeIntervalSince(lastUI) > 0.2 { currentResponse = buffer; notifyChatChanged(); lastUI = now }
            }
            currentResponse = stripMarkdown(buffer)
            chatHistory.append(ChatMessage(role: .assistant, content: currentResponse))
            notifyChatChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
        isStreaming = false
        notifyChatChanged()
        persistChatHistory()
    }

    // MARK: - Flashcard Generator

    func generateFlashcards(count: Int = 10) async -> [(front: String, back: String)] {
        guard let gemini = getOrCreateGemini() else { return [] }
        // Limit context to 3000 chars to avoid timeout with large knowledge bases
        var context = knowledgeBase?.buildContext(for: "flashcards key concepts definitions rules").contextString ?? ""
        if context.count > 3000 { context = String(context.prefix(3000)) }
        let prompt = """
        Generate \(count) flashcards from the study materials. Format each as:
        Q: [question/term]
        A: [answer/definition]

        Cover key concepts, definitions, and important rules. One blank line between cards.
        """

        do {
            var response = ""
            let stream = gemini.ask(question: prompt, context: context, history: [])
            for try await chunk in stream { response += chunk }

            // Parse Q: / A: pairs
            var cards: [(front: String, back: String)] = []
            let lines = response.components(separatedBy: "\n")
            var currentQ = ""
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("Q:") || trimmed.hasPrefix("q:") {
                    currentQ = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                } else if (trimmed.hasPrefix("A:") || trimmed.hasPrefix("a:")) && !currentQ.isEmpty {
                    let a = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    cards.append((front: currentQ, back: a))
                    currentQ = ""
                }
            }
            return cards
        } catch {
            return []
        }
    }

    // MARK: - Export Chat to PDF

    func exportChatToPDF() -> URL? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dria-chat-\(activeMode.name).pdf")

        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 50

        var context = CGContext(tempURL as CFURL, mediaBox: nil, nil)
        guard context != nil else { return nil }

        let textWidth = pageWidth - margin * 2
        var yPosition: CGFloat = pageHeight - margin
        let lineHeight: CGFloat = 16

        func newPage() {
            context?.endPage()
            context?.beginPage(mediaBox: nil)
            yPosition = pageHeight - margin
        }

        context?.beginPage(mediaBox: nil)

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16)
        ]
        let title = "dria Chat Export — \(activeMode.name)" as NSString
        title.draw(at: CGPoint(x: margin, y: yPosition - 20), withAttributes: titleAttr)
        yPosition -= 40

        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let roleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11)
        ]

        for msg in chatHistory {
            let role = msg.role == .user ? "You" : "dria"
            let roleText = "\(role):" as NSString
            let bodyText = msg.content as NSString

            // Estimate height
            let estimatedLines = Int(ceil(CGFloat(msg.content.count) / (textWidth / 6.5)))
            let blockHeight = CGFloat(estimatedLines + 1) * lineHeight + 10

            if yPosition - blockHeight < margin { newPage() }

            roleText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: roleAttr)
            yPosition -= lineHeight

            let rect = CGRect(x: margin, y: yPosition - blockHeight + lineHeight, width: textWidth, height: blockHeight)
            bodyText.draw(in: rect, withAttributes: bodyAttr)
            yPosition -= blockHeight + 5
        }

        context?.endPage()
        context?.closePDF()

        return tempURL
    }

    // MARK: - Ollama Fallback

    func checkOllamaAvailable() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        knowledgeBaseTask?.cancel()
        clipboard.stopMonitoring()
        voice.stopListening()
        hotkey.unregister()
    }
}
