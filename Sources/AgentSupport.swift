import AppKit
import Foundation

enum AgentKind: String, CaseIterable, Equatable, Sendable {
    case codex
    case cursor

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }
}

enum AgentPreference {
    private static let key = "selectedAgent"

    static var selected: AgentKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let agent = AgentKind(rawValue: raw) else { return .codex }
            return agent
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}

enum CursorUsagePreference {
    private static let officialUsageKey = "cursorOfficialUsageEnabled"
    private static let providerIDKey = "cursorBalanceProviderID"

    static var officialUsageEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: officialUsageKey) }
        set { UserDefaults.standard.set(newValue, forKey: officialUsageKey) }
    }

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

struct CursorStatus: Sendable {
    let isInstalled: Bool
    let cliAvailable: Bool
    let isAuthenticated: Bool?
    let detail: String

    static let unavailable = CursorStatus(
        isInstalled: false,
        cliAvailable: false,
        isAuthenticated: nil,
        detail: "未找到 Cursor"
    )
}

enum CursorIntegrationError: LocalizedError {
    case appNotFound
    case cannotRestart
    case invalidHooksFile
    case cannotInstallHooks(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "未找到 Cursor.app，请先安装 Cursor。"
        case .cannotRestart:
            return "Cursor 未能正常退出，请结束当前任务后手动重启 Cursor。"
        case .invalidHooksFile:
            return "~/.cursor/hooks.json 不是有效的 JSON，已停止安装以保护现有配置。"
        case let .cannotInstallHooks(message):
            return "无法安装 Cursor 状态 Hooks：\(message)"
        }
    }
}

@MainActor
enum CursorLauncher {
    private static let bundleIdentifiers = [
        "com.todesktop.230313mzl4w4u92",
        "com.cursor.Cursor"
    ]

