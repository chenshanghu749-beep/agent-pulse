import Foundation

struct ConfigBackupRecord: Codable, Hashable, Sendable {
    let id: String
    let createdAt: Date
    let reason: String
    let modelProvider: String
    let name: String?
    let note: String?
}

enum ConfigRestoreScope: String, CaseIterable, Sendable {
    case all, config, providers

    var displayName: String {
        switch self {
        case .all: return "全部"
        case .config: return "仅 config.toml"
        case .providers: return "仅提供商"
        }
    }
}

struct ConfigImportPreview: Sendable {
    let summary: String
    let diff: String
}

struct SanitizedConfigBundle: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let configTOML: String
    let providers: [ProviderProfile]
    let selectedProviderID: String?
}

enum SensitiveConfigSanitizer {
    static func sanitize(_ content: String) -> String {
        let sensitiveNames = ["api_key", "apikey", "token", "authorization", "password", "secret"]
        return content.components(separatedBy: .newlines).map { line in
            guard let equals = line.firstIndex(of: "=") else { return line }
            let key = line[..<equals].lowercased()
            let value = line[line.index(after: equals)...].lowercased()
            let sensitiveKey = !key.contains("env_key") && sensitiveNames.contains(where: { key.contains($0) })
            let sensitiveInlineValue = !key.contains("env_key")
                && ["authorization", "bearer ", "api_key", "password", "secret"].contains {
                    value.contains($0)
                }
            guard sensitiveKey || sensitiveInlineValue else { return line }
            let prefix = line[...equals]
            return "\(prefix) \"<redacted>\""
        }.joined(separator: "\n")
    }
}

