//
//  VoiceInputService.swift
//  dria
//
//  Pre-warmed speech transcription using Spokestack's prepare/activate pattern.
//  Audio engine is prepared at launch so startListening() is near-instant.

import AppKit
import Speech
import ScreenCaptureKit

enum AudioSource: String, CaseIterable {
    case mic = "Microphone"
    case desktop = "Desktop Audio"
    case both = "Mic + Desktop"
}

@MainActor
final class VoiceInputService: NSObject {
    var isListening: Bool = false
    var transcript: String = ""
    var onTranscriptReady: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var audioSource: AudioSource = .mic
    var permissionGranted = false
    var prefixText: String = ""

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var committedText: String = ""  // Finalized segments that won't change
    private var isPrepared = false

    // ScreenCaptureKit
    private var scStream: SCStream?
    private var scOutput: AudioStreamOutput?

    static let supportedLanguages: [(id: String, name: String)] = [
        ("en-US", "English"), ("fil-PH", "Filipino"), ("es-ES", "Spanish"),
        ("fr-FR", "French"), ("de-DE", "German"), ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"), ("zh-CN", "Chinese (Simplified)"),
        ("pt-BR", "Portuguese"), ("it-IT", "Italian"),
    ]

    override init() {
        super.init()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func setLanguage(_ localeId: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))
    }

    // MARK: - Permission (call once, result cached)

    func requestPermission() async -> Bool {
        if permissionGranted { return true }

        let speechOk = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micOk: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micOk = true
        case .notDetermined: micOk = await AVCaptureDevice.requestAccess(for: .audio)
        default: micOk = false
        }
        permissionGranted = speechOk && micOk
        return permissionGranted
    }

    // MARK: - Pre-warm (call after permission granted)

    /// Pre-warm flag — engine will be prepared on first use
    func prepareEngine() {
        // Don't call audioEngine.prepare() here — it crashes if no nodes connected.
        // Engine will be prepared inline in startMic() after tap is installed.
        isPrepared = true
    }

    // MARK: - Start (instant if pre-warmed)

    func startListening() {
        print("[VOICE] startListening called")
        print("[VOICE]   recognizer=\(recognizer != nil), available=\(recognizer?.isAvailable ?? false)")
        print("[VOICE]   permission=\(permissionGranted), isPrepared=\(isPrepared)")
        print("[VOICE]   audioSource=\(audioSource.rawValue), prefixText='\(prefixText)'")
        guard let recognizer, recognizer.isAvailable else { print("[VOICE] BAIL: no recognizer"); return }
        guard permissionGranted else { print("[VOICE] BAIL: no permission"); return }

        // Clean up any previous session
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)

        isListening = true
        transcript = ""
        committedText = ""

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            isListening = false
            return
        }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // On-device for English only
        if recognizer.supportsOnDeviceRecognition && recognizer.locale.identifier.hasPrefix("en") {
            request.requiresOnDeviceRecognition = true
        }

        // Start audio source
        switch audioSource {
        case .mic: startMic(request: request)
        case .desktop: Task { await startDesktop(request: request) }
        case .both:
            startMic(request: request)
            Task { await startDesktop(request: request) }
        }

        // Start recognition
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening else { return }
                if let result {
                    let current = result.bestTranscription.formattedString
                    let isFinal = result.isFinal

                    if isFinal {
                        self.committedText += (self.committedText.isEmpty ? "" : " ") + current
                        self.transcript = self.committedText
                        print("[VOICE] FINAL: '\(current)' → committed='\(self.committedText)'")
                    } else {
                        self.transcript = self.committedText.isEmpty
                            ? current
                            : self.committedText + " " + current
                        print("[VOICE] PARTIAL: '\(current)' → transcript='\(self.transcript)'")
                    }
                    self.onPartialTranscript?(self.transcript)
                }
                if let error {
                    print("[VOICE] RECOGNITION ERROR: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Mic

    private func startMic(request: SFSpeechAudioBufferRecognitionRequest) {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        if !isPrepared { audioEngine.prepare(); isPrepared = true }

        do {
            try audioEngine.start()
            print("[VOICE] Engine started OK, sampleRate=\(format.sampleRate), channels=\(format.channelCount)")
        } catch {
            print("[VOICE] Engine start FAILED: \(error)")
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    // MARK: - Desktop Audio

    private func startDesktop(request: SFSpeechAudioBufferRecognitionRequest) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 1

            let output = AudioStreamOutput(request: request)
            scOutput = output

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
            try await stream.startCapture()
            scStream = stream
        } catch {
            // Desktop capture failed silently — mic still works
        }
    }

    // MARK: - Stop

    func stopListening() {
        print("[VOICE] stopListening called, isListening=\(isListening), committed='\(committedText)', transcript='\(transcript)'")
        guard isListening else { print("[VOICE] BAIL: not listening"); return }

        recognitionRequest?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        if let stream = scStream {
            Task { try? await stream.stopCapture() }
            scStream = nil
            scOutput = nil
        }

        recognitionTask?.finish()
        recognitionRequest = nil
        isListening = false

        // Don't fire onTranscriptReady — text is already in the field from onPartialTranscript
        // This prevents duplication

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.recognitionTask = nil
        }
    }
}

// MARK: - ScreenCaptureKit Audio Bridge

private class AudioStreamOutput: NSObject, SCStreamOutput {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer),
              let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        // Create AVAudioFormat matching the sample buffer
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            channels: AVAudioChannelCount(asbd.mChannelsPerFrame),
            interleaved: true
        ) else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy audio data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let src = dataPointer, let dst = pcmBuffer.floatChannelData?[0] else { return }

        let byteCount = min(length, Int(frameCount) * MemoryLayout<Float>.size)
        memcpy(dst, src, byteCount)

        request.append(pcmBuffer)
    }
}
