//
//  KnowledgeBaseService.swift
//  dria
//

import Foundation

struct KnowledgeContext {
    let relevantChunks: [KnowledgeChunk]
    let sourceFiles: [String]
    let contextString: String
}

final class KnowledgeBaseService: Sendable {
    let chunks: [KnowledgeChunk]

    init(chunks: [KnowledgeChunk] = []) {
        self.chunks = chunks
    }

    func buildContext(for query: String, topK: Int = 8) -> KnowledgeContext {
        guard !chunks.isEmpty else {
            return KnowledgeContext(relevantChunks: [], sourceFiles: [], contextString: "")
        }

        let relevant = selectRelevantChunks(for: query, topK: topK)
        let sourceFiles = Array(Set(relevant.map(\.sourceFileName))).sorted()

        let contextString = relevant.map { chunk in
            "--- Source: \(chunk.sourceFileName) (chunk \(chunk.chunkIndex)) ---\n\(chunk.content)"
        }.joined(separator: "\n\n")

        return KnowledgeContext(
            relevantChunks: relevant,
            sourceFiles: sourceFiles,
            contextString: "=== KNOWLEDGE BASE ===\n\n\(contextString)"
        )
    }

    private func selectRelevantChunks(for query: String, topK: Int) -> [KnowledgeChunk] {
        let stopWords: Set<String> = [
            "the", "and", "for", "are", "but", "not", "you", "all", "can",
            "had", "her", "was", "one", "our", "out", "has", "his", "how",
            "its", "may", "who", "did", "get", "let", "say", "she", "too",
            "use", "what", "this", "that", "with", "from", "have", "they",
            "been", "said", "each", "which", "their", "will", "other"
        ]

        let queryTokens = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        guard !queryTokens.isEmpty else {
            return Array(chunks.prefix(topK))
        }

        let scored: [(KnowledgeChunk, Int)] = chunks.map { chunk in
            var score = 0
            for token in queryTokens {
                for keyword in chunk.keywords where keyword.contains(token) || token.contains(keyword) {
                    score += 1
                }
            }
            return (chunk, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map(\.0)
    }
}
