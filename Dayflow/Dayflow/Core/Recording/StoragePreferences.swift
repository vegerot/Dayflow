import Foundation

enum StoragePreferences {
    private static let limitKey = "storageLimitBytes"
    private static let defaults = UserDefaults.standard
    private static let defaultLimit: Int64 = 10_000_000_000 // 10 GB

    static var limitBytes: Int64 {
        get {
            let stored = defaults.object(forKey: limitKey) as? NSNumber
            return stored?.int64Value ?? defaultLimit
        }
        set {
            defaults.set(NSNumber(value: newValue), forKey: limitKey)
        }
    }
}
