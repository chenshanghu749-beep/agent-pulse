import Foundation

enum AppIdentity {
    static let name = "Agent Pulse"
    static let bundleIdentifier = "net.nexita.agent-pulse"
    static let legacyBundleIdentifier = "net.nexita.codeapi-status"
    static let repository = "chenshanghu749-beep/agent-pulse"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!

    @discardableResult
    static func migrateLegacyPreferencesIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        let marker = "agentPulseIdentityMigrationV1"
        guard !defaults.bool(forKey: marker) else { return false }
        if let legacy = defaults.persistentDomain(forName: legacyBundleIdentifier) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
        return true
    }
}
