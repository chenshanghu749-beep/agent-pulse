import AppKit
import Foundation

enum HermesPreference {
    private static let providerIDKey = "hermesProviderID"

    static var providerID: String? {
        get { UserDefaults.standard.string(forKey: providerIDKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: providerIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerIDKey)
            }
        }
    }
}

struct HermesModelConfig: Codable, Equatable, Sendable {
    let model: String
    let provider: String
    let baseURL: String?
    let apiMode: String?

    static let unavailable = HermesModelConfig(
        model: "未配置模型",
        provider: "Hermes",
        baseURL: nil,
        apiMode: nil
    )
}

struct HermesStatus: Sendable, Equatable {
    let isInstalled: Bool
    let cliAvailable: Bool
    let version: String?
    let modelConfig: HermesModelConfig
    let detail: String

    static let unavailable = HermesStatus(
        isInstalled: false,
        cliAvailable: false,
        version: nil,
        modelConfig: .unavailable,
        detail: "未找到 Hermes"
    )
}

struct HermesUsageSnapshot: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let apiCalls: Int
    let estimatedCostUSD: Double
    let actualCostUSD: Double

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + reasoningTokens
    }

    var displayCostUSD: Double {
        actualCostUSD > 0 ? actualCostUSD : estimatedCostUSD
    }
}

enum HermesIntegrationError: LocalizedError {
    case appNotFound
    case cliNotFound
    case invalidConfiguration
    case commandFailed(String)
    case timeout
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "未找到 Hermes.app，请先安装 Hermes。"
        case .cliNotFound:
            return "未找到 hermes CLI，无法更新模型配置。"
        case .invalidConfiguration:
            return "Hermes 模型配置无法识别。"
        case let .commandFailed(message):
            return "Hermes 配置失败：\(message)"
        case .timeout:
            return "Hermes 命令执行超时。"
        case let .cannotWrite(message):
            return "无法更新 Hermes 配置：\(message)"
        }
    }
}

@MainActor
enum HermesLauncher {
    static let bundleIdentifier = "com.nousresearch.hermes.setup"

    static func applicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/Hermes.app", isDirectory: true),
            home.appendingPathComponent("Applications/Hermes.app", isDirectory: true)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func launch() async throws {
        guard let appURL = applicationURL() else { throw HermesIntegrationError.appNotFound }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}

enum HermesIntegration {
    private struct Backup: Codable {
        let modelConfig: HermesModelConfig
        let openAIEnvironmentLine: String?
    }

    static var homeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
    }

    static var configURL: URL { homeURL.appendingPathComponent("config.yaml") }
    static var environmentURL: URL { homeURL.appendingPathComponent(".env") }
    static var gatewayStateURL: URL { homeURL.appendingPathComponent("gateway_state.json") }
    static var stateDatabaseURL: URL { homeURL.appendingPathComponent("state.db") }
    private static var backupURL: URL { homeURL.appendingPathComponent("agent-pulse-model-backup.json") }

