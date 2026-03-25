//
//  UpdateChecker.swift
//  dria
//
//  Checks GitHub releases API for new versions. No redirect — shows in-app.

import AppKit
import ServiceManagement

@Observable
@MainActor
final class UpdateChecker {
    private static let repoURL = "https://api.github.com/repos/CelestialBrain/dria/releases/latest"
    private static let releasesPage = "https://github.com/CelestialBrain/dria/releases"

    var canCheckForUpdates: Bool = true
    var updateAvailable: Bool = false
    var latestVersion: String = ""
    var downloadURL: String = ""
    var releaseNotes: String = ""
    var isChecking: Bool = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Launch at login
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can toggle in System Settings
            }
        }
    }

    init() {
        // Auto-check on launch (after 5s delay to not block startup)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await checkForUpdatesQuietly()
        }
    }

    /// Silent check — no UI unless update found
    func checkForUpdatesQuietly() async {
        await fetchLatestRelease()
    }

    /// Manual check — shows status
    func checkForUpdates() {
        isChecking = true
        Task {
            await fetchLatestRelease()
            isChecking = false
        }
    }

    /// Download the latest DMG directly
    func downloadUpdate() {
        guard !downloadURL.isEmpty, let url = URL(string: downloadURL) else {
            // Fallback to releases page
            if let url = URL(string: Self.releasesPage) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func fetchLatestRelease() async {
        guard let url = URL(string: Self.repoURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            guard let tagName = json["tag_name"] as? String else { return }
            let version = tagName.replacingOccurrences(of: "v", with: "")

            latestVersion = version
            releaseNotes = (json["body"] as? String ?? "").prefix(500).description

            // Find DMG asset
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                       let url = asset["browser_download_url"] as? String {
                        downloadURL = url
                        break
                    }
                }
            }

            // Compare versions
            updateAvailable = isNewer(latestVersion, than: currentVersion)

        } catch {
            // Silent fail — don't bother user
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
