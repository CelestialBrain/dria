//
//  ChatPersistence.swift
//  dria
//
//  Per-mode chat history storage in UserDefaults.
//  Extracted from AppState to isolate persistence logic.
//

import Foundation

@MainActor
final class ChatPersistence {
    static let maxPersistedMessages = 50

    private func chatKey(for modeId: UUID) -> String {
        "chatHistory_\(modeId.uuidString)"
    }

    /// One-time migration: copy old shared "chatHistory" key to the General mode key.
    func migrateOldChatHistory() {
        let oldKey = "chatHistory"
        let newKey = chatKey(for: StudyMode.general.id)
        guard UserDefaults.standard.data(forKey: oldKey) != nil,
              UserDefaults.standard.data(forKey: newKey) == nil else { return }
        if let data = UserDefaults.standard.data(forKey: oldKey) {
            UserDefaults.standard.set(data, forKey: newKey)
        }
        UserDefaults.standard.removeObject(forKey: oldKey)
    }

    func save(_ history: [ChatMessage], for modeId: UUID) {
        let toSave = Array(history.suffix(Self.maxPersistedMessages))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: chatKey(for: modeId))
        }
    }

    func load(for modeId: UUID) -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: chatKey(for: modeId)),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return Array(messages.suffix(Self.maxPersistedMessages))
    }

    func clear(for modeId: UUID) {
        UserDefaults.standard.removeObject(forKey: chatKey(for: modeId))
    }
}
