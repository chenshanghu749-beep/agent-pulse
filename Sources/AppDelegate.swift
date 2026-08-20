import AppKit
import Foundation

struct DashboardSnapshot {
    let agentName: String
    let routeName: String
    let taskStatus: String
    let taskSignal: TrafficSignal
    let usageLabel: String
    let usageValue: String
    let usageDetail: String
    let updatedText: String
    let version: String
    let message: String?
}

struct HermesDashboardPresentation: Equatable {
    let routeName: String
    let usageLabel: String
    let usageValue: String
    let usageDetail: String

    var statusValue: String {
        guard usageValue != "—" else { return routeName }
        return usageLabel == "今日 Token" ? "\(usageValue) Token" : usageValue
    }

    static func make(
        providerName: String?,
        config: HermesModelConfig,
        usage: HermesUsageSnapshot?,
        codeBalance: Double?,
        providerBalance: ProviderBalanceSnapshot?
    ) -> HermesDashboardPresentation {
        let routeName = providerName ?? config.provider
        let localUsageDetail: String
        if let usage {
            localUsageDetail = "\(formattedNumber(usage.totalTokens)) Token · \(usage.apiCalls) 次请求 · 费用 \(money(usage.displayCostUSD)) · \(config.model)"
        } else {
            localUsageDetail = "\(config.provider) · \(config.model)"
        }
        if let codeBalance {
            return HermesDashboardPresentation(
                routeName: routeName,
                usageLabel: "提供商余额",
                usageValue: money(codeBalance),
                usageDetail: localUsageDetail
            )
        }
        if let providerBalance {
            let isQuota = providerBalance.displayText.hasPrefix("配额 ")
            let value = providerBalance.displayText
                .replacingOccurrences(of: "余额 ", with: "")
                .replacingOccurrences(of: "配额 ", with: "")
            return HermesDashboardPresentation(
                routeName: routeName,
                usageLabel: isQuota ? "提供商配额" : "提供商余额",
                usageValue: value,
                usageDetail: "\(providerBalance.detail) · \(localUsageDetail)"
            )
        }
        if let usage {
            return HermesDashboardPresentation(
                routeName: routeName,
                usageLabel: "今日 Token",
                usageValue: formattedNumber(usage.totalTokens),
                usageDetail: "\(usage.apiCalls) 次请求 · 费用 \(money(usage.displayCostUSD)) · \(config.model)"
            )
        }
        return HermesDashboardPresentation(
            routeName: routeName,
            usageLabel: "今日 Token",
            usageValue: "—",
            usageDetail: "\(config.provider) · \(config.model)"
        )
    }

    private static func money(_ value: Double) -> String { String(format: "$%.2f", value) }

    private static func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private final class StatusIconOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct StatusRenderKey: Equatable {
        let style: StatusIconStyle
        let previousSignal: TrafficSignal
        let targetSignal: TrafficSignal
        let previousFrame: Int
        let targetFrame: Int
        let transitionStep: Int
        let toolTip: String
        let appearance: String
    }

    private var statusItem: NSStatusItem!
    private let mainMenu = NSMenu()
    private let contextMenu = NSMenu()

    private var usageTimer: Timer?
    private var taskTimer: Timer?
    private var balanceRotationTimer: Timer?
    private var balanceRotationIndex = 0
    private var taskActivityMonitor: TaskActivityMonitor?
    private var taskMonitorActive = false
    private var iconAnimationTimer: Timer?
    private var startupChaseTimer: Timer?
    private var startupChaseIndex: Int?
    private var agent = AgentPreference.selected
    private var route = RouteConfigManager.currentRoute()
    private var routeDisplayName = "OpenAI 官方"
    private var latestCodeUsage: UsageResponse?
    private var latestProviderBalance: ProviderBalanceSnapshot?
    private var latestOfficialUsage: OfficialUsageSnapshot?
    private var latestCursorStatus = CursorStatus.unavailable
    private var latestCursorOfficialUsage: CursorOfficialUsageSnapshot?
    private var latestCursorProviderUsage: UsageResponse?
    private var latestHermesStatus = HermesStatus.unavailable
    private var latestHermesUsage: HermesUsageSnapshot?
    private var latestCLIStatuses: [AgentKind: CLIAgentStatus] = [:]
    private var cursorHooksNeedRestart = false
    private var latestError: String?
    private var lastUpdated: Date?
    private var isRefreshingUsage = false
    private var isRefreshingTask = false
    private var pendingTaskFileEvents: [String: TaskActivityFileEvent] = [:]
    private var pendingTaskForceScan = false
    private var taskSnapshot = TaskActivitySnapshot(state: .ready, changedAt: nil)
    private var statusIconStyle = StatusIconPreference.selected
    private var displayedSignal: TrafficSignal = .green
    private var previousSignal: TrafficSignal = .green
    private var targetSignal: TrafficSignal = .green
    private var transitionStartedAt = Date.distantPast
    private var animationFrame = 0
    private var iconAnimationFPS: Double = 0
    private var lastStatusRenderKey: StatusRenderKey?
    private weak var statusIconOverlayView: StatusIconOverlayView?
    private var statusIconPlaceholderSize = NSSize.zero
    private var isUsingNativeStatusImage = false
    private var statusTitleText = ""
    private let iconAnimationStartUptime = ProcessInfo.processInfo.systemUptime
    private lazy var settings = SettingsWindowController(appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppThemePreference.apply(AppThemePreference.selected)
        CursorUsagePreference.officialUsageEnabled = true
        CursorUsagePreference.providerID = nil
        installTextEditingCommands()
        WidgetRegistration.ensureRegistered()

        do {
            let startupRoute = RouteConfigManager.currentRoute()
            _ = try RouteUpgradeCoordinator.reconcileIfNeeded(
                needsReconciliation: {
                    RouteConfigManager.needsUpgradeReconciliation()
                        || CodexAuthStore.providerAuthNeedsRepair(for: startupRoute)
                },
                currentRoute: { startupRoute },
                snapshotAuth: { try CodexAuthStore.snapshot() },
                prepareAuth: { _ = try CodexAuthStore.prepareForSwitch(to: $0) },
                restoreAuth: { try CodexAuthStore.restore($0) },
                applyConfig: { try RouteConfigManager.apply($0) }
            )
        } catch {
            latestError = error.localizedDescription
        }
        route = RouteConfigManager.currentRoute()
        routeDisplayName = route.displayName
        if agent == .cursor {
            do {
                cursorHooksNeedRestart = try CursorIntegration.installHooks()
                if cursorHooksNeedRestart {
                    latestError = "Cursor 状态 Hooks 已更新，请重启 Cursor 使其生效。"
                }
            } catch {
                latestError = error.localizedDescription
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AgentPulseStatusItem"
        mainMenu.delegate = self
        configureStatusButton()
        startStartupChase()
        rebuildMainMenu()

        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
        usageTimer?.tolerance = 5
        startTaskActivityMonitor()
        taskTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTaskActivity(forceFileScan: true) }
        }
        taskTimer?.tolerance = 2
        [usageTimer, taskTimer].compactMap { $0 }.forEach {
            RunLoop.main.add($0, forMode: .common)
        }
        configureBalanceRotationTimer()

        updateWidget()
        Task {
            await refreshTaskActivity(forceFileScan: true)
            await refreshUsage()
        }

        // Route changes must never inspect or mutate the Codex session database.
        // Legacy-session migration is intentionally kept out of startup; it can
        // be reintroduced later as an explicit, advanced recovery action.
        Task { @MainActor [weak self] in
            self?.settings.present()
        }
    }

