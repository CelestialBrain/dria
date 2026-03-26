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

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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
    }

    func setLanguage(_ localeId: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    /// Request permission (one-time)
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start listening — call when hotkey pressed
    func startListening() {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        // Use on-device if available
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        transcript = ""
        isListening = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopListening()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    // Don't auto-stop — wait for user to release hotkey
                }
            }
        }
    }

    /// Stop listening — call when hotkey released. Returns final transcript.
    func stopListening() {
        guard isListening else { return }
        isListening = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty {
            onTranscriptReady?(final)
        }
    }
}
