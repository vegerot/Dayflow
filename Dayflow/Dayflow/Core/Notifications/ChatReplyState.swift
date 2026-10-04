import Foundation

/// Stores unread state and suppresses duplicate alerts after polling or relaunching.
struct ChatReplyState {
  let defaults: UserDefaults
  let keyPrefix: String

  var unreadCount: Int {
    defaults.integer(forKey: "\(keyPrefix).unreadCount")
  }

  /// Returns whether this response contains a reply we have not notified about.
  func receive(unreadCount: Int, latestReplyID: String?) -> Bool {
    let unreadCount = max(0, unreadCount)
    defaults.set(unreadCount, forKey: "\(keyPrefix).unreadCount")
    guard unreadCount > 0, let latestReplyID, !latestReplyID.isEmpty else { return false }
    let key = "\(keyPrefix).lastNotifiedReply"
    guard defaults.string(forKey: key) != latestReplyID else { return false }
    defaults.set(latestReplyID, forKey: key)
    return true
  }
}
