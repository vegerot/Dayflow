import AppKit
import Combine

@MainActor
final class InactivityMonitor: ObservableObject {
    static let shared = InactivityMonitor()

    // Published so views can react when an idle reset is pending
    @Published var pendingReset: Bool = false

    // Config
    private let defaultsKey = "idleResetMinutes"
    var thresholdMinutes: Int {
        get { max(1, UserDefaults.standard.integer(forKey: defaultsKey) == 0 ? 15 : UserDefaults.standard.integer(forKey: defaultsKey)) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    // State
    private var lastInteractionAt: Date = Date()
    private var firedForCurrentIdle: Bool = false
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

    // MARK: - Private
    private func setupEventMonitors() {
        removeEventMonitors()

        let masks: [NSEvent.EventTypeMask] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .mouseMoved, .scrollWheel
        ]

        for mask in masks {
            if let token = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self = self else { return event }
                self.handleInteraction()
                return event
            } {
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
        firedForCurrentIdle = false
        if pendingReset { pendingReset = false }
    }

    private func startTimer() {
        stopTimer()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
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
        let threshold = TimeInterval(thresholdMinutes * 60)
        if elapsed >= threshold {
            if !firedForCurrentIdle {
                pendingReset = true
                firedForCurrentIdle = true
            }
        }
    }
}
