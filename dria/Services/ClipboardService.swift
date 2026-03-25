//
//  ClipboardService.swift
//  dria
//

import AppKit

@MainActor
final class ClipboardService {
    var isMonitoring: Bool = false
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    var detector = QuestionDetector()

    /// Set to true before writing to clipboard programmatically — skips next detection
    var skipNextChange: Bool = false

    var onQuestionDetected: ((DetectedQuestion, String) -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = NSPasteboard.general.changeCount

        timer?.invalidate() // Always invalidate old timer first
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let current = NSPasteboard.general.changeCount
            guard current != self.lastChangeCount else { return }
            self.lastChangeCount = current

            // Skip if we wrote to clipboard ourselves
            if self.skipNextChange {
                self.skipNextChange = false
                return
            }

            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }

            if let question = self.detector.detect(from: text),
               question.confidence >= self.detector.sensitivity.minConfidence {
                self.onQuestionDetected?(question, text)
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }

    func readCurrentClipboard() -> (text: String?, image: NSImage?) {
        let pb = NSPasteboard.general
        if let text = pb.string(forType: .string), !text.isEmpty {
            return (text, nil)
        }
        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: imageData) {
            return (nil, image)
        }
        return (nil, nil)
    }

    func detectQuestion(from text: String) -> DetectedQuestion? {
        detector.detect(from: text)
    }

}
