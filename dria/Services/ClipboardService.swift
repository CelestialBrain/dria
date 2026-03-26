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
        let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif", "webp"])

        // 1. Ask NSPasteboard to give us an NSImage directly — handles ALL sources
        //    (screenshots, Clop, Preview, Finder, drag, any app)
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            return (nil, image)
        }

        // 2. Fallback: raw image data
        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: imageData) {
            return (nil, image)
        }

        // 3. Check for file URL pasteboard type (Finder copy, etc.)
        if let fileURL = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])?.first as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if imageExtensions.contains(ext), let image = NSImage(contentsOf: fileURL) {
                return (nil, image)
            }
        }

        // 3. Check for file path as plain text
        if let text = pb.string(forType: .string), !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isFilePath = trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") || trimmed.hasPrefix("~")
            if isFilePath {
                var cleanPath = trimmed
                if cleanPath.hasPrefix("file://") {
                    cleanPath = URL(string: cleanPath)?.path ?? cleanPath
                }
                if cleanPath.hasPrefix("~") {
                    cleanPath = (cleanPath as NSString).expandingTildeInPath
                }
                let ext = (cleanPath as NSString).pathExtension.lowercased()
                if imageExtensions.contains(ext),
                   FileManager.default.fileExists(atPath: cleanPath),
                   let image = NSImage(contentsOfFile: cleanPath) {
                    return (nil, image)
                }
            }

            // If it was a file path but file doesn't exist or isn't an image, don't send path as text
            if isFilePath {
                return (nil, nil)
            }

            // Regular text
            return (text, nil)
        }

        return (nil, nil)
    }

    func detectQuestion(from text: String) -> DetectedQuestion? {
        detector.detect(from: text)
    }

}
