import AppKit
import CoreGraphics
import Foundation

enum ScreenRecordingPermissionNotice {
  static var isGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  /// Posted when macOS reports access as granted but every capture request
  /// keeps failing, so the notice shows even though `isGranted` is true.
  static let captureFailingReason = "capture_failing_while_granted"

  static func post(reason: String) {
    let notification = {
      NotificationCenter.default.post(
        name: .showScreenRecordingPermissionNotice,
        object: nil,
        userInfo: ["reason": reason]
      )
    }

    if Thread.isMainThread {
      notification()
    } else {
      DispatchQueue.main.async(execute: notification)
    }
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    else { return }

    NSWorkspace.shared.open(url)
  }
}