    private func offerLegacySessionMigrationIfNeeded() async {
        guard LegacySessionMigration.shouldPrompt() else { return }
        let scan: LegacySessionMigrationScan?
        do {
            scan = try await Task.detached(priority: .utility) {
                try LegacySessionMigration.scan()
            }.value
        } catch {
            latestError = error.localizedDescription
            return
        }
        guard let scan else {
            LegacySessionMigration.markPromptHandled()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现旧版第三方会话"
        alert.informativeText = """
        检测到 \(scan.providerCount) 个第三方配置、\(scan.sessionCount) 条旧会话（\(sizeFormatter.string(fromByteCount: scan.totalBytes))）。

        新版 Codex 使用统一的 OpenAI 会话标识。Agent Pulse 可以为这些会话创建一份兼容副本，让官方和第三方路由都能看到。原会话不会修改，并会额外备份数据库和源文件。
        """
        alert.addButton(withTitle: "复制并保留备份")
        alert.addButton(withTitle: "暂不处理")
        guard alert.runModal() == .alertFirstButtonReturn else {
            LegacySessionMigration.markPromptHandled()
            return
        }

        let codexWasRunning = CodexLauncher.isRunning
        do {
            if codexWasRunning {
                try await CodexLauncher.terminate()
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try LegacySessionMigration.migrate(scan)
            }.value
            LegacySessionMigration.markPromptHandled()
            if codexWasRunning {
                try await CodexLauncher.launch()
            }
            let success = NSAlert()
            success.alertStyle = .informational
            success.messageText = "旧会话兼容副本已创建"
            success.informativeText = """
            已复制 \(result.copiedSessions) 条会话到统一列表，原会话保持不变。

            备份位置：
            \(result.backupDirectory.path)
            """
            success.addButton(withTitle: "完成")
            success.runModal()
        } catch {
            if codexWasRunning, !CodexLauncher.isRunning {
                try? await CodexLauncher.launch()
            }
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "旧会话复制未完成"
            failure.informativeText = "\(error.localizedDescription)\n\n原会话未修改，下次启动时可以重新尝试。"
            failure.addButton(withTitle: "知道了")
            failure.runModal()
        }
    }

    private func installTextEditingCommands() {
        let applicationMenu = NSMenu()
        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = editMenu
        applicationMenu.addItem(editRoot)
        NSApp.mainMenu = applicationMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageTimer?.invalidate()
        taskTimer?.invalidate()
        taskActivityMonitor?.stop()
        iconAnimationTimer?.invalidate()
        startupChaseTimer?.invalidate()
        balanceRotationTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.present()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === mainMenu { rebuildMainMenu() }
        if menu === contextMenu { rebuildContextMenu() }
    }

    func routeDidChange(to route: RouteChoice, validatedCodeUsage: UsageResponse?) {
        self.route = route
        routeDisplayName = route.displayName
        latestError = nil
        lastUpdated = Date()
        latestCodeUsage = validatedCodeUsage
        latestProviderBalance = nil
        latestOfficialUsage = nil
        startStartupChase()
        updateStatusTitle()
        rebuildMainMenu()
        updateWidget()
        settings.refreshDashboard()
        Task { await refreshUsage() }
    }

    func agentDidChange(to agent: AgentKind) {
        self.agent = agent
        AgentPreference.selected = agent
        latestError = nil
        latestCodeUsage = nil
        latestProviderBalance = nil
        latestOfficialUsage = nil
        latestCursorOfficialUsage = nil
        latestCursorProviderUsage = nil
        latestHermesStatus = .unavailable
        latestHermesUsage = nil
        taskSnapshot = TaskActivitySnapshot(state: .ready, changedAt: nil)
        startStartupChase()
        updateStatusTitle()
        rebuildMainMenu()
        updateWidget()
        settings.refreshDashboard()
        Task {
            await refreshTaskActivity()
            await refreshUsage()
        }
    }

    func statusIconStyleDidChange(to style: StatusIconStyle) {
        statusIconStyle = style
        StatusIconPreference.selected = style
        lastStatusRenderKey = nil
        renderStatusButton()
        rebuildMainMenu()
    }

    func statusBalanceDisplayModeDidChange(to mode: StatusBalanceDisplayMode) {
        StatusBalanceDisplayPreference.selected = mode
        balanceRotationIndex = 0
        configureBalanceRotationTimer()
        updateStatusTitle()
    }

    func balanceOverviewDidChange() {
        let count = BalanceOverviewStore.entries().count
        if count > 0 { balanceRotationIndex %= count }
        else { balanceRotationIndex = 0 }
        updateStatusTitle()
        updateWidget()
    }

    func cursorHooksDidRestart() {
        cursorHooksNeedRestart = false
        latestError = nil
        rebuildMainMenu()
    }

    func cursorHooksDidChange(restartRequired: Bool) {
        cursorHooksNeedRestart = restartRequired
        latestError = restartRequired ? "Cursor 状态 Hooks 已更新，下次手动重启 Cursor 后生效。" : nil
        rebuildMainMenu()
    }

    func presentLaunchWarning(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(agent.displayName) 未能自动打开"
        alert.informativeText = "配置已经生效。你可以稍后手动打开 \(agent.displayName)。\n\n\(message)"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func presentOfficialLoginRequired() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "请重新登录 OpenAI 官方账号"
        alert.informativeText = "检测到 Codex 的认证文件中残留了第三方 API Key，已将它安全移出官方认证。请在 Codex 中登录一次，后续切换会自动备份和恢复官方登录。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleNone
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.wantsLayer = true
        let overlay = StatusIconOverlayView()
        overlay.layer?.contentsGravity = .center
        overlay.layer?.contentsScale = 2
        button.addSubview(overlay)
        statusIconOverlayView = overlay
        updateStatusTitle()
        renderStatusButton()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildContextMenu()
            showMenu(contextMenu)
        } else {
            rebuildMainMenu()
            showMenu(mainMenu)
        }
    }