    static func cliURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/hermes"),
            home.appendingPathComponent(".hermes/bin/hermes"),
            URL(fileURLWithPath: "/opt/homebrew/bin/hermes"),
            URL(fileURLWithPath: "/usr/local/bin/hermes")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func readStatus() -> HermesStatus {
        let appInstalled = FileManager.default.fileExists(
            atPath: "/Applications/Hermes.app"
        ) || FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Hermes.app").path
        )
        guard let cli = cliURL() else {
            return HermesStatus(
                isInstalled: appInstalled,
                cliAvailable: false,
                version: nil,
                modelConfig: readModelConfig(),
                detail: appInstalled ? "Hermes 已安装；未找到 hermes CLI" : "未找到 Hermes"
            )
        }
        let versionOutput = try? run(executable: cli, arguments: ["--version"], timeout: 4)
        let version = versionOutput?
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let config = readModelConfig()
        return HermesStatus(
            isInstalled: appInstalled,
            cliAvailable: true,
            version: version,
            modelConfig: config,
            detail: "\(config.provider) · \(config.model)"
        )
    }

    static func readModelConfig(at url: URL? = nil) -> HermesModelConfig {
        guard let content = try? String(contentsOf: url ?? configURL, encoding: .utf8) else {
            return .unavailable
        }
        var inModel = false
        var values: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                if trimmed == "model:" {
                    inModel = true
                    continue
                }
                if inModel, !trimmed.isEmpty { break }
            }
            guard inModel,
                  let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if ["default", "provider", "base_url", "api_mode"].contains(key), !value.isEmpty {
                values[key] = value
            }
        }
        return HermesModelConfig(
            model: values["default"] ?? "未配置模型",
            provider: values["provider"] ?? "Hermes",
            baseURL: values["base_url"],
            apiMode: values["api_mode"]
        )
    }

    static func apply(profile: ProviderProfile, apiKey: String) throws {
        guard let cli = cliURL() else { throw HermesIntegrationError.cliNotFound }
        try snapshotIfNeeded()
        do {
            try setConfig(cli: cli, key: "model.provider", value: "custom")
            try setConfig(cli: cli, key: "model.base_url", value: profile.normalizedBaseURL)
            try setConfig(cli: cli, key: "model.default", value: profile.model)
            try setConfig(cli: cli, key: "model.api_mode", value: "responses")
            try writeEnvironmentLine(key: "OPENAI_API_KEY", value: apiKey)
        } catch {
            try? restoreOriginalConfiguration()
            throw error
        }
    }

    static func restoreOriginalConfiguration() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        guard let cli = cliURL() else { throw HermesIntegrationError.cliNotFound }
        do {
            let data = try Data(contentsOf: backupURL)
            let backup = try JSONDecoder().decode(Backup.self, from: data)
            try setConfig(cli: cli, key: "model.default", value: backup.modelConfig.model)
            try setConfig(cli: cli, key: "model.provider", value: backup.modelConfig.provider)
            try setOptionalConfig(cli: cli, key: "model.base_url", value: backup.modelConfig.baseURL)
            try setOptionalConfig(cli: cli, key: "model.api_mode", value: backup.modelConfig.apiMode)
            try restoreEnvironmentLine(key: "OPENAI_API_KEY", originalLine: backup.openAIEnvironmentLine)
            try FileManager.default.removeItem(at: backupURL)
        } catch let error as HermesIntegrationError {
            throw error
        } catch {
            throw HermesIntegrationError.cannotWrite(error.localizedDescription)
        }
    }

    static func hasManagedConfiguration() -> Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    private static func snapshotIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
            let current = readModelConfig()
            guard current != .unavailable else {
                throw HermesIntegrationError.invalidConfiguration
            }
            let backup = Backup(
                modelConfig: current,
                openAIEnvironmentLine: environmentLine(key: "OPENAI_API_KEY")
            )
            let data = try JSONEncoder().encode(backup)
            try data.write(to: backupURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backupURL.path
            )
        } catch {
            throw HermesIntegrationError.cannotWrite(error.localizedDescription)
        }
    }

    private static func setConfig(cli: URL, key: String, value: String) throws {
        _ = try run(executable: cli, arguments: ["config", "set", key, value], timeout: 8)
    }

    private static func setOptionalConfig(cli: URL, key: String, value: String?) throws {
        if let value, !value.isEmpty {
            try setConfig(cli: cli, key: key, value: value)
        } else {
            _ = try run(executable: cli, arguments: ["config", "unset", key], timeout: 8)
        }
    }

    private static func environmentLine(key: String) -> String? {
        guard let content = try? String(contentsOf: environmentURL, encoding: .utf8) else { return nil }
        return content.components(separatedBy: .newlines).first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=")
        }
    }

    private static func writeEnvironmentLine(key: String, value: String) throws {
        guard !value.contains("\n"), !value.contains("\r") else {
            throw HermesIntegrationError.invalidConfiguration
        }
        try replaceEnvironmentLine(key: key, replacement: "\(key)=\(value)")
    }

    private static func restoreEnvironmentLine(key: String, originalLine: String?) throws {
        try replaceEnvironmentLine(key: key, replacement: originalLine)
    }

    private static func replaceEnvironmentLine(key: String, replacement: String?) throws {
        do {
            try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
            var lines = ((try? String(contentsOf: environmentURL, encoding: .utf8)) ?? "")
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") }
            while lines.last?.isEmpty == true { lines.removeLast() }
            if let replacement { lines.append(replacement) }
            let rendered = lines.joined(separator: "\n") + "\n"
            try Data(rendered.utf8).write(to: environmentURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: environmentURL.path
            )
        } catch {
            throw HermesIntegrationError.cannotWrite(error.localizedDescription)
        }
    }

    private static func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do {
            try process.run()
        } catch {
            throw HermesIntegrationError.commandFailed(error.localizedDescription)
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw HermesIntegrationError.timeout
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw HermesIntegrationError.commandFailed(String(text.prefix(400)))
        }
        return text
    }
}

