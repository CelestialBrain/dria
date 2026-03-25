//
//  AnalyticsService.swift
//  dria
//
//  Local-only, opt-in analytics. No data leaves the device.
//  Stats are written to ~/Library/Application Support/dria/analytics.json

import Foundation

struct UsageStats: Codable {
    var totalQueries: Int = 0
    var screenshotCaptures: Int = 0
    var clipboardDetections: Int = 0
    var autoAnswers: Int = 0
    var inlineChats: Int = 0
    var modesSwitched: Int = 0
    var filesImported: Int = 0
    var totalTokensEstimate: Int = 0  // rough estimate from response lengths
    var sessionsCount: Int = 0
    var firstUsed: Date = Date()
    var lastUsed: Date = Date()

    // Per-provider breakdown
    var vertexAICalls: Int = 0
    var googleAICalls: Int = 0
    var claudeCalls: Int = 0

    // Per-question-type breakdown
    var mcDetected: Int = 0
    var tfDetected: Int = 0
    var idDetected: Int = 0
    var essayDetected: Int = 0

    // Errors
    var aiErrors: Int = 0
    var captureErrors: Int = 0
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private(set) var stats = UsageStats()
    private let filePath: String

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "analyticsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "analyticsEnabled") }
    }

    private init() {
        let dir = NSHomeDirectory() + "/Library/Application Support/dria"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        filePath = dir + "/analytics.json"
        load()
        stats.sessionsCount += 1
        stats.lastUsed = Date()
        save()
    }

    // MARK: - Track Events

    func track(_ event: Event) {
        guard isEnabled else { return }
        stats.lastUsed = Date()

        switch event {
        case .query(let provider):
            stats.totalQueries += 1
            switch provider {
            case "vertexai": stats.vertexAICalls += 1
            case "googleai": stats.googleAICalls += 1
            case "claude": stats.claudeCalls += 1
            default: break
            }
        case .screenshot:
            stats.screenshotCaptures += 1
        case .clipboardDetection(let type):
            stats.clipboardDetections += 1
            switch type {
            case .multipleChoice: stats.mcDetected += 1
            case .trueFalse: stats.tfDetected += 1
            case .identification: stats.idDetected += 1
            case .essay: stats.essayDetected += 1
            case .unknown: break
            }
        case .autoAnswer:
            stats.autoAnswers += 1
        case .inlineChat:
            stats.inlineChats += 1
        case .modeSwitch:
            stats.modesSwitched += 1
        case .fileImport:
            stats.filesImported += 1
        case .responseReceived(let charCount):
            stats.totalTokensEstimate += charCount / 4 // rough token estimate
        case .aiError:
            stats.aiErrors += 1
        case .captureError:
            stats.captureErrors += 1
        }

        save()
    }

    enum Event {
        case query(provider: String)
        case screenshot
        case clipboardDetection(QuestionType)
        case autoAnswer
        case inlineChat
        case modeSwitch
        case fileImport
        case responseReceived(charCount: Int)
        case aiError
        case captureError
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let loaded = try? JSONDecoder().decode(UsageStats.self, from: data) else { return }
        stats = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }

    /// Reset all stats
    func reset() {
        stats = UsageStats()
        save()
    }

    /// Export stats as readable text
    func exportSummary() -> String {
        """
        DRIA Usage Summary
        ==================
        First used: \(stats.firstUsed.formatted())
        Last used: \(stats.lastUsed.formatted())
        Sessions: \(stats.sessionsCount)

        Queries: \(stats.totalQueries)
          Vertex AI: \(stats.vertexAICalls)
          Google AI: \(stats.googleAICalls)
          Claude: \(stats.claudeCalls)

        Screenshots: \(stats.screenshotCaptures)
        Clipboard detections: \(stats.clipboardDetections)
          MC: \(stats.mcDetected) | T/F: \(stats.tfDetected) | ID: \(stats.idDetected) | Essay: \(stats.essayDetected)
        Auto-answers: \(stats.autoAnswers)
        Inline chats: \(stats.inlineChats)
        Mode switches: \(stats.modesSwitched)
        Files imported: \(stats.filesImported)

        Est. tokens used: ~\(stats.totalTokensEstimate)
        AI errors: \(stats.aiErrors)
        Capture errors: \(stats.captureErrors)
        """
    }
}
