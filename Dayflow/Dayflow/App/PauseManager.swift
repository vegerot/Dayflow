//
//  PauseManager.swift
//  Dayflow
//
//  Manages pause functionality for recording.
//  Timed pauses are session-local, while indefinite pause keeps recording off until resumed.
//

import AppKit
import Combine
import Foundation

// MARK: - Pause Types

enum PauseDuration: Equatable {
  case timed(minutes: Int)
  case indefinite

  var timeInterval: TimeInterval? {
    switch self {
    case .timed(let minutes): return TimeInterval(minutes * 60)
    case .indefinite: return nil
    }
  }

  var analyticsValue: String {
    switch self {
    // Same value an hour sent before pause lengths became customizable.
    case .timed(minutes: 60): return "1_hour"
    case .timed(let minutes): return "\(minutes)_mins"
    case .indefinite: return "indefinite"
    }
  }

  /// Short label for chips and menu segments, e.g. "15m", "1h", "1h 30m".
  var shortLabel: String {
    switch self {
    case .timed(let minutes):
      return Duration.seconds(minutes * 60)
        .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    case .indefinite:
      return "∞"
    }
  }
}

/// The three timed pause lengths offered in the menu bar and the main window.
/// Editable in Settings.
enum PausePresets {
  static let defaultMinutes = [15, 30, 60]
  static let minuteOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 480]
  private static let storageKey = "pausePresetMinutes"

  static var minutes: [Int] {
    get {
      let stored = UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? []
      return stored.count == defaultMinutes.count ? stored : defaultMinutes
    }
    set { UserDefaults.standard.set(newValue, forKey: storageKey) }
  }

  /// The timed presets followed by the indefinite pause.
  static var durations: [PauseDuration] {
    minutes.map { .timed(minutes: $0) } + [.indefinite]
  }
}

enum PauseSource: String {
  case menuBar = "menu_bar"
  case mainApp = "main_app"
  case deeplink = "deeplink"
}

enum ResumeSource: String {
  case userClickedMenuBar = "user_menu_bar"
  case userClickedMainApp = "user_main_app"
  case timerExpired = "timer_expired"
  case wakeFromSleep = "wake_from_sleep"
}

@MainActor
final class PauseManager: ObservableObject {
  static let shared = PauseManager()

  /// When the timed pause should end. nil = not on a timed pause.
  @Published private(set) var pauseEndTime: Date?

  /// True if user selected indefinite pause (∞). Separate from timed pause.
  @Published private(set) var isPausedIndefinitely: Bool = false

  /// The duration that was selected (for analytics)
  private var currentPauseDuration: PauseDuration?

  /// Convenience: true if any kind of user-initiated pause is active
  var isPaused: Bool {
    isPausedIndefinitely || pauseEndTime != nil
  }

  /// Remaining seconds for countdown display. nil if not on timed pause.
  var remainingSeconds: Int? {
    guard let end = pauseEndTime else { return nil }
    let remaining = end.timeIntervalSinceNow
    return remaining > 0 ? Int(ceil(remaining)) : 0
  }

  /// Formatted remaining time for display (e.g., "14:59")
  var remainingTimeFormatted: String? {
    guard let seconds = remainingSeconds, seconds > 0 else { return nil }
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
  }

  private var timer: Timer?

  private init() {
    registerForWakeNotification()
  }

  // MARK: - Public API

  func clearPauseState() {
    stopTimer()
    pauseEndTime = nil
    isPausedIndefinitely = false
    currentPauseDuration = nil
  }

  /// Pause recording for a specific duration from a specific source.
  /// - Parameters:
  ///   - duration: The pause duration (15 mins, 30 mins, 1 hour, or indefinite)
  ///   - source: Where the pause was initiated from (menu bar, main app, etc.)
  func pause(for duration: PauseDuration, source: PauseSource) {
    clearPauseState()

    // Store for analytics
    currentPauseDuration = duration

    if let interval = duration.timeInterval {
      // Timed pause
      pauseEndTime = Date().addingTimeInterval(interval)
      isPausedIndefinitely = false
      startTimer()
    } else {
      // Indefinite pause
      pauseEndTime = nil
      isPausedIndefinitely = true
    }

    // Stop recording
    AppState.shared.setRecording(
      false,
      analyticsReason: source.rawValue,
      persistPreference: duration == .indefinite
    )

    // Send analytics
    AnalyticsService.shared.capture(
      "recording_paused",
      [
        "source": source.rawValue,
        "pause_type": duration.analyticsValue,
      ])
  }

  /// Resume recording immediately from a specific source.
  /// - Parameter source: What triggered the resume
  func resume(source: ResumeSource) {
    let wasTimed = pauseEndTime != nil
    let pauseType = currentPauseDuration?.analyticsValue ?? "unknown"

    clearPauseState()

    // Start recording
    AppState.shared.setRecording(true, analyticsReason: source.rawValue)

    // Send analytics
    AnalyticsService.shared.capture(
      "recording_resumed",
      [
        "source": source.rawValue,
        "was_timed": wasTimed,
        "original_pause_type": pauseType,
      ])
  }

  // MARK: - Timer Management

  private func startTimer() {
    timer?.invalidate()

    // Fire every second to update the countdown display
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.timerTick()
      }
    }

    // Ensure timer fires even when menu is open (modal runloop)
    if let timer = timer {
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func timerTick() {
    // Trigger UI update by notifying observers
    objectWillChange.send()

    // Check if pause has expired
    checkAndResumeIfExpired()
  }

  private func checkAndResumeIfExpired() {
    guard let end = pauseEndTime else { return }

    if Date() >= end {
      resume(source: .timerExpired)
    }
  }

  // MARK: - Wake Notification

  private func registerForWakeNotification() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleWake()
      }
    }
  }

  private func handleWake() {
    // If we were on a timed pause and it has now expired, auto-resume
    // This handles the case where computer slept past the pause end time
    if let end = pauseEndTime, Date() >= end {
      resume(source: .wakeFromSleep)
    }
    // If paused indefinitely, stay paused (no action needed)
  }
}
