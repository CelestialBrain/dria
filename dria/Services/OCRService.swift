//
//  OCRService.swift
//  dria
//

import AppKit
import Vision

struct OCRService {
    /// Hard cap so a noisy OCR can't push the chat into a layout spin.
    static let maxOutputChars = 8000

    /// Collapse OCR junk: long whitespace runs, useless 1-char lines, blank-line storms.
    /// Conservative — keeps actual content, just trims layout-toxic patterns.
    static func cleanup(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        // Drop lines that are 1-2 chars of punctuation / orphan glyphs.
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true } // keep blanks for collapse step below
            if trimmed.count <= 2 {
                // Keep only if it has at least one alphanumeric
                return trimmed.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
            }
            return true
        }

        // Collapse runs of 3+ blank lines to 1 blank.
        var result: [String] = []
        var blankRun = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankRun += 1
                if blankRun <= 1 { result.append("") }
            } else {
                blankRun = 0
                result.append(line)
            }
        }
        var joined = result.joined(separator: "\n")

        // Cap overall length — extreme captures stay capped to keep layout sane.
        if joined.count > maxOutputChars {
            joined = String(joined.prefix(maxOutputChars)) + "\n…[truncated by dria]"
        }
        return joined
    }

    /// Recognize text from an image using Apple's Vision framework
    func recognizeText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            let request = VNRecognizeTextRequest { request, error in
                guard !hasResumed else { return } // Prevent double resume
                hasResumed = true

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let raw = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: Self.cleanup(raw))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard !hasResumed else { return } // Prevent double resume
                hasResumed = true
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not convert image for text recognition."
        }
    }
}
