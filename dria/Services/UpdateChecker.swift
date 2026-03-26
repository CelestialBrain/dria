//
//  UpdateChecker.swift
//  dria
//
//  Manages app updates via Sparkle framework.

import AppKit
import ServiceManagement
import Sparkle

@Observable
@MainActor
final class UpdateChecker: NSObject, @preconcurrency SPUUpdaterDelegate {

    // MARK: - Observable State

    var canCheckForUpdates: Bool = false
    var updateAvailable: Bool = false
    var latestVersion: String = ""
    var isChecking: Bool = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Sparkle (not tracked by @Observable)

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var canCheckObservation: NSKeyValueObservation?

    // MARK: - Init

    override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Mirror Sparkle's KVO property to our @Observable
        canCheckObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = value
            }
        }

        updaterController.updater.updateCheckInterval = 4 * 60 * 60
        updaterController.updater.automaticallyChecksForUpdates = true
    }

    deinit {
        canCheckObservation?.invalidate()
    }

    // MARK: - Public API

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func downloadUpdate() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        "https://github.com/CelestialBrain/dria/releases/latest/download/appcast.xml"
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersion = item.displayVersionString ?? item.versionString
            self.isChecking = false
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.updateAvailable = false
            self.isChecking = false
        }
    }
}
