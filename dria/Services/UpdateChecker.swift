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

    var canCheckForUpdates: Bool = true
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

    // MARK: - Sparkle (lazy, not created on init)

    @ObservationIgnored
    private var _updaterController: SPUStandardUpdaterController?

    @ObservationIgnored
    private var canCheckObservation: NSKeyValueObservation?

    private var updaterController: SPUStandardUpdaterController {
        if let existing = _updaterController { return existing }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        _updaterController = controller

        // Mirror KVO
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = value
            }
        }

        controller.updater.updateCheckInterval = 4 * 60 * 60
        controller.updater.automaticallyChecksForUpdates = true

        // Start updater
        try? controller.updater.start()

        return controller
    }

    // MARK: - Init

    override init() {
        super.init()

        // Start Sparkle after a delay — avoids TCC crash on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            _ = self?.updaterController
        }
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