enum ConfigBackupCenter {
    static var rootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Pulse", isDirectory: true)
            .appendingPathComponent("config-backups", isDirectory: true)
    }

    static func records() -> [ConfigBackupRecord] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories.compactMap { directory in
            let url = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ConfigBackupRecord.self, from: data) else { return nil }
            return record
        }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func create(reason: String, name: String? = nil, note: String? = nil) throws -> ConfigBackupRecord {
        let now = Date()
        let id = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let directory = rootURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let config = (try? String(contentsOf: RouteConfigManager.configURL, encoding: .utf8)) ?? ""
        let configDestination = directory.appendingPathComponent("config.toml")
        try Data(config.utf8).write(to: configDestination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configDestination.path)
        if let providerData = try? Data(contentsOf: ProviderStore.databaseURL) {
            let providerDestination = directory.appendingPathComponent("providers.json")
            try providerData.write(to: providerDestination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: providerDestination.path)
        }
        let record = ConfigBackupRecord(
            id: id,
            createdAt: now,
            reason: reason,
            modelProvider: RouteConfigManager.currentModelProvider(),
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let metadataDestination = directory.appendingPathComponent("metadata.json")
        try encoder.encode(record).write(to: metadataDestination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataDestination.path)
        prune()
        return record
    }

    static func configText(for record: ConfigBackupRecord) -> String {
        let url = rootURL.appendingPathComponent(record.id).appendingPathComponent("config.toml")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func restore(_ record: ConfigBackupRecord, scope: ConfigRestoreScope = .all) throws {
        _ = try create(reason: "恢复前自动备份")
        let directory = rootURL.appendingPathComponent(record.id)
        let configURL = directory.appendingPathComponent("config.toml")
        if scope != .providers {
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let config = try String(contentsOf: configURL, encoding: .utf8)
            try RouteConfigManager.replaceConfigText(config)
        }
        let providerURL = directory.appendingPathComponent("providers.json")
        if scope != .config, FileManager.default.fileExists(atPath: providerURL.path) {
            let data = try Data(contentsOf: providerURL)
            try FileManager.default.createDirectory(
                at: ProviderStore.databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: ProviderStore.databaseURL, options: .atomic)
        }
    }

    static func exportBundle() -> SanitizedConfigBundle {
        let config = (try? String(contentsOf: RouteConfigManager.configURL, encoding: .utf8)) ?? ""
        return SanitizedConfigBundle(
            formatVersion: 1,
            exportedAt: Date(),
            configTOML: SensitiveConfigSanitizer.sanitize(config),
            providers: ProviderStore.providers(),
            selectedProviderID: ProviderStore.selectedProviderID()
        )
    }

    static func exportData() throws -> Data { try encoder.encode(exportBundle()) }

    static func decodeImport(_ data: Data) throws -> SanitizedConfigBundle {
        let bundle = try decoder.decode(SanitizedConfigBundle.self, from: data)
        guard bundle.formatVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        try validate(bundle)
        return bundle
    }

    static func previewImport(_ bundle: SanitizedConfigBundle) -> ConfigImportPreview {
        let current = (try? String(contentsOf: RouteConfigManager.configURL, encoding: .utf8)) ?? ""
        let configDiff = lineDiff(old: current, new: bundle.configTOML, oldTitle: "当前配置", newTitle: "导入配置")
        let currentProviders = ProviderStore.providers()
        let currentIDs = Set(currentProviders.map(\.id))
        let incomingIDs = Set(bundle.providers.map(\.id))
        let added = incomingIDs.subtracting(currentIDs).count
        let deleted = currentIDs.subtracting(incomingIDs).count
        let changed = bundle.providers.filter { incoming in
            currentProviders.first(where: { $0.id == incoming.id }).map { $0 != incoming } ?? false
        }.count
        return ConfigImportPreview(
            summary: "提供商：新增 \(added) · 修改 \(changed) · 删除 \(deleted)；API Key 不会导入或覆盖。",
            diff: configDiff
        )
    }

    static func importBundle(_ bundle: SanitizedConfigBundle) throws {
        _ = try create(reason: "导入前自动备份")
        if !bundle.configTOML.contains("<redacted>") {
            try RouteConfigManager.replaceConfigText(bundle.configTOML)
        }
        try ProviderStore.saveProviders(bundle.providers, selectedProviderID: bundle.selectedProviderID)
    }

    static func diff(record: ConfigBackupRecord) -> String {
        let oldText = configText(for: record)
        let currentText = (try? String(contentsOf: RouteConfigManager.configURL, encoding: .utf8)) ?? ""
        return lineDiff(old: oldText, new: currentText, oldTitle: "备份 \(record.id)", newTitle: "当前配置")
    }

    private static func lineDiff(old oldText: String, new newText: String, oldTitle: String, newTitle: String) -> String {
        let old = oldText.components(separatedBy: .newlines)
        let current = newText.components(separatedBy: .newlines)
        let count = max(old.count, current.count)
        var output = ["--- \(oldTitle)", "+++ \(newTitle)"]
        for index in 0..<count {
            let lhs = index < old.count ? old[index] : nil
            let rhs = index < current.count ? current[index] : nil
            guard lhs != rhs else { continue }
            if let lhs { output.append("- \(SensitiveConfigSanitizer.sanitize(lhs))") }
            if let rhs { output.append("+ \(SensitiveConfigSanitizer.sanitize(rhs))") }
        }
        return output.count == 2 ? "当前配置与所选备份一致。" : output.joined(separator: "\n")
    }

    private static func validate(_ bundle: SanitizedConfigBundle) throws {
        var ids = Set<String>()
        var names = Set<String>()
        for profile in bundle.providers {
            guard ids.insert(profile.id.lowercased()).inserted else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "存在重复的提供商 ID：\(profile.id)"])
            }
            guard names.insert(profile.name.lowercased()).inserted else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "存在重复的提供商名称：\(profile.name)"])
            }
            guard let url = URL(string: profile.baseURL),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "提供商 \(profile.name) 的 Base URL 无效。"])
            }
        }
        if let selected = bundle.selectedProviderID, !ids.contains(selected.lowercased()) {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "选中的提供商不存在。"])
        }
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }
    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }

    private static func prune() {
        for record in records().dropFirst(20) {
            try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(record.id))
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
