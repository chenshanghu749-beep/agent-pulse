import AppKit
import Foundation
import UserNotifications

struct UsageObservation: Codable, Equatable, Sendable {
    let recordedAt: Date
    let agent: String
    let route: String
    let metric: String
    let displayValue: String
    let detail: String
    let remainingPercent: Double?
    let balance: Double?
    let resetAt: Date?
    let modelKey: String?
    let modelName: String?
}

struct UsageDailySummary: Sendable {
    let date: Date
    let minimumRemainingPercent: Double?
    let latestBalance: Double?
    let sampleCount: Int
}

enum UsageHistoryStore {
    private static let queue = DispatchQueue(label: "net.nexita.agent-pulse.usage-history")
    private static var cachedValues: [UsageObservation]?
    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Pulse", isDirectory: true)
    }
    static var fileURL: URL { directoryURL.appendingPathComponent("usage-history.json") }

    static func record(_ observation: UsageObservation) {
        queue.async {
            var values = loadUnlocked()
            if let last = values.last,
               last.agent == observation.agent,
               last.route == observation.route,
               observation.recordedAt.timeIntervalSince(last.recordedAt) < 240,
               last.displayValue == observation.displayValue,
               last.detail == observation.detail {
                return
            }
            values.append(observation)
            let cutoff = Date().addingTimeInterval(-90 * 86_400)
            values = Array(values.filter { $0.recordedAt >= cutoff }.suffix(10_000))
            saveUnlocked(values)
        }
    }

    static func observations() -> [UsageObservation] { queue.sync { loadUnlocked() } }

    static func dailySummaries(days: Int = 7) -> [UsageDailySummary] {
        let calendar = Calendar.current
        let values = observations()
        return (0..<max(days, 1)).reversed().map { offset in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            let samples = values.filter { $0.recordedAt >= date && $0.recordedAt < next }
            return UsageDailySummary(
                date: date,
                minimumRemainingPercent: samples.compactMap(\.remainingPercent).min(),
                latestBalance: samples.last(where: { $0.balance != nil })?.balance,
                sampleCount: samples.count
            )
        }
    }

    static func csvData() -> Data {
        var rows = ["recorded_at,agent,route,metric,value,detail,remaining_percent,balance,reset_at"]
        let formatter = ISO8601DateFormatter()
        for value in observations() {
            let rawColumns: [String] = [
                formatter.string(from: value.recordedAt), value.agent, value.route, value.metric,
                value.displayValue, value.detail,
                value.remainingPercent.map { String($0) } ?? "",
                value.balance.map { String($0) } ?? "",
                value.resetAt.map { formatter.string(from: $0) } ?? ""
            ]
            let columns = rawColumns.map { csvEscape($0) }
            rows.append(columns.joined(separator: ","))
        }
        return Data((rows.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func loadUnlocked() -> [UsageObservation] {
        if let cachedValues { return cachedValues }
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? historyDecoder.decode([UsageObservation].self, from: data) else {
            cachedValues = []
            return []
        }
        let sorted = values.sorted { $0.recordedAt < $1.recordedAt }
        cachedValues = sorted
        return sorted
    }

    private static func saveUnlocked(_ values: [UsageObservation]) {
        cachedValues = values
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(values)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Agent Pulse failed to save usage history: %@", error.localizedDescription)
        }
    }

    private static var historyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum UsageAlertPreferences {
    private static let enabledKey = "usageAlertsEnabled"
    private static let warningKey = "usageWarningThreshold"
    private static let criticalKey = "usageCriticalThreshold"
    private static let balanceWarningKey = "balanceWarningThreshold"
    private static let balanceCriticalKey = "balanceCriticalThreshold"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    static var warningThreshold: Double {
        get { UserDefaults.standard.object(forKey: warningKey) == nil ? 20 : UserDefaults.standard.double(forKey: warningKey) }
        set { UserDefaults.standard.set(max(1, min(99, newValue)), forKey: warningKey) }
    }
    static var criticalThreshold: Double {
        get { UserDefaults.standard.object(forKey: criticalKey) == nil ? 10 : UserDefaults.standard.double(forKey: criticalKey) }
        set { UserDefaults.standard.set(max(1, min(99, newValue)), forKey: criticalKey) }
    }
    static var balanceWarningThreshold: Double {
        get { UserDefaults.standard.object(forKey: balanceWarningKey) == nil ? 10 : UserDefaults.standard.double(forKey: balanceWarningKey) }
        set { UserDefaults.standard.set(max(0.1, newValue), forKey: balanceWarningKey) }
    }
    static var balanceCriticalThreshold: Double {
        get { UserDefaults.standard.object(forKey: balanceCriticalKey) == nil ? 3 : UserDefaults.standard.double(forKey: balanceCriticalKey) }
        set { UserDefaults.standard.set(max(0.1, newValue), forKey: balanceCriticalKey) }
    }
}

enum UsageAlertMetricKind: String, Codable, Sendable {
    case percentage
    case balance

    var unit: String { self == .percentage ? "%" : "$" }
    var displayName: String { self == .percentage ? "剩余用量" : "可用余额" }
}

struct UsageAlertRule: Codable, Sendable {
    let metric: UsageAlertMetricKind
    let threshold: Double
}

enum UsageAlertRuleStore {
    private static let defaultsKey = "usageAlertRulesByModel"

    static func rule(for modelKey: String, metric: UsageAlertMetricKind) -> UsageAlertRule {
        if let stored = load()[modelKey], stored.metric == metric { return stored }
        let threshold = metric == .percentage
            ? UsageAlertPreferences.warningThreshold
            : UsageAlertPreferences.balanceWarningThreshold
        return UsageAlertRule(metric: metric, threshold: threshold)
    }

    static func save(_ rule: UsageAlertRule, for modelKey: String) {
        var values = load()
        values[modelKey] = rule
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func load() -> [String: UsageAlertRule] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let values = try? JSONDecoder().decode([String: UsageAlertRule].self, from: data) else {
            return [:]
        }
        return values
    }
}

enum UsageAlertManager {
    static func level(for remaining: Double) -> String? {
        if remaining <= UsageAlertPreferences.criticalThreshold { return "critical" }
        if remaining <= UsageAlertPreferences.warningThreshold { return "warning" }
        return nil
    }

    static func balanceLevel(for balance: Double) -> String? {
        if balance <= UsageAlertPreferences.balanceCriticalThreshold { return "critical" }
        if balance <= UsageAlertPreferences.balanceWarningThreshold { return "warning" }
        return nil
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func evaluate(_ observation: UsageObservation) {
        guard UsageAlertPreferences.enabled else { return }
        let modelKey = observation.modelKey ?? "\(observation.agent):\(observation.route)"
        let alertRule: UsageAlertRule
        let body: String
        if let remaining = observation.remainingPercent {
            alertRule = UsageAlertRuleStore.rule(for: modelKey, metric: .percentage)
            guard remaining <= alertRule.threshold else { return }
            body = "\(observation.route) 剩余 \(Int(remaining.rounded()))%" + resetText(observation.resetAt)
        } else if let balance = observation.balance {
            alertRule = UsageAlertRuleStore.rule(for: modelKey, metric: .balance)
            guard balance <= alertRule.threshold else { return }
            body = String(format: "%@ 可用余额 $%.2f。", observation.route, balance)
        } else { return }
        let resetKey = observation.resetAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        let key = "usageAlert.\(modelKey).\(alertRule.metric.rawValue).\(alertRule.threshold).\(resetKey)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "Agent Pulse：\(alertRule.metric.displayName)提醒"
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }

    private static func resetText(_ date: Date?) -> String {
        guard let date else { return "。" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return "，预计 \(formatter.string(from: date)) 重置。"
    }
}

enum RouteHealthState: String, Codable, Sendable {
    case unknown, checking, healthy, degraded, offline

    var title: String {
        switch self {
        case .unknown: return "未检测"
        case .checking: return "检测中"
        case .healthy: return "正常"
        case .degraded: return "可达"
        case .offline: return "异常"
        }
    }
}

struct RouteHealthSnapshot: Codable, Sendable {
    let providerID: String
    let state: RouteHealthState
    let latencyMilliseconds: Int?
    let checkedAt: Date
    let message: String
}

enum RouteHealthStore {
    private static let lock = NSLock()
    private static var values: [String: RouteHealthSnapshot] = [:]
    static func snapshot(for providerID: String) -> RouteHealthSnapshot? {
        lock.withLock { values[providerID] }
    }
    static func save(_ snapshot: RouteHealthSnapshot) {
        lock.withLock { values[snapshot.providerID] = snapshot }
    }
}

enum RouteHealthChecker {
    static func check(profile: ProviderProfile, key: String) async -> RouteHealthSnapshot {
        let started = Date()
        do {
            let message = try await ProviderConnectionTester.test(profile: profile, key: key)
            return RouteHealthSnapshot(
                providerID: profile.id,
                state: .healthy,
                latencyMilliseconds: Int(Date().timeIntervalSince(started) * 1000),
                checkedAt: Date(),
                message: message
            )
        } catch let error as ProviderConnectionError {
            let state: RouteHealthState
            switch error {
            case let .server(code, _) where code == 401 || code == 403:
                state = .degraded
            default:
                state = .offline
            }
            return RouteHealthSnapshot(
                providerID: profile.id,
                state: state,
                latencyMilliseconds: nil,
                checkedAt: Date(),
                message: error.localizedDescription
            )
        } catch {
            return RouteHealthSnapshot(
                providerID: profile.id,
                state: .offline,
                latencyMilliseconds: nil,
                checkedAt: Date(),
                message: error.localizedDescription
            )
        }
    }
}

final class UsageHistoryChartView: NSView {
    var summaries: [UsageDailySummary] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !summaries.isEmpty else { return }
        let width = bounds.width / CGFloat(summaries.count)
        for (index, summary) in summaries.enumerated() {
            let value = summary.minimumRemainingPercent ?? (summary.sampleCount > 0 ? 100 : 0)
            let height = max(3, bounds.height * CGFloat(value / 100))
            let rect = NSRect(x: CGFloat(index) * width + 5, y: 0, width: max(4, width - 10), height: height)
            let color: NSColor = value <= 10 ? .systemRed : (value <= 20 ? .systemOrange : .labelColor)
            color.withAlphaComponent(summary.sampleCount == 0 ? 0.12 : 0.82).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }
    }
}
