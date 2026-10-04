import XCTest

@testable import Dayflow

final class FlowWaitlistRegistrationTests: XCTestCase {
  func testSignedOutSignupSurvivesRelaunchAndSignInWithoutChangingChatIdentity() {
    let suiteName = "FlowWaitlistRegistrationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(" Person@Example.com ", forKey: "flowWaitlistJoinedEmail")
    defaults.set("", forKey: "flowWaitlistJoinedAccountID")

    let restored = FlowWaitlistRegistration(defaults: UserDefaults(suiteName: suiteName)!)
    XCTAssertTrue(restored.belongsTo(userID: nil, email: nil))
    XCTAssertTrue(restored.belongsTo(userID: "account-a", email: "person@example.com"))
    XCTAssertEqual(restored.chatContext.sessionKey, "signed-out:person@example.com")
  }

  func testSigningOutKeepsTheRegisteredConversationOnThisMac() {
    let registration = FlowWaitlistRegistration(email: "person@example.com", accountID: "account-a")
    XCTAssertTrue(registration.belongsTo(userID: nil, email: nil))
    XCTAssertTrue(registration.belongsTo(userID: "account-a", email: "person@example.com"))
    XCTAssertEqual(registration.chatContext.accountID, "account-a")
  }

  func testSwitchingToAnotherAccountDoesNotExposeThePreviousConversation() {
    let registration = FlowWaitlistRegistration(email: "person@example.com", accountID: "account-a")
    XCTAssertFalse(registration.belongsTo(userID: "account-b", email: "person@example.com"))
    let anonymous = FlowWaitlistRegistration(email: "person@example.com", accountID: "")
    XCTAssertFalse(anonymous.belongsTo(userID: "account-b", email: "other@example.com"))
  }

  func testAnEmailPrefillIsNotAWaitlistSignup() {
    let registration = FlowWaitlistRegistration(email: "", accountID: "")
    XCTAssertFalse(registration.belongsTo(userID: nil, email: "person@example.com"))
    XCTAssertFalse(registration.belongsTo(userID: "account-a", email: "person@example.com"))
  }
}
