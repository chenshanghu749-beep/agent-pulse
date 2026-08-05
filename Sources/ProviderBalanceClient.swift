import Foundation

struct ProviderBalanceSnapshot: Sendable, Equatable {
    let displayText: String
    let detail: String
}

enum ProviderBalanceError: LocalizedError {
    case unsupported
    case missingManagementCredential
    case invalidURL
    case invalidResponse
    case timeout
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "该自定义提供商没有可用的余额查询接口。"
        case .missingManagementCredential:
            return "xAI 余额查询需要填写 Management Key 和 Team ID。"
        case .invalidURL:
            return "余额查询地址无效。"
        case .invalidResponse:
            return "余额接口返回了无法识别的数据。"
        case .timeout:
            return "余额查询超时，请稍后重试。"
        case let .server(code, message):
            return "余额查询失败（HTTP \(code)）：\(message)"
        }
    }
}

enum ProviderBalanceClient {
    static func managementCredentialID(for providerID: String) -> String {
        "\(providerID)-xai-management"
    }

    static func fetch(
        profile: ProviderProfile,
        apiKey: String,
        managementKey: String? = nil
    ) async throws -> ProviderBalanceSnapshot {
        if profile.isCodeAPI {
            let usage = try await CodeAPIClient.fetch(key: apiKey)
            return ProviderBalanceSnapshot(
                displayText: String(format: "余额 $%.2f", usage.balance),
                detail: "CodeAPI 账户余额"
            )
        }

        switch profile.effectiveVendor {
        case .deepSeek:
            return try await fetchDeepSeek(apiKey: apiKey)
        case .zhipuAI:
            return try await fetchZhipu(apiKey: apiKey, baseURL: profile.baseURL)
        case .moonshot:
            return try await fetchMoonshot(apiKey: apiKey, baseURL: profile.baseURL)
        case .miniMax:
            return try await fetchMiniMax(apiKey: apiKey, baseURL: profile.baseURL)
        case .stepFun:
            return try await fetchStepFun(apiKey: apiKey, baseURL: profile.baseURL)
        case .miMo, .bailian:
            throw ProviderBalanceError.unsupported
        case .xAI:
            guard let managementKey = managementKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !managementKey.isEmpty,
                  let teamID = profile.balanceTeamID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !teamID.isEmpty else {
                throw ProviderBalanceError.missingManagementCredential
            }
            return try await fetchXAI(managementKey: managementKey, teamID: teamID)
        case .custom:
            throw ProviderBalanceError.unsupported
        }
    }

    private static func fetchDeepSeek(apiKey: String) async throws -> ProviderBalanceSnapshot {
        let object = try await getJSON(
            urlString: "https://api.deepseek.com/user/balance",
            authorization: "Bearer \(apiKey)"
        )
        guard let infos = object["balance_infos"] as? [[String: Any]], !infos.isEmpty else {
            throw ProviderBalanceError.invalidResponse
        }
        let values = infos.compactMap { info -> String? in
            guard let amount = number(info["topped_up_balance"]) else { return nil }
            return currency(amount, code: info["currency"] as? String)
        }
        guard !values.isEmpty else { throw ProviderBalanceError.invalidResponse }
        return ProviderBalanceSnapshot(
            displayText: "余额 \(values.joined(separator: " · "))",
            detail: "充值余额，不含赠送额度"
        )
    }

    private static func fetchMoonshot(apiKey: String, baseURL: String) async throws -> ProviderBalanceSnapshot {
        let root = normalizedV1Base(baseURL, fallback: "https://api.moonshot.cn/v1")
        let object = try await getJSON(
            urlString: root + "/users/me/balance",
            authorization: "Bearer \(apiKey)"
        )
        let data = object["data"] as? [String: Any] ?? object
        guard let amount = number(data["cash_balance"]) else {
            throw ProviderBalanceError.invalidResponse
        }
        return ProviderBalanceSnapshot(
            displayText: "余额 \(currency(amount, code: "CNY"))",
            detail: "现金余额，不含代金券"
        )
    }

    private static func fetchStepFun(apiKey: String, baseURL _: String) async throws -> ProviderBalanceSnapshot {
        let object = try await getJSON(
            urlString: "https://api.stepfun.com/v1/accounts",
            authorization: "Bearer \(apiKey)"
        )
        guard let amount = number(object["balance"]) else {
            throw ProviderBalanceError.invalidResponse
        }
        return ProviderBalanceSnapshot(
            displayText: "余额 \(currency(amount, code: "CNY"))",
            detail: "账户当前可用余额"
        )
    }

