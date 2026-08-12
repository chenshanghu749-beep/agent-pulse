import AppKit
import Foundation

enum RouteChoice: Equatable, Sendable {
    case official
    case provider(String)

    var displayName: String {
        switch self {
        case .official: return "OpenAI 官方"
        case let .provider(id): return ProviderStore.provider(id: id)?.name ?? "第三方提供商"
        }
    }
}

enum RouteConfigError: LocalizedError {
    case cannotReadConfig
    case cannotWriteConfig(String)
    case invalidRenderedConfig(String)
    case chatGPTNotFound
    case cannotCloseCodex
    case providerNotFound

    var errorDescription: String? {
        switch self {
        case .cannotReadConfig:
            return "无法读取 ~/.codex/config.toml。"
        case let .cannotWriteConfig(message):
            return "无法更新 Codex 配置：\(message)"
        case let .invalidRenderedConfig(message):
            return "生成的 Codex 配置无效：\(message)"
        case .chatGPTNotFound:
            return "未找到 Codex 应用，请确认它已安装。"
        case .cannotCloseCodex:
            return "Codex 仍在运行，已停止切换以保护本地会话；请结束当前任务后重试。"
        case .providerNotFound:
            return "未找到所选第三方提供商，请先完成配置。"
        }
    }
}

enum RouteConfigManager {
    static let legacyManagedProviderID = "codeapi_status_custom"
    static let beginMarker = "# >>> Agent Pulse managed provider >>>"
    static let endMarker = "# <<< Agent Pulse managed provider <<<"
    static let legacyBeginMarker = "# >>> CodeAPI Status managed provider >>>"
    static let legacyEndMarker = "# <<< CodeAPI Status managed provider <<<"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    /// Returns the top-level Codex provider exactly as it is configured.
    /// This is independent from Agent Pulse's selected route.
    static func currentModelProvider() -> String {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8),
              let value = topLevelValue(named: "model_provider", in: content),
              !value.isEmpty else {
            return "openai"
        }
        return value
    }

    /// Lists provider IDs declared in config.toml for display and validation.
    static func configuredModelProviderIDs() -> [String] {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return ["openai"]
        }
        var ids = ["openai"]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("[model_providers."), trimmed.hasSuffix("]") else { continue }
            let start = trimmed.index(trimmed.startIndex, offsetBy: "[model_providers.".count)
            let end = trimmed.index(before: trimmed.endIndex)
            let id = String(trimmed[start..<end])
            guard !id.isEmpty, !id.hasSuffix(".auth"), !ids.contains(id) else { continue }
            ids.append(id)
        }
        return ids
    }

    /// Updates only the top-level model_provider line. No session database or
    /// JSONL file is read or written by this operation.
    static func setModelProvider(_ provider: String) throws {
        let value = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw RouteConfigError.invalidRenderedConfig("model_provider 只能包含字母、数字、点、下划线和连字符。")
        }

        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let backup = directory.appendingPathComponent("config.toml.agent-pulse.bak")
        if !existing.isEmpty {
            try Data(existing.utf8).write(to: backup, options: .atomic)
        }

        var lines = existing.components(separatedBy: .newlines)
        var replaced = false
        var root = true
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { root = false }
            guard root,
                  let equals = trimmed.firstIndex(of: "="),
                  String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces) == "model_provider" else {
                continue
            }
            lines[index] = "model_provider = \"\(tomlEscape(value))\""
            replaced = true
            break
        }
        if !replaced {
            lines.insert("model_provider = \"\(tomlEscape(value))\"", at: 0)
        }

        let rendered = lines.joined(separator: "\n")
        try validate(rendered)
        try Data(rendered.utf8).write(to: configURL, options: .atomic)
    }

    /// Replaces config.toml after creating the same recoverable backup used by
    /// route switching. This method never reads or writes Codex session data.
    static func replaceConfigText(_ content: String) throws {
        guard !content.contains("<redacted>") else {
            throw RouteConfigError.invalidRenderedConfig("脱敏导出文件不能直接恢复，请重新填写 API Key 后再导入。")
        }
        try validate(content)
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: configURL), !existing.isEmpty {
            try existing.write(to: directory.appendingPathComponent("config.toml.agent-pulse.bak"), options: .atomic)
        }
        try Data(content.utf8).write(to: configURL, options: .atomic)
    }

    static func currentRoute() -> RouteChoice {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return .official
        }
        return detectedRoute(
            in: content,
            profiles: ProviderStore.providers(for: .codex),
            selectedProviderID: ProviderStore.selectedProviderID()
        )
    }

    static func needsUpgradeReconciliation() -> Bool {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return false
        }
        let profiles = ProviderStore.providers(for: .codex)
        let selectedProviderID = ProviderStore.selectedProviderID()
        return needsUpgradeReconciliation(
            in: content,
            profiles: profiles,
            selectedProviderID: selectedProviderID
        )
    }

    static func needsUpgradeReconciliation(
        in content: String,
        profiles: [ProviderProfile],
        selectedProviderID: String?
    ) -> Bool {
        guard containsManagedBlock(content) else { return false }
        let legacyCredential = content.contains("command = \"/usr/bin/security\"")
            || content.contains(CredentialStore.legacyDirectoryURL.path)
            || content.contains(legacyBeginMarker)
        var requiredIDs = profiles.map { codexProviderID(for: $0.id) }
        if selectedProviderID != nil { requiredIDs.append(legacyManagedProviderID) }
        if profiles.contains(where: { $0.id == "codeapi" || $0.isCodeAPI }) {
            requiredIDs.append("codeapi")
        }
        let missingManagedProvider = requiredIDs.contains {
            !content.contains("[model_providers.\($0)]")
        }
        // A non-openai model_provider may be intentional and is exposed in
        // settings. Never rewrite it merely because the selected route changed.
        return legacyCredential || missingManagedProvider
    }

    static func detectedRoute(
        in content: String,
        profiles: [ProviderProfile],
        selectedProviderID: String?
    ) -> RouteChoice {
        let topLevel = topLevelProvider(in: content)?.lowercased()
        if topLevel == "openai",
           topLevelValue(named: "openai_base_url", in: content) != nil,
           containsManagedBlock(content),
           let selectedProviderID,
           profiles.contains(where: { $0.id == selectedProviderID }) {
            return .provider(selectedProviderID)
        }
        if let topLevel,
           let profile = profiles.first(where: {
               codexProviderID(for: $0.id) == topLevel
           }) {
            return .provider(profile.id)
        }
        if topLevel == legacyManagedProviderID,
           let id = selectedProviderID,
           profiles.contains(where: { $0.id == id }) {
            return .provider(id)
        }
        if topLevel == "codeapi" {
            if let codeAPI = profiles.first(where: { $0.id == "codeapi" || $0.isCodeAPI }) {
                return .provider(codeAPI.id)
            }
        }
        if let topLevel,
           content.range(of: "[model_providers.\(topLevel)]", options: .caseInsensitive) != nil,
           content.range(of: "codeapi.nexita.net", options: .caseInsensitive) != nil,
           let codeAPI = profiles.first(where: { $0.id == "codeapi" || $0.isCodeAPI }) {
            return .provider(codeAPI.id)
        }
        return .official
    }

    static func apply(_ route: RouteChoice) throws {
        let fileManager = FileManager.default
        let directory = configURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let existingModelProvider = topLevelValue(named: "model_provider", in: existing) ?? "openai"
            let existingProvider = topLevelProvider(in: existing)?.lowercased()
            let existingRoute = detectedRoute(
                in: existing,
                profiles: ProviderStore.providers(for: .codex),
                selectedProviderID: ProviderStore.selectedProviderID()
            )
            if existingProvider == nil || existingRoute == .official {
                try ProviderStore.setOfficialModel(topLevelValue(named: "model", in: existing))
                try ProviderStore.setOfficialModelCatalogJSON(
                    topLevelValue(named: "model_catalog_json", in: existing)
                )
            }
            let profile: ProviderProfile?
            switch route {
            case .official:
                profile = nil
            case let .provider(id):
                guard let selected = ProviderStore.provider(id: id) else { throw RouteConfigError.providerNotFound }
                profile = selected
                try ProviderStore.setSelectedProviderID(id)
            }
            let compatibilityCatalogURL = try profile.flatMap {
                try CodexModelCatalog.prepareIfNeeded(model: $0.model)
            }
            if fileManager.fileExists(atPath: configURL.path) {
                let backup = directory.appendingPathComponent("config.toml.agent-pulse.bak")
                try Data(existing.utf8).write(to: backup, options: .atomic)
            }
            let profiles = ProviderStore.providers(for: .codex)
            let legacyProfile = ProviderStore.selectedProviderID().flatMap { ProviderStore.provider(id: $0) }
            let rendered = render(
                existing,
                route: route,
                profile: profile,
                profiles: profiles,
                legacyProfile: legacyProfile,
                officialModel: ProviderStore.officialModel(),
                officialModelCatalogJSON: ProviderStore.officialModelCatalogJSON(),
                compatibilityModelCatalogJSON: compatibilityCatalogURL?.path,
                modelProvider: existingModelProvider
            )
            try validate(rendered)
            try Data(rendered.utf8).write(to: configURL, options: .atomic)
        } catch {
            throw RouteConfigError.cannotWriteConfig(error.localizedDescription)
        }
    }

    @discardableResult
    static func migrateLegacyCredentialCommandIfNeeded() throws -> Bool {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8),
              containsManagedBlock(content),
              content.contains("command = \"/usr/bin/security\"")
                || content.contains(CredentialStore.legacyDirectoryURL.path)
                || content.contains(legacyBeginMarker) else {
            return false
        }
        try apply(currentRoute())
        return true
    }

    @discardableResult
    static func reconcileManagedProvidersIfNeeded() throws -> Bool {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8),
              containsManagedBlock(content) else { return false }
        let profiles = ProviderStore.providers(for: .codex)
        var requiredIDs = profiles.map { codexProviderID(for: $0.id) }
        if ProviderStore.selectedProviderID() != nil { requiredIDs.append(legacyManagedProviderID) }
        if profiles.contains(where: { $0.id == "codeapi" || $0.isCodeAPI }) { requiredIDs.append("codeapi") }
        guard requiredIDs.contains(where: { !content.contains("[model_providers.\($0)]") }) else { return false }
        try apply(currentRoute())
        return true
    }

    static func render(
        _ content: String,
        route: RouteChoice,
        profile: ProviderProfile? = nil,
        profiles: [ProviderProfile] = [],
        legacyProfile: ProviderProfile? = nil,
        officialModel: String? = nil,
        officialModelCatalogJSON: String? = nil,
        compatibilityModelCatalogJSON: String? = nil,
        modelProvider: String? = nil
    ) -> String {
        let configuredProfiles = profiles.isEmpty ? profile.map { [$0] } ?? [] : profiles
        var providerEntries: [(id: String, profile: ProviderProfile)] = []
        var emittedProviderIDs = Set<String>()
        func appendProvider(id: String, profile: ProviderProfile) {
            guard emittedProviderIDs.insert(id.lowercased()).inserted else { return }
            providerEntries.append((id, profile))
        }
        for configuredProfile in configuredProfiles {
            appendProvider(id: codexProviderID(for: configuredProfile.id), profile: configuredProfile)
        }
        if let legacy = legacyProfile ?? profile {
            appendProvider(id: legacyManagedProviderID, profile: legacy)
        }
        if let codeAPI = configuredProfiles.first(where: { $0.id == "codeapi" || $0.isCodeAPI }) {
            appendProvider(id: "codeapi", profile: codeAPI)
        }

        var cleaned = removingManagedBlocks(from: content)
        cleaned = removingProviderTables(
            from: cleaned,
            providerIDs: Set(providerEntries.map { $0.id.lowercased() })
        )
        var lines = cleaned.components(separatedBy: .newlines)
        var inTopLevel = true
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { inTopLevel = false }
            guard inTopLevel, let key = trimmed.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) else {
                return false
            }
            return key == "model_provider"
                || key == "model"
                || key == "openai_base_url"
                || key == "forced_login_method"
                || key == "cli_auth_credentials_store"
                || key == "model_catalog_json"
        }

        while lines.first?.isEmpty == true { lines.removeFirst() }
        let renderedModelProvider = tomlEscape(modelProvider ?? "openai")
        switch route {
        case .official:
            lines.insert("model_provider = \"\(renderedModelProvider)\"", at: 0)
            if let officialModel, !officialModel.isEmpty {
                lines.insert("model = \"\(tomlEscape(officialModel))\"", at: 1)
            }
            if let officialModelCatalogJSON, !officialModelCatalogJSON.isEmpty {
                lines.insert(
                    "model_catalog_json = \"\(tomlEscape(officialModelCatalogJSON))\"",
                    at: min(2, lines.count)
                )
            }
        case .provider:
            guard let profile else { return content }
            lines.insert("model_provider = \"\(renderedModelProvider)\"", at: 0)
            lines.insert("model = \"\(tomlEscape(profile.model))\"", at: 1)
            lines.insert("openai_base_url = \"\(tomlEscape(activeBaseURL(for: profile)))\"", at: 2)
            lines.insert("forced_login_method = \"api\"", at: 3)
            lines.insert("cli_auth_credentials_store = \"file\"", at: 4)
            if let compatibilityModelCatalogJSON, !compatibilityModelCatalogJSON.isEmpty {
                lines.insert(
                    "model_catalog_json = \"\(tomlEscape(compatibilityModelCatalogJSON))\"",
                    at: 5
                )
            }
        }
        cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerEntries.isEmpty else { return cleaned + "\n" }
        let blocks = providerEntries.map { providerBlock(id: $0.id, profile: $0.profile) }
        let managed = ([beginMarker] + blocks + [endMarker]).joined(separator: "\n\n")
        return cleaned + "\n\n" + managed + "\n"
    }

    static func validate(_ content: String) throws {
        var currentTable = "<root>"
        var seenTables = Set<String>()
        var seenKeysByTable: [String: Set<String>] = [:]
        var arrayTableInstances: [String: Int] = [:]

        for (offset, line) in content.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if let header = tableHeader(in: trimmed) {
                if header.isArray {
                    let instance = arrayTableInstances[header.name, default: 0]
                    arrayTableInstances[header.name] = instance + 1
                    currentTable = "[[\(header.name)]]#\(instance)"
                } else {
                    guard seenTables.insert(header.name).inserted else {
                        throw RouteConfigError.invalidRenderedConfig(
                            "第 \(offset + 1) 行重复定义表 [\(header.name)]。"
                        )
                    }
                    currentTable = header.name
                }
                continue
            }

            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var seenKeys = seenKeysByTable[currentTable, default: []]
            guard seenKeys.insert(key).inserted else {
                throw RouteConfigError.invalidRenderedConfig(
                    "第 \(offset + 1) 行重复定义键 \(key)。"
                )
            }
            seenKeysByTable[currentTable] = seenKeys
        }
    }

    static func codexProviderID(for profileID: String) -> String {
        // Keep the historical CodeAPI identifier stable. Codex stores the
        // provider identifier with every local thread; changing it makes older
        // CodeAPI conversations look like they belong to another provider.
        if profileID.lowercased() == "codeapi" { return "codeapi" }
        let safe = profileID.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
                ? Character(String(scalar)) : "_"
        }
        return "codeapi_status_provider_" + String(safe)
    }

    static func profile(forCodexProviderID providerID: String) -> ProviderProfile? {
        ProviderStore.providers(for: .codex).first {
            codexProviderID(for: $0.id) == providerID.lowercased()
        }
    }

    private static func providerBlock(id: String, profile: ProviderProfile) -> String {
        let baseURL = activeBaseURL(for: profile)
        return """
        [model_providers.\(id)]
        name = "\(tomlEscape(profile.name))"
        base_url = "\(tomlEscape(baseURL))"
        wire_api = "responses"

        [model_providers.\(id).auth]
        command = "/bin/cat"
        args = ["\(tomlEscape(CredentialStore.keyURL(for: profile.id).path))"]
        timeout_ms = 5000
        """
    }

    private static func activeBaseURL(for profile: ProviderProfile) -> String {
        if profile.isCodeAPI, !profile.normalizedBaseURL.lowercased().hasSuffix("/v1") {
            return profile.normalizedBaseURL + "/v1"
        }
        return profile.normalizedBaseURL
    }

    private static func topLevelProvider(in content: String) -> String? {
        topLevelValue(named: "model_provider", in: content)
    }

    private static func topLevelValue(named name: String, in content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == name else { continue }
            return trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func tomlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func removingManagedBlocks(from content: String) -> String {
        var result = content
        for markers in [(beginMarker, endMarker), (legacyBeginMarker, legacyEndMarker)] {
            while let start = result.range(of: markers.0),
                  let end = result.range(of: markers.1, range: start.lowerBound..<result.endIndex) {
                var upper = end.upperBound
                if upper < result.endIndex, result[upper] == "\n" { upper = result.index(after: upper) }
                result.removeSubrange(start.lowerBound..<upper)
            }
        }
        return result
    }

    private static func containsManagedBlock(_ content: String) -> Bool {
        (content.contains(beginMarker) && content.contains(endMarker))
            || (content.contains(legacyBeginMarker) && content.contains(legacyEndMarker))
    }

    private static func removingProviderTables(
        from content: String,
        providerIDs: Set<String>
    ) -> String {
        guard !providerIDs.isEmpty else { return content }
        var output: [String] = []
        var shouldSkip = false

        for line in content.components(separatedBy: .newlines) {
            if let header = tableHeader(in: line.trimmingCharacters(in: .whitespaces)) {
                let table = header.name.lowercased()
                shouldSkip = providerIDs.contains { providerID in
                    let root = "model_providers.\(providerID)"
                    return table == root || table.hasPrefix(root + ".")
                }
            }
            if !shouldSkip { output.append(line) }
        }
        return output.joined(separator: "\n")
    }

    private static func tableHeader(in line: String) -> (name: String, isArray: Bool)? {
        guard line.hasPrefix("[") else { return nil }
        let isArray = line.hasPrefix("[[")
        let closing = isArray ? "]]" : "]"
        guard let end = line.range(of: closing) else { return nil }
        let start = line.index(line.startIndex, offsetBy: isArray ? 2 : 1)
        guard start <= end.lowerBound else { return nil }
        let suffix = line[end.upperBound...].trimmingCharacters(in: .whitespaces)
        guard suffix.isEmpty || suffix.hasPrefix("#") else { return nil }
        let name = line[start..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : (name, isArray)
    }
}

@MainActor
enum CodexLauncher {
    nonisolated static let bundleIdentifier = "com.openai.codex"

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func terminate() async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in running { app.terminate() }

        if !running.isEmpty {
            for _ in 0..<25 {
                if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            throw RouteConfigError.cannotCloseCodex
        }
    }

    static func launch() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw RouteConfigError.chatGPTNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    static func restart() async throws {
        try await terminate()
        try await launch()
    }
}
