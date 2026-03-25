//
//  FocusDetector.swift
//  dria
//

import AppKit

@MainActor
final class FocusDetector {
    struct FocusInfo {
        let appName: String
        let windowTitle: String?
        let url: String? // Extracted URL from window title if browser
    }

    func currentFocus() -> FocusInfo {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        let windowTitle = getWindowTitle(for: app)
        let url = extractURL(from: windowTitle, appName: appName)
        return FocusInfo(appName: appName, windowTitle: windowTitle, url: url)
    }

    private func getWindowTitle(for app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windowList
            .first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid })
            .flatMap { $0[kCGWindowName as String] as? String }
    }

    /// Extract URL from browser window titles
    private func extractURL(from windowTitle: String?, appName: String) -> String? {
        guard let title = windowTitle else { return nil }
        let browsers = ["Chrome", "Safari", "Firefox", "Arc", "Brave", "Edge"]
        guard browsers.contains(where: { appName.contains($0) }) else { return nil }
        // Browser titles often contain the URL or domain
        return title
    }

    /// Check if current focus is on an exam platform
    func isExamPlatform(_ focus: FocusInfo) -> Bool {
        let examDomains = [
            "instructure.com",       // Canvas
            "docs.google.com/forms", // Google Forms
            "quizizz.com",
            "kahoot.it",
            "schoology.com",
            "blackboard.com",
        ]
        let searchText = "\(focus.windowTitle ?? "") \(focus.url ?? "")".lowercased()
        return examDomains.contains(where: { searchText.contains($0) })
    }

    func suggestMode(from focus: FocusInfo, availableModes: [StudyMode]) -> StudyMode? {
        let searchText = "\(focus.appName) \(focus.windowTitle ?? "")".lowercased()
        for mode in availableModes where !mode.keywords.isEmpty {
            if mode.keywords.contains(where: { searchText.contains($0) }) {
                return mode
            }
        }
        return nil
    }
}
