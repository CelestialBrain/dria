//
//  QuestionDetector.swift
//  dria
//
//  Detects exam questions from clipboard text or OCR output.
//  Three sensitivity modes: Normal, Sensitive, Catch-All

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

enum DetectionSensitivity: String, Codable {
    case normal = "normal"       // Default — balanced, some false positives
    case sensitive = "sensitive"  // Aggressive — catches more, more false positives
    case catchAll = "catchAll"   // Everything >20 chars gets sent to AI

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .sensitive: return "Sensitive"
        case .catchAll: return "Catch All"
        }
    }

    var description: String {
        switch self {
        case .normal: return "Balanced detection. Catches most exam questions."
        case .sensitive: return "Aggressive. Catches almost anything that looks like a question."
        case .catchAll: return "Send EVERYTHING you copy to AI. No filtering."
        }
    }

    var minConfidence: Double {
        switch self {
        case .normal: return 0.6
        case .sensitive: return 0.3
        case .catchAll: return 0.0
        }
    }

    var minLength: Int {
        switch self {
        case .normal: return 30
        case .sensitive: return 20
        case .catchAll: return 10
        }
    }
}

struct QuestionDetector {

    var sensitivity: DetectionSensitivity = .normal

    // MARK: - Public

    func detect(from text: String) -> DetectedQuestion? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown formatting
        trimmed = trimmed.replacingOccurrences(of: "**", with: "")
        trimmed = trimmed.replacingOccurrences(of: "__", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
        trimmed = trimmed.replacingOccurrences(of: "##", with: "")

        guard trimmed.count >= sensitivity.minLength else { return nil }
        guard trimmed.count < 10000 else { return nil }

        // Catch-All mode: send everything
        if sensitivity == .catchAll {
            return DetectedQuestion(type: .unknown, stem: trimmed, options: [], rawText: trimmed, confidence: 1.0)
        }

        // Try each detector in priority order
        if let tf = detectTrueFalse(trimmed) { return tf }
        if let mc = detectMultipleChoice(trimmed) { return mc }
        if let id = detectIdentification(trimmed) { return id }
        if let essay = detectEssay(trimmed) { return essay }
        if let generic = detectGenericQuestion(trimmed) { return generic }

        return nil
    }

    var examURLPatterns: [String] = [
        "instructure.com", "docs.google.com/forms", "quizizz.com",
        "kahoot.it", "schoology.com", "blackboard.com", "moodle",
    ]

    func isExamURL(_ url: String) -> Bool {
        examURLPatterns.contains(where: { url.lowercased().contains($0) })
    }

    // MARK: - True/False

