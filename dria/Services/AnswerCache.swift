//
//  AnswerCache.swift
//  dria
//
//  Caches AI answers by question hash. Same question = instant cached answer.

import Foundation

@MainActor
final class AnswerCache {
    static let shared = AnswerCache()

    private struct CachedAnswer: Codable {
        let question: String
        let answer: String
        let modeId: String
        let timestamp: Date
    }

    private var cache: [String: CachedAnswer] = [:]
    private let maxEntries = 200
    private let maxAge: TimeInterval = 86400 * 7 // 7 days
    private let filePath: String

    private init() {
        let dir = NSHomeDirectory() + "/Library/Application Support/dria"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        filePath = dir + "/answer_cache.json"
        load()
    }

    /// Look up a cached answer
    func lookup(question: String, modeId: UUID) -> String? {
        let key = cacheKey(question: question, modeId: modeId)
        guard let entry = cache[key] else { return nil }
        // Check expiry
        if Date().timeIntervalSince(entry.timestamp) > maxAge {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.answer
    }

    /// Store an answer
    func store(question: String, answer: String, modeId: UUID) {
        let key = cacheKey(question: question, modeId: modeId)
        cache[key] = CachedAnswer(question: question, answer: answer, modeId: modeId.uuidString, timestamp: Date())
        evictIfNeeded()
        save()
    }

    func clear() {
        cache.removeAll()
        save()
    }

    var count: Int { cache.count }

    // MARK: - Private

    private func cacheKey(question: String, modeId: UUID) -> String {
        // Normalize: lowercase, trim, remove extra spaces
        let normalized = question.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return "\(modeId.uuidString):\(normalized.hashValue)"
    }

    private func evictIfNeeded() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < maxAge }
        if cache.count > maxEntries {
            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sorted.prefix(cache.count - maxEntries)
            toRemove.forEach { cache.removeValue(forKey: $0.key) }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let loaded = try? JSONDecoder().decode([String: CachedAnswer].self, from: data) else { return }
        cache = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
