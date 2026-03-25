//
//  KeychainService.swift
//  dria
//

import Foundation

struct KeychainService {
    private let key = "com.dev.dria.api-key"

    func saveAPIKey(_ apiKey: String) throws {
        UserDefaults.standard.set(apiKey, forKey: key)
    }

    func getAPIKey() throws -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func deleteAPIKey() throws {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
