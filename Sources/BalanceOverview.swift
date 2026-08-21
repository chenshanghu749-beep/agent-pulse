import Foundation

enum StatusBalanceLayout {
    static let statusItemWidth: CGFloat = 154
    static let statusIconX: CGFloat = 4
    static let statusIconSlotWidth: CGFloat = 24
    static let balanceX: CGFloat = 32
    static let balanceWidth: CGFloat = 114
    static let trafficLightIconWidth: CGFloat = 54
    static let trafficLightBalanceX: CGFloat = 62
    static let trafficLightStatusItemWidth: CGFloat = 184
    static let pinwheelIconWidth: CGFloat = 29
    static let pinwheelBalanceX: CGFloat = 36
    static let pinwheelStatusItemWidth: CGFloat = 158
    static let rotationInterval: TimeInterval = 5
    static let contentMaxX = balanceX + balanceWidth

    static var fitsStatusItem: Bool {
        statusIconX + statusIconSlotWidth <= balanceX
            && contentMaxX <= statusItemWidth
    }

    static var trafficLightFitsStatusItem: Bool {
        statusIconX + trafficLightIconWidth <= trafficLightBalanceX
            && trafficLightBalanceX + balanceWidth <= trafficLightStatusItemWidth
    }

    static var pinwheelFitsStatusItem: Bool {
        statusIconX + pinwheelIconWidth <= pinwheelBalanceX
            && pinwheelBalanceX + balanceWidth <= pinwheelStatusItemWidth
    }
}

enum StatusBalanceFormatter {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([¥￥$€£₽₩]?)([-+]?\d[\d,]*(?:\.\d+)?)(%?)$"#
    )

    static func twoDecimalDisplay(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let numberRange = Range(match.range(at: 2), in: trimmed),
              let number = Double(trimmed[numberRange].replacingOccurrences(of: ",", with: "")) else {
            return value
        }
        let prefix = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]) } ?? ""
        let suffix = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) } ?? ""
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        let formatted = formatter.string(from: NSNumber(value: number)) ?? String(format: "%.2f", number)
        return prefix + formatted + suffix
    }
}

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

    static func entry(providerID: String) -> BalanceOverviewEntry? {
        entries().first { $0.providerID == providerID }
    }

    static func hasUsableValue(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let transientValues = [
            "—", "-", "余额读取中", "配额读取中", "余额不可用", "配额不可用",
            "余额 —", "余额 未配置", "暂不支持查询", "未配置 API Key", "正在读取"
        ]
        return !transientValues.contains(normalized)
    }

    static func upsert(_ entry: BalanceOverviewEntry) {
        var values = entries().filter { $0.id != entry.id }
        values.append(entry)
        save(values)
    }

    static func removeProvider(_ providerID: String) {
        save(entries().filter { $0.providerID != providerID })
    }

    static func remove(id: String) {
        save(entries().filter { $0.id != id })
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
