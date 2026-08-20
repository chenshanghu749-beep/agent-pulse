import Foundation
import WidgetKit

struct AgentPulseWidgetBalanceItem: Codable {
    let name: String
    let value: String
    let detail: String
    let isOfficial: Bool
}

struct AgentPulseWidgetData: Codable {
    let updatedAt: Date
    let routeName: String
    let modelName: String
    let primaryValue: String
    let primaryLabel: String
    let detail: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let taskText: String
    let taskColor: String
    let balances: [AgentPulseWidgetBalanceItem]?

    static let placeholder = AgentPulseWidgetData(
        updatedAt: Date(),
        routeName: "OpenAI 官方",
        modelName: "Codex",
        primaryValue: "—",
        primaryLabel: "正在读取用量",
        detail: "打开 Agent Pulse 以刷新数据",
        inputTokens: nil,
        outputTokens: nil,
        totalTokens: nil,
        taskText: "可以继续对话",
        taskColor: "green",
        balances: [
            AgentPulseWidgetBalanceItem(
                name: "OpenAI 官方",
                value: "82%",
                detail: "5 小时剩余",
                isOfficial: true
            )
        ]
    )
}

enum AgentPulseWidgetStore {
    static let kind = "AgentPulseUsageWidget"
    static let dataDirectoryName = "Agent Pulse"
    static let dataFileName = "widget-data.json"

