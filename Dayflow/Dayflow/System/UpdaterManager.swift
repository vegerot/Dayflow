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

    private let userDriver = SilentUserDriver()
    private lazy var updater: SPUUpdater = {
        let u = SPUUpdater(hostBundle: .main,
                           applicationBundle: .main,
                           userDriver: userDriver,
                           delegate: self)
        // Prefer background checks and automatic downloads
        u.automaticallyChecksForUpdates = true
        u.automaticallyDownloadsUpdates = true
        u.updateCheckInterval = TimeInterval(60 * 60) // hourly cadence
        return u
    }()

    // Fallback interactive updater for cases requiring authorization/UI
    private lazy var interactiveController: SPUStandardUpdaterController = {
        let c = SPUStandardUpdaterController(startingUpdater: true,
                                             updaterDelegate: self,
                                             userDriverDelegate: nil)
        // Keep automatic checks enabled on the shared preference so the silent updater stays active
        c.updater.automaticallyChecksForUpdates = true
        c.updater.automaticallyDownloadsUpdates = true
        c.updater.updateCheckInterval = TimeInterval(60 * 60) // hourly cadence
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
        // Start updater immediately so background checks can run
        try? updater.start()
    }

    func checkForUpdates(showUI: Bool = false) {
        isChecking = true
        statusText = "Checking…"
        if showUI {
            // Route interactive checks through the UI driver to allow auth prompts
            interactiveController.updater.checkForUpdates()
        } else {
            // Sparkle only allows background checks after the user has granted permission.
            if updater.automaticallyChecksForUpdates {
                updater.checkForUpdates()
            } else {
                // If permission hasn’t been granted yet, fall back to the interactive flow.
                interactiveController.updater.checkForUpdates()
            }
        }
    }
}


extension UpdaterManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Task { @MainActor in
            AppDelegate.allowTermination = true
        }
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Task { @MainActor in
            AppDelegate.allowTermination = true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        if choice != .install {
            Task { @MainActor in
                AppDelegate.allowTermination = false
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
            self.latestVersionString = item.displayVersionString ?? item.versionString
            self.statusText = "Update available: v\(self.latestVersionString ?? "?")"
            self.isChecking = false
            AppDelegate.allowTermination = false
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
            self.statusText = "Latest version"
            self.isChecking = false
            AppDelegate.allowTermination = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // If silent install failed due to requiring interaction (auth, permission),
        // fall back to interactive flow so the user can authorize.
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        print("[Sparkle] updater error: \(domain) \(code) - \(error.localizedDescription)")
        let needsInteraction = (domain == "SUSparkleErrorDomain") && [
            4001, // SUAuthenticationFailure
            4008, // SUInstallationAuthorizeLaterError
            4011, // SUInstallationRootInteractiveError
            4012  // SUInstallationWriteNoPermissionError
        ].contains(code)

        Task { @MainActor in
            self.isChecking = false
            self.statusText = needsInteraction ? "Update needs authorization" : "Update check failed"
            AppDelegate.allowTermination = needsInteraction
            if needsInteraction {
                // Trigger interactive updater; if a download already exists, Sparkle resumes and prompts
                self.interactiveController.updater.checkForUpdates()
            }
        }
    }
}
