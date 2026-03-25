//
//  UpdateChecker.swift
//  dria
//
//  Placeholder for Sparkle auto-updater integration.
//  To complete setup:
//  1. Add Sparkle SPM package in Xcode: https://github.com/sparkle-project/Sparkle (from 2.6.0)
//  2. Uncomment the Sparkle import and SPUStandardUpdaterController usage below
//  3. Configure your appcast URL in Info.plist (SUFeedURL)
//

import AppKit

// import Sparkle  // Uncomment after adding Sparkle SPM package

@Observable
@MainActor
final class UpdateChecker {
    // Uncomment after adding Sparkle SPM package:
    // private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool = true

    init() {
        // self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        // updaterController.checkForUpdates(nil)

        // Placeholder: open releases page until Sparkle is configured
        if let url = URL(string: "https://github.com/AntGravity-AI/dria/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}
