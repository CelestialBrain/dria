//
//  EmbeddingService.swift
//  dria
//
//  Local, offline sentence embeddings via Apple's NLEmbedding.
//  No API key required — works for every AI provider.
//

import Foundation
import NaturalLanguage
import CryptoKit

struct LocalEmbedder {
    let embedding: NLEmbedding

    /// Pick an embedding for a language code like "en-US", "tl-PH", "es-ES".
    /// Falls back to English then to any available sentence embedding.
    static func make(languageCode: String) -> LocalEmbedder? {
        let lang = NLLanguage(rawValue: String(languageCode.prefix(2)))
        if let emb = NLEmbedding.sentenceEmbedding(for: lang) {
            return LocalEmbedder(embedding: emb)
        }
        if let emb = NLEmbedding.sentenceEmbedding(for: .english) {
            return LocalEmbedder(embedding: emb)
        }
        return nil
    }

    func embed(_ text: String) -> [Float]? {
        guard let vector = embedding.vector(for: text) else {
            // NLEmbedding returns nil for very short/empty strings — fall back to averaging word vectors.
            return averagedWordVector(for: text)
        }
        return vector.map { Float($0) }
    }

    /// Fallback when sentenceEmbedding can't produce a vector — average per-word vectors.
    private func averagedWordVector(for text: String) -> [Float]? {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        let dim = embedding.dimension
        var sum = [Double](repeating: 0, count: dim)
        var hits = 0
        for w in words {
            if let v = embedding.vector(for: w) {
                for i in 0..<dim { sum[i] += v[i] }
                hits += 1
            }
        }
        guard hits > 0 else { return nil }
        return sum.map { Float($0 / Double(hits)) }
    }

    func embed(batch texts: [String]) -> [[Float]?] {
        texts.map { embed($0) }
    }
}

/// Cosine similarity between two equal-length vectors.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = sqrt(normA) * sqrt(normB)
    return denom > 0 ? dot / denom : 0
}

/// Stable hash of content (for cache keys).
func contentHash(_ text: String) -> String {
    let data = Data(text.utf8)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}
