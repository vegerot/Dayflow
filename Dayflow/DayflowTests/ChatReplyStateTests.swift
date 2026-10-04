import XCTest

@testable import Dayflow

final class ChatReplyStateTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    suiteName = "ChatReplyStateTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func testUnreadReplySurvivesRelaunchWithoutAnotherNotification() {
    let state = ChatReplyState(defaults: defaults, keyPrefix: "flowWaitlist.person")
    XCTAssertTrue(state.receive(unreadCount: 1, latestReplyID: "reply-1"))
    let restored = ChatReplyState(
      defaults: UserDefaults(suiteName: suiteName)!, keyPrefix: "flowWaitlist.person")
    XCTAssertEqual(restored.unreadCount, 1)
    XCTAssertFalse(restored.receive(unreadCount: 1, latestReplyID: "reply-1"))
    XCTAssertTrue(restored.receive(unreadCount: 2, latestReplyID: "reply-2"))
  }

  func testReadingTheConversationClearsItsPersistedUnreadCount() {
    let state = ChatReplyState(defaults: defaults, keyPrefix: "flowWaitlist.person")
    XCTAssertTrue(state.receive(unreadCount: 1, latestReplyID: "reply-1"))
    XCTAssertFalse(state.receive(unreadCount: 0, latestReplyID: "reply-1"))
    XCTAssertEqual(state.unreadCount, 0)
  }

  func testFlowAndSupportKeepIndependentUnreadAndNotificationState() {
    let flow = ChatReplyState(defaults: defaults, keyPrefix: "flowWaitlist.person")
    let support = ChatReplyState(defaults: defaults, keyPrefix: "support")
    XCTAssertTrue(flow.receive(unreadCount: 2, latestReplyID: "reply-1"))
    XCTAssertTrue(support.receive(unreadCount: 1, latestReplyID: "reply-1"))
    XCTAssertFalse(support.receive(unreadCount: 0, latestReplyID: "reply-1"))
    XCTAssertEqual(flow.unreadCount, 2)
    XCTAssertEqual(support.unreadCount, 0)
  }

  func testAReadReplyDoesNotNotifyAndInvalidCountsDoNotBadge() {
    let state = ChatReplyState(defaults: defaults, keyPrefix: "flowWaitlist.person")
    XCTAssertFalse(state.receive(unreadCount: 0, latestReplyID: "reply-1"))
    XCTAssertFalse(state.receive(unreadCount: -1, latestReplyID: "reply-2"))
    XCTAssertEqual(state.unreadCount, 0)
    XCTAssertFalse(state.receive(unreadCount: 1, latestReplyID: nil))
  }
}
