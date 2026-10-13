//
//  GettingStarted.swift
//  Dayflow
//
//  First-day guide shown after onboarding: a short welcome tour, a
//  "Your first day" checklist on the timeline, and a one-time notification
//  when the first real timeline cards land.
//
//  Most people who drop off after onboarding quit within minutes, before the
//  first ~15 minute analysis batch could show them anything. The guide sets
//  that expectation, tells them it's fine to close the window, and brings
//  them back when there is something to see.
//

import AppKit
import Foundation

enum GettingStarted {
  enum Keys {
    /// Set when onboarding finishes. Existing users never get the guide.
    static let isActive = "gettingStartedActive"
    static let startedAt = "gettingStartedStartedAt"
    static let tourPending = "gettingStartedTourPending"
    static let openedCard = "gettingStartedOpenedCard"
    static let firstCardsReady = "gettingStartedFirstCardsReady"
    static let checklistDismissed = "gettingStartedChecklistDismissed"
    static let checklistCollapsed = "gettingStartedChecklistCollapsed"
  }

  /// The checklist retires itself after the first week even if unfinished.
  static let checklistLifetime: TimeInterval = 7 * 24 * 60 * 60

  private static var defaults: UserDefaults { .standard }

  static var isActive: Bool {
    defaults.bool(forKey: Keys.isActive)
  }

  static var startedAt: Date? {
    defaults.object(forKey: Keys.startedAt) as? Date
  }

  /// PostHog experiment with a `control` variant (no guide) and a `guide` variant.
  static let experimentFlagKey = "getting-started-guide"

  /// Called from the onboarding completion button.
  static func begin() {
    // Read once, here, so someone's group never changes after onboarding. People without a
    // variant (analytics off, or flags not loaded yet) get the guide.
    let variant = AnalyticsService.shared.featureFlagVariant(experimentFlagKey) ?? "none"
    AnalyticsService.shared.setPersonProperties(["getting_started_variant": variant])

    guard variant != "control" else {
      defaults.set(false, forKey: Keys.isActive)
      defaults.set(false, forKey: Keys.tourPending)
      return
    }

    defaults.set(true, forKey: Keys.isActive)
    defaults.set(Date(), forKey: Keys.startedAt)
    defaults.set(true, forKey: Keys.tourPending)
    defaults.set(false, forKey: Keys.openedCard)
    defaults.set(false, forKey: Keys.firstCardsReady)
    defaults.set(false, forKey: Keys.checklistDismissed)
    defaults.set(false, forKey: Keys.checklistCollapsed)
  }

  /// Called from Settings. Shows the tour again and brings the checklist back with a fresh
  /// week. Someone who already has analyzed batches is past the "first cards" moment, so
  /// that notification isn't sent again.
  static func replay() {
    defaults.set(true, forKey: Keys.isActive)
    defaults.set(Date(), forKey: Keys.startedAt)
    defaults.set(false, forKey: Keys.checklistDismissed)
    defaults.set(false, forKey: Keys.checklistCollapsed)
    if FeatureAccessRequirements.completedBatchCount() > 0 {
      defaults.set(true, forKey: Keys.firstCardsReady)
    }

    AnalyticsService.shared.capture("getting_started_replayed")
    NotificationCenter.default.post(name: .showGettingStartedTour, object: nil)
  }

  static var isChecklistExpired: Bool {
    guard let startedAt else { return true }
    return Date().timeIntervalSince(startedAt) > checklistLifetime
  }

  static func markCardOpened() {
    guard isActive, !defaults.bool(forKey: Keys.openedCard) else { return }
    defaults.set(true, forKey: Keys.openedCard)
    AnalyticsService.shared.capture(
      "getting_started_step_completed",
      ["step": "open_card", "minutes_since_onboarding": minutesSinceStart])
  }

  /// Called after every successfully analyzed batch. Only the first one after
  /// onboarding does anything: it records the milestone and sends a
  /// notification so people who closed the window come back to see it.
  @MainActor
  static func handleBatchAnalyzed(cardCount: Int) {
    guard isActive, cardCount > 0, !defaults.bool(forKey: Keys.firstCardsReady) else { return }
    defaults.set(true, forKey: Keys.firstCardsReady)

    AnalyticsService.shared.capture(
      "getting_started_first_cards_ready",
      [
        "minutes_since_onboarding": minutesSinceStart,
        "card_count": cardCount,
        "app_active": NSApp.isActive,
      ])

    NotificationService.shared.notifyFirstCardsReady()
  }

  static var minutesSinceStart: Int {
    guard let startedAt else { return -1 }
    return Int(Date().timeIntervalSince(startedAt) / 60)
  }
}
