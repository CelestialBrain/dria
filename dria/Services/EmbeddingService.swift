//
//  EmbeddingService.swift
//  dria
//
//  Local, offline sentence embeddings. Prefers Apple's NLContextualEmbedding
//  (macOS 14+) — a real transformer with multi-script support and stronger
//  retrieval quality. Falls back to NLEmbedding.sentenceEmbedding for any
//  language NLContextualEmbedding doesn't ship for.
//
//  No API key, no network at query time. NLContextualEmbedding may download
//  language assets on first use; we trigger that lazily through
//  prepareEmbeddings.
//
//  Cache compatibility: the on-disk embeddings cache is keyed by SHA-256 of
//  content. When this file ships a different backend or dimension, the
//  cached vectors are silently incompatible. We protect against that by
//  storing the backend identifier alongside each entry (see EmbeddingsCache).
//

import Foundation
import NaturalLanguage
import CryptoKit

struct LocalEmbedder: Sendable {
    enum Backend: Sendable {
        case contextual(any NSObjectProtocol & Sendable)  // NLContextualEmbedding, opaque so we can keep the struct Sendable
        case sentence(NLEmbedding)
    }

    let backend: Backend
    /// Identifier baked into cache keys so a backend swap invalidates old vectors.
    let backendID: String
    /// Vector dimension (used to validate cache reads).
    let dimension: Int

    // MARK: - Construction

    /// Try to build the best embedder for the given language. Async because
    /// NLContextualEmbedding may need to download language assets.
    static func make(languageCode: String) async -> LocalEmbedder? {
        let twoLetter = String(languageCode.prefix(2))
        let lang = NLLanguage(rawValue: twoLetter)

        if #available(macOS 14, *) {
            if let ctx = await loadContextual(language: lang) ?? loadContextualIfReady(.english) {
                return LocalEmbedder(
                    backend: .contextual(ctx),
                    backendID: "nlctx-\(ctx.modelIdentifier ?? "unknown")",
                    dimension: ctx.dimension
                )
            }
        }

        if let emb = NLEmbedding.sentenceEmbedding(for: lang)
            ?? NLEmbedding.sentenceEmbedding(for: .english) {
            return LocalEmbedder(
                backend: .sentence(emb),
                backendID: "nlemb-sentence-\(emb.dimension)",
                dimension: emb.dimension
            )
        }
        return nil
    }

    @available(macOS 14, *)
    private static func loadContextualIfReady(_ language: NLLanguage) -> NLContextualEmbedding? {
        guard let ctx = NLContextualEmbedding(language: language),
              ctx.hasAvailableAssets else { return nil }
        do {
            try ctx.load()
            return ctx
        } catch {
            return nil
        }
    }

    @available(macOS 14, *)
    private static func loadContextual(language: NLLanguage?) async -> NLContextualEmbedding? {
        guard let language, let ctx = NLContextualEmbedding(language: language) else { return nil }
        if ctx.hasAvailableAssets {
            do { try ctx.load(); return ctx } catch { return nil }
        }
        // Request the assets — Apple downloads them in the background.
        // The call returns immediately; we only attempt to load when ready.
        do {
            let status = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NLContextualEmbedding.AssetsResult, Error>) in
                ctx.requestAssets { result, error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: result)
                }
            }
            guard status == .available else { return nil }
            try ctx.load()
            return ctx
        } catch {
            return nil
        }
    }

    // MARK: - Embedding

    func embed(_ text: String) -> [Float]? {
        switch backend {
        case .contextual(let any):
            guard #available(macOS 14, *), let ctx = any as? NLContextualEmbedding else { return nil }
            return embedContextual(text, ctx: ctx)
        case .sentence(let emb):
            return embedSentence(text, emb: emb)
        }
    }

    func embed(batch texts: [String]) -> [[Float]?] {
        texts.map { embed($0) }
    }

    @available(macOS 14, *)
    private func embedContextual(_ text: String, ctx: NLContextualEmbedding) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let result = try ctx.embeddingResult(for: trimmed, language: nil)
            let dim = ctx.dimension
            var sum = [Float](repeating: 0, count: dim)
            var count = 0
            result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vec, _ in
                let limit = Swift.min(dim, vec.count)
                for i in 0..<limit { sum[i] += Float(vec[i]) }
                count += 1
                return true
            }
            guard count > 0 else { return nil }
            return sum.map { $0 / Float(count) }
        } catch {
            return nil
        }
    }

    private func embedSentence(_ text: String, emb: NLEmbedding) -> [Float]? {
        if let vector = emb.vector(for: text) {
            return vector.map { Float($0) }
        }
        return averagedWordVector(text: text, emb: emb)
    }

    private func averagedWordVector(text: String, emb: NLEmbedding) -> [Float]? {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        let dim = emb.dimension
        var sum = [Double](repeating: 0, count: dim)
        var hits = 0
        for w in words {
            if let v = emb.vector(for: w) {
                for i in 0..<dim { sum[i] += v[i] }
                hits += 1
            }
        }
        guard hits > 0 else { return nil }
        return sum.map { Float($0 / Double(hits)) }
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

/// Stable hash of content (for cache keys). Backend ID is mixed in by the
/// caller so model swaps don't collide.
func contentHash(_ text: String) -> String {
    let data = Data(text.utf8)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
}

/// Mix the backend identifier into a hash so a different model invalidates
/// older entries automatically.
func cacheKey(content: String, backendID: String) -> String {
    var hasher = SHA256()
    hasher.update(data: Data(backendID.utf8))
    hasher.update(data: [0])
    hasher.update(data: Data(content.utf8))
    return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
}
