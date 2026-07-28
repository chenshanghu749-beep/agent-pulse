import Foundation

struct AppUpdateStatus: Sendable {
    let currentVersion: String
    let latestVersion: String

    var updateAvailable: Bool {
        Self.compare(latestVersion, currentVersion) == .orderedDescending
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无法读取远程版本信息。"
        case .versionMissing: return "远程版本信息不完整。"
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
