import AppKit
import Foundation

enum CLIAgentPreference {
    private static func key(_ agent: AgentKind) -> String { "\(agent.rawValue)ProviderID" }

    static func providerID(for agent: AgentKind) -> String? {
        UserDefaults.standard.string(forKey: key(agent))
    }

    static func setProviderID(_ providerID: String?, for agent: AgentKind) {
        if let providerID, !providerID.isEmpty {
            UserDefaults.standard.set(providerID, forKey: key(agent))
        } else {
            UserDefaults.standard.removeObject(forKey: key(agent))
        }
    }
}

struct CLIAgentModelConfig: Equatable, Sendable {
    let model: String
    let provider: String
    let baseURL: String?

    static func unavailable(_ agent: AgentKind) -> CLIAgentModelConfig {
        CLIAgentModelConfig(model: "未配置模型", provider: agent.displayName, baseURL: nil)
    }
}

struct CLIAgentStatus: Equatable, Sendable {
    let installed: Bool
    let version: String?
    let config: CLIAgentModelConfig
    let detail: String

    static func unavailable(_ agent: AgentKind) -> CLIAgentStatus {
        CLIAgentStatus(
            installed: false,
            version: nil,
            config: .unavailable(agent),
            detail: "尚未读取 \(agent.displayName) 状态"
        )
    }
}

enum CLIAgentIntegrationError: LocalizedError {
    case cliNotFound(String)
    case incompatibleProtocol(String)
    case invalidConfiguration(String)
    case cannotWrite(String)
    case cannotLaunch(String)

    var errorDescription: String? {
        switch self {
        case let .cliNotFound(name): return "未找到 \(name) CLI。"
        case let .incompatibleProtocol(message): return message
        case let .invalidConfiguration(message): return "配置无法识别：\(message)"
        case let .cannotWrite(message): return "无法更新 Agent 配置：\(message)"
        case let .cannotLaunch(message): return "无法打开终端 Agent：\(message)"
        }
    }
}

private enum CLIJSONConfig {
    static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIAgentIntegrationError.invalidConfiguration(url.path)
        }
        return object
    }

    static func write(_ object: [String: Any], to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch let error as CLIAgentIntegrationError {
            throw error
        } catch {
            throw CLIAgentIntegrationError.cannotWrite(error.localizedDescription)
        }
    }

    static func snapshotIfNeeded(configURL: URL, backupURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try CredentialStore.prepareDirectory()
            let existed = FileManager.default.fileExists(atPath: configURL.path)
            let payload: [String: Any] = [
                "existed": existed,
                "data": existed ? (try Data(contentsOf: configURL)).base64EncodedString() : ""
            ]
            try write(payload, to: backupURL)
        } catch {
            throw CLIAgentIntegrationError.cannotWrite(error.localizedDescription)
        }
    }

    static func restore(configURL: URL, backupURL: URL) throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            let backup = try read(backupURL)
            if backup["existed"] as? Bool == true,
               let encoded = backup["data"] as? String,
               let data = Data(base64Encoded: encoded) {
                try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: configURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: configURL.path) {
                try FileManager.default.removeItem(at: configURL)
            }
            try FileManager.default.removeItem(at: backupURL)
        } catch {
            throw CLIAgentIntegrationError.cannotWrite(error.localizedDescription)
        }
    }
}

enum TerminalCLILauncher {
    static func launch(executable: URL) throws {
        let command = shellQuote(executable.path)
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escaped)\"\ntell application \"Terminal\" to activate"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do { try process.run() }
        catch { throw CLIAgentIntegrationError.cannotLaunch(error.localizedDescription) }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ClaudeCodeIntegration {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private static var backupURL: URL { CredentialStore.directoryURL.appendingPathComponent("claude-settings.backup.json") }

    static func cliURL() -> URL? {
        executable(candidates: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ])
    }

    static func readStatus() -> CLIAgentStatus {
        let config = (try? CLIJSONConfig.read(configURL)) ?? [:]
        let env = config["env"] as? [String: Any] ?? [:]
        let model = config["model"] as? String ?? env["ANTHROPIC_MODEL"] as? String ?? "default"
        let baseURL = env["ANTHROPIC_BASE_URL"] as? String
        let provider = baseURL == nil ? "Anthropic 官方" : "自定义 Anthropic"
        let cli = cliURL()
        return CLIAgentStatus(
            installed: cli != nil,
            version: cli.flatMap { version(executable: $0) },
            config: CLIAgentModelConfig(model: model, provider: provider, baseURL: baseURL),
            detail: cli == nil ? "未找到 Claude CLI" : "\(provider) · \(model)"
        )
    }