    private static func fetchZhipu(apiKey: String, baseURL: String) async throws -> ProviderBalanceSnapshot {
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        let root = host == "api.z.ai" ? "https://api.z.ai" : "https://open.bigmodel.cn"
        let object = try await getJSON(
            urlString: root + "/api/monitor/usage/quota/limit",
            authorization: apiKey,
            acceptLanguage: true
        )
        guard object["success"] as? Bool != false,
              let data = object["data"] as? [String: Any],
              let limits = data["limits"] as? [[String: Any]] else {
            throw ProviderBalanceError.invalidResponse
        }
        let tokenLimits = limits.filter {
            (($0["type"] as? String) ?? "").caseInsensitiveCompare("TOKENS_LIMIT") == .orderedSame
        }
        let fiveHour = tokenLimits.first(where: { integer($0["unit"]) == 3 }) ?? tokenLimits.first
        let weekly = tokenLimits.first(where: { integer($0["unit"]) == 6 })
        var pieces: [String] = []
        if let used = fiveHour.flatMap({ number($0["percentage"]) }) {
            pieces.append("5h \(percentRemaining(fromUsed: used))")
        }
        if let used = weekly.flatMap({ number($0["percentage"]) }) {
            pieces.append("周 \(percentRemaining(fromUsed: used))")
        }
        guard !pieces.isEmpty else { throw ProviderBalanceError.invalidResponse }
        return ProviderBalanceSnapshot(
            displayText: "配额 \(pieces.joined(separator: " · "))",
            detail: "智谱 Coding Plan 剩余额度"
        )
    }

    private static func fetchMiniMax(apiKey: String, baseURL: String) async throws -> ProviderBalanceSnapshot {
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        let root = host.contains("minimax.io") ? "https://api.minimax.io" : "https://api.minimaxi.com"
        let object = try await getJSON(
            urlString: root + "/v1/api/openplatform/coding_plan/remains",
            authorization: "Bearer \(apiKey)"
        )
        guard let remains = object["model_remains"] as? [[String: Any]],
              let general = remains.first(where: { ($0["model_name"] as? String) == "general" }) else {
            throw ProviderBalanceError.invalidResponse
        }
        var pieces: [String] = []
        if let remaining = number(general["current_interval_remaining_percent"]) {
            pieces.append("5h \(percent(remaining))")
        }
        if integer(general["current_weekly_status"]) == 1,
           let remaining = number(general["current_weekly_remaining_percent"]) {
            pieces.append("周 \(percent(remaining))")
        }
        guard !pieces.isEmpty else { throw ProviderBalanceError.invalidResponse }
        return ProviderBalanceSnapshot(
            displayText: "配额 \(pieces.joined(separator: " · "))",
            detail: "MiniMax Coding Plan 剩余额度"
        )
    }

    private static func fetchXAI(managementKey: String, teamID: String) async throws -> ProviderBalanceSnapshot {
        let encodedTeamID = teamID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? teamID
        let object = try await getJSON(
            urlString: "https://management-api.x.ai/v1/billing/teams/\(encodedTeamID)/prepaid/balance",
            authorization: "Bearer \(managementKey)"
        )
        let total = object["total"] as? [String: Any]
        guard let cents = number(total?["val"] ?? object["balance"]) else {
            throw ProviderBalanceError.invalidResponse
        }
        return ProviderBalanceSnapshot(
            displayText: "余额 \(currency(cents / 100, code: "USD"))",
            detail: "xAI Team 预付余额"
        )
    }

    private static func getJSON(
        urlString: String,
        authorization: String,
        acceptLanguage: Bool = false
    ) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw ProviderBalanceError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Agent-Pulse/3.0.1", forHTTPHeaderField: "User-Agent")
        if acceptLanguage { request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderBalanceError.timeout
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderBalanceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderBalanceError.server(http.statusCode, errorMessage(from: data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderBalanceError.invalidResponse
        }
        return object
    }

    private static func normalizedV1Base(_ baseURL: String, fallback: String) -> String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if value.isEmpty { value = fallback }
        if !value.lowercased().hasSuffix("/v1") { value += "/v1" }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        number(value).map(Int.init)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", min(100, max(0, value)))
    }

    private static func percentRemaining(fromUsed used: Double) -> String {
        percent(100 - used)
    }

    private static func currency(_ amount: Double, code: String?) -> String {
        let currencyCode = code?.uppercased() ?? ""
        let prefix: String
        switch currencyCode {
        case "CNY", "RMB": prefix = "¥"
        case "USD": prefix = "$"
        default: prefix = currencyCode.isEmpty ? "" : "\(currencyCode) "
        }
        return String(format: "%@%.2f", prefix, amount)
    }

    private static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return String(message.prefix(300))
            }
            for key in ["message", "msg"] {
                if let message = object[key] as? String { return String(message.prefix(300)) }
            }
            if let base = object["base_resp"] as? [String: Any], let message = base["status_msg"] as? String {
                return String(message.prefix(300))
            }
        }
        return String(String(data: data, encoding: .utf8)?.prefix(300) ?? "未知错误")
    }
}
