import Foundation

enum ProviderAPIFormat: String, Codable, CaseIterable, Sendable {
    case automatic
    case responses
    case chatCompletions

    var displayName: String {
        switch self {
        case .automatic: return "自动识别"
        case .responses: return "Responses API"
        case .chatCompletions: return "Chat Completions（旧配置）"
        }
    }
}

enum ProviderVendor: String, Codable, CaseIterable, Sendable {
    case deepSeek
    case zhipuAI
    case moonshot
    case miniMax
    case stepFun
    case miMo
    case bailian
    case xAI
    case custom

    static let presetChoices: [ProviderVendor] = [
        .deepSeek, .zhipuAI, .moonshot, .miniMax, .stepFun, .miMo, .bailian, .custom
    ]

    var displayName: String {
        switch self {
        case .deepSeek: return "DeepSeek"
        case .zhipuAI: return "智谱 AI"
        case .moonshot: return "月之暗面"
        case .miniMax: return "MiniMax"
        case .stepFun: return "阶跃星辰"
        case .miMo: return "MiMo"
        case .bailian: return "阿里百炼云"
        case .xAI: return "xAI"
        case .custom: return "自定义"
        }
    }

    var shortName: String {
        switch self {
        case .deepSeek: return "DS"
        case .zhipuAI: return "GLM"
        case .moonshot: return "K"
        case .miniMax: return "M"
        case .stepFun: return "STEP"
        case .miMo: return "MiMo"
        case .bailian: return "QWEN"
        case .xAI: return "xAI"
        case .custom: return "+"
        }
    }

    var symbolName: String {
        switch self {
        case .deepSeek: return "wave.3.right.circle.fill"
        case .zhipuAI: return "sparkles.rectangle.stack.fill"
        case .moonshot: return "moon.stars.fill"
        case .miniMax: return "arrow.up.left.and.arrow.down.right.circle.fill"
        case .stepFun: return "square.3.layers.3d.top.filled"
        case .miMo: return "circle.grid.cross.fill"
        case .bailian: return "hexagon.fill"
        case .xAI: return "xmark.circle.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .deepSeek: return "https://api.deepseek.com"
        case .zhipuAI: return "https://open.bigmodel.cn/api/coding/paas/v4"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .miniMax: return "https://api.minimaxi.com/v1"
        case .stepFun: return "https://api.stepfun.ai/v1"
        case .miMo: return "https://api.xiaomimimo.com/v1"
        case .bailian: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .xAI: return "https://api.x.ai/v1"
        case .custom: return nil
        }
    }

    var defaultModel: String? {
        switch self {
        case .deepSeek: return "deepseek-v4-flash"
        case .zhipuAI: return "glm-5.2"
        case .moonshot: return "kimi-k2.7-code"
        case .miniMax: return "MiniMax-M2.7"
        case .stepFun: return "step-3.5-flash"
        case .miMo: return "mimo-v2.5-pro"
        case .bailian: return "qwen3-coder-plus"
        case .xAI: return "grok-4.5"
        case .custom: return nil
        }
    }

    var balanceDescription: String {
        switch self {
        case .deepSeek: return "查询充值余额，不计赠送余额。"
        case .zhipuAI: return "查询 Coding Plan 的 5 小时与周配额。"
        case .moonshot: return "查询现金余额，不计代金券。"
        case .miniMax: return "查询 Coding Plan 的 5 小时与周配额。"
        case .stepFun: return "查询账户当前可用余额。"
        case .miMo: return "MiMo 暂未公开余额查询 API，可前往控制台查看。"
        case .bailian: return "余额请前往阿里百炼云控制台查看。"
        case .xAI: return "余额查询需要独立的 Management Key 与 Team ID。"
        case .custom: return "自定义提供商暂不自动查询余额。"
        }
    }

