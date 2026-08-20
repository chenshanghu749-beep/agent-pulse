import Foundation

struct BalanceOverviewEntry: Codable, Equatable, Sendable {
    let id: String
    let providerID: String?
    let name: String
    let value: String
    let detail: String
    let isOfficial: Bool
    let updatedAt: Date
}

enum BalanceOverviewStore {
    private static let key = "balanceOverviewEntries"

    static func entries() -> [BalanceOverviewEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([BalanceOverviewEntry].self, from: data) else {
            return []
        }
        return values.sorted(by: sort)
    }

    static func upsert(_ entry: BalanceOverviewEntry) {
        var values = entries().filter { $0.id != entry.id }
        values.append(entry)
        save(values)
    }

    static func removeProvider(_ providerID: String) {
        save(entries().filter { $0.providerID != providerID })
    }

    static func retainProviders(_ providerIDs: Set<String>) {
        save(entries().filter { entry in
            entry.isOfficial || entry.providerID.map(providerIDs.contains) == true
        })
    }

    private static func save(_ entries: [BalanceOverviewEntry]) {
        guard let data = try? JSONEncoder().encode(entries.sorted(by: sort)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func sort(_ lhs: BalanceOverviewEntry, _ rhs: BalanceOverviewEntry) -> Bool {
        if lhs.isOfficial != rhs.isOfficial { return lhs.isOfficial }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

enum StatusBalanceDisplayMode: String, CaseIterable {
    case current
    case rotateAll

    var displayName: String {
        switch self {
        case .current: return "当前余额"
        case .rotateAll: return "轮播全部"
        }
    }
}

enum StatusBalanceDisplayPreference {
    private static let key = "statusBalanceDisplayMode"

    static var selected: StatusBalanceDisplayMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let mode = StatusBalanceDisplayMode(rawValue: raw) else {
                return .current
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}
