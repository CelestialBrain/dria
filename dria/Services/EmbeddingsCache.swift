//
//  EmbeddingsCache.swift
//  dria
//
//  Persistent on-disk cache of embeddings keyed by SHA-256 of chunk content.
//  Stored as JSON in ~/Library/Caches/dria/embeddings.json.
//

import Foundation

actor EmbeddingsCache {
    private var store: [String: [Float]] = [:]
    private let cacheURL: URL
    private var dirty = false

    init() {
        let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let driaDir = cachesRoot.appendingPathComponent("dria", isDirectory: true)
        try? FileManager.default.createDirectory(at: driaDir, withIntermediateDirectories: true)
        self.cacheURL = driaDir.appendingPathComponent("embeddings.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: [Float]].self, from: data) else { return }
        store = dict
    }

    func get(_ hash: String) -> [Float]? {
        store[hash]
    }

    func set(_ hash: String, _ vector: [Float]) {
        store[hash] = vector
        dirty = true
    }

    func setMany(_ pairs: [(String, [Float])]) {
        for (h, v) in pairs { store[h] = v }
        dirty = true
    }

    /// Persist any pending changes. Call after batch insertions.
    func flush() {
        guard dirty else { return }
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: cacheURL, options: .atomic)
            dirty = false
        }
    }

    func missingHashes(from hashes: [String]) -> [String] {
        hashes.filter { store[$0] == nil }
    }
}
