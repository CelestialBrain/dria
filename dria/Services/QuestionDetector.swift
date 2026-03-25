//
//  QuestionDetector.swift
//  dria
//
//  Detects exam questions from clipboard text or OCR output.
//  Only fires on HIGH-confidence matches to avoid false positives.

import Foundation

enum QuestionType: String, Codable {
    case multipleChoice = "MULTIPLE_CHOICE"
    case trueFalse = "TRUE_FALSE"
    case identification = "IDENTIFICATION"
    case essay = "ESSAY"
    case unknown = "UNKNOWN"

    var label: String {
        switch self {
        case .multipleChoice: return "MC"
        case .trueFalse: return "T/F"
        case .identification: return "ID"
        case .essay: return "Essay"
        case .unknown: return "?"
        }
    }
}

struct DetectedQuestion {
    let type: QuestionType
    let stem: String
    let options: [String]
    let rawText: String
    let confidence: Double
}

struct QuestionDetector {

    /// Minimum confidence to report a detection (0.0–1.0)
    static let minConfidence: Double = 0.7

    // MARK: - Public

    func detect(from text: String) -> DetectedQuestion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else { return nil }  // Too short to be a real question
        guard trimmed.count < 5000 else { return nil } // Too long — probably a document, not a question

        // Try each detector in priority order (most specific first)
        if let tf = detectTrueFalse(trimmed) { return tf }
        if let mc = detectMultipleChoice(trimmed) { return mc }
        if let id = detectIdentification(trimmed) { return id }
        if let essay = detectEssay(trimmed) { return essay }

