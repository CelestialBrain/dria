//
//  StudyMode.swift
//  dria
//

import Foundation

struct StudyMode: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var iconName: String            // SF Symbol name
    var colorHex: String            // e.g., "5E5CE6"
    var systemPrompt: String?       // custom AI instructions, nil = use default
    var keywords: [String]          // for auto-detection from window title
    var isBuiltIn: Bool
    var createdAt: Date
    var files: [ModeFile]

    var directoryName: String { id.uuidString }

    static let general = StudyMode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "General",
        iconName: "sparkles",
        colorHex: "8E8E93",
        systemPrompt: nil,
        keywords: [],
        isBuiltIn: true,
        createdAt: .distantPast,
        files: []
    )

    static let llawBuiltInId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func llawBuiltIn() -> StudyMode {
        StudyMode(
            id: llawBuiltInId,
            name: "LLAW 113",
            iconName: "scale.3d",
            colorHex: "5E5CE6",
            systemPrompt: """
            You are DRIA, specializing in Philippine Obligations and Contracts (ObliCon) \
            under the Civil Code of the Philippines (Arts. 1156-1422).

            ANSWER FORMAT (Atty. Aguila's rubric — this is how the student will be graded):
            1. STATE THE RULE FIRST (40% of grade) — begin with the governing Civil Code article, \
            legal principle, or doctrine. Cite the article number and case name with G.R. number.
            2. APPLY TO THE FACTS (30%) — show how the rule applies to the specific situation given. \
            Do not stop at definitions.
            3. BE PRECISE AND CLEAR (20%) — use correct legal terms, structure your answer logically. \
            A direct, disciplined answer beats a long unfocused one.
            4. ANTICIPATE FOLLOW-UPS (10%) — distinguish related concepts, note exceptions.

            RULES:
            - Reference the 34 Supreme Court case digests in your knowledge base
            - For multiple choice: answer letter FIRST, then explain using the format above
            - For true/false: state TRUE or FALSE first, then the rule
            - For essay/oral: full IRAC using the rubric weights above
            - Be concise — the student needs quick answers during an exam
            - Do NOT use markdown formatting (no **, ##, or * bullets). Plain text only.
            """,
            keywords: ["llaw", "oblicon", "obligations", "contracts", "civil code", "civil law"],
            isBuiltIn: true,
            createdAt: .distantPast,
            files: []
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: StudyMode, rhs: StudyMode) -> Bool {
        lhs.id == rhs.id
    }
}
