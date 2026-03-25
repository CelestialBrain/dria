//
//  AnalysisResult.swift
//  dria
//

import Foundation

struct AnalysisResult: Codable {
    let type: String          // TRUE_FALSE, IDENTIFICATION, MULTIPLE_CHOICE, ESSAY
    let answer: String
    let question: String
    let questionSummary: String  // 3 words
    let answerSummary: String    // 3 words (full for ESSAY)

    /// Marquee-friendly display: "questionSummary = answerSummary"
    var marqueeText: String {
        "\(questionSummary) = \(answerSummary)"
    }

    /// Parse an AnalysisResult from AI response text, with robust fallback.
    static func parse(from text: String) -> AnalysisResult? {
        let cleaned = extractJSON(from: text)
        guard !cleaned.isEmpty else { return nil }

        // Try JSONDecoder first
        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) {
            return result
        }

        // Try JSONSerialization (more lenient)
        if let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let answer = json["answer"] as? String {
            return AnalysisResult(
                type: json["type"] as? String ?? "IDENTIFICATION",
                answer: answer,
                question: json["question"] as? String ?? "",
                questionSummary: json["questionSummary"] as? String ?? "",
                answerSummary: json["answerSummary"] as? String ?? answer
            )
        }

        return nil
    }

    /// Extract JSON object from various AI response formats
    private static func extractJSON(from text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find first { and last } — extract the JSON object
        if let start = s.firstIndex(of: "{"),
           let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }

        return ""
    }
}
