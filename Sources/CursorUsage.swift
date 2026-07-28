import Foundation

struct CursorOfficialUsageSnapshot: Sendable {
    let billingCycleStart: Date?
    let billingCycleEnd: Date?
    let usedCents: Int
    let limitCents: Int
    let remainingCents: Int
    let bonusCents: Int?

    var remainingPercent: Double? {
        guard limitCents > 0 else { return nil }
        return min(100, max(0, Double(remainingCents) / Double(limitCents) * 100))
    }
}

enum CursorOfficialUsageError: LocalizedError {
    case permissionRequired
    case accountDatabaseMissing
    case notLoggedIn
    case tokenReadFailed
    case unauthorized
    case server(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "请在设置中允许读取 Cursor 官方用量。"
        case .accountDatabaseMissing:
            return "未找到 Cursor 本地账号数据。"
        case .notLoggedIn:
            return "Cursor 官方账号未登录。"
        case .tokenReadFailed:
            return "无法读取 Cursor 本地登录状态。"
        case .unauthorized:
            return "Cursor 登录状态已失效，请重新登录。"
        case let .server(code, message):
            return "Cursor 用量服务错误（HTTP \(code)）：\(message)"
        case .invalidResponse:
            return "Cursor 官方用量格式暂不兼容。"
        }
    }
}

enum CursorOfficialUsageClient {
    private static let endpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!

    static func fetch() async throws -> CursorOfficialUsageSnapshot {
        guard CursorUsagePreference.officialUsageEnabled else {
            throw CursorOfficialUsageError.permissionRequired
        }
        let token = try await Task.detached(priority: .utility) {
            try readAccessToken()
        }.value
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorOfficialUsageError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorOfficialUsageError.unauthorized
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)?
                .prefix(160)
                .description ?? "未知错误"
            throw CursorOfficialUsageError.server(http.statusCode, message)
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> CursorOfficialUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = dictionary(root, camel: "planUsage", snake: "plan_usage") else {
            throw CursorOfficialUsageError.invalidResponse
        }
        let used = integer(usage, camel: "totalSpend", snake: "total_spend") ?? 0
        let limit = integer(usage, camel: "limit", snake: "limit") ?? 0
        let remaining = integer(usage, camel: "remaining", snake: "remaining")
            ?? max(0, limit - used)
        let remainingBonus = integer(
            usage,
            camel: "remainingBonus",
            snake: "remaining_bonus"
        )
        guard limit > 0 || remaining > 0 || used > 0 else {
            throw CursorOfficialUsageError.invalidResponse
        }
        return CursorOfficialUsageSnapshot(
            billingCycleStart: date(root, camel: "billingCycleStart", snake: "billing_cycle_start"),
            billingCycleEnd: date(root, camel: "billingCycleEnd", snake: "billing_cycle_end"),
            usedCents: used,
            limitCents: limit,
            remainingCents: remaining,
            bonusCents: remainingBonus
        )
    }

    private static func readAccessToken(databaseURL customDatabaseURL: URL? = nil) throws -> String {
        let databaseURL = customDatabaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CursorOfficialUsageError.accountDatabaseMissing
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            databaseURL.path,
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CursorOfficialUsageError.tokenReadFailed
        }
        guard process.terminationStatus == 0 else {
            throw CursorOfficialUsageError.tokenReadFailed
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        var token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.first == "\"", token.last == "\"",
           let decoded = try? JSONDecoder().decode(String.self, from: Data(token.utf8)) {
            token = decoded
        }
        guard !token.isEmpty else { throw CursorOfficialUsageError.notLoggedIn }
        return token
    }

    private static func dictionary(
        _ value: [String: Any],
        camel: String,
        snake: String
    ) -> [String: Any]? {
        value[camel] as? [String: Any] ?? value[snake] as? [String: Any]
    }

    private static func integer(
        _ value: [String: Any],
        camel: String,
        snake: String
    ) -> Int? {
        let raw = value[camel] ?? value[snake]
        if let number = raw as? NSNumber { return number.intValue }
        if let string = raw as? String { return Int(string) }
        return nil
    }

    private static func date(
        _ value: [String: Any],
        camel: String,
        snake: String
    ) -> Date? {
        guard let timestamp = integer(value, camel: camel, snake: snake) else { return nil }
        let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1_000 : Double(timestamp)
        return Date(timeIntervalSince1970: seconds)
    }
}
