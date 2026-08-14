import Foundation

struct DiagnosticRow: Sendable {
    let title: String
    let value: String
    let isWarning: Bool
}

struct AgentPulseDiagnosticReport: Sendable {
    let generatedAt: Date
    let rows: [DiagnosticRow]

    var redactedText: String {
        let formatter = ISO8601DateFormatter()
        let body = (["Agent Pulse 诊断报告", "生成时间：\(formatter.string(from: generatedAt))"]
            + rows.map { "\($0.title)：\($0.value)" })
            .joined(separator: "\n")
        return SensitiveConfigSanitizer.sanitize(body)
    }
}

enum DiagnosticsCenter {
    static func makeReport(
        agent: AgentKind,
        route: RouteChoice,
        task: TaskActivitySnapshot,
        lastUsageRefresh: Date?,
        latestError: String?,
        monitorActive: Bool,
        agentPath: String?,
        agentVersion: String?
    ) -> AgentPulseDiagnosticReport {
        let provider: ProviderProfile?
        switch agent {
        case .codex:
            if case let .provider(id) = route { provider = ProviderStore.provider(id: id) } else { provider = nil }
        case .hermes:
            provider = HermesPreference.providerID.flatMap { ProviderStore.provider(id: $0) }
        case .cursor:
            provider = CursorUsagePreference.providerID.flatMap { ProviderStore.provider(id: $0) }
        case .claude, .openCode:
            provider = CLIAgentPreference.providerID(for: agent).flatMap { ProviderStore.provider(id: $0) }
        }

        let config = (try? String(contentsOf: RouteConfigManager.configURL, encoding: .utf8)) ?? ""
        var conflicts: [String] = []
        if agent == .codex {
            do { try RouteConfigManager.validate(config) } catch { conflicts.append(error.localizedDescription) }
            if case let .provider(id) = route, ProviderStore.provider(id: id) == nil {
                conflicts.append("当前路由引用了不存在的提供商")
            }
            if RouteConfigManager.needsUpgradeReconciliation() {
                conflicts.append("托管提供商配置需要重新同步")
            }
        }
        let profiles = ProviderStore.providers(for: agent)
        let duplicateNames = Dictionary(grouping: profiles, by: { $0.name.lowercased() })
            .filter { $0.value.count > 1 }
            .keys
        if !duplicateNames.isEmpty { conflicts.append("存在重复配置名：\(duplicateNames.sorted().joined(separator: ", "))") }

        let activity = TaskActivityReader.compatibilityInfo()
        let routeName = provider?.name ?? (agent == .codex ? route.displayName : "官方")
        let model = provider?.model ?? currentModel(agent: agent)
        let taskText: String
        let taskIsActive: Bool
        switch task.state {
        case let .running(count): taskText = "执行中（\(count)）"; taskIsActive = true
        case let .waiting(count): taskText = "等待本地工具（\(count)）"; taskIsActive = true
        case .ready: taskText = "已完成，可以继续输入"; taskIsActive = false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        func dateText(_ date: Date?) -> String { date.map(formatter.string(from:)) ?? "暂无" }

        let listenerText: String
        switch agent {
        case .codex: listenerText = activity.summary
        case .cursor: listenerText = CursorIntegration.hooksInstalled() ? "Hooks 已安装" : "Hooks 缺失或需要重装"
        case .hermes: listenerText = FileManager.default.fileExists(atPath: HermesIntegration.homeURL.path)
            ? "Hermes 本地状态目录可用" : "Hermes 本地状态目录不存在"
        case .claude, .openCode:
            listenerText = "已支持模型与提供商配置；任务状态监听暂未启用"
        }

        let eventDate = task.changedAt ?? activity.latestEventAt
        let stale = taskIsActive && eventDate.map { Date().timeIntervalSince($0) > 20 * 60 } == true
        var rows = [
            DiagnosticRow(title: "应用版本", value: "\(AppUpdateChecker.currentVersion)（\(AppUpdateChecker.currentBuild)）", isWarning: false),
            DiagnosticRow(title: "当前 Agent", value: agent.displayName, isWarning: false),
            DiagnosticRow(title: "Agent 版本", value: agentVersion ?? "未识别", isWarning: agentVersion == nil),
            DiagnosticRow(title: "Agent 路径", value: agentPath ?? "未找到", isWarning: agentPath == nil),
            DiagnosticRow(title: "当前路由", value: routeName, isWarning: false),
            DiagnosticRow(title: "当前模型", value: model ?? "未识别", isWarning: model == nil),
            DiagnosticRow(title: "Model Provider", value: agent == .codex ? RouteConfigManager.currentModelProvider() : "不适用", isWarning: false),
            DiagnosticRow(title: "API URL", value: provider?.baseURL ?? "官方服务", isWarning: false),
            DiagnosticRow(title: "连接状态", value: latestError ?? "最近一次刷新正常", isWarning: latestError != nil),
            DiagnosticRow(title: "余额刷新", value: dateText(lastUsageRefresh), isWarning: lastUsageRefresh == nil),
            DiagnosticRow(title: "任务状态", value: stale ? "\(taskText) · 超过 20 分钟无新事件，请重置监听" : taskText, isWarning: stale),
            DiagnosticRow(title: "最后任务事件", value: dateText(eventDate), isWarning: eventDate == nil || stale),
            DiagnosticRow(title: "状态监听", value: "\(monitorActive ? "运行中" : "未启动") · \(listenerText)", isWarning: !monitorActive),
            DiagnosticRow(title: "配置冲突", value: conflicts.isEmpty ? "未发现" : conflicts.joined(separator: "；"), isWarning: !conflicts.isEmpty)
        ]
        if agent == .codex {
            rows.append(DiagnosticRow(
                title: "会话安全",
                value: "路由切换不读取、不移动、不修改会话数据库",
                isWarning: false
            ))
        }
        return AgentPulseDiagnosticReport(generatedAt: Date(), rows: rows)
    }

    private static func currentModel(agent: AgentKind) -> String? {
        switch agent {
        case .codex:
            return ProviderStore.officialModel()
        case .cursor:
            return "Cursor 官方模型"
        case .hermes:
            let model = HermesIntegration.readModelConfig().model
            return model == HermesModelConfig.unavailable.model ? nil : model
        case .claude:
            return ClaudeCodeIntegration.readStatus().config.model
        case .openCode:
            return OpenCodeIntegration.readStatus().config.model
        }
    }
}
