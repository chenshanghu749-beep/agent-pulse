import Foundation

struct AppUpdateStatus: Sendable {
    let currentVersion: String
    let latestVersion: String

    var updateAvailable: Bool {
        Self.compare(latestVersion, currentVersion) == .orderedDescending
    }

    var installerURL: URL {
        URL(
            string: "https://raw.githubusercontent.com/\(AppIdentity.repository)/main/dist/Agent-Pulse-\(latestVersion).dmg"
        )!
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case versionMissing
    case invalidPackage(String)
    case unsupportedInstallLocation
    case installLocationNotWritable
    case helperLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无法读取远程版本信息。"
        case .versionMissing: return "远程版本信息不完整。"
        case let .invalidPackage(message): return "更新包校验失败：\(message)"
        case .unsupportedInstallLocation: return "请先将 Agent Pulse 安装到 Applications 文件夹后再更新。"
        case .installLocationNotWritable: return "当前安装位置不可写，请使用安装包手动更新。"
        case let .helperLaunchFailed(message): return "无法启动更新程序：\(message)"
        }
    }
}

struct PreparedAppUpdate: Sendable {
    let helperURL: URL
    let currentAppURL: URL
    let stagedAppURL: URL
    let workingDirectoryURL: URL

    func launch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            currentAppURL.path,
            stagedAppURL.path,
            workingDirectoryURL.path
        ]
        do {
            try process.run()
        } catch {
            throw AppUpdateError.helperLaunchFailed(error.localizedDescription)
        }
    }
}

enum AppUpdateChecker {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static let remoteInfoURL = URL(
        string: "https://raw.githubusercontent.com/\(AppIdentity.repository)/main/Resources/Info.plist"
    )!

    static func check() async throws -> AppUpdateStatus {
        var request = URLRequest(url: remoteInfoURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppUpdateError.invalidResponse
        }
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
              let latest = plist["CFBundleShortVersionString"] as? String,
              !latest.isEmpty else {
            throw AppUpdateError.versionMissing
        }
        return AppUpdateStatus(currentVersion: currentVersion, latestVersion: latest)
    }
}

enum AppUpdateInstaller {
    private static let appName = "Agent Pulse.app"

    static func validateHelperScriptForTesting() throws {
        try run("/bin/zsh", ["-n", "-c", helperScript])
    }

    static func prepare(_ status: AppUpdateStatus) async throws -> PreparedAppUpdate {
        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL
        let parent = currentAppURL.deletingLastPathComponent().standardizedFileURL
        guard currentAppURL.pathExtension == "app",
              parent == homeApplications || parent == systemApplications else {
            throw AppUpdateError.unsupportedInstallLocation
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw AppUpdateError.installLocationNotWritable
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-update-\(UUID().uuidString)", isDirectory: true)
        let dmgURL = root.appendingPathComponent("Agent-Pulse-\(status.latestVersion).dmg")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var request = URLRequest(url: status.installerURL)
            request.timeoutInterval = 90
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Agent-Pulse/\(status.currentVersion)", forHTTPHeaderField: "User-Agent")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 180
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppUpdateError.invalidResponse
            }
            try FileManager.default.moveItem(at: temporaryURL, to: dmgURL)
            return try await Task.detached(priority: .userInitiated) {
                try stage(
                    dmgURL: dmgURL,
                    root: root,
                    currentAppURL: currentAppURL,
                    expectedVersion: status.latestVersion
                )
            }.value
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private static func stage(
        dmgURL: URL,
        root: URL,
        currentAppURL: URL,
        expectedVersion: String
    ) throws -> PreparedAppUpdate {
        try run("/usr/bin/hdiutil", ["verify", dmgURL.path])
        let mountURL = root.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        var mounted = false
        defer {
            if mounted {
                try? run("/usr/bin/hdiutil", ["detach", mountURL.path])
            }
        }
        try run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-mountpoint", mountURL.path, dmgURL.path
        ])
        mounted = true

        let sourceAppURL = mountURL.appendingPathComponent(appName, isDirectory: true)
        let infoURL = sourceAppURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == AppIdentity.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == expectedVersion else {
            throw AppUpdateError.invalidPackage("应用标识或版本号不匹配。")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", sourceAppURL.path])

        let stagedAppURL = root.appendingPathComponent("Agent Pulse.new.app", isDirectory: true)
        try run("/usr/bin/ditto", [sourceAppURL.path, stagedAppURL.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedAppURL.path])
        try run("/usr/bin/hdiutil", ["detach", mountURL.path])
        mounted = false

        let helperURL = root.appendingPathComponent("install-update.zsh")
        try helperScript.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        return PreparedAppUpdate(
            helperURL: helperURL,
            currentAppURL: currentAppURL,
            stagedAppURL: stagedAppURL,
            workingDirectoryURL: root
        )
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw AppUpdateError.invalidPackage(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateError.invalidPackage(message?.isEmpty == false ? message! : executable)
        }
    }

    private static let helperScript = #"""
#!/bin/zsh
set -euo pipefail

pid="$1"
target_app="$2"
staged_app="$3"
work_dir="$4"
log_dir="$HOME/Library/Logs/Agent Pulse"
log_file="$log_dir/update.log"
/bin/mkdir -p "$log_dir"
exec >>"$log_file" 2>&1

for _ in {1..120}; do
  /bin/kill -0 "$pid" 2>/dev/null || break
  /bin/sleep 0.1
done
if /bin/kill -0 "$pid" 2>/dev/null; then
  print "等待 Agent Pulse 退出超时。"
  exit 1
fi

trash_dir="$HOME/.Trash"
/bin/mkdir -p "$trash_dir"
backup_app="$trash_dir/Agent Pulse（升级前）.app"
if [[ -e "$backup_app" ]]; then
  backup_app="$trash_dir/Agent Pulse（升级前） $(/bin/date +%Y%m%d-%H%M%S).app"
fi

if [[ -d "$target_app" ]]; then
  /bin/mv "$target_app" "$backup_app"
fi
if ! /bin/mv "$staged_app" "$target_app"; then
  [[ -d "$backup_app" ]] && /bin/mv "$backup_app" "$target_app"
  print "新版应用替换失败，已恢复旧版。"
  exit 1
fi

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$target_app" >/dev/null 2>&1 || true
/usr/bin/open "$target_app"
/bin/rm -rf "$work_dir"
"""#
}
