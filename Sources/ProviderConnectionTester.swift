import Foundation

enum ProviderConnectionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case timeout
    case modelUnavailable(String)
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Base URL 无效。"
        case .invalidResponse:
            return "提供商返回了无法识别的数据。"
        case .timeout:
            return "连接超时。提供商已收到请求，但模型服务未在 15 秒内返回。"
        case let .modelUnavailable(model):
            return "API Key 有效，但模型列表中没有 \(model)。"
        case let .server(code, message):
            return "请求失败（HTTP \(code)）：\(message)"
        }
    }
}

enum ProviderConnectionTester {
    static func test(profile: ProviderProfile, key: String) async throws -> String {
        if profile.isCodeAPI {
            return try await testCodeAPI(profile: profile, key: key)
        }

        let endpoint = try endpointURL(profile: profile)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Agent-Pulse/\(AppUpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")

        let usesChatCompletions = profile.effectiveVendor == .zhipuAI
        let body: [String: Any]
        if usesChatCompletions {
            body = [
                "model": profile.model,
                "messages": [["role": "user", "content": "Reply with OK only."]],
                "max_tokens": 16,
                "stream": false
            ]
        } else {
            body = [
                "model": profile.model,
                "input": "Reply with OK only.",
                "max_output_tokens": 16,
                "stream": false
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startedAt = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.data(for: request, timeout: 15)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderConnectionError.timeout
        }
        guard let http = response as? HTTPURLResponse else { throw ProviderConnectionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderConnectionError.server(http.statusCode, errorMessage(from: data))
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw ProviderConnectionError.invalidResponse
        }
        let duration = Date().timeIntervalSince(startedAt)
        let protocolName = usesChatCompletions ? "智谱 OpenAI Chat Completions" : "Responses API"
        return String(format: "连接成功 · %@ · %.1f 秒", protocolName, duration)
    }

    private static func testCodeAPI(profile: ProviderProfile, key: String) async throws -> String {
        let usage = try await CodeAPIClient.fetch(key: key)
        let modelsURL = try codeAPIModelsURL(profile: profile)
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Agent-Pulse/\(AppUpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await self.data(for: request, timeout: 10)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderConnectionError.timeout
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderConnectionError.server(http.statusCode, errorMessage(from: data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["data"] as? [[String: Any]] else {
            throw ProviderConnectionError.invalidResponse
        }
        let models = Set(entries.compactMap { $0["id"] as? String })
        guard models.contains(profile.model) else {
            throw ProviderConnectionError.modelUnavailable(profile.model)
        }
        return String(format: "连接成功 · CodeAPI · 余额 $%.2f · 模型可用", usage.balance)
    }

    private static func codeAPIModelsURL(profile: ProviderProfile) throws -> URL {
        var base = profile.normalizedBaseURL
        if !base.lowercased().hasSuffix("/v1") {
            base += "/v1"
        }
        guard let url = URL(string: base + "/models") else {
            throw ProviderConnectionError.invalidURL
        }
        return url
    }

    private static func data(
        for request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    static func endpointURL(profile: ProviderProfile) throws -> URL {
        let base = profile.normalizedBaseURL
        let suffix = profile.effectiveVendor == .zhipuAI ? "/chat/completions" : "/responses"
        if base.lowercased().hasSuffix(suffix) {
            guard let url = URL(string: base) else { throw ProviderConnectionError.invalidURL }
            return url
        }
        guard let url = URL(string: base + suffix) else { throw ProviderConnectionError.invalidURL }
        return url
    }

    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return String(message.prefix(400))
        }
        return String(String(data: data, encoding: .utf8)?.prefix(400) ?? "未知错误")
    }
}
