//
//  BridgeTokenStore.swift
//  dria
//
//  Keychain-backed storage for the LLM bridge auth token.
//
//  Previous versions wrote the token to
//  ~/Library/Application Support/dria/bridge-token (0600), which is
//  Spotlight-indexed, Time-Machine-backed, and indirectly readable by any
//  process running as the same user. We now use the user's login keychain
//  with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
//
//  - never roams via iCloud Keychain
//  - never copied into an encrypted Time Machine backup as plaintext
//  - destroyed on Erase All Content & Settings
//
//  On first run with this version we migrate any pre-existing on-disk token
//  into the keychain, then delete the file.
//

import Foundation
import Security

struct BridgeTokenStore {
    private static let service = "com.dev.dria.bridge-token"
    private static let account = "default"

    /// Returns the token, creating + storing a fresh one on first call.
    /// Performs a one-time migration from the legacy on-disk file.
    static func loadOrCreate() -> String {
        if let existing = read() { return existing }

        // Migrate legacy on-disk token if present, then delete the file.
        let legacyURL = legacyTokenURL()
        if let data = try? Data(contentsOf: legacyURL),
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            _ = write(s)
            try? FileManager.default.removeItem(at: legacyURL)
            NSLog("[dria-bridge] migrated legacy bridge-token to Keychain")
            return s
        }

        let fresh = generate()
        _ = write(fresh)
        return fresh
    }

    /// Regenerate the token (revokes any client that cached the old one).
    @discardableResult
    static func rotate() -> String {
        let fresh = generate()
        _ = write(fresh)
        return fresh
    }

    static func delete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: - Implementation

    private static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    @discardableResult
    private static func write(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete existing item first; SecItemAdd doesn't update by default.
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse
        let status = SecItemAdd(attrs as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func legacyTokenURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/dria", isDirectory: true)
            .appendingPathComponent("bridge-token")
    }
}