enum HermesActivityReader {
    static func read(
        gatewayStateURL: URL? = nil,
        stateDatabaseURL: URL? = nil,
        now: Date = Date()
    ) -> TaskActivitySnapshot {
        let stateURL = gatewayStateURL ?? HermesIntegration.gatewayStateURL
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TaskActivitySnapshot(state: .ready, changedAt: nil)
        }
        let activeAgents = (object["active_agents"] as? NSNumber)?.intValue ?? 0
        let changedAt = (object["updated_at"] as? String).flatMap(parseDate)
        guard activeAgents > 0 else {
            return TaskActivitySnapshot(state: .ready, changedAt: changedAt)
        }
        let databaseURL = stateDatabaseURL ?? HermesIntegration.stateDatabaseURL
        if let activity = latestMessageActivity(databaseURL: databaseURL),
           now.timeIntervalSince1970 - activity.timestamp < 120,
           activity.isToolActivity {
            return TaskActivitySnapshot(state: .waiting(activeAgents), changedAt: changedAt)
        }
        return TaskActivitySnapshot(state: .running(activeAgents), changedAt: changedAt)
    }

    private struct MessageActivity {
        let isToolActivity: Bool
        let timestamp: TimeInterval
    }

    private static func latestMessageActivity(databaseURL: URL) -> MessageActivity? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let query = """
        SELECT role, tool_name,
               CASE WHEN tool_calls IS NULL OR tool_calls = '' THEN 0 ELSE 1 END AS has_tool_calls,
               timestamp
        FROM messages ORDER BY timestamp DESC LIMIT 1;
        """
        guard let output = runSQLite(databaseURL: databaseURL, query: query),
              let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        let role = (row["role"] as? String)?.lowercased() ?? ""
        let toolName = (row["tool_name"] as? String) ?? ""
        let hasToolCalls = (row["has_tool_calls"] as? NSNumber)?.intValue == 1
        let timestamp = (row["timestamp"] as? NSNumber)?.doubleValue ?? 0
        return MessageActivity(
            isToolActivity: role == "tool" || !toolName.isEmpty || hasToolCalls,
            timestamp: timestamp
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    fileprivate static func runSQLite(databaseURL: URL, query: String) -> String? {
        let executable = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-json", databaseURL.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

enum HermesUsageReader {
    static func readToday(
        databaseURL: URL? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HermesUsageSnapshot? {
        let url = databaseURL ?? HermesIntegration.stateDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let start = calendar.startOfDay(for: now).timeIntervalSince1970
        let query = """
        SELECT COALESCE(SUM(input_tokens), 0) AS input_tokens,
               COALESCE(SUM(output_tokens), 0) AS output_tokens,
               COALESCE(SUM(cache_read_tokens), 0) AS cache_read_tokens,
               COALESCE(SUM(reasoning_tokens), 0) AS reasoning_tokens,
               COALESCE(SUM(api_call_count), 0) AS api_calls,
               COALESCE(SUM(estimated_cost_usd), 0) AS estimated_cost_usd,
               COALESCE(SUM(actual_cost_usd), 0) AS actual_cost_usd
        FROM session_model_usage WHERE last_seen >= \(start);
        """
        guard let output = HermesActivityReader.runSQLite(databaseURL: url, query: query),
              let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        func integer(_ key: String) -> Int { (row[key] as? NSNumber)?.intValue ?? 0 }
        func double(_ key: String) -> Double { (row[key] as? NSNumber)?.doubleValue ?? 0 }
        return HermesUsageSnapshot(
            inputTokens: integer("input_tokens"),
            outputTokens: integer("output_tokens"),
            cacheReadTokens: integer("cache_read_tokens"),
            reasoningTokens: integer("reasoning_tokens"),
            apiCalls: integer("api_calls"),
            estimatedCostUSD: double("estimated_cost_usd"),
            actualCostUSD: double("actual_cost_usd")
        )
    }
}
