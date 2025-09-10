import AppKit
import Sparkle

// A no-UI user driver that silently installs updates immediately
final class SilentUserDriver: NSObject, SPUUserDriver {
    // MARK: Permission
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Enable automatic checks & downloads by default; do not send system profile
        let response = SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: NSNumber(value: true),
            sendSystemProfile: false
        )
        reply(response)
    }

    // MARK: User-initiated check
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // No UI; ignore
    }

    // MARK: Update discovery
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Always proceed to install
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // No-op
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        // No-op
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    // MARK: Downloading
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        // No UI
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        // No UI
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        // No UI
    }

    func showDownloadDidStartExtractingUpdate() {
        // No UI
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        // No UI
    }

    // MARK: Install & Relaunch
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Install and relaunch immediately
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // No UI; don't retry programmatically here
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        // No UI
    }

    func dismissUpdateInstallation() {
        // No UI
    }
}
