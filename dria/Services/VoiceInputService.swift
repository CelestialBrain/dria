//
//  VoiceInputService.swift
//  dria
//
//  On-device voice transcription using Apple Speech framework.
//  No API key, no internet needed.

import AppKit
import Speech

@MainActor
final class VoiceInputService {
    var isListening: Bool = false
    var transcript: String = ""
    var onTranscriptReady: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var permissionGranted = false
    /// Text that was in the field before voice started — preserve it
    var prefixText: String = ""

    /// Supported languages for speech recognition
    static let supportedLanguages: [(id: String, name: String)] = [
        ("en-US", "English"),
        ("fil-PH", "Filipino"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("zh-CN", "Chinese (Simplified)"),
        ("pt-BR", "Portuguese"),
        ("it-IT", "Italian"),
    ]

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        // Don't request permission at init — causes TCC crash on fresh install
        // Permission will be requested when user first taps mic
    }

    func setLanguage(_ localeId: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    /// Request permission (one-time)
    func requestPermission() async -> Bool {
        // Speech permission
        let speechOk = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        // Mic permission
        let micOk: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micOk = true
        case .notDetermined:
            micOk = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            micOk = false
        }
        permissionGranted = speechOk && micOk
        return permissionGranted
    }

    /// Start listening — call when mic button tapped
    func startListening() {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        // Check permissions
        guard permissionGranted else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return
        }

        // Show listening state immediately — don't wait for engine
        isListening = true
        transcript = ""
        prefixText = ""

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            isListening = false
            return
        }
        request.shouldReportPartialResults = true

        // Don't force on-device — allow server for better Filipino support
        // On-device doesn't support all languages
        if recognizer.supportsOnDeviceRecognition {
            // Only use on-device for English — Filipino needs server
            let locale = recognizer.locale.identifier
            if locale.hasPrefix("en") {
                request.requiresOnDeviceRecognition = true
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            isListening = false
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            isListening = false
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    let combined = self.prefixText.isEmpty
                        ? self.transcript
                        : self.prefixText + "\n" + self.transcript
                    self.onPartialTranscript?(combined)
                }
                if let error {
                }
                if let error, !self.isListening {
                    _ = error
                }
            }
        }
    }

    /// Stop listening — keeps transcript in text field
    func stopListening() {
        guard isListening else { return }

        // Save transcript before any cleanup
        let savedTranscript = transcript
        let combined = prefixText.isEmpty ? savedTranscript : prefixText + "\n" + savedTranscript

        // End audio
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.finish()
        recognitionRequest = nil

        isListening = false

        // Fire final callback with saved text
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onTranscriptReady?(trimmed)
        }

        // Cleanup task reference after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.recognitionTask = nil
        }
    }
}