    private func detectTrueFalse(_ text: String) -> DetectedQuestion? {
        let lower = text.lowercased()

        // "True or False:" prefix
        let tfPrefixes = ["true or false:", "true or false.", "true or false -", "t or f:"]
        for prefix in tfPrefixes {
            if lower.hasPrefix(prefix) || lower.contains("\n\(prefix)") {
                let stem = extractStemAfterPrefix(text, prefix: prefix)
                let options = extractTFOptions(text)
                return DetectedQuestion(type: .trueFalse, stem: stem, options: options, rawText: text, confidence: 0.95)
            }
        }

        // Options are "True" and "False" on separate lines
        let lines = nonEmptyLines(text)
        let tfOptions = lines.filter { line in
            let l = line.lowercased().trimmingCharacters(in: .whitespaces)
            return l == "true" || l == "false" || l.hasPrefix("it depends") || l.hasPrefix("depends on")
        }
        let hasTrue = tfOptions.contains(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "true" })
        let hasFalse = tfOptions.contains(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "false" })
        if hasTrue && hasFalse && lines.count > tfOptions.count {
            let stem = lines.filter { !tfOptions.contains($0) }.joined(separator: " ")
            return DetectedQuestion(type: .trueFalse, stem: stem, options: tfOptions, rawText: text, confidence: 0.9)
        }

        return nil
    }

    // MARK: - Multiple Choice

    private func detectMultipleChoice(_ text: String) -> DetectedQuestion? {
        let lines = nonEmptyLines(text)

        // Lettered options: A) B) C) D) or A. B. C. or a) b) c)
        let letterPattern = #"^[A-Ea-e][\.\)\:]\s"#
        let letteredOptions = lines.filter { $0.range(of: letterPattern, options: .regularExpression) != nil }
        if letteredOptions.count >= 2 {
            let stem = lines.filter { !letteredOptions.contains($0) }.joined(separator: " ")
            return DetectedQuestion(type: .multipleChoice, stem: stem, options: letteredOptions, rawText: text, confidence: 0.95)
        }

        // Numbered options: 1) 2) 3) or 1. 2. 3.
        let numberPattern = #"^[1-5][\.\)\:]\s"#
        let numberedOptions = lines.filter { $0.range(of: numberPattern, options: .regularExpression) != nil }
        if numberedOptions.count >= 3 {
            let stem = lines.filter { !numberedOptions.contains($0) }.joined(separator: " ")
            return DetectedQuestion(type: .multipleChoice, stem: stem, options: numberedOptions, rawText: text, confidence: 0.85)
        }

        // Canvas-style: question + short option lines
        if lines.count >= 4 && lines.count <= 12 {
            let stemEnd = lines.firstIndex(where: { line in
                line.contains("?") || line.hasSuffix(":") || line.hasSuffix(".")
                    || line.lowercased().hasPrefix("this is") || line.lowercased().hasPrefix("the answer is")
            }) ?? 0

            let stemLines = Array(lines[0...stemEnd])
            let optionLines = Array(lines[(stemEnd + 1)...])

            guard optionLines.count >= 2 && optionLines.count <= 8 else { return nil }

            let allShort = optionLines.allSatisfy { $0.count < 120 && $0.count > 1 }
            guard allShort else { return nil }

            let avgLen = optionLines.reduce(0) { $0 + $1.count } / max(optionLines.count, 1)
            guard avgLen < 100 else { return nil }

            let stemText = stemLines.joined(separator: " ")

            return DetectedQuestion(
                type: .multipleChoice,
                stem: stemText,
                options: optionLines,
                rawText: text,
                confidence: 0.7
            )
        }

        return nil
    }

    // MARK: - Identification

    private func detectIdentification(_ text: String) -> DetectedQuestion? {
        if text.contains("___") || text.contains("______") || text.contains("________") {
            return DetectedQuestion(type: .identification, stem: text, options: [], rawText: text, confidence: 0.85)
        }

        let lower = text.lowercased()

        let keywords = [
            "this is known as", "this is called", "identify the", "name the",
            "the term for", "fill in the blank", "what do you call",
            "this is an example of", "what is the term", "give the term",
            "what type of", "what kind of", "what form of",
            "this refers to", "this pertains to",
        ]

        for keyword in keywords {
            if lower.contains(keyword) {
                return DetectedQuestion(type: .identification, stem: text, options: [], rawText: text, confidence: 0.75)
            }
        }

        // Sensitive mode: "what is" / "define"
        if sensitivity == .sensitive {
            let sensitiveKeywords = ["what is ", "define ", "what are "]
            for keyword in sensitiveKeywords {
                if lower.hasPrefix(keyword) || lower.contains("\n\(keyword)") {
                    return DetectedQuestion(type: .identification, stem: text, options: [], rawText: text, confidence: 0.5)
                }
            }
        }

        return nil
    }

    // MARK: - Essay

    private func detectEssay(_ text: String) -> DetectedQuestion? {
        let lower = text.lowercased()
        guard text.count > 50 else { return nil }

        // Starts with imperative instruction
        let essayStarters = [
            "explain", "discuss", "distinguish", "compare and contrast", "compare",
            "write a", "give an example", "in your own words", "elaborate",
            "analyze", "describe", "state the", "enumerate", "differentiate",
            "what are the elements", "what are the requisites", "provide",
        ]

        for starter in essayStarters {
            if lower.hasPrefix(starter) {
                return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.8)
            }
        }

        // Contains exam-specific phrasing
        let examPhrases = [
            "your answer must", "using the irac method", "cite the relevant",
            "apply the rule", "state the legal", "under the civil code",
            "is your obligation", "are you liable", "who should pay",
            "what is the effect", "what are the rights", "what remedy",
            "is the contract", "can the creditor", "can the debtor",
            "explain your answer", "justify your answer", "support your answer",
            "discuss the", "distinguish between", "what is the difference",
            "how would you", "in this case", "given the facts",
            "under philippine law", "according to the civil code",
            "what article", "which article", "cite the provision",
            "is there a breach", "was there a valid", "does the obligation",
            "may the obligor", "may the obligee", "is the debtor",
        ]

        for phrase in examPhrases {
            if lower.contains(phrase) {
                return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.8)
            }
        }

        // Text ending with ? (>60 chars = likely a real question)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") && trimmed.count > 60 {
            return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.7)
        }

        // Sensitive mode: shorter questions with ?
        if sensitivity == .sensitive && trimmed.hasSuffix("?") && trimmed.count > 20 {
            return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.5)
        }

        return nil
    }

    // MARK: - Generic Question (catch-more)

    private func detectGenericQuestion(_ text: String) -> DetectedQuestion? {
        let lower = text.lowercased()
        guard text.count > 40 else { return nil }

        // Question words at start
        let questionStarters = [
            "what ", "how ", "why ", "when ", "which ", "who ",
            "is ", "are ", "does ", "can ", "should ", "would ",
            "do you agree", "is it true", "is it correct",
        ]

        for starter in questionStarters {
            if lower.hasPrefix(starter) {
                let conf: Double = sensitivity == .sensitive ? 0.5 : 0.6
                return DetectedQuestion(type: .unknown, stem: text, options: [], rawText: text, confidence: conf)
            }
        }

        // Contains a question mark anywhere
        if text.contains("?") && text.count > 50 {
            let conf: Double = sensitivity == .sensitive ? 0.4 : 0.55
            return DetectedQuestion(type: .unknown, stem: text, options: [], rawText: text, confidence: conf)
        }

        // Sensitive mode: any substantial text that looks academic
        if sensitivity == .sensitive && text.count > 80 {
            let academicWords = ["obligation", "contract", "article", "provision", "doctrine",
                                "liable", "breach", "damages", "creditor", "debtor", "remedy",
                                "law", "court", "legal", "rights", "civil code", "rule"]
            let matchCount = academicWords.filter { lower.contains($0) }.count
            if matchCount >= 2 {
                return DetectedQuestion(type: .essay, stem: text, options: [], rawText: text, confidence: 0.5)
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
