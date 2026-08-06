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
    let installerURL: URL
    let expectedVersion: String
    let workingDirectoryURL: URL

    func launch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            currentAppURL.path,
            installerURL.absoluteString,
            expectedVersion,
            AppIdentity.bundleIdentifier,
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
    static func validateHelperScriptForTesting() throws {
        try run("/bin/zsh", ["-n", "-c", helperScript])
        let requiredSteps = [
            "/usr/bin/curl",
            "/usr/bin/hdiutil verify",
            "expected_bundle_id",
            "/usr/bin/codesign --verify",
            "/usr/bin/open \"$target_app\""
        ]
        guard requiredSteps.allSatisfy(helperScript.contains) else {
            throw AppUpdateError.invalidPackage("更新助手缺少必要步骤。")
        }
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
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let helperURL = root.appendingPathComponent("install-update.zsh")
            try helperScript.write(to: helperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
            return PreparedAppUpdate(
                helperURL: helperURL,
                currentAppURL: currentAppURL,
                installerURL: status.installerURL,
                expectedVersion: status.latestVersion,
                workingDirectoryURL: root
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
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
installer_url="$3"
expected_version="$4"
expected_bundle_id="$5"
work_dir="$6"
log_dir="$HOME/Library/Logs/Agent Pulse"
log_file="$log_dir/update.log"
/bin/mkdir -p "$log_dir"
exec >>"$log_file" 2>&1

dmg="$work_dir/Agent-Pulse-$expected_version.dmg"
mount_dir="$work_dir/mount"
staged_app="$work_dir/Agent Pulse.new.app"
mounted=0

cleanup_mount() {
  if [[ "$mounted" == "1" ]]; then
    /usr/bin/hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
    mounted=0
  fi
}

fail_update() {
  print "$1"
  cleanup_mount
  [[ -d "$target_app" ]] && /usr/bin/open "$target_app" >/dev/null 2>&1 || true
  /usr/bin/osascript -e 'display alert "Agent Pulse 更新失败" message "旧版本未被替换，请稍后重试或查看日志。"' >/dev/null 2>&1 || true
  /bin/rm -rf "$work_dir"
  exit 1
}

for _ in {1..120}; do
  /bin/kill -0 "$pid" 2>/dev/null || break
  /bin/sleep 0.1
done
if /bin/kill -0 "$pid" 2>/dev/null; then
  fail_update "等待 Agent Pulse 退出超时。"
fi

/usr/bin/osascript -e 'display notification "正在后台下载并安装新版本…" with title "Agent Pulse"' >/dev/null 2>&1 || true
print "正在下载 Agent Pulse $expected_version…"
/usr/bin/curl -fL --retry 3 --connect-timeout 15 --max-time 600 \
  -A "Agent-Pulse-Updater/$expected_version" \
  -o "$dmg" "$installer_url" || fail_update "更新包下载失败。"
/usr/bin/hdiutil verify "$dmg" || fail_update "更新包校验失败。"
/bin/mkdir -p "$mount_dir"
/usr/bin/hdiutil attach -nobrowse -readonly -mountpoint "$mount_dir" "$dmg" \
  || fail_update "无法挂载更新包。"
mounted=1

source_app="$mount_dir/Agent Pulse.app"
info_plist="$source_app/Contents/Info.plist"
[[ -f "$info_plist" ]] || fail_update "更新包中缺少 Agent Pulse.app。"
actual_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)
actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist" 2>/dev/null || true)
[[ "$actual_bundle_id" == "$expected_bundle_id" ]] || fail_update "更新包应用标识不匹配。"
[[ "$actual_version" == "$expected_version" ]] || fail_update "更新包版本号不匹配。"
/usr/bin/codesign --verify --deep --strict "$source_app" || fail_update "更新包签名校验失败。"
/usr/bin/ditto "$source_app" "$staged_app" || fail_update "无法准备新版应用。"
/usr/bin/codesign --verify --deep --strict "$staged_app" || fail_update "新版应用签名校验失败。"
cleanup_mount

trash_dir="$HOME/.Trash"
/bin/mkdir -p "$trash_dir"
backup_app="$trash_dir/Agent Pulse（升级前）.app"
if [[ -e "$backup_app" ]]; then
  backup_app="$trash_dir/Agent Pulse（升级前） $(/bin/date +%Y%m%d-%H%M%S).app"
fi

if [[ -d "$target_app" ]]; then
  /bin/mv "$target_app" "$backup_app" || fail_update "无法备份当前版本，更新已取消。"
fi
if ! /bin/mv "$staged_app" "$target_app"; then
  [[ -d "$backup_app" ]] && /bin/mv "$backup_app" "$target_app"
  fail_update "新版应用替换失败，已恢复旧版。"
fi

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$target_app" >/dev/null 2>&1 || true
/usr/bin/osascript -e 'display notification "更新完成，正在重新打开。" with title "Agent Pulse"' >/dev/null 2>&1 || true
/usr/bin/open "$target_app"
/bin/rm -rf "$work_dir"
"""#
}
