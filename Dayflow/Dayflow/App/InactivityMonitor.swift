import AppKit
import Combine

@MainActor
final class InactivityMonitor: ObservableObject {
    static let shared = InactivityMonitor()

    // Published so views can react when an idle reset is pending
    @Published var pendingReset: Bool = false

    // Config
    private let secondsOverrideKey = "idleResetSecondsOverride"
    private let legacyMinutesKey = "idleResetMinutes"
    private let defaultThresholdSeconds: TimeInterval = 15 * 60

    var thresholdSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: secondsOverrideKey)
        if override > 0 { return override }

        let legacyMinutes = UserDefaults.standard.integer(forKey: legacyMinutesKey)
        if legacyMinutes > 0 {
            return TimeInterval(legacyMinutes * 60)
        }

        return defaultThresholdSeconds
    }

    // State
    private var lastInteractionAt: Date = Date()
    private var lastResetAt: Date? = nil
    private var checkTimer: Timer?
    private var monitors: [Any] = []

    private init() {}

    func start() {
        setupEventMonitors()
        startTimer()
    }

    func stop() {
        stopTimer()
        removeEventMonitors()
    }

    func markHandledIfPending() {
        if pendingReset {
            pendingReset = false
            // We stay in the fired state until the next user interaction
        }
    }

    private func setupEventMonitors() {
        removeEventMonitors()

        let masks: [NSEvent.EventTypeMask] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .mouseMoved, .scrollWheel
        ]

        for mask in masks {
            let token = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self = self else { return event }
                self.handleInteraction()
                return event
            }
            if let token = token {
                monitors.append(token)
            }
        }

        // Also observe app activation as an interaction (e.g., returning to the app)
        let center = NotificationCenter.default
        let act = center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleInteraction()
        }
        monitors.append(act)
    }

    private func removeEventMonitors() {
        for monitor in monitors {
            if let m = monitor as? AnyObject, NSStringFromClass(type(of: m)).contains("NSConcreteNotification") {
                NotificationCenter.default.removeObserver(m)
            } else {
                NSEvent.removeMonitor(monitor)
            }
        }
        monitors.removeAll()
    }

    private func handleInteraction() {
        lastInteractionAt = Date()
        lastResetAt = nil
        if pendingReset { pendingReset = false }
    }

    private func startTimer() {
        stopTimer()
        let interval = max(1.0, min(5.0, thresholdSeconds / 2))
        checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
    }

    private func stopTimer() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkIdle() {
        let elapsed = Date().timeIntervalSince(lastInteractionAt)
        let threshold = thresholdSeconds
        guard elapsed >= threshold else { return }

        let now = Date()
        if let lastResetAt, now.timeIntervalSince(lastResetAt) < threshold {
            return
        }

        pendingReset = true
        lastResetAt = now
    }
}