    private static var dataURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent(dataFileName)
    }

    static func update(
        agent: AgentKind,
        route: RouteChoice,
        codeUsage: UsageResponse?,
        officialUsage: OfficialUsageSnapshot?,
        cursorOfficialUsage: CursorOfficialUsageSnapshot?,
        cursorProviderUsage: UsageResponse?,
        hermesStatus: HermesStatus?,
        hermesUsage: HermesUsageSnapshot?,
        task: TaskActivitySnapshot,
        balances: [BalanceOverviewEntry]
    ) {
        var routeName = "Codex · \(route.displayName)"
        var modelName = "Codex"
        var primaryValue = "—"
        var primaryLabel = "正在读取用量"
        var detail = ""
        var inputTokens: Int?
        var outputTokens: Int?
        var totalTokens: Int?

        if agent == .cursor {
            routeName = "Cursor"
            modelName = "Cursor Agent"
            if let cursorOfficialUsage {
                if let compact = cursorOfficialUsage.compactUsageText {
                    primaryValue = compact
                    primaryLabel = "Cursor 官方用量剩余"
                } else {
                    primaryValue = String(
                        format: "$%.2f",
                        Double(cursorOfficialUsage.remainingCents) / 100
                    )
                    primaryLabel = "Cursor 官方剩余额度"
                }
                if let cursorProviderUsage {
                    detail = "提供商余额 $\(String(format: "%.2f", cursorProviderUsage.balance))"
                } else if cursorOfficialUsage.limitCents > 0 {
                    detail = "账期内已用 $\(String(format: "%.2f", Double(cursorOfficialUsage.usedCents) / 100))"
                } else {
                    detail = cursorOfficialUsage.displayMessage ?? "官方用量自动刷新"
                }
            } else if let cursorProviderUsage {
                primaryValue = String(format: "$%.2f", cursorProviderUsage.balance)
                primaryLabel = "提供商余额"
                detail = "今日费用 $\(String(format: "%.2f", cursorProviderUsage.usage.today.actualCost))"
                inputTokens = cursorProviderUsage.usage.today.inputTokens
                outputTokens = cursorProviderUsage.usage.today.outputTokens
                totalTokens = cursorProviderUsage.usage.today.totalTokens
            } else {
                primaryValue = "Cursor"
                primaryLabel = "当前 Agent"
                detail = "状态 Hooks · 自动同步"
            }
        } else if agent == .hermes {
            let config = hermesStatus?.modelConfig ?? .unavailable
            routeName = "Hermes · \(config.provider)"
            modelName = config.model
            if let hermesUsage {
                primaryValue = formattedNumber(hermesUsage.totalTokens)
                primaryLabel = "今日 Token"
                detail = "\(hermesUsage.apiCalls) 次请求 · $\(String(format: "%.2f", hermesUsage.displayCostUSD))"
                inputTokens = hermesUsage.inputTokens
                outputTokens = hermesUsage.outputTokens
                totalTokens = hermesUsage.totalTokens
            } else {
                primaryValue = "Hermes"
                primaryLabel = "当前 Agent"
                detail = hermesStatus?.detail ?? "等待 Hermes 数据"
            }
        } else if agent == .claude || agent == .openCode {
            let provider = CLIAgentPreference.providerID(for: agent)
                .flatMap { ProviderStore.provider(id: $0) }
            routeName = "\(agent.displayName) · \(provider?.name ?? "当前配置")"
            modelName = provider?.model ?? agent.displayName
            if let codeUsage {
                primaryValue = String(format: "$%.2f", codeUsage.balance)
                primaryLabel = "提供商余额"
                detail = "今日费用 $\(String(format: "%.2f", codeUsage.usage.today.actualCost))"
                inputTokens = codeUsage.usage.today.inputTokens
                outputTokens = codeUsage.usage.today.outputTokens
                totalTokens = codeUsage.usage.today.totalTokens
            } else {
                primaryValue = provider?.model ?? agent.displayName
                primaryLabel = "当前模型"
                detail = provider?.baseURL ?? "CLI 配置已启用"
            }
        } else {
            switch route {
            case let .provider(id):
                let provider = ProviderStore.provider(id: id)
                modelName = provider?.model ?? "第三方模型"
                if provider?.isCodeAPI == true, let codeUsage {
                    primaryValue = String(format: "$%.2f", codeUsage.balance)
                    primaryLabel = "账户余额"
                    detail = "今日费用 $\(String(format: "%.2f", codeUsage.usage.today.actualCost))"
                    inputTokens = codeUsage.usage.today.inputTokens
                    outputTokens = codeUsage.usage.today.outputTokens
                    totalTokens = codeUsage.usage.today.totalTokens
                } else {
                    primaryValue = provider?.name ?? "第三方"
                    primaryLabel = "当前提供商"
                    detail = provider?.baseURL ?? "配置不可用"
                }
            case .official:
                if let officialUsage, officialUsage.isLoggedIn {
                    modelName = officialUsage.planType ?? "ChatGPT"
                    if let window = officialUsage.primary {
                        primaryValue = String(format: "%.0f%%", window.remainingPercent)
                        primaryLabel = "官方用量剩余"
                        detail = "\(window.label) · 自动刷新"
                    } else {
                        primaryValue = "—"
                        primaryLabel = "官方用量剩余"
                        detail = officialUsage.email ?? "用量数据暂不可用"
                    }
                    totalTokens = officialUsage.tokenUsage?.todayTokens
                } else if officialUsage != nil {
                    primaryValue = "未登录"
                    primaryLabel = "OpenAI 官方账号"
                    detail = "请在 Codex 中完成登录"
                }
            }
        }

        let taskText: String
        let taskColor: String
        switch task.state {
        case let .running(count):
            taskText = count > 1 ? "\(count) 个会话执行中" : "会话执行中"
            taskColor = "red"
        case let .waiting(count):
            taskText = count > 1 ? "\(count) 个会话等待中" : "等待工具或命令"
            taskColor = "yellow"
        case .ready:
            taskText = "可以继续对话"
            taskColor = "green"
        }

        let value = AgentPulseWidgetData(
            updatedAt: Date(), routeName: routeName, modelName: modelName,
            primaryValue: primaryValue, primaryLabel: primaryLabel, detail: detail,
            inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: totalTokens,
            taskText: taskText, taskColor: taskColor,
            balances: balances.map {
                AgentPulseWidgetBalanceItem(
                    name: $0.name,
                    value: $0.value,
                    detail: $0.detail,
                    isOfficial: $0.isOfficial
                )
            }
        )
        guard let data = try? JSONEncoder().encode(value) else { return }
        let directory = dataURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dataURL.path)
        } catch {
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
