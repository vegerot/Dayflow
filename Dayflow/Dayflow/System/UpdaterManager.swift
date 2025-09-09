//
//  UpdaterManager.swift
//  Dayflow
//
//  Thin wrapper around Sparkle to expose simple update actions/state to SwiftUI.
//

import Foundation
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    lazy var controller: SPUStandardUpdaterController = {
        let c = SPUStandardUpdaterController(startingUpdater: true,
                                             updaterDelegate: self,
                                             userDriverDelegate: nil)
        // Prefer background checks and automatic downloads
        c.updater.automaticallyChecksForUpdates = true
        c.updater.automaticallyDownloadsUpdates = true
        c.updater.updateCheckInterval = TimeInterval(60 * 60 * 24)
        return c
    }()

    // Simple state for Settings UI
    @Published var isChecking = false
    @Published var statusText: String = ""
    @Published var updateAvailable = false
    @Published var latestVersionString: String? = nil

    private override init() {
        super.init()
        // Initial status
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        statusText = "v\(version)"
    }

    func checkForUpdates(showUI: Bool = false) {
        isChecking = true
        statusText = "Checking…"
        if showUI {
            controller.updater.checkForUpdates()
        } else {
            controller.updater.checkForUpdatesInBackground()
        }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersionString = item.displayVersionString ?? item.versionString
            self.statusText = "Update available: v\(self.latestVersionString ?? "?")"
            self.isChecking = false
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
            self.statusText = "Latest version"
            self.isChecking = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.isChecking = false
            self.statusText = "Update check failed"
        }
    }
}