    private func showMenu(_ menu: NSMenu) {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 3), in: button)
    }

    private func configureBalanceRotationTimer() {
        balanceRotationTimer?.invalidate()
        balanceRotationTimer = nil
        guard StatusBalanceDisplayPreference.selected == .rotateAll else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let entries = BalanceOverviewStore.entries()
                guard !entries.isEmpty else { return }
                self.balanceRotationIndex = (self.balanceRotationIndex + 1) % entries.count
                self.updateStatusTitle()
            }
        }
        timer.tolerance = 0.4
        balanceRotationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if StatusBalanceDisplayPreference.selected == .rotateAll {
            let entries = BalanceOverviewStore.entries()
            if !entries.isEmpty {
                let entry = entries[balanceRotationIndex % entries.count]
                applyStatusTitle(
                    "\(entry.name) · \(compact(entry.value))",
                    toolTip: "Agent Pulse · \(entry.detail)",
                    to: button
                )
                return
            }
        }
        if agent == .cursor {
            var parts = ["Cursor"]
            if let usage = latestCursorOfficialUsage {
                if let compact = usage.compactUsageText {
                    parts.append(compact)
                } else {
                    parts.append(money(Double(usage.remainingCents) / 100))
                }
            }
            if let usage = latestCursorProviderUsage {
                parts.append(money(usage.balance))
            }
            applyStatusTitle(parts.joined(separator: " · "), toolTip: "Agent Pulse · Cursor", to: button)
            return
        }
        if agent == .hermes {
            let providerName = HermesPreference.providerID
                .flatMap { ProviderStore.provider(id: $0)?.name }
            let presentation = HermesDashboardPresentation.make(
                providerName: providerName,
                config: latestHermesStatus.modelConfig,
                usage: latestHermesUsage,
                codeBalance: latestCodeUsage?.balance,
                providerBalance: latestProviderBalance
            )
            applyStatusTitle(
                "Hermes · \(compact(presentation.statusValue))",
                toolTip: "Agent Pulse · Hermes · \(latestHermesStatus.detail)",
                to: button
            )
            return
        }
        if agent == .claude || agent == .openCode {
            let status = latestCLIStatuses[agent] ?? .unavailable(agent)
            let provider = CLIAgentPreference.providerID(for: agent)
                .flatMap { ProviderStore.provider(id: $0) }
            let value: String
            if let balance = latestCodeUsage?.balance {
                value = money(balance)
            } else if let balance = latestProviderBalance {
                value = compact(balance.displayText)
            } else {
                value = compact(provider?.model ?? status.config.model)
            }
            applyStatusTitle(
                "\(agent.displayName) · \(value)",
                toolTip: "Agent Pulse · \(agent.displayName) · \(status.detail)",
                to: button
            )
            return
        }
        let title: String
        switch route {
        case let .provider(id):
            let provider = ProviderStore.provider(id: id)
            if provider?.isCodeAPI == true, let data = latestCodeUsage {
                title = money(data.balance)
            } else if let balance = latestProviderBalance {
                title = compact(balance.displayText)
            } else {
                title = compact(provider?.name ?? "第三方")
            }
        case .official:
            if latestOfficialUsage?.isLoggedIn == false {
                title = "官方 · 未登录"
            } else if let window = latestOfficialUsage?.primary {
                title = "官方 \(percent(window.remainingPercent))"
            } else if latestOfficialUsage?.isLoggedIn == true {
                title = "官方 —"
            } else {
                title = "官方 …"
            }
        }
        applyStatusTitle(
            "Codex · \(title)",
            toolTip: "Agent Pulse · Codex · \(route.displayName)",
            to: button
        )
    }

    private func applyStatusTitle(_ title: String, toolTip: String, to button: NSStatusBarButton) {
        let titleChanged = title != statusTitleText
        if titleChanged { animateStatusTitleTransition(in: button) }
        statusTitleText = title
        button.toolTip = toolTip
        if statusIconStyle.usesCompositeStatusItemImage {
            button.title = ""
            if titleChanged {
                lastStatusRenderKey = nil
                renderStatusButton()
            }
        } else {
            button.title = title
        }
    }

    private func animateStatusTitleTransition(in button: NSStatusBarButton) {
        guard StatusBalanceDisplayPreference.selected == .rotateAll,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = button.layer else { return }
        layer.removeAnimation(forKey: "AgentPulseBalanceCrossfade")
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.26
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transition, forKey: "AgentPulseBalanceCrossfade")
    }

    private func compact(_ value: String) -> String {
        value.count > 12 ? String(value.prefix(11)) + "…" : value
    }

    private func currentSignal() -> TrafficSignal {
        if let startupChaseIndex {
            return TrafficSignal.allCases[startupChaseIndex % TrafficSignal.allCases.count]
        }
        switch taskSnapshot.state {
        case .running: return .red
        case .waiting: return .yellow
        case .ready: return .green
        }
    }

    private func updateSignalTarget() {
        let newSignal = currentSignal()
        guard newSignal != targetSignal else { return }
        previousSignal = targetSignal
        targetSignal = newSignal
        transitionStartedAt = Date()
        lastStatusRenderKey = nil
    }

    private func renderStatusButton() {
        guard let button = statusItem?.button else { return }
        updateSignalTarget()
        let elapsed = Date().timeIntervalSince(transitionStartedAt)
        let progress = min(1, max(0, elapsed / 0.28))
        let transitionStep = progress >= 1 ? 20 : Int((progress * 20).rounded())
        let previousFrame = StatusIconRenderer.animationPhase(
            style: statusIconStyle,
            active: previousSignal,
            frame: animationFrame
        )
        let targetFrame = StatusIconRenderer.animationPhase(
            style: statusIconStyle,
            active: targetSignal,
            frame: animationFrame
        )
        let routeText = agent == .codex ? " · \(routeDisplayName)" : ""
        let toolTip = "Agent Pulse · \(agent.displayName) · \(taskStatusText())\(routeText)"
        let appearance = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? "dark"
            : "light"
        let renderKey = StatusRenderKey(
            style: statusIconStyle,
            previousSignal: previousSignal,
            targetSignal: targetSignal,
            previousFrame: previousFrame,
            targetFrame: targetFrame,
            transitionStep: transitionStep,
            toolTip: toolTip,
            appearance: appearance
        )
        if renderKey == lastStatusRenderKey {
            syncIconAnimationTimer()
            return
        }
        lastStatusRenderKey = renderKey
        let oldImage = StatusIconRenderer.image(
            style: statusIconStyle,
            active: previousSignal,
            frame: animationFrame,
            appearance: button.effectiveAppearance
        )
        let newImage = StatusIconRenderer.image(
            style: statusIconStyle,
            active: targetSignal,
            frame: animationFrame,
            appearance: button.effectiveAppearance
        )
        let statusImage: NSImage
        if progress >= 1 {
            displayedSignal = targetSignal
            statusImage = newImage
        } else {
            statusImage = StatusIconRenderer.blended(
                from: oldImage,
                to: newImage,
                progress: CGFloat(transitionStep) / 20
            )
        }
        displayStatusImage(statusImage, in: button)
        button.toolTip = toolTip
        syncIconAnimationTimer()
    }

    private func displayStatusImage(_ image: NSImage, in button: NSStatusBarButton) {
        if statusIconStyle.usesCompositeStatusItemImage {
            let composite = StatusIconRenderer.statusItemImage(
                style: statusIconStyle,
                active: targetSignal,
                frame: animationFrame,
                title: statusTitleText,
                font: button.font ?? .systemFont(ofSize: 12, weight: .medium),
                appearance: button.effectiveAppearance
            )
            isUsingNativeStatusImage = true
            statusIconPlaceholderSize = composite.size
            statusIconOverlayView?.isHidden = true
            button.title = ""
            button.image = composite
            return
        }
        button.title = statusTitleText
        statusIconOverlayView?.isHidden = false
        if isUsingNativeStatusImage || statusIconPlaceholderSize != image.size {
            isUsingNativeStatusImage = false
            statusIconPlaceholderSize = image.size
            button.image = NSImage(size: image.size)
            button.needsLayout = true
            button.layoutSubtreeIfNeeded()
        }
        layoutStatusIconOverlay(in: button)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            statusIconOverlayView?.layer?.contents = cgImage
        }
    }

    private func layoutStatusIconOverlay(in button: NSStatusBarButton) {
        guard let overlay = statusIconOverlayView else { return }
        button.layoutSubtreeIfNeeded()
        if let cell = button.cell as? NSButtonCell {
            overlay.frame = cell.imageRect(forBounds: button.bounds)
        }
    }

    private func syncIconAnimationTimer() {
        let transitionActive = !statusIconStyle.usesCompositeStatusItemImage
            && Date().timeIntervalSince(transitionStartedAt) < 0.28
        let desiredFPS = transitionActive
            ? 16
            : statusIconStyle.animationFramesPerSecond(for: targetSignal)
        guard desiredFPS != iconAnimationFPS else { return }
        iconAnimationTimer?.invalidate()
        iconAnimationTimer = nil
        iconAnimationFPS = desiredFPS
        guard desiredFPS > 0 else { return }
        let timer = Timer(
            timeInterval: 1 / desiredFPS,
            target: self,
            selector: #selector(iconAnimationTick),
            userInfo: nil,
            repeats: true
        )
        iconAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func iconAnimationTick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - iconAnimationStartUptime
        animationFrame = Int(elapsed * 60)
        if statusIconStyle.usesCompositeStatusItemImage,
           let button = statusItem?.button {
            button.image = StatusIconRenderer.statusItemImage(
                style: statusIconStyle,
                active: targetSignal,
                frame: animationFrame,
                title: statusTitleText,
                font: button.font ?? .systemFont(ofSize: 12, weight: .medium),
                appearance: button.effectiveAppearance
            )
            return
        }
        renderStatusButton()
    }

    private func taskStatusText() -> String {
        if startupChaseIndex != nil { return "正在检测任务状态" }
        switch taskSnapshot.state {
        case let .running(count): return count > 1 ? "\(count) 个会话执行中" : "会话执行中"
        case let .waiting(count): return count > 1 ? "\(count) 个会话等待中" : "等待工具或命令"
        case .ready: return "可以继续对话"
        }
    }

    func dashboardSnapshot() -> DashboardSnapshot {
        let taskSignal: TrafficSignal
        switch taskSnapshot.state {
        case .running: taskSignal = .red
        case .waiting: taskSignal = .yellow
        case .ready: taskSignal = .green
        }

        var routeName = route.displayName
        var usageLabel = "用量"
        var usageValue = "—"
        var usageDetail = "正在等待数据"

        if agent == .cursor {
            routeName = "Cursor 官方"
            if CursorUsagePreference.officialUsageEnabled {
                usageLabel = "官方用量剩余"
                if let usage = latestCursorOfficialUsage {
                    usageValue = usage.compactUsageText ?? usage.remainingPercent.map(percent) ?? "—"
                    if usage.limitCents > 0 {
                        usageDetail = "本期已用 \(money(Double(usage.usedCents) / 100)) / \(money(Double(usage.limitCents) / 100))"
                    } else {
                        usageDetail = usage.displayMessage ?? "Cursor 当前账期"
                    }
                } else {
                    usageDetail = "尚未读取到 Cursor 官方用量"
                }
            } else if let id = CursorUsagePreference.providerID,
                      let provider = ProviderStore.provider(id: id) {
                routeName = provider.name
                if let usage = latestCursorProviderUsage {
                    usageLabel = "提供商余额"
                    usageValue = money(usage.balance)
                    usageDetail = "今日费用 \(money(usage.usage.today.actualCost)) · \(number(usage.usage.today.totalTokens)) Token"
                } else {
                    usageLabel = "当前模型"
                    usageValue = provider.model
                    usageDetail = provider.name
                }
            } else {
                usageDetail = "Cursor 官方用量已关闭"
            }
        } else if agent == .hermes {
            let config = latestHermesStatus.modelConfig
            let providerName = HermesPreference.providerID
                .flatMap { ProviderStore.provider(id: $0)?.name }
            let presentation = HermesDashboardPresentation.make(
                providerName: providerName,
                config: config,
                usage: latestHermesUsage,
                codeBalance: latestCodeUsage?.balance,
                providerBalance: latestProviderBalance
            )
            routeName = presentation.routeName
            usageLabel = presentation.usageLabel
            usageValue = presentation.usageValue
            usageDetail = presentation.usageDetail
        } else if agent == .claude || agent == .openCode {
            let status = latestCLIStatuses[agent] ?? .unavailable(agent)
            let provider = CLIAgentPreference.providerID(for: agent)
                .flatMap { ProviderStore.provider(id: $0) }
            routeName = provider?.name ?? status.config.provider
            if let balance = latestCodeUsage?.balance {
                usageLabel = "提供商余额"
                usageValue = money(balance)
                usageDetail = provider.map { "\($0.model) · \($0.baseURL)" } ?? status.detail
            } else if let balance = latestProviderBalance {
                usageLabel = balance.displayText.hasPrefix("配额 ") ? "提供商配额" : "提供商余额"
                usageValue = balance.displayText
                    .replacingOccurrences(of: "余额 ", with: "")
                    .replacingOccurrences(of: "配额 ", with: "")
                usageDetail = "\(balance.detail) · \(provider?.model ?? status.config.model)"
            } else {
                usageLabel = "当前模型"
                usageValue = provider?.model ?? status.config.model
                usageDetail = status.installed ? status.detail : "未找到 \(agent.displayName) CLI"
            }
        } else {
            switch route {
            case .official:
                usageLabel = "官方用量剩余"
                if latestOfficialUsage?.isLoggedIn == false {
                    usageValue = "未登录"
                    usageDetail = "请先登录 OpenAI 官方账号"
                } else if let primary = latestOfficialUsage?.primary {
                    usageValue = percent(primary.remainingPercent)
                    if let secondary = latestOfficialUsage?.secondary {
                        usageDetail = "\(primary.label) · \(secondary.label)剩余 \(percent(secondary.remainingPercent))"
                    } else {
                        usageDetail = "\(primary.label) · \(resetFormatter.string(from: primary.resetsAt)) 重置"
                    }
                } else if latestOfficialUsage?.isLoggedIn == true {
                    usageDetail = "官方账号已连接，暂未返回用量"
                }
            case let .provider(id):
                if let provider = ProviderStore.provider(id: id) {
                    routeName = provider.name
                    if provider.isCodeAPI, let usage = latestCodeUsage {
                        usageLabel = "提供商余额"
                        usageValue = money(usage.balance)
                        usageDetail = "今日费用 \(money(usage.usage.today.actualCost)) · \(number(usage.usage.today.totalTokens)) Token"
                    } else if let balance = latestProviderBalance {
                        usageLabel = balance.displayText.hasPrefix("配额") ? "提供商配额" : "提供商余额"
                        usageValue = balance.displayText
                            .replacingOccurrences(of: "余额 ", with: "")
                            .replacingOccurrences(of: "配额 ", with: "")
                        usageDetail = balance.detail
                    } else {
                        usageLabel = "当前模型"
                        usageValue = provider.model
                        usageDetail = provider.baseURL
                    }
                }
            }
        }

        return DashboardSnapshot(
            agentName: agent.displayName,
            routeName: routeName,
            taskStatus: taskStatusText(),
            taskSignal: taskSignal,
            usageLabel: usageLabel,
            usageValue: usageValue,
            usageDetail: usageDetail,
            updatedText: lastUpdated.map { "\(timeFormatter.string(from: $0)) · 每分钟自动刷新" } ?? "等待首次刷新",
            version: AppUpdateChecker.currentVersion,
            message: latestError
        )
    }

    func refreshDashboardData() async {
        await refreshTaskActivity(forceFileScan: true)
        await refreshUsage()
        settings.refreshDashboard()
    }

    func diagnosticReport() -> AgentPulseDiagnosticReport {
        let appURL: URL?
        switch agent {
        case .codex:
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexLauncher.bundleIdentifier)
        case .cursor:
            appURL = CursorLauncher.applicationURL()
        case .hermes:
            appURL = HermesLauncher.applicationURL()
        case .claude:
            appURL = ClaudeCodeIntegration.cliURL()
        case .openCode:
            appURL = OpenCodeIntegration.cliURL()
        }
        let version = appURL.flatMap {
            Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        } ?? (agent == .hermes
            ? latestHermesStatus.version
            : latestCLIStatuses[agent]?.version)
        return DiagnosticsCenter.makeReport(
            agent: agent,
            route: route,
            task: taskSnapshot,
            lastUsageRefresh: lastUpdated,
            latestError: latestError,
            monitorActive: taskMonitorActive,
            agentPath: appURL?.path,
            agentVersion: version
        )
    }

    func reinitializeTaskMonitoring() async {
        taskActivityMonitor?.stop()
        taskActivityMonitor = nil
        taskMonitorActive = false
        pendingTaskFileEvents.removeAll(keepingCapacity: false)
        pendingTaskForceScan = false
        startTaskActivityMonitor()
        await refreshTaskActivity(forceFileScan: true)
    }

    @objc private func manualRefresh() { Task { await refreshUsage() } }

    private func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        if agent == .codex {
            let currentRoute = RouteConfigManager.currentRoute()
            if currentRoute != route {
                route = currentRoute
                routeDisplayName = currentRoute.displayName
                lastStatusRenderKey = nil
            }
        }
        rebuildMainMenu()
        defer {
            isRefreshingUsage = false
            recordCurrentUsage()
            rebuildMainMenu()
            updateWidget()
            settings.refreshDashboard()
            settings.refreshBalanceDisplaysIfVisible()
            settings.refreshMonitoringIfVisible()
        }

        do {
            if agent == .cursor {
                let appInstalled = CursorLauncher.applicationURL() != nil
                latestCursorStatus = await Task.detached(priority: .utility) {
                    CursorIntegration.readCLIStatus(appInstalled: appInstalled)
                }.value
                var errors: [String] = []
                if !latestCursorStatus.isInstalled {
                    errors.append(latestCursorStatus.detail)
                }
                if CursorUsagePreference.officialUsageEnabled {
                    do {
                        latestCursorOfficialUsage = try await CursorOfficialUsageClient.fetch()
                    } catch {
                        latestCursorOfficialUsage = nil
                        errors.append(error.localizedDescription)
                    }
                } else {
                    latestCursorOfficialUsage = nil
                }
                latestCursorProviderUsage = nil
                if let id = CursorUsagePreference.providerID,
                   let provider = ProviderStore.provider(id: id),
                   provider.isCodeAPI {
                    if let key = CredentialStore.load(providerID: id), !key.isEmpty {
                        do {
                            latestCursorProviderUsage = try await CodeAPIClient.fetch(key: key)
                            if let usage = latestCursorProviderUsage {
                                publishProviderBalance(providerID: id, usage: usage)
                            }
                        } catch {
                            errors.append("\(provider.name)：\(error.localizedDescription)")
                        }
                    } else {
                        errors.append("\(provider.name) 尚未配置 API Key")
                    }
                }
                if cursorHooksNeedRestart {
                    errors.append("状态 Hooks 已更新，请重启 Cursor。")
                } else if !CursorIntegration.hooksInstalled() {
                    errors.append("Cursor 状态 Hooks 不完整，请在设置中重新应用。")
                }
                latestError = errors.isEmpty ? nil : errors.joined(separator: "；")
                lastUpdated = Date()
                updateStatusTitle()
                return
            }
            if agent == .hermes {
                let result = await Task.detached(priority: .utility) {
                    (HermesIntegration.readStatus(), HermesUsageReader.readToday())
                }.value
                latestHermesStatus = result.0
                latestHermesUsage = result.1
                latestCodeUsage = nil
                latestProviderBalance = nil
                var errors: [String] = []
                if !latestHermesStatus.isInstalled || !latestHermesStatus.cliAvailable {
                    errors.append(latestHermesStatus.detail)
                }
                if let id = HermesPreference.providerID,
                   let provider = ProviderStore.provider(id: id),
                   let key = CredentialStore.load(providerID: id), !key.isEmpty {
                    if provider.isCodeAPI {
                        do {
                            latestCodeUsage = try await CodeAPIClient.fetch(key: key)
                            if let usage = latestCodeUsage {
                                publishProviderBalance(providerID: id, usage: usage)
                            }
                        } catch {
                            errors.append("\(provider.name)：\(error.localizedDescription)")
                        }
                    } else if provider.effectiveVendor.supportsBalanceLookup {
                        let managementKey = CredentialStore.load(
                            providerID: ProviderBalanceClient.managementCredentialID(for: provider.id)
                        )
                        do {
                            latestProviderBalance = try await ProviderBalanceClient.fetch(
                                profile: provider,
                                apiKey: key,
                                managementKey: managementKey
                            )
                            if let balance = latestProviderBalance {
                                settings.providerBalanceDidRefresh(providerID: id, snapshot: balance)
                            }
                        } catch {
                            errors.append("\(provider.name)余额：\(error.localizedDescription)")
                        }
                    }
                }
                latestError = errors.isEmpty ? nil : errors.joined(separator: "；")
                lastUpdated = Date()
                updateStatusTitle()
                return
            }
            if agent == .claude || agent == .openCode {
                let selectedAgent = agent
                let status = await Task.detached(priority: .utility) {
                    selectedAgent == .claude
                        ? ClaudeCodeIntegration.readStatus()
                        : OpenCodeIntegration.readStatus()
                }.value
                latestCLIStatuses[selectedAgent] = status
                latestCodeUsage = nil
                latestProviderBalance = nil
                var errors: [String] = status.installed ? [] : [status.detail]
                if let id = CLIAgentPreference.providerID(for: selectedAgent),
                   let provider = ProviderStore.provider(id: id),
                   provider.supports(selectedAgent) {
                    if let key = CredentialStore.load(providerID: id), !key.isEmpty {
                        if provider.isCodeAPI {
                            do {
                                latestCodeUsage = try await CodeAPIClient.fetch(key: key)
                                if let usage = latestCodeUsage {
                                    publishProviderBalance(providerID: id, usage: usage)
                                }
                            } catch {
                                errors.append("\(provider.name)：\(error.localizedDescription)")
                            }
                        } else if provider.effectiveVendor.supportsBalanceLookup {
                            let managementKey = CredentialStore.load(
                                providerID: ProviderBalanceClient.managementCredentialID(for: provider.id)
                            )
                            do {
                                latestProviderBalance = try await ProviderBalanceClient.fetch(
                                    profile: provider,
                                    apiKey: key,
                                    managementKey: managementKey
                                )
                                if let balance = latestProviderBalance {
                                    settings.providerBalanceDidRefresh(providerID: id, snapshot: balance)
                                }
                            } catch {
                                errors.append("\(provider.name)余额：\(error.localizedDescription)")
                            }
                        }
                    } else {
                        errors.append("\(provider.name) 尚未配置 API Key")
                    }
                }
                latestError = errors.isEmpty ? nil : errors.joined(separator: "；")
                lastUpdated = Date()
                updateStatusTitle()
                return
            }
            switch route {
            case let .provider(id):
                guard let provider = ProviderStore.provider(id: id) else {
                    latestError = "当前第三方提供商不存在"
                    updateStatusTitle()
                    return
                }
                guard let key = CredentialStore.load(providerID: id), !key.isEmpty else {
                    latestError = "\(provider.name) 尚未配置 API Key"
                    updateStatusTitle()
                    return
                }
                latestCodeUsage = nil
                latestProviderBalance = nil
                if provider.isCodeAPI {
                    latestCodeUsage = try await CodeAPIClient.fetch(key: key)
                    if let usage = latestCodeUsage {
                        publishProviderBalance(providerID: id, usage: usage)
                    }
                } else if provider.effectiveVendor.supportsBalanceLookup {
                    let managementKey = CredentialStore.load(
                        providerID: ProviderBalanceClient.managementCredentialID(for: provider.id)
                    )
                    if provider.effectiveVendor != .xAI
                        || (managementKey?.isEmpty == false && provider.balanceTeamID?.isEmpty == false) {
                        latestProviderBalance = try? await ProviderBalanceClient.fetch(
                            profile: provider,
                            apiKey: key,
                            managementKey: managementKey
                        )
                        if let balance = latestProviderBalance {
                            settings.providerBalanceDidRefresh(providerID: id, snapshot: balance)
                        }
                    }
                }
            case .official:
                latestProviderBalance = nil
                latestOfficialUsage = try await OfficialUsageClient.fetch()
            }
            latestError = nil
            lastUpdated = Date()
        } catch {
            latestError = error.localizedDescription
        }
        updateStatusTitle()
    }

    private func recordCurrentUsage() {
        guard latestError == nil, let observation = currentUsageObservation() else { return }
        UsageHistoryStore.record(observation)
        UsageAlertManager.evaluate(observation)
    }

    func currentUsageObservation() -> UsageObservation? {
        let snapshot = dashboardSnapshot()
        var remainingPercent: Double?
        var balance: Double?
        var resetAt: Date?
        var modelKey = "\(agent.rawValue):official"
        var modelName: String?
        var tokens: Int?
        var cost: Double?

        if agent == .cursor {
            modelName = "Cursor 官方模型"
            if CursorUsagePreference.officialUsageEnabled {
                remainingPercent = latestCursorOfficialUsage?.remainingPercent
            } else {
                balance = latestCursorProviderUsage?.balance
                if let id = CursorUsagePreference.providerID,
                   let provider = ProviderStore.provider(id: id) {
                    modelKey = "cursor:\(id)"
                    modelName = provider.model
                }
            }
        } else if agent == .hermes {
            balance = latestCodeUsage?.balance ?? Self.numericValue(in: latestProviderBalance?.displayText)
            remainingPercent = Self.percentValue(in: latestProviderBalance?.displayText)
            tokens = latestHermesUsage?.totalTokens
            cost = latestHermesUsage?.displayCostUSD
            if let id = HermesPreference.providerID,
               let provider = ProviderStore.provider(id: id) {
                modelKey = "hermes:\(id)"
                modelName = provider.model
            } else {
                modelName = latestHermesStatus.modelConfig.model
            }
        } else if agent == .claude || agent == .openCode {
            balance = latestCodeUsage?.balance ?? Self.numericValue(in: latestProviderBalance?.displayText)
            remainingPercent = Self.percentValue(in: latestProviderBalance?.displayText)
            if let id = CLIAgentPreference.providerID(for: agent),
               let provider = ProviderStore.provider(id: id) {
                modelKey = "\(agent.rawValue):\(id)"
                modelName = provider.model
            } else {
                modelName = latestCLIStatuses[agent]?.config.model
            }
        } else {
            switch route {
            case .official:
                remainingPercent = latestOfficialUsage?.primary?.remainingPercent
                resetAt = latestOfficialUsage?.primary?.resetsAt
                modelName = ProviderStore.officialModel() ?? "ChatGPT 登录模型"
            case let .provider(id):
                modelKey = "codex:\(id)"
                modelName = ProviderStore.provider(id: id)?.model
                if ProviderStore.provider(id: id)?.isCodeAPI == true {
                    balance = latestCodeUsage?.balance
                    tokens = latestCodeUsage?.usage.today.totalTokens
                    cost = latestCodeUsage?.usage.today.actualCost
                } else {
                    remainingPercent = Self.percentValue(in: latestProviderBalance?.displayText)
                    balance = Self.numericValue(in: latestProviderBalance?.displayText)
                }
            }
        }
        guard remainingPercent != nil || balance != nil || snapshot.usageValue != "—" else { return nil }
        return UsageObservation(
            recordedAt: Date(),
            agent: snapshot.agentName,
            route: snapshot.routeName,
            metric: snapshot.usageLabel,
            displayValue: snapshot.usageValue,
            detail: snapshot.usageDetail,
            remainingPercent: remainingPercent,
            balance: balance,
            resetAt: resetAt,
            modelKey: modelKey,
            modelName: modelName,
            tokens: tokens,
            cost: cost
        )
    }

    private static func percentValue(in text: String?) -> Double? {
        guard let text,
              let range = text.range(of: #"[0-9]+(?:\.[0-9]+)?(?=\s*%)"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range])
    }

    private static func numericValue(in text: String?) -> Double? {
        guard let text, !text.contains("%"),
              let range = text.range(of: #"-?[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range])
    }

    private func publishProviderBalance(providerID: String, usage: UsageResponse) {
        settings.providerBalanceDidRefresh(
            providerID: providerID,
            snapshot: ProviderBalanceSnapshot(
                displayText: String(format: "余额 $%.2f", usage.balance),
                detail: "CodeAPI 账户余额"
            )
        )
    }

    private func rebuildMainMenu() {
        mainMenu.removeAllItems()
        mainMenu.addItem(info("Agent Pulse", emphasis: true))
        let routeText: String
        if agent == .codex {
            routeText = "  ·  \(route.displayName)"
        } else if agent == .hermes {
            routeText = "  ·  \(latestHermesStatus.modelConfig.model)"
        } else if agent == .claude || agent == .openCode {
            routeText = "  ·  \((latestCLIStatuses[agent] ?? .unavailable(agent)).config.model)"
        } else {
            routeText = ""
        }
        mainMenu.addItem(info("\(agent.displayName)  ·  \(taskStatusText())\(routeText)"))
        mainMenu.addItem(.separator())

        if agent == .cursor {
            addCursorMenu(to: mainMenu)
        } else if agent == .hermes {
            addHermesMenu(to: mainMenu)
        } else if agent == .claude || agent == .openCode {
            addCLIAgentMenu(agent, to: mainMenu)
        } else {
            switch route {
            case let .provider(id):
                if ProviderStore.provider(id: id)?.isCodeAPI == true { addCodeUsageMenu(to: mainMenu) }
                else { addProviderMenu(id: id, to: mainMenu) }
            case .official:
                addOfficialUsageMenu(to: mainMenu)
            }
        }

        if let error = latestError {
            mainMenu.addItem(.separator())
            let item = info("⚠︎ \(error)")
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
            mainMenu.addItem(item)
        }

        mainMenu.addItem(.separator())
        mainMenu.addItem(info(lastUpdated.map { "更新于 \(timeFormatter.string(from: $0)) · 每分钟刷新" } ?? "每分钟自动刷新"))
        let refresh = NSMenuItem(title: isRefreshingUsage ? "正在刷新…" : "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !isRefreshingUsage
        mainMenu.addItem(refresh)

        let settingsItem = NSMenuItem(title: "打开 Agent Pulse…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        mainMenu.addItem(settingsItem)
        let widgetItem = NSMenuItem(title: "添加桌面组件…", action: #selector(openWidgetGuide), keyEquivalent: "")
        widgetItem.target = self
        mainMenu.addItem(widgetItem)

        let dashboardTitle: String
        if agent == .cursor {
            dashboardTitle = "打开 Cursor 用量页面"
        } else if agent == .hermes {
            dashboardTitle = HermesPreference.providerID == nil ? "打开 Hermes" : "打开提供商地址"
        } else if agent == .claude || agent == .openCode {
            dashboardTitle = CLIAgentPreference.providerID(for: agent) == nil
                ? "打开 \(agent.displayName)"
                : "打开提供商地址"
        } else {
            switch route {
            case .official: dashboardTitle = "打开官方用量页面"
            case let .provider(id): dashboardTitle = ProviderStore.provider(id: id)?.isCodeAPI == true ? "打开 CodeAPI 控制台" : "打开提供商地址"
            }
        }
        let dashboard = NSMenuItem(title: dashboardTitle, action: #selector(openUsageDashboard), keyEquivalent: "")
        dashboard.target = self
        mainMenu.addItem(dashboard)
        mainMenu.addItem(.separator())
        let open = NSMenuItem(title: "打开 \(agent.displayName)", action: #selector(openSelectedAgent), keyEquivalent: "")
        open.target = self
        mainMenu.addItem(open)
        let quit = NSMenuItem(title: "退出 Agent Pulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        mainMenu.addItem(quit)
    }

    private func rebuildContextMenu() {
        contextMenu.removeAllItems()
        contextMenu.delegate = self
        let widgetItem = NSMenuItem(title: "添加 macOS 桌面组件…", action: #selector(openWidgetGuide), keyEquivalent: "")
        widgetItem.target = self
        contextMenu.addItem(widgetItem)
        let refresh = NSMenuItem(title: "立即刷新用量", action: #selector(manualRefresh), keyEquivalent: "")
        refresh.target = self
        contextMenu.addItem(refresh)
        contextMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "打开 Agent Pulse…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        contextMenu.addItem(settingsItem)
    }

    private func addCodeUsageMenu(to menu: NSMenu) {
        guard let data = latestCodeUsage else {
            menu.addItem(info("暂无 CodeAPI 用量数据"))
            return
        }
        menu.addItem(info("余额  \(money(data.balance))", emphasis: true))
        menu.addItem(info("今日费用  \(money(data.usage.today.actualCost))"))
        let todayItem = NSMenuItem(title: "今日用量", action: nil, keyEquivalent: "")
        let todayMenu = NSMenu()
        todayMenu.addItem(info("请求  \(number(data.usage.today.requests)) 次"))
        todayMenu.addItem(info("总 Token  \(number(data.usage.today.totalTokens))"))
        todayMenu.addItem(info("输入  \(number(data.usage.today.inputTokens))"))
        todayMenu.addItem(info("输出  \(number(data.usage.today.outputTokens))"))
        todayMenu.addItem(info("缓存读取  \(number(data.usage.today.cacheReadTokens))"))
        todayItem.submenu = todayMenu
        menu.addItem(todayItem)
    }

    private func addProviderMenu(id: String, to menu: NSMenu) {
        guard let provider = ProviderStore.provider(id: id) else {
            menu.addItem(info("提供商配置已不存在"))
            return
        }
        menu.addItem(info(provider.name, emphasis: true))
        if let balance = latestProviderBalance {
            menu.addItem(info(balance.displayText, emphasis: true))
            menu.addItem(info(balance.detail))
        }
        menu.addItem(info("模型  \(provider.model)"))
        menu.addItem(info("地址  \(provider.baseURL)"))
        if provider.effectiveVendor == .custom {
            menu.addItem(info("该自定义提供商未配置用量查询接口"))
        } else if provider.effectiveVendor == .miMo {
            menu.addItem(info("余额请前往 MiMo 控制台查看"))
        } else if latestProviderBalance == nil {
            menu.addItem(info("余额或配额暂不可用"))
        }
    }

    private func addOfficialUsageMenu(to menu: NSMenu) {
        guard let data = latestOfficialUsage else {
            menu.addItem(info("正在读取 OpenAI 官方账号…"))
            return
        }
        guard data.isLoggedIn else {
            menu.addItem(info("OpenAI 官方账号未登录", emphasis: true))
            menu.addItem(info("路由已切换成功；登录 Codex 后即可显示用量。"))
            return
        }
        if data.primary == nil, data.secondary == nil, data.tokenUsage == nil {
            menu.addItem(info("官方用量暂不可用", emphasis: true))
            menu.addItem(info("请稍后重新刷新。"))
        }
        if let primary = data.primary {
            menu.addItem(info("\(primary.label)剩余  \(percent(primary.remainingPercent))", emphasis: true))
            menu.addItem(info("重置时间  \(resetFormatter.string(from: primary.resetsAt))"))
        }
        if let secondary = data.secondary {
            menu.addItem(info("\(secondary.label)剩余  \(percent(secondary.remainingPercent))"))
            menu.addItem(info("重置时间  \(resetFormatter.string(from: secondary.resetsAt))"))
        }
        if let tokens = data.tokenUsage {
            menu.addItem(.separator())
            if let today = tokens.todayTokens { menu.addItem(info("今日 Token  \(number(today))")) }
            if let lifetime = tokens.lifetimeTokens { menu.addItem(info("累计 Token  \(number(lifetime))")) }
            if let peak = tokens.peakDailyTokens { menu.addItem(info("单日峰值  \(number(peak))")) }
        }
        if let plan = data.planType { menu.addItem(info("方案  \(plan)")) }
        if let credits = data.resetCredits { menu.addItem(info("可用重置次数  \(credits)")) }
    }

    private func addCursorMenu(to menu: NSMenu) {
        menu.addItem(info("Cursor", emphasis: true))
        guard latestCursorStatus.isInstalled else {
            menu.addItem(info("未找到 Cursor.app"))
            return
        }
        let authText: String
        if latestCursorOfficialUsage != nil {
            authText = "已登录"
        } else {
            switch latestCursorStatus.isAuthenticated {
            case .some(true): authText = "CLI 已登录"
            case .some(false): authText = "CLI 未登录"
            case .none: authText = latestCursorStatus.cliAvailable ? "登录状态未知" : "未安装 cursor-agent CLI"
            }
        }
        menu.addItem(info("账号  \(authText)"))
        if CursorUsagePreference.officialUsageEnabled {
            if let usage = latestCursorOfficialUsage {
                if let remaining = usage.autoRemainingPercent {
                    menu.addItem(info("Auto / Composer 剩余  \(percent(remaining))", emphasis: true))
                }
                if let remaining = usage.apiRemainingPercent {
                    menu.addItem(info("API 用量剩余  \(percent(remaining))", emphasis: usage.autoRemainingPercent == nil))
                }
                if usage.autoRemainingPercent == nil,
                   usage.apiRemainingPercent == nil,
                   let remaining = usage.remainingPercent {
                    menu.addItem(info("官方用量剩余  \(percent(remaining))", emphasis: true))
                }
                if usage.limitCents > 0 {
                    menu.addItem(info("官方剩余额度  \(money(Double(usage.remainingCents) / 100))"))
                    menu.addItem(info(
                        "本期已用  \(money(Double(usage.usedCents) / 100)) / \(money(Double(usage.limitCents) / 100))"
                    ))
                }
                if let message = usage.displayMessage, !message.isEmpty {
                    menu.addItem(info(message))
                }
                if let end = usage.billingCycleEnd {
                    menu.addItem(info("账期结束  \(resetFormatter.string(from: end))"))
                }
            } else {
                menu.addItem(info("正在读取 Cursor 官方用量…"))
            }
        } else {
            menu.addItem(info("官方用量  未授权（可在设置中启用）"))
        }
        if let id = CursorUsagePreference.providerID,
           let provider = ProviderStore.provider(id: id) {
            if let usage = latestCursorProviderUsage {
                menu.addItem(.separator())
                menu.addItem(info("\(provider.name) 余额  \(money(usage.balance))", emphasis: true))
                menu.addItem(info("今日费用  \(money(usage.usage.today.actualCost))"))
                menu.addItem(info("今日 Token  \(number(usage.usage.today.totalTokens))"))
            } else {
                menu.addItem(info("提供商  \(provider.name) · \(provider.model)"))
            }
        }
        menu.addItem(.separator())
        menu.addItem(info("状态 Hooks  \(CursorIntegration.hooksInstalled() ? "已启用" : "未启用")"))
        if let diagnostic = CursorActivityReader.diagnostic() {
            menu.addItem(info("最近事件  \(diagnostic)"))
        } else {
            menu.addItem(info("最近事件  暂无（配置后需重启 Cursor）"))
        }
        if cursorHooksNeedRestart {
            let restart = NSMenuItem(
                title: "重新启动 Cursor 以启用状态同步",
                action: #selector(restartCursorForHooks),
                keyEquivalent: ""
            )
            restart.target = self
            menu.addItem(restart)
        }
        if !latestCursorStatus.detail.isEmpty {
            menu.addItem(info(latestCursorStatus.detail))
        }
    }

    private func addHermesMenu(to menu: NSMenu) {
        menu.addItem(info("Hermes", emphasis: true))
        guard latestHermesStatus.isInstalled else {
            menu.addItem(info("未找到 Hermes.app"))
            return
        }
        menu.addItem(info("CLI  \(latestHermesStatus.cliAvailable ? "已连接" : "未找到")"))
        if let id = HermesPreference.providerID,
           let provider = ProviderStore.provider(id: id) {
            menu.addItem(info("提供商  \(provider.name)", emphasis: true))
            menu.addItem(info("模型  \(provider.model)"))
            if provider.isCodeAPI, let usage = latestCodeUsage {
                menu.addItem(info("提供商余额  \(money(usage.balance))"))
            } else if let balance = latestProviderBalance {
                menu.addItem(info(balance.displayText))
            }
        } else {
            menu.addItem(info("配置  \(latestHermesStatus.modelConfig.provider)", emphasis: true))
            menu.addItem(info("模型  \(latestHermesStatus.modelConfig.model)"))
        }
        menu.addItem(.separator())
        if let usage = latestHermesUsage {
            menu.addItem(info("今日 Token  \(number(usage.totalTokens))", emphasis: true))
            menu.addItem(info("输入  \(number(usage.inputTokens)) · 输出  \(number(usage.outputTokens))"))
            menu.addItem(info("缓存读取  \(number(usage.cacheReadTokens)) · 推理  \(number(usage.reasoningTokens))"))
            menu.addItem(info("API 请求  \(number(usage.apiCalls)) 次"))
            menu.addItem(info("今日费用  \(money(usage.displayCostUSD))"))
        } else {
            menu.addItem(info("暂无今日 Token / 费用记录"))
        }
    }

    private func addCLIAgentMenu(_ agent: AgentKind, to menu: NSMenu) {
        let status = latestCLIStatuses[agent] ?? .unavailable(agent)
        menu.addItem(info(agent.displayName, emphasis: true))
        menu.addItem(info("CLI  \(status.installed ? "已安装" : "未找到")"))
        if let version = status.version, !version.isEmpty {
            menu.addItem(info("版本  \(version)"))
        }
        if let id = CLIAgentPreference.providerID(for: agent),
           let provider = ProviderStore.provider(id: id) {
            menu.addItem(info("提供商  \(provider.name)", emphasis: true))
            menu.addItem(info("模型  \(provider.model)"))
            if let usage = latestCodeUsage {
                menu.addItem(info("提供商余额  \(money(usage.balance))"))
            } else if let balance = latestProviderBalance {
                menu.addItem(info(balance.displayText))
            }
        } else {
            menu.addItem(info("配置  \(status.config.provider)", emphasis: true))
            menu.addItem(info("模型  \(status.config.model)"))
        }
        menu.addItem(.separator())
        menu.addItem(info("任务状态监听  暂未启用"))
    }

    private func startTaskActivityMonitor() {
        taskActivityMonitor?.stop()
        let monitor = TaskActivityMonitor(paths: [
            TaskActivityReader.defaultRootURL,
            CursorIntegration.supportDirectoryURL,
            HermesIntegration.homeURL,
            ClaudeCodeIntegration.configURL.deletingLastPathComponent(),
            OpenCodeIntegration.configURL.deletingLastPathComponent()
        ]) { [weak self] events in
            Task { @MainActor in
                guard let self else { return }
                let root: URL
                switch self.agent {
                case .codex: root = TaskActivityReader.defaultRootURL
                case .cursor: root = CursorIntegration.supportDirectoryURL
                case .hermes: root = HermesIntegration.homeURL
                case .claude: root = ClaudeCodeIntegration.configURL.deletingLastPathComponent()
                case .openCode: root = OpenCodeIntegration.configURL.deletingLastPathComponent()
                }
                let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
                let relevantEvents = events.filter { $0.path.hasPrefix(normalizedRoot) }
                guard !relevantEvents.isEmpty else { return }
                await self.refreshTaskActivity(fileEvents: relevantEvents)
            }
        }
        taskActivityMonitor = monitor
        taskMonitorActive = monitor.start()
    }

    private func refreshTaskActivity(
        fileEvents: [TaskActivityFileEvent] = [],
        forceFileScan: Bool = false
    ) async {
        guard !isRefreshingTask else {
            mergePendingTaskEvents(fileEvents, forceFileScan: forceFileScan)
            return
        }
        isRefreshingTask = true
        let selectedAgent = agent
        let snapshot = await Task.detached(priority: .utility) {
            switch selectedAgent {
            case .cursor: return CursorActivityReader.read()
            case .hermes: return HermesActivityReader.read()
            case .claude, .openCode: return TaskActivitySnapshot(state: .ready, changedAt: nil)
            case .codex:
                return TaskActivityReader.read(
                    fileEvents: fileEvents,
                    forceFileScan: forceFileScan
                )
            }
        }.value
        isRefreshingTask = false
        schedulePendingTaskRefreshIfNeeded()
        guard snapshot != taskSnapshot else {
            return
        }
        let shouldPlayCompletionChase: Bool
        switch (taskSnapshot.state, snapshot.state) {
        case (.running, .ready), (.waiting, .ready): shouldPlayCompletionChase = true
        default: shouldPlayCompletionChase = false
        }
        taskSnapshot = snapshot
        if shouldPlayCompletionChase { startStartupChase() }
        else { renderStatusButton() }
        rebuildMainMenu()
        updateWidget()
        settings.refreshDashboard()
    }

    private func mergePendingTaskEvents(
        _ events: [TaskActivityFileEvent],
        forceFileScan: Bool
    ) {
        pendingTaskForceScan = pendingTaskForceScan || forceFileScan
        for event in events {
            if let existing = pendingTaskFileEvents[event.path] {
                pendingTaskFileEvents[event.path] = TaskActivityFileEvent(
                    path: event.path,
                    flags: existing.flags | event.flags
                )
            } else {
                pendingTaskFileEvents[event.path] = event
            }
        }
    }

    private func schedulePendingTaskRefreshIfNeeded() {
        guard pendingTaskForceScan || !pendingTaskFileEvents.isEmpty else { return }
        let events = Array(pendingTaskFileEvents.values)
        let forceFileScan = pendingTaskForceScan
        pendingTaskFileEvents.removeAll(keepingCapacity: true)
        pendingTaskForceScan = false
        Task { @MainActor [weak self] in
            await self?.refreshTaskActivity(fileEvents: events, forceFileScan: forceFileScan)
        }
    }

    private func startStartupChase() {
        startupChaseTimer?.invalidate()
        startupChaseIndex = 0
        renderStatusButton()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let current = self.startupChaseIndex else {
                    timer.invalidate()
                    return
                }
                let next = current + 1
                if next >= 9 {
                    timer.invalidate()
                    self.startupChaseTimer = nil
                    self.startupChaseIndex = nil
                } else {
                    self.startupChaseIndex = next
                }
                self.renderStatusButton()
            }
        }
        startupChaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateWidget() {
        AgentPulseWidgetStore.update(
            agent: agent,
            route: route,
            codeUsage: latestCodeUsage,
            officialUsage: latestOfficialUsage,
            cursorOfficialUsage: latestCursorOfficialUsage,
            cursorProviderUsage: latestCursorProviderUsage,
            hermesStatus: latestHermesStatus,
            hermesUsage: latestHermesUsage,
            task: taskSnapshot,
            balances: widgetBalanceEntries()
        )
    }

    private func widgetBalanceEntries() -> [BalanceOverviewEntry] {
        let entries = BalanceOverviewStore.entries()
        let preferredID: String?
        if agent == .cursor {
            preferredID = "official:cursor"
        } else if agent == .hermes {
            preferredID = HermesPreference.providerID.map { "provider:\($0)" }
        } else if agent == .claude || agent == .openCode {
            preferredID = CLIAgentPreference.providerID(for: agent).map { "provider:\($0)" }
        } else {
            switch route {
            case .official: preferredID = "official:openai"
            case let .provider(id): preferredID = "provider:\(id)"
            }
        }
        guard let preferredID,
              let preferred = entries.first(where: { $0.id == preferredID }) else {
            return entries
        }
        return [preferred] + entries.filter { $0.id != preferredID }
    }

    private func info(_ title: String, emphasis: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if emphasis {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
        }
        return item
    }

    @objc private func openSettings() { settings.present() }

    @objc private func openWidgetGuide() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "添加 Agent Pulse 桌面组件"
        alert.informativeText = "在 macOS 桌面空白处点按右键，选择“编辑小组件”，搜索 Agent Pulse，然后把小号或中号组件拖到桌面。\n\n组件会展示当前 Agent、路由、用量和任务状态。需要 macOS 14 或更高版本。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @objc private func openUsageDashboard() {
        if agent == .cursor {
            NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!)
            return
        }
        if agent == .hermes {
            if let id = HermesPreference.providerID,
               let provider = ProviderStore.provider(id: id),
               let url = URL(string: provider.baseURL) {
                NSWorkspace.shared.open(url)
            } else {
                Task { try? await HermesLauncher.launch() }
            }
            return
        }
        if agent == .claude || agent == .openCode {
            if let id = CLIAgentPreference.providerID(for: agent),
               let provider = ProviderStore.provider(id: id),
               let url = URL(string: provider.baseURL) {
                NSWorkspace.shared.open(url)
            } else {
                openSelectedAgent()
            }
            return
        }
        switch route {
        case .official:
            NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!)
        case let .provider(id):
            guard let provider = ProviderStore.provider(id: id) else { return }
            let url = provider.isCodeAPI ? dashboardURL : URL(string: provider.baseURL)
            if let url { NSWorkspace.shared.open(url) }
        }
    }

    @objc private func openSelectedAgent() {
        if agent == .cursor {
            Task {
                do {
                    try await CursorLauncher.launch()
                } catch {
                    presentLaunchWarning(error.localizedDescription)
                }
            }
        } else if agent == .hermes {
            Task {
                do {
                    try await HermesLauncher.launch()
                } catch {
                    presentLaunchWarning(error.localizedDescription)
                }
            }
        } else if agent == .claude {
            do {
                try ClaudeCodeIntegration.launch()
            } catch {
                presentLaunchWarning(error.localizedDescription)
            }
        } else if agent == .openCode {
            do {
                try OpenCodeIntegration.launch()
            } catch {
                presentLaunchWarning(error.localizedDescription)
            }
        } else {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CodexLauncher.bundleIdentifier) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    @objc private func restartCursorForHooks() {
        Task {
            do {
                try await CursorLauncher.restart()
                cursorHooksDidRestart()
                await refreshTaskActivity()
                await refreshUsage()
            } catch {
                latestError = error.localizedDescription
                rebuildMainMenu()
            }
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }

    private func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private lazy var resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