    static func applicationURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications/Cursor.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Cursor.app", isDirectory: true)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var isRunning: Bool {
        bundleIdentifiers.contains { identifier in
            !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
        }
    }

    static func launch() async throws {
        guard let appURL = applicationURL() else {
            throw CursorIntegrationError.appNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func restart() async throws {
        let running = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        for application in running {
            application.terminate()
        }
        if !running.isEmpty {
            for _ in 0..<30 {
                if running.allSatisfy({ $0.isTerminated }) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard running.allSatisfy({ $0.isTerminated }) else {
                throw CursorIntegrationError.cannotRestart
            }
        }
        try await launch()
    }

    static func openModelSettings() async throws {
        try await launch()
        if let settingsURL = URL(string: "cursor://settings/cursor-settings-models") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

enum CursorIntegration {
    private static let hookMappings: [(event: String, state: String)] = [
        ("beforeSubmitPrompt", "running"),
        ("afterAgentThought", "running"),
        ("preToolUse", "waiting"),
        ("postToolUse", "running"),
        ("postToolUseFailure", "running"),
        ("beforeShellExecution", "waiting"),
        ("afterShellExecution", "running"),
        ("beforeMCPExecution", "waiting"),
        ("afterMCPExecution", "running"),
        ("beforeReadFile", "waiting"),
        ("afterFileEdit", "running"),
        ("afterAgentResponse", "running"),
        ("stop", "ready"),
        ("sessionEnd", "ready")
    ]

    private static var cursorDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor", isDirectory: true)
    }

    static var hooksURL: URL {
        cursorDirectoryURL.appendingPathComponent("hooks.json")
    }

    static var supportDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Pulse", isDirectory: true)
    }

    static var hookScriptURL: URL {
        supportDirectoryURL.appendingPathComponent("cursor-hook.sh")
    }

    static var stateURL: URL {
        supportDirectoryURL.appendingPathComponent("cursor-state.json")
    }

    static func cliURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/cursor-agent"),
            URL(fileURLWithPath: "/opt/homebrew/bin/cursor-agent"),
            URL(fileURLWithPath: "/usr/local/bin/cursor-agent")
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func readCLIStatus(appInstalled: Bool) -> CursorStatus {
        guard let executable = cliURL() else {
            return CursorStatus(
                isInstalled: appInstalled,
                cliAvailable: false,
                isAuthenticated: nil,
                detail: appInstalled ? "Cursor 已安装；未找到 cursor-agent CLI" : "未找到 Cursor"
            )
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            return CursorStatus(
                isInstalled: appInstalled,
                cliAvailable: true,
                isAuthenticated: nil,
                detail: "无法读取 Cursor 登录状态"
            )
        }

        if semaphore.wait(timeout: .now() + 4) == .timedOut {
            process.terminate()
            return CursorStatus(
                isInstalled: appInstalled,
                cliAvailable: true,
                isAuthenticated: nil,
                detail: "Cursor 登录状态检查超时"
            )
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowercased = text.lowercased()
        let explicitlyLoggedOut = lowercased.contains("not authenticated")
            || lowercased.contains("not logged in")
            || lowercased.contains("unauthenticated")
        let authenticated = !explicitlyLoggedOut && (
            lowercased.contains("authenticated")
                || lowercased.contains("logged in")
                || process.terminationStatus == 0
        )
        return CursorStatus(
            isInstalled: appInstalled,
            cliAvailable: true,
            isAuthenticated: explicitlyLoggedOut ? false : authenticated,
            detail: text.isEmpty
                ? (authenticated ? "Cursor 已登录" : "Cursor 未登录")
                : text.components(separatedBy: .newlines).first ?? text
        )
    }

    static func hooksInstalled() -> Bool {
        guard let data = try? Data(contentsOf: hooksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }
        return hookMappings.allSatisfy { mapping in
            let entries = hooks[mapping.event] as? [[String: Any]] ?? []
            return entries.contains {
                ($0["command"] as? String)?.contains(hookScriptURL.path) == true
            }
        }
    }

    static func missingHookEvents() -> [String] {
        guard let data = try? Data(contentsOf: hooksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return hookMappings.map(\.event)
        }
        return hookMappings.compactMap { mapping in
            let entries = hooks[mapping.event] as? [[String: Any]] ?? []
            return entries.contains {
                ($0["command"] as? String)?.contains(hookScriptURL.path) == true
            } ? nil : mapping.event
        }
    }

    @discardableResult
    static func installHooks(
        cursorDirectory customCursorDirectory: URL? = nil,
        supportDirectory customSupportDirectory: URL? = nil
    ) throws -> Bool {
        let fileManager = FileManager.default
        let cursorDirectory = customCursorDirectory ?? cursorDirectoryURL
        let supportDirectory = customSupportDirectory ?? supportDirectoryURL
        let hooksFile = cursorDirectory.appendingPathComponent("hooks.json")
        let hookScriptFile = supportDirectory.appendingPathComponent("cursor-hook.sh")
        do {
            try fileManager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let scriptData = Data(hookScript.utf8)
            let existingScript = try? Data(contentsOf: hookScriptFile)
            let scriptChanged = existingScript != scriptData
            if scriptChanged {
                try scriptData.write(to: hookScriptFile, options: .atomic)
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: hookScriptFile.path
            )

            var root: [String: Any] = ["version": 1, "hooks": [String: Any]()]
            var existingHooksData: Data?
            if fileManager.fileExists(atPath: hooksFile.path) {
                let data = try Data(contentsOf: hooksFile)
                existingHooksData = data
                let backup = cursorDirectory.appendingPathComponent("hooks.json.agent-pulse.bak")
                if !fileManager.fileExists(atPath: backup.path) {
                    try data.write(to: backup, options: .atomic)
                }
                guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw CursorIntegrationError.invalidHooksFile
                }
                root = existing
            }

            var hooks = root["hooks"] as? [String: Any] ?? [:]
            for event in Array(hooks.keys) {
                guard let entries = hooks[event] as? [Any] else { continue }
                let filtered = entries.filter {
                    guard let entry = $0 as? [String: Any],
                          let command = entry["command"] as? String else { return true }
                    return !command.contains(hookScriptFile.path)
                }
                if filtered.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = filtered
                }
            }
            for mapping in hookMappings {
                let command = "\"\(shellEscaped(hookScriptFile.path))\" \(mapping.state) \(mapping.event)"
                var entries = hooks[mapping.event] as? [Any] ?? []
                entries.append(["command": command])
                hooks[mapping.event] = entries
            }
            root["version"] = root["version"] ?? 1
            root["hooks"] = hooks

            guard JSONSerialization.isValidJSONObject(root) else {
                throw CursorIntegrationError.invalidHooksFile
            }
            let rendered = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            let hooksChanged = existingHooksData != rendered
            if hooksChanged {
                try rendered.write(to: hooksFile, options: .atomic)
            }
            return scriptChanged || hooksChanged
        } catch let error as CursorIntegrationError {
            throw error
        } catch {
            throw CursorIntegrationError.cannotInstallHooks(error.localizedDescription)
        }
    }

    private static func shellEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private static let hookScript = """
    #!/bin/sh
    set -eu
    state="${1:-ready}"
    source="${2:-unknown}"
    state_dir="$HOME/Library/Application Support/Agent Pulse"
    state_file="$state_dir/cursor-state.json"
    temp_file="$state_file.tmp.$$"
    /bin/mkdir -p "$state_dir"
    /bin/cat >/dev/null || true
    timestamp=$(/bin/date +%s)
    /usr/bin/printf '{"state":"%s","source":"%s","timestamp":%s}\\n' "$state" "$source" "$timestamp" > "$temp_file"
    /bin/mv "$temp_file" "$state_file"
    /usr/bin/printf '{}\\n'
    """
}

enum CursorActivityReader {
    private struct StateFile: Decodable {
        let state: String
        let source: String?
        let timestamp: TimeInterval
    }

    static func read(stateURL customStateURL: URL? = nil) -> TaskActivitySnapshot {
        let stateURL = customStateURL ?? CursorIntegration.stateURL
        guard let data = try? Data(contentsOf: stateURL),
              let value = try? JSONDecoder().decode(StateFile.self, from: data) else {
            return TaskActivitySnapshot(state: .ready, changedAt: nil)
        }
        let changedAt = Date(timeIntervalSince1970: value.timestamp)
        guard changedAt > Date().addingTimeInterval(-12 * 60 * 60) else {
            return TaskActivitySnapshot(state: .ready, changedAt: changedAt)
        }
        switch value.state {
        case "running":
            return TaskActivitySnapshot(state: .running(1), changedAt: changedAt)
        case "waiting":
            return TaskActivitySnapshot(state: .waiting(1), changedAt: changedAt)
        default:
            return TaskActivitySnapshot(state: .ready, changedAt: changedAt)
        }
    }

    static func diagnostic(stateURL customStateURL: URL? = nil) -> String? {
        let stateURL = customStateURL ?? CursorIntegration.stateURL
        guard let data = try? Data(contentsOf: stateURL),
              let value = try? JSONDecoder().decode(StateFile.self, from: data) else {
            return nil
        }
        let source = value.source ?? value.state
        let date = Date(timeIntervalSince1970: value.timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return "\(source) · \(formatter.string(from: date))"
    }
}
