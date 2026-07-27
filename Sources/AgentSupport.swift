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
    case invalidHooksFile
    case cannotInstallHooks(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return "未找到 Cursor.app，请先安装 Cursor。"
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

    static func launch() async throws {
        guard let appURL = applicationURL() else {
            throw CursorIntegrationError.appNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func openModelSettings() async throws {
        try await launch()
        if let settingsURL = URL(string: "cursor://settings/cursor-settings-models") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}

enum CursorIntegration {
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
        guard let content = try? String(contentsOf: hooksURL, encoding: .utf8) else {
            return false
        }
        return content
            .replacingOccurrences(of: "\\/", with: "/")
            .contains(hookScriptURL.path)
    }

    static func installHooks(
        cursorDirectory customCursorDirectory: URL? = nil,
        supportDirectory customSupportDirectory: URL? = nil
    ) throws {
        let fileManager = FileManager.default
        let cursorDirectory = customCursorDirectory ?? cursorDirectoryURL
        let supportDirectory = customSupportDirectory ?? supportDirectoryURL
        let hooksFile = cursorDirectory.appendingPathComponent("hooks.json")
        let hookScriptFile = supportDirectory.appendingPathComponent("cursor-hook.sh")
        do {
            try fileManager.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try Data(hookScript.utf8).write(to: hookScriptFile, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: hookScriptFile.path
            )

            var root: [String: Any] = ["version": 1, "hooks": [String: Any]()]
            if fileManager.fileExists(atPath: hooksFile.path) {
                let data = try Data(contentsOf: hooksFile)
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
            let mappings: [(event: String, state: String)] = [
                ("beforeSubmitPrompt", "running"),
                ("beforeShellCommand", "waiting"),
                ("afterShellCommand", "running"),
                ("beforeMCPExecution", "waiting"),
                ("afterMCPExecution", "running"),
                ("stop", "ready"),
                ("sessionEnd", "ready")
            ]
            for mapping in mappings {
                let command = "\"\(shellEscaped(hookScriptFile.path))\" \(mapping.state)"
                var entries = hooks[mapping.event] as? [Any] ?? []
                let alreadyInstalled = entries.contains {
                    guard let entry = $0 as? [String: Any],
                          let existingCommand = entry["command"] as? String else { return false }
                    return existingCommand.contains(hookScriptFile.path)
                }
                if !alreadyInstalled {
                    entries.append(["command": command])
                }
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
            try rendered.write(to: hooksFile, options: .atomic)
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
    state_dir="$HOME/Library/Application Support/Agent Pulse"
    state_file="$state_dir/cursor-state.json"
    temp_file="$state_file.tmp.$$"
    /bin/mkdir -p "$state_dir"
    /bin/cat >/dev/null || true
    timestamp=$(/bin/date +%s)
    /usr/bin/printf '{"state":"%s","timestamp":%s}\\n' "$state" "$timestamp" > "$temp_file"
    /bin/mv "$temp_file" "$state_file"
    /usr/bin/printf '{}\\n'
    """
}

enum CursorActivityReader {
    private struct StateFile: Decodable {
        let state: String
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
}
