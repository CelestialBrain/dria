//
//  ChatMessage.swift
//  dria
//

import AppKit
import Foundation

/// Reference type to avoid expensive struct copies in @Observable arrays.
/// SwiftUI was triggering initializeWithCopy on every render cycle,
/// causing 100% CPU loops with struct-based messages.
final class ChatMessage: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var referencedSources: [String]

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(role: Role, content: String, referencedSources: [String] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.referencedSources = referencedSources
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Separate cache for attachments — NOT in the @Observable array
@MainActor
final class AttachmentCache {
    static let shared = AttachmentCache()

    private struct Entry {
        let imageData: Data?
        let clipboardText: String?
        let timestamp: Date
    }

    private var entries: [UUID: Entry] = [:]
    private let maxEntries = 30
    private let maxAge: TimeInterval = 3600 // 1 hour

    func store(messageId: UUID, imageData: Data? = nil, clipboardText: String? = nil) {
        entries[messageId] = Entry(imageData: imageData, clipboardText: clipboardText, timestamp: Date())
        evictIfNeeded()
    }

    func imageData(for messageId: UUID) -> Data? { entries[messageId]?.imageData }
    func clipboardText(for messageId: UUID) -> String? { entries[messageId]?.clipboardText }

    func clear() { entries.removeAll() }

    private func evictIfNeeded() {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.timestamp) < maxAge }

        if entries.count > maxEntries {
            let sorted = entries.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = sorted.prefix(entries.count - maxEntries)
            toRemove.forEach { entries.removeValue(forKey: $0.key) }
        }
    }
}
