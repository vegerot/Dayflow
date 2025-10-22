import Foundation

enum UserDefaultsMigrator {
    private static let sentinelKey = "didMigrateFromSandboxDefaults"

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: sentinelKey) {
            return
        }

        guard let bundleId = Bundle.main.bundleIdentifier else {
            defaults.set(true, forKey: sentinelKey)
            return
        }

        let fileManager = FileManager.default
        let containerPlist = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")
        let targetPlist = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(bundleId).plist")

        guard fileManager.fileExists(atPath: containerPlist.path) else {
            defaults.set(true, forKey: sentinelKey)
            return
        }

        do {
            if fileManager.fileExists(atPath: targetPlist.path) {
                let backup = targetPlist.appendingPathExtension("preMigration")
                do {
                    try? fileManager.removeItem(at: backup)
                    try fileManager.moveItem(at: targetPlist, to: backup)
                } catch {
                    print("⚠️ UserDefaultsMigrator: failed to back up existing defaults: \(error)")
                }
            }

            if fileManager.fileExists(atPath: targetPlist.path) {
                try fileManager.removeItem(at: targetPlist)
            }

            try fileManager.copyItem(at: containerPlist, to: targetPlist)
            if let migratedDefaults = NSDictionary(contentsOf: targetPlist) as? [String: Any] {
                var mergedDefaults = defaults.persistentDomain(forName: bundleId) ?? [:]
                var didMerge = false

                for (key, value) in migratedDefaults where mergedDefaults[key] == nil {
                    mergedDefaults[key] = value
                    didMerge = true
                }

                if didMerge {
                    // Hydrate missing keys so callers see the migrated values without clobbering newer writes.
                    defaults.setPersistentDomain(mergedDefaults, forName: bundleId)
                }
            } else {
                print("⚠️ UserDefaultsMigrator: failed to hydrate migrated defaults from \(targetPlist.path)")
            }
            defaults.set(true, forKey: sentinelKey)
            print("UserDefaultsMigrator: copied sandbox defaults to \(targetPlist.path)")
        } catch {
            print("⚠️ UserDefaultsMigrator: failed to migrate defaults: \(error)")
        }
    }
}