    static func infer(from baseURL: String) -> ProviderVendor {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return .custom }
        if host.contains("deepseek.com") { return .deepSeek }
        if host.contains("bigmodel.cn") || host == "api.z.ai" { return .zhipuAI }
        if host.contains("moonshot.cn") || host == "api.moonshot.ai" || host == "api.kimi.com" { return .moonshot }
        if host.contains("minimaxi.com") || host.contains("minimax.io") { return .miniMax }
        if host.contains("stepfun.ai") || host.contains("stepfun.com") { return .stepFun }
        if host.contains("xiaomimimo.com") { return .miMo }
        if host.contains("dashscope.aliyuncs.com") || host.hasSuffix("maas.aliyuncs.com") { return .bailian }
        if host == "api.x.ai" { return .xAI }
        return .custom
    }

    var logoResourceName: String? {
        switch self {
        case .deepSeek: return "deepseek"
        case .zhipuAI: return "zhipu"
        case .moonshot: return "kimi"
        case .miniMax: return "minimax"
        case .stepFun: return "stepfun"
        case .miMo: return "xiaomimimo"
        case .bailian: return "bailian"
        case .xAI: return nil
        case .custom: return nil
        }
    }

    var defaultAPIFormat: ProviderAPIFormat? {
        switch self {
        case .custom: return nil
        default: return .responses
        }
    }

    var supportsBalanceLookup: Bool {
        switch self {
        case .deepSeek, .zhipuAI, .moonshot, .miniMax, .stepFun, .xAI: return true
        case .miMo, .bailian, .custom: return false
        }
    }
}

struct ProviderProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var apiFormat: ProviderAPIFormat?
    var agents: [AgentKind]?
    var vendor: ProviderVendor?
    var balanceTeamID: String?

    init(
        id: String,
        name: String,
        baseURL: String,
        model: String,
        apiFormat: ProviderAPIFormat? = nil,
        agents: [AgentKind]? = nil,
        vendor: ProviderVendor? = nil,
        balanceTeamID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiFormat = apiFormat
        self.agents = agents
        self.vendor = vendor
        self.balanceTeamID = balanceTeamID
    }

    var boundAgents: Set<AgentKind> {
        let configured = agents ?? AgentKind.allCases
        return Set(configured.isEmpty ? AgentKind.allCases : configured)
    }

    func supports(_ agent: AgentKind) -> Bool {
        boundAgents.contains(agent)
    }

    var isCodeAPI: Bool {
        URL(string: baseURL)?.host?.lowercased() == "codeapi.nexita.net"
    }

    var isDeepSeek: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "api.deepseek.com" || host.hasSuffix(".deepseek.com")
    }

    var effectiveVendor: ProviderVendor {
        vendor ?? ProviderVendor.infer(from: baseURL)
    }

    var effectiveAPIFormat: ProviderAPIFormat {
        switch apiFormat ?? .automatic {
        case .automatic, .chatCompletions, .responses: return .responses
        }
    }

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static let codeAPI = ProviderProfile(
        id: "codeapi",
        name: "CodeAPI",
        baseURL: "https://codeapi.nexita.net",
        model: "gpt-5.6-sol",
        apiFormat: .responses,
        agents: nil,
        vendor: .custom
    )
}

private struct ProviderDatabase: Codable {
    var providers: [ProviderProfile]
    var selectedProviderID: String?
    var officialModel: String?
    var officialModelCatalogJSON: String?
}

enum ProviderStoreError: LocalizedError {
    case cannotSave(String)
    case duplicateID
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case let .cannotSave(message): return "无法保存提供商配置：\(message)"
        case .duplicateID: return "提供商内部标识重复，请删除异常配置后重新添加。"
        case let .duplicateName(name): return "路由名称“\(name)”已存在，请使用不同的名称。"
        }
    }
}

enum ProviderStore {
    static var databaseURL: URL {
        CredentialStore.directoryURL.appendingPathComponent("providers.json")
    }

    static func providers() -> [ProviderProfile] { load().providers }