    static func apply(profile: ProviderProfile) throws {
        guard profile.effectiveAPIFormat == .anthropicMessages else {
            throw CLIAgentIntegrationError.incompatibleProtocol("Claude CLI 只支持 Anthropic Messages 格式，请编辑提供商的 API 格式。")
        }
        guard CredentialStore.load(providerID: profile.id)?.isEmpty == false else {
            throw CLIAgentIntegrationError.invalidConfiguration("API Key 未配置")
        }
        try CLIJSONConfig.snapshotIfNeeded(configURL: configURL, backupURL: backupURL)
        var config = try CLIJSONConfig.read(configURL)
        var env = config["env"] as? [String: Any] ?? [:]
        env["ANTHROPIC_BASE_URL"] = profile.normalizedBaseURL
        env["ANTHROPIC_MODEL"] = profile.model
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        config["env"] = env
        config["model"] = profile.model
        config["apiKeyHelper"] = "/bin/cat \(TerminalCLILauncher.shellQuote(CredentialStore.keyURL(for: profile.id).path))"
        try CLIJSONConfig.write(config, to: configURL)
    }

    static func restoreOfficial() throws { try CLIJSONConfig.restore(configURL: configURL, backupURL: backupURL) }
    static func launch() throws {
        guard let cli = cliURL() else { throw CLIAgentIntegrationError.cliNotFound("Claude") }
        try TerminalCLILauncher.launch(executable: cli)
    }
}

enum OpenCodeIntegration {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode/opencode.json")
    }
    private static var backupURL: URL { CredentialStore.directoryURL.appendingPathComponent("opencode-settings.backup.json") }

    static func cliURL() -> URL? {
        executable(candidates: [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".opencode/bin/opencode"),
            URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
            URL(fileURLWithPath: "/usr/local/bin/opencode")
        ])
    }

    static func readStatus() -> CLIAgentStatus {
        let config = (try? CLIJSONConfig.read(configURL)) ?? [:]
        let model = config["model"] as? String ?? "未选择模型"
        let providerID = model.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "OpenCode"
        let cli = cliURL()
        return CLIAgentStatus(
            installed: cli != nil,
            version: cli.flatMap { version(executable: $0) },
            config: CLIAgentModelConfig(model: model, provider: providerID, baseURL: nil),
            detail: cli == nil ? "未找到 OpenCode CLI" : "\(providerID) · \(model)"
        )
    }

    static func apply(profile: ProviderProfile) throws {
        guard CredentialStore.load(providerID: profile.id)?.isEmpty == false else {
            throw CLIAgentIntegrationError.invalidConfiguration("API Key 未配置")
        }
        try CLIJSONConfig.snapshotIfNeeded(configURL: configURL, backupURL: backupURL)
        var config = try CLIJSONConfig.read(configURL)
        var providers = config["provider"] as? [String: Any] ?? [:]
        let providerID = "agent-pulse-\(profile.id.lowercased())"
        let package: String
        switch profile.effectiveAPIFormat {
        case .anthropicMessages:
            package = "@ai-sdk/anthropic"
        case .chatCompletions:
            package = "@ai-sdk/openai-compatible"
        case .automatic, .responses:
            package = "@ai-sdk/openai"
        }
        providers[providerID] = [
            "name": profile.name,
            "npm": package,
            "options": [
                "baseURL": profile.normalizedBaseURL,
                "apiKey": "{file:\(CredentialStore.keyURL(for: profile.id).path)}"
            ],
            "models": [profile.model: ["name": profile.model]]
        ]
        config["provider"] = providers
        config["model"] = "\(providerID)/\(profile.model)"
        config["small_model"] = "\(providerID)/\(profile.model)"
        if config["$schema"] == nil { config["$schema"] = "https://opencode.ai/config.json" }
        try CLIJSONConfig.write(config, to: configURL)
    }

    static func restoreOfficial() throws { try CLIJSONConfig.restore(configURL: configURL, backupURL: backupURL) }
    static func launch() throws {
        guard let cli = cliURL() else { throw CLIAgentIntegrationError.cliNotFound("OpenCode") }
        try TerminalCLILauncher.launch(executable: cli)
    }
}

private func executable(candidates: [URL]) -> URL? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
}

private func version(executable: URL) -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = ["--version"]
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        process.waitUntilExit()
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return nil }
}
