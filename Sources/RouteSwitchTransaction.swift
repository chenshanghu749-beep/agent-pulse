import Foundation

enum RouteSwitchTransactionError: LocalizedError {
    case missingProvider
    case missingCredential(String)
    case invalidProvider(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .missingProvider: return "所选提供商不存在，请重新选择。"
        case let .missingCredential(name): return "\(name) 尚未配置 API Key。"
        case let .invalidProvider(message): return "提供商配置无效：\(message)"
        case .verificationFailed: return "路由写入后的校验未通过，已恢复切换前配置。"
        }
    }
}

struct RouteSwitchTransactionResult {
    let authPreparation: CodexAuthPreparation
    let backup: ConfigBackupRecord
    fileprivate let authSnapshot: CodexAuthSnapshot
    fileprivate let selectedProviderID: String?
    fileprivate let configExisted: Bool
    fileprivate let configData: Data?
}

/// Applies a Codex route as a recoverable transaction. It never reads or writes
/// Codex session databases and preserves the user's top-level model_provider.
enum RouteSwitchTransaction {
    static func preflight(_ route: RouteChoice) throws {
        guard case let .provider(id) = route else { return }
        guard let profile = ProviderStore.provider(id: id) else {
            throw RouteSwitchTransactionError.missingProvider
        }
        guard URL(string: profile.baseURL)?.host != nil, !profile.model.isEmpty else {
            throw RouteSwitchTransactionError.invalidProvider("Base URL 或模型为空")
        }
        guard CredentialStore.load(providerID: id)?.isEmpty == false else {
            throw RouteSwitchTransactionError.missingCredential(profile.name)
        }
    }

    static func apply(_ route: RouteChoice) throws -> RouteSwitchTransactionResult {
        try preflight(route)
        let authSnapshot = try CodexAuthStore.snapshot()
        let selectedProviderSnapshot = ProviderStore.selectedProviderID()
        let configExisted = FileManager.default.fileExists(atPath: RouteConfigManager.configURL.path)
        let configSnapshot = try? Data(contentsOf: RouteConfigManager.configURL)
        let backup = try ConfigBackupCenter.create(reason: "路由切换前自动备份")

        do {
            let preparation = try CodexAuthStore.prepareForSwitch(to: route)
            try RouteConfigManager.apply(route)
            guard RouteConfigManager.currentRoute() == route else {
                throw RouteSwitchTransactionError.verificationFailed
            }
            return RouteSwitchTransactionResult(
                authPreparation: preparation,
                backup: backup,
                authSnapshot: authSnapshot,
                selectedProviderID: selectedProviderSnapshot,
                configExisted: configExisted,
                configData: configSnapshot
            )
        } catch {
            try? CodexAuthStore.restore(authSnapshot)
            try? ProviderStore.setSelectedProviderID(selectedProviderSnapshot)
            restoreConfig(existed: configExisted, data: configSnapshot)
            throw error
        }
    }

    static func rollback(_ result: RouteSwitchTransactionResult) {
        try? CodexAuthStore.restore(result.authSnapshot)
        try? ProviderStore.setSelectedProviderID(result.selectedProviderID)
        restoreConfig(existed: result.configExisted, data: result.configData)
    }

    private static func restoreConfig(existed: Bool, data: Data?) {
        let fileManager = FileManager.default
        if existed, let data {
            try? fileManager.createDirectory(
                at: RouteConfigManager.configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: RouteConfigManager.configURL, options: .atomic)
        } else if fileManager.fileExists(atPath: RouteConfigManager.configURL.path) {
            try? fileManager.removeItem(at: RouteConfigManager.configURL)
        }
    }
}
