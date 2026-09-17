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

        return try await testInference(profile: profile, key: key)
    }

    private static func testInference(profile: ProviderProfile, key: String) async throws -> String {
        let endpoint = try endpointURL(profile: profile)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        if profile.effectiveAPIFormat == .anthropicMessages {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Agent-Pulse/\(AppUpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")

        let usesAnthropic = profile.effectiveAPIFormat == .anthropicMessages
        let usesChatCompletions = !usesAnthropic && (
            profile.effectiveAPIFormat == .chatCompletions || profile.effectiveVendor == .zhipuAI
        )
        let body: [String: Any]
        if usesAnthropic {
            body = [
                "model": profile.model,
                "messages": [["role": "user", "content": "Reply with OK only."]],
                "max_tokens": 16,
                "stream": false
            ]
        } else if usesChatCompletions {
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
        let protocolName = usesAnthropic
            ? "Anthropic Messages API"
            : (usesChatCompletions ? "OpenAI Chat Completions" : "Responses API")
        return String(format: "连接成功 · %@ · %.1f 秒", protocolName, duration)
    }

    private static func testCodeAPI(profile: ProviderProfile, key: String) async throws -> String {
        // A successful /models response only proves that a model is listed.
        // Perform an actual inference before allowing a route to be selected.
        let result = try await testInference(profile: profile, key: key)
        return "\(result) · CodeAPI 模型可用"
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
        var base = profile.normalizedBaseURL
        if profile.isCodeAPI,
           !(URL(string: base)?.path.lowercased().hasPrefix("/v1") ?? false) {
            base += "/v1"
        }
        let suffix: String
        switch profile.effectiveAPIFormat {
        case .anthropicMessages:
            suffix = base.lowercased().hasSuffix("/v1") ? "/messages" : "/v1/messages"
        case .chatCompletions:
            suffix = "/chat/completions"
        case .automatic, .responses:
            suffix = profile.effectiveVendor == .zhipuAI ? "/chat/completions" : "/responses"
        }
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