    static func providers(for agent: AgentKind) -> [ProviderProfile] {
        load().providers.filter { $0.supports(agent) }
    }

    static func provider(id: String) -> ProviderProfile? {
        load().providers.first { $0.id == id }
    }

    static func selectedProviderID() -> String? { load().selectedProviderID }

    static func officialModel() -> String? { load().officialModel }

    static func officialModelCatalogJSON() -> String? { load().officialModelCatalogJSON }

    static func saveProviders(_ providers: [ProviderProfile], selectedProviderID: String?) throws {
        let normalizedIDs = providers.map { $0.id.lowercased() }
        guard Set(normalizedIDs).count == normalizedIDs.count else {
            throw ProviderStoreError.duplicateID
        }
        if let collision = firstDuplicateName(in: providers) {
            throw ProviderStoreError.duplicateName(collision)
        }
        var database = load()
        database.providers = providers
        database.selectedProviderID = selectedProviderID
        try save(database)
    }

    static func normalizedName(_ name: String) -> String {
        name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func hasNameCollision(
        _ name: String,
        excluding providerID: String,
        in providers: [ProviderProfile],
        agent: AgentKind? = nil
    ) -> Bool {
        let candidate = normalizedName(name)
        return providers.contains { provider in
            provider.id != providerID
                && normalizedName(provider.name) == candidate
                && (agent.map { provider.supports($0) } ?? true)
        }
    }

    static func popupTitles(for providers: [ProviderProfile]) -> [String] {
        let counts = Dictionary(grouping: providers, by: { normalizedName($0.name) })
            .mapValues(\.count)
        var usedTitles = Set<String>()
        return providers.map { provider in
            guard counts[normalizedName(provider.name), default: 0] > 1 else {
                usedTitles.insert(provider.name)
                return provider.name
            }
            let host = URL(string: provider.baseURL)?.host ?? provider.normalizedBaseURL
            let descriptive = "\(provider.name) · \(host) · \(provider.model)"
            if usedTitles.insert(descriptive).inserted {
                return descriptive
            }
            let unique = "\(descriptive) · \(provider.id.prefix(8))"
            usedTitles.insert(unique)
            return unique
        }
    }

    static func makeProviderID(existing providers: [ProviderProfile]) -> String {
        let existingIDs = Set(providers.map { $0.id.lowercased() })
        var candidate: String
        repeat {
            candidate = UUID().uuidString.lowercased()
        } while existingIDs.contains(candidate)
        return candidate
    }

    static func setSelectedProviderID(_ id: String?) throws {
        var database = load()
        database.selectedProviderID = id
        try save(database)
    }

    static func setOfficialModel(_ model: String?) throws {
        var database = load()
        database.officialModel = model
        try save(database)
    }

    static func setOfficialModelCatalogJSON(_ path: String?) throws {
        var database = load()
        database.officialModelCatalogJSON = path
        try save(database)
    }

    private static func load() -> ProviderDatabase {
        guard let data = try? Data(contentsOf: databaseURL),
              let database = try? JSONDecoder().decode(ProviderDatabase.self, from: data) else {
            return ProviderDatabase(
                providers: [.codeAPI],
                selectedProviderID: "codeapi",
                officialModel: nil,
                officialModelCatalogJSON: nil
            )
        }
        return database
    }

    private static func firstDuplicateName(in providers: [ProviderProfile]) -> String? {
        for (index, provider) in providers.enumerated() {
            for other in providers.dropFirst(index + 1) {
                if normalizedName(provider.name) == normalizedName(other.name),
                   !provider.boundAgents.isDisjoint(with: other.boundAgents) {
                    return other.name
                }
            }
        }
        return nil
    }

    private static func save(_ database: ProviderDatabase) throws {
        do {
            try CredentialStore.prepareDirectory()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(database)
            try data.write(to: databaseURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
        } catch {
            throw ProviderStoreError.cannotSave(error.localizedDescription)
        }
    }
}