        // Do NOT return unknown — too many false positives
        return nil
    }

    /// Configurable exam URL patterns
    var examURLPatterns: [String] = [
        "instructure.com",       // Canvas LMS
        "docs.google.com/forms", // Google Forms
        "quizizz.com",
        "kahoot.it",
        "schoology.com",
        "blackboard.com",
    ]

    func isExamURL(_ url: String) -> Bool {
        examURLPatterns.contains(where: { url.lowercased().contains($0) })
    }

    // MARK: - True/False Detection (HIGH specificity)

    private func detectTrueFalse(_ text: String) -> DetectedQuestion? {
        let lower = text.lowercased()

        // Must have explicit "True or False" prefix
        let tfPrefixes = ["true or false:", "true or false."]
        for prefix in tfPrefixes {
            if lower.hasPrefix(prefix) || lower.contains("\n\(prefix)") {
                let stem = extractStemAfterPrefix(text, prefix: prefix)
                let options = extractTFOptions(text)
                return DetectedQuestion(type: .trueFalse, stem: stem, options: options, rawText: text, confidence: 0.95)
            }
        }

        // Pattern: statement + exactly "True" and "False" as standalone option lines
        let lines = nonEmptyLines(text)
        let tfOptions = lines.filter { line in
            let l = line.lowercased().trimmingCharacters(in: .whitespaces)
            return l == "true" || l == "false" || l == "it depends" || l == "it depends on the moral duty."
                || l == "depends on the kind of estoppel."
        }
        // Need both True AND False present as options, plus a stem
        let hasTrue = tfOptions.contains(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "true" })
        let hasFalse = tfOptions.contains(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "false" })
        if hasTrue && hasFalse && lines.count > tfOptions.count {
            let stem = lines.filter { !tfOptions.contains($0) }.joined(separator: " ")
            return DetectedQuestion(type: .trueFalse, stem: stem, options: tfOptions, rawText: text, confidence: 0.9)
        }

        return nil
    }

    // MARK: - Multiple Choice Detection (HIGH specificity)

    private func detectMultipleChoice(_ text: String) -> DetectedQuestion? {
        let lines = nonEmptyLines(text)

        // Pattern 1: Lettered options — A) B) C) D) or A. B. C. D. or a) b) c) d)
        let letterPattern = #"^[A-Da-d][\.\)\:]\s"#
        let letteredOptions = lines.filter { $0.range(of: letterPattern, options: .regularExpression) != nil }
        if letteredOptions.count >= 3 {
            let stem = lines.filter { !letteredOptions.contains($0) }.joined(separator: " ")
            return DetectedQuestion(type: .multipleChoice, stem: stem, options: letteredOptions, rawText: text, confidence: 0.95)
        }

        // Pattern 2: Canvas-style — question stem followed by 3-6 short option lines
        // STRICT: the stem must look like a question (ends with ? or contains question words)
        // AND the options must be clearly distinct short phrases
        if lines.count >= 4 && lines.count <= 10 {
            // First line(s) = stem, remaining = options
            // Find where stem ends: the longest line or line with ? is the stem
            let stemEnd = lines.firstIndex(where: { line in
                line.contains("?") || line.hasSuffix(":") || line.hasSuffix(".")
                    || line.lowercased().hasPrefix("this is")
            }) ?? 0

            let stemLines = Array(lines[0...stemEnd])
            let optionLines = Array(lines[(stemEnd + 1)...])

            guard optionLines.count >= 3 && optionLines.count <= 6 else { return nil }

            // Options must be short (< 100 chars each) and NOT look like paragraphs
            let allShort = optionLines.allSatisfy { $0.count < 100 && $0.count > 1 }
            guard allShort else { return nil }

            // Options must not all be very long (that's just paragraphs)
            let avgLen = optionLines.reduce(0) { $0 + $1.count } / max(optionLines.count, 1)
            guard avgLen < 80 else { return nil }

            // Stem must be longer than average option (question is usually longer than choices)
            let stemText = stemLines.joined(separator: " ")
            guard stemText.count > avgLen else { return nil }

            return DetectedQuestion(
                type: .multipleChoice,
                stem: stemText,
                options: optionLines,
                rawText: text,
                confidence: 0.75
            )
        }

        return nil
    }

    // MARK: - Identification Detection (STRICT)

    private func detectIdentification(_ text: String) -> DetectedQuestion? {
        // Only match if text has blank/fill patterns OR very specific phrasing
        if text.contains("___") || text.contains("______") {
            return DetectedQuestion(type: .identification, stem: text, options: [], rawText: text, confidence: 0.85)
        }

        let lower = text.lowercased()

        // These are very specific exam phrases — not generic "what is"
        let strictKeywords = [
            "this is known as", "this is called", "identify the",
            "name the", "the term for", "fill in the blank",
            "what do you call", "this is an example of",
        ]

        for keyword in strictKeywords {
            if lower.contains(keyword) {
                return DetectedQuestion(type: .identification, stem: text, options: [], rawText: text, confidence: 0.75)
            }
        }

        return nil
    }

    // MARK: - Essay Detection (STRICT)

    private func detectEssay(_ text: String) -> DetectedQuestion? {
        let lower = text.lowercased()
        guard text.count > 80 else { return nil } // Essays are prompted with longer text

        // Must START with an imperative exam instruction
        let essayStarters = [
            "explain ", "discuss ", "distinguish ", "compare and contrast",
            "write a", "give an example", "in your own words",
            "elaborate on", "analyze the", "describe how",
        ]

        for starter in essayStarters {
            if lower.hasPrefix(starter) {
                return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.8)
            }
        }

        // Or contains exam-specific phrasing
        let examPhrases = [
            "your answer must", "using the irac method", "cite the relevant",
            "apply the rule", "state the legal", "under the civil code",
        ]

        for phrase in examPhrases {
            if lower.contains(phrase) {
                return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.85)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func nonEmptyLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func extractStemAfterPrefix(_ text: String, prefix: String) -> String {
        let lower = text.lowercased()
        guard let range = lower.range(of: prefix) else { return text }
        let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = nonEmptyLines(after)
        // Stem = first non-option line
        return lines.first(where: { line in
            let l = line.lowercased()
            return l != "true" && l != "false" && !l.hasPrefix("it depends")
        }) ?? after
    }

    private func extractTFOptions(_ text: String) -> [String] {
        nonEmptyLines(text).filter { line in
            let l = line.lowercased().trimmingCharacters(in: .whitespaces)
            return l == "true" || l == "false" || l.hasPrefix("it depends") || l.hasPrefix("depends on")
        }
    }
}
