//
//  ScreenCaptureMonitor.swift
//  Dayflow
//
//  Shared bookkeeping for ScreenCaptureKit traffic (issue #381).
//
//  macOS's permission daemon (tccd) re-checks Dayflow's code signature on
//  every ScreenCaptureKit request. Under a burst of requests it can fail to
//  match the existing grant and show the "would like to record this computer's
//  screen" prompt even though access is on. This type:
//  - tracks whether the screen is locked / asleep / showing the screensaver,
//    so the recorder and Flow can skip captures while it is,
//  - counts ScreenCaptureKit requests for the hourly heartbeat,
//  - reports failures that happen while the grant looks intact, and bursts of
//    SCShareableContent fetches, so we can see how often this hits users.
//

import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureMonitor: @unchecked Sendable {
  static let shared = ScreenCaptureMonitor()

  enum Source: String, CaseIterable {
    case recorderSetup = "recorder_setup"
    case recorderRefresh = "recorder_refresh"
    case recorderCapture = "recorder_capture"
    case flow
  }

  enum Request {
    case shareableContent
    case screenshot
  }

  // Tunables
  private let failureEventInterval: TimeInterval = 10 * 60
  private let burstWindow: TimeInterval = 60
  private let burstThreshold = 10
  private let burstEventInterval: TimeInterval = 10 * 60

  private let lock = NSLock()
  private var isObserving = false

  // Screen availability (guarded by `lock`)
  private var screenLocked = false
  private var screensaverRunning = false
  private var systemAsleep = false
  private var lastUnlockAt: Date?
  private var lastWakeAt: Date?

  // Heartbeat counters (guarded by `lock`, reset on each heartbeat)
  private var shareableContentCalls = 0
  private var screenshotCalls = 0
  private var failuresWhileGranted = 0

  // Event throttling (guarded by `lock`)
  private var lastFailureEventAt: [Source: Date] = [:]
  private var suppressedFailures: [Source: Int] = [:]
  private var recentContentFetches: [(date: Date, source: Source)] = []
  private var lastBurstEventAt: Date?

  private init() {}

  // MARK: - Screen availability

  /// True while the screen is locked, asleep, or showing the screensaver.
  /// Nothing useful can be captured then, and requests only add tccd load.
  var isCaptureBlocked: Bool {
    lock.withLock { screenLocked || screensaverRunning || systemAsleep }
  }

  /// Registers the lock / sleep / screensaver observers. Safe to call more than once.
  func startObserving() {
    let shouldStart = lock.withLock {
      guard !isObserving else { return false }
      isObserving = true
      return true
    }
    guard shouldStart else { return }

    let workspace = NSWorkspace.shared.notificationCenter
    let distributed = DistributedNotificationCenter.default()

    workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) {
      [weak self] _ in
      self?.update { $0.systemAsleep = true }
    }
    workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) {
      [weak self] _ in
      self?.update {
        $0.systemAsleep = false
        $0.lastWakeAt = Date()
      }
    }
    distributed.addObserver(
      forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil
    ) { [weak self] _ in
      self?.update { $0.screenLocked = true }
    }
    distributed.addObserver(
      forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: nil
    ) { [weak self] _ in
      self?.update {
        $0.screenLocked = false
        $0.lastUnlockAt = Date()
      }
    }
    distributed.addObserver(
      forName: .init("com.apple.screensaver.didstart"), object: nil, queue: nil
    ) { [weak self] _ in
      self?.update { $0.screensaverRunning = true }
    }
    distributed.addObserver(
      forName: .init("com.apple.screensaver.didstop"), object: nil, queue: nil
    ) { [weak self] _ in
      self?.update { $0.screensaverRunning = false }
    }
  }

  /// Runs `change` with `lock` held.
  private func update(_ change: (ScreenCaptureMonitor) -> Void) {
    lock.withLock { change(self) }
  }

  // MARK: - Request counting

  /// Call right before every ScreenCaptureKit request.
  func recordRequest(_ request: Request, source: Source) {
    let now = Date()
    var burstProps: [String: Any]?

    lock.withLock {
      switch request {
      case .screenshot:
        screenshotCalls += 1
      case .shareableContent:
        shareableContentCalls += 1
        recentContentFetches.append((now, source))
        recentContentFetches.removeAll { now.timeIntervalSince($0.date) > burstWindow }

        let canSendBurst =
          lastBurstEventAt.map { now.timeIntervalSince($0) >= burstEventInterval } ?? true
        if recentContentFetches.count >= burstThreshold, canSendBurst {
          lastBurstEventAt = now
          var props: [String: Any] = ["calls_last_minute": recentContentFetches.count]
          for source in Source.allCases {
            props["calls_\(source.rawValue)"] =
              recentContentFetches.filter {
                $0.source == source
              }.count
          }
          props.merge(timingProperties(now: now)) { _, new in new }
          burstProps = props
        }
      }
    }

    if let burstProps {
      AnalyticsService.shared.capture("screen_capture_burst", burstProps)
    }
  }

  // MARK: - Failure reporting

  /// Call when a ScreenCaptureKit request throws. Only failures that happen
  /// while the Screen Recording grant still looks intact are reported: those
  /// are the ones that line up with the spurious system prompt.
  func recordFailure(_ error: Error, source: Source) {
    guard CGPreflightScreenCaptureAccess() else { return }
    // A capture cut off by the screen locking isn't the bug we're measuring.
    guard !isCaptureBlocked else { return }

    let now = Date()
    let nsError = error as NSError
    var eventProps: [String: Any]?

    lock.withLock {
      failuresWhileGranted += 1

      let canSend =
        lastFailureEventAt[source].map { now.timeIntervalSince($0) >= failureEventInterval }
        ?? true
      guard canSend else {
        suppressedFailures[source, default: 0] += 1
        return
      }

      lastFailureEventAt[source] = now
      var props: [String: Any] = [
        "source": source.rawValue,
        "error_domain": nsError.domain,
        "error_code": nsError.code,
        "user_declined": nsError.domain == SCStreamErrorDomain
          && nsError.code == SCStreamError.Code.userDeclined.rawValue,
        "suppressed_count": suppressedFailures[source] ?? 0,
        "capture_interval_s": Int(ScreenshotConfig.interval),
        "display_count": NSScreen.screens.count,
      ]
      props.merge(timingProperties(now: now)) { _, new in new }
      suppressedFailures[source] = 0
      eventProps = props
    }

    if let eventProps {
      AnalyticsService.shared.capture("screen_capture_denied_while_granted", eventProps)
    }
  }

  // MARK: - Heartbeat

  /// Counts since the previous heartbeat, then resets them.
  func heartbeatPropertiesAndReset() -> [String: Any] {
    lock.withLock {
      let props: [String: Any] = [
        "sck_shareable_content_calls": shareableContentCalls,
        "sck_screenshot_calls": screenshotCalls,
        "sck_failures_while_granted": failuresWhileGranted,
      ]
      shareableContentCalls = 0
      screenshotCalls = 0
      failuresWhileGranted = 0
      return props
    }
  }

  // MARK: - Helpers

  /// Must be called with `lock` held.
  private func timingProperties(now: Date) -> [String: Any] {
    var props: [String: Any] = [:]
    if let lastUnlockAt {
      props["since_unlock_bucket"] = AnalyticsService.shared.secondsBucket(
        now.timeIntervalSince(lastUnlockAt))
    }
    if let lastWakeAt {
      props["since_wake_bucket"] = AnalyticsService.shared.secondsBucket(
        now.timeIntervalSince(lastWakeAt))
    }
    return props
  }
}
