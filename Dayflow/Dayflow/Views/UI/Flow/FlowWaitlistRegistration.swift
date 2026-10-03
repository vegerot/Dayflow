import Foundation

/// The signup and chat identity survive independently of the in-memory auth session.
struct FlowWaitlistRegistration: Equatable {
  let email: String
  let accountID: String

  init(email: String, accountID: String) {
    self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    self.accountID = accountID
  }

  init(defaults: UserDefaults = .standard) {
    self.init(
      email: defaults.string(forKey: "flowWaitlistJoinedEmail") ?? "",
      accountID: defaults.string(forKey: "flowWaitlistJoinedAccountID") ?? ""
    )
  }

  func belongsTo(userID: String?, email userEmail: String?) -> Bool {
    guard !email.isEmpty else { return false }
    guard let userID else { return true }
    if !accountID.isEmpty { return accountID == userID }
    // Signing into the same email must keep the original anonymous chat store.
    return email == userEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var chatContext: SupportChatContext {
    .flowWaitlist(email: email, accountID: accountID.isEmpty ? nil : accountID)
  }
}
