import AppKit
import Foundation

let usageURL = URL(string: "https://codeapi.nexita.net/v1/usage")!
let dashboardURL = URL(string: "https://codeapi.nexita.net/dashboard")!

struct UsageResponse: Codable {
    let balance: Double
    let dailyUsage: [DailyUsage]?
    let isValid: Bool
    let mode: String?
    let modelStats: [ModelStat]?
    let planName: String?
    let remaining: Double?
    let unit: String?
    let usage: UsageSummary

    enum CodingKeys: String, CodingKey {
        case balance
        case dailyUsage = "daily_usage"
        case isValid
        case mode
        case modelStats = "model_stats"
        case planName
        case remaining
        case unit
        case usage
    }
}

struct DailyUsage: Codable {
    let date: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let actualCost: Double

    enum CodingKeys: String, CodingKey {
        case date, requests
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
    }
}

struct ModelStat: Codable {
    let model: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let totalTokens: Int
    let cost: Double
    let actualCost: Double

    enum CodingKeys: String, CodingKey {
        case model, requests, cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case totalTokens = "total_tokens"
        case actualCost = "actual_cost"
    }
}

struct UsageSummary: Codable {
    let averageDurationMs: Double
    let rpm: Int?
    let tpm: Int?
    let today: UsagePeriod
    let total: UsagePeriod

    enum CodingKeys: String, CodingKey {
        case averageDurationMs = "average_duration_ms"
        case rpm, tpm, today, total
    }
}

struct UsagePeriod: Codable {
    let actualCost: Double
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let requests: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case actualCost = "actual_cost"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case requests
        case totalTokens = "total_tokens"
    }
}

enum APIError: LocalizedError {
    case invalidKey
    case server(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "API Key 无效，请检查后重试。"
        case let .server(code, message): return "服务返回错误（HTTP \(code)）：\(message)"
        case .invalidResponse: return "接口返回了无法识别的数据。"
        }
    }
}

enum CodeAPIClient {
    static func fetch(key: String) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw APIError.invalidKey }
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw APIError.server(http.statusCode, body)
        }
        let value = try JSONDecoder().decode(UsageResponse.self, from: data)
        guard value.isValid else { throw APIError.invalidKey }
        return value
    }
}

#if false
@MainActor
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    weak var appDelegate: AppDelegate?
    private let keyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存并验证", target: nil, action: nil)

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Pulse 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "连接 CodeAPI")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let help = NSTextField(wrappingLabelWithString: "输入 API Key。密钥只会保存在当前 Mac 的系统钥匙串中。")
        help.textColor = .secondaryLabelColor

        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        keyField.placeholderString = "sk-…"
        keyField.stringValue = KeychainStore.load() ?? ""
        keyField.delegate = self

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        saveButton.target = self
        saveButton.action = #selector(saveAndVerify)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded

        let buttons = NSView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        buttons.addSubview(cancelButton)
        buttons.addSubview(saveButton)
        NSLayoutConstraint.activate([
            buttons.heightAnchor.constraint(equalToConstant: 32),
            saveButton.trailingAnchor.constraint(equalTo: buttons.trailingAnchor),
            saveButton.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: buttons.centerYAnchor)
        ])

        let stack = NSStackView(views: [title, help, keyLabel, keyField, statusLabel, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        keyField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
    }

    func present() {
        keyField.stringValue = KeychainStore.load() ?? ""
        statusLabel.stringValue = ""
        saveButton.isEnabled = true
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(keyField)
    }

    @objc private func closeWindow() { window?.close() }

    @objc private func saveAndVerify() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            showError("请输入 API Key。")
            return
        }
        saveButton.isEnabled = false
        saveButton.title = "正在验证…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在连接 CodeAPI…"

        Task {
            do {
                let usage = try await CodeAPIClient.fetch(key: key)
                try KeychainStore.save(key)
                appDelegate?.acceptValidatedUsage(usage)
                statusLabel.textColor = .systemGreen
                statusLabel.stringValue = "验证成功，已保存到系统钥匙串。"
                saveButton.title = "已保存"
                try? await Task.sleep(for: .milliseconds(550))
                window?.close()
            } catch {
                showError(error.localizedDescription)
                saveButton.isEnabled = true
                saveButton.title = "保存并验证"
            }
        }
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var latestUsage: UsageResponse?
    private var latestError: String?
    private var lastUpdated: Date?
    private var isRefreshing = false
    private lazy var preferences = PreferencesWindowController(appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        configureStatusButton(title: "CodeAPI …", symbol: "chart.bar.fill")
        rebuildMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)

        if KeychainStore.load() == nil {
            configureStatusButton(title: "CodeAPI 设置", symbol: "key.fill")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.preferences.present()
            }
        } else {
            Task { await refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func configureStatusButton(title: String, symbol: String) {
        guard let button = statusItem.button else { return }
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CodeAPI")
        button.imagePosition = .imageLeading
        button.toolTip = "CodeAPI 使用情况"
    }

    func acceptValidatedUsage(_ usage: UsageResponse) {
        latestUsage = usage
        latestError = nil
        lastUpdated = Date()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func manualRefresh() { Task { await refresh() } }

    private func refresh() async {
        guard !isRefreshing else { return }
        guard let key = KeychainStore.load(), !key.isEmpty else {
            latestError = "尚未配置 API Key"
            configureStatusButton(title: "CodeAPI 设置", symbol: "key.fill")
            rebuildMenu()
            return
        }

        isRefreshing = true
        rebuildMenu()
        defer { isRefreshing = false; rebuildMenu() }
        do {
            let usage = try await CodeAPIClient.fetch(key: key)
            acceptValidatedUsage(usage)
        } catch {
            latestError = error.localizedDescription
            if latestUsage == nil {
                configureStatusButton(title: "CodeAPI ⚠︎", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func updateStatusTitle() {
        guard let data = latestUsage else { return }
        configureStatusButton(
            title: "\(money(data.balance)) · 今日 \(money(data.usage.today.actualCost))",
            symbol: "chart.bar.fill"
        )
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if let data = latestUsage {
            menu.addItem(info("余额  \(money(data.balance))", emphasis: true))
            menu.addItem(info("今日费用  \(money(data.usage.today.actualCost))"))
            menu.addItem(.separator())

            let todayItem = NSMenuItem(title: "今日用量", action: nil, keyEquivalent: "")
            let todayMenu = NSMenu()
            todayMenu.addItem(info("请求  \(number(data.usage.today.requests)) 次"))
            todayMenu.addItem(info("总 Token  \(number(data.usage.today.totalTokens))"))
            todayMenu.addItem(info("输入  \(number(data.usage.today.inputTokens))"))
            todayMenu.addItem(info("输出  \(number(data.usage.today.outputTokens))"))
            todayMenu.addItem(info("缓存读取  \(number(data.usage.today.cacheReadTokens))"))
            todayItem.submenu = todayMenu
            menu.addItem(todayItem)

            let totalItem = NSMenuItem(title: "累计用量", action: nil, keyEquivalent: "")
            let totalMenu = NSMenu()
            totalMenu.addItem(info("实际费用  \(money(data.usage.total.actualCost))"))
            totalMenu.addItem(info("请求  \(number(data.usage.total.requests)) 次"))
            totalMenu.addItem(info("总 Token  \(number(data.usage.total.totalTokens))"))
            totalMenu.addItem(info(String(format: "平均响应  %.2f 秒", data.usage.averageDurationMs / 1000)))
            totalItem.submenu = totalMenu
            menu.addItem(totalItem)

            if let stats = data.modelStats, !stats.isEmpty {
                let modelsItem = NSMenuItem(title: "模型统计", action: nil, keyEquivalent: "")
                let modelsMenu = NSMenu()
                for model in stats.sorted(by: { $0.actualCost > $1.actualCost }) {
                    let item = NSMenuItem(title: model.model, action: nil, keyEquivalent: "")
                    let detail = NSMenu()
                    detail.addItem(info("费用  \(money(model.actualCost))"))
                    detail.addItem(info("请求  \(number(model.requests)) 次"))
                    detail.addItem(info("Token  \(number(model.totalTokens))"))
                    item.submenu = detail
                    modelsMenu.addItem(item)
                }
                modelsItem.submenu = modelsMenu
                menu.addItem(modelsItem)
            }

            menu.addItem(.separator())
            if let plan = data.planName { menu.addItem(info("方案  \(plan)")) }
            if let mode = data.mode { menu.addItem(info("模式  \(mode)")) }
        } else {
            menu.addItem(info("暂无使用数据"))
        }

        if let error = latestError {
            menu.addItem(.separator())
            let item = info("⚠︎ \(error)")
            item.attributedTitle = NSAttributedString(
                string: item.title,
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if let date = lastUpdated {
            menu.addItem(info("更新于 \(timeFormatter.string(from: date)) · 每分钟自动刷新"))
        } else {
            menu.addItem(info("每分钟自动刷新"))
        }

        let refresh = NSMenuItem(title: isRefreshing ? "正在刷新…" : "立即刷新", action: #selector(manualRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !isRefreshing
        menu.addItem(refresh)

        let settings = NSMenuItem(title: "设置 API Key…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let dashboard = NSMenuItem(title: "打开 CodeAPI 控制台", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Agent Pulse", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func info(_ title: String, emphasis: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if emphasis {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]
            )
        }
        return item
    }

    @objc private func openPreferences() { preferences.present() }
    @objc private func openDashboard() { NSWorkspace.shared.open(dashboardURL) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func money(_ value: Double) -> String { String(format: "$%.2f", value) }

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
}
#endif

if CommandLine.arguments.contains("--login-status-test") {
    print("LOGIN_STATUS \(OfficialUsageClient.loginStatusDiagnostic())")
} else if CommandLine.arguments.contains("--task-state-test") {
    let snapshot = TaskActivityReader.read()
    switch snapshot.state {
    case let .running(count): print("TASK_STATE_OK running=\(count)")
    case let .waiting(count): print("TASK_STATE_OK waiting=\(count)")
    case .ready: print("TASK_STATE_OK ready")
    }
} else if CommandLine.arguments.contains("--official-usage-test") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let snapshot = try await OfficialUsageClient.fetch()
            let remaining = snapshot.primary?.remainingPercent ?? -1
            print(String(format: "OFFICIAL_USAGE_OK loggedIn=%@ remaining=%.0f", snapshot.isLoggedIn ? "yes" : "no", remaining))
        } catch {
            print("OFFICIAL_USAGE_ERROR \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
} else if CommandLine.arguments.contains("--session-history-test") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let sessions = try await SessionHistoryClient.fetch()
            let providerCounts = Dictionary(grouping: sessions, by: \.modelProvider)
                .map { "\($0.key)=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            print("SESSION_HISTORY_OK count=\(sessions.count) providers=\(providerCounts)")
        } catch {
            print("SESSION_HISTORY_ERROR \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
} else if CommandLine.arguments.contains("--repair-route-config") {
    do {
        let route = RouteConfigManager.currentRoute()
        try RouteConfigManager.apply(route)
        print("ROUTE_CONFIG_REPAIRED \(route.displayName)")
    } catch {
        FileHandle.standardError.write(Data("ROUTE_CONFIG_REPAIR_ERROR \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--provider-connection-test") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        defer { semaphore.signal() }
        guard let providerID = ProviderStore.selectedProviderID(),
              let profile = ProviderStore.provider(id: providerID),
              let key = CredentialStore.load(providerID: providerID) else {
            print("PROVIDER_CONNECTION_ERROR 未找到当前提供商或 API Key。")
            return
        }
        do {
            let result = try await ProviderConnectionTester.test(profile: profile, key: key)
            print("PROVIDER_CONNECTION_OK \(result)")
        } catch {
            print("PROVIDER_CONNECTION_ERROR \(error.localizedDescription)")
        }
    }
    semaphore.wait()
} else if CommandLine.arguments.contains("--model-catalog-test") {
    do {
        guard let providerID = ProviderStore.selectedProviderID(),
              let profile = ProviderStore.provider(id: providerID) else {
            print("MODEL_CATALOG_ERROR 未找到当前提供商。")
            exit(EXIT_FAILURE)
        }
        if let url = try CodexModelCatalog.prepareIfNeeded(model: profile.model) {
            let data = try Data(contentsOf: url)
            let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let models = root["models"] as! [[String: Any]]
            let selected = models.first {
                ($0["slug"] as? String)?.caseInsensitiveCompare(profile.model) == .orderedSame
            }
            precondition(selected?["use_responses_lite"] as? Bool == false)
            print("MODEL_CATALOG_OK \(profile.model) Responses Lite disabled")
        } else {
            print("MODEL_CATALOG_OK \(profile.model) override not required")
        }
    } catch {
        print("MODEL_CATALOG_ERROR \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--pinwheel-preview")
            || CommandLine.arguments.contains("--gears-preview") {
    let previewStyle: StatusIconStyle = CommandLine.arguments.contains("--gears-preview")
        ? .gears
        : .pinwheel
    let previewName = previewStyle == .gears ? "gears" : "pinwheel"
    let scale: CGFloat = 8
    let cellSize = NSSize(width: 34 * scale, height: 24 * scale)
    let preview = NSImage(
        size: NSSize(width: cellSize.width * 3, height: cellSize.height),
        flipped: false
    ) { rect in
        NSColor.windowBackgroundColor.setFill()
        rect.fill()
        for (index, signal) in TrafficSignal.allCases.enumerated() {
            let icon = StatusIconRenderer.image(
                style: previewStyle,
                active: signal,
                frame: previewStyle == .gears ? index * 18 + 12 : index * 3
            )
            let target = NSRect(
                x: CGFloat(index) * cellSize.width + (cellSize.width - icon.size.width * scale) / 2,
                y: (cellSize.height - icon.size.height * scale) / 2,
                width: icon.size.width * scale,
                height: icon.size.height * scale
            )
            icon.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
        return true
    }
    let outputURL = URL(fileURLWithPath: "/tmp/agent-pulse-\(previewName)-preview.png")
    guard let tiff = preview.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("STATUS_PREVIEW_ERROR 无法生成预览图")
        exit(EXIT_FAILURE)
    }
    try! png.write(to: outputURL, options: .atomic)
    print("STATUS_PREVIEW_OK \(outputURL.path)")
} else if CommandLine.arguments.contains("--install-cursor-hooks") {
    do {
        try CursorIntegration.installHooks()
        print("CURSOR_HOOKS_OK \(CursorIntegration.hooksURL.path)")
    } catch {
        print("CURSOR_HOOKS_ERROR \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
} else if CommandLine.arguments.contains("--provider-ui-preview") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        let controller = SettingsWindowController(appDelegate: delegate)
        controller.presentProviderPreview()
        app.run()
    }
} else if CommandLine.arguments.contains("--appearance-ui-preview") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        let controller = SettingsWindowController(appDelegate: delegate)
        controller.presentAppearancePreview()
        app.run()
    }
} else if CommandLine.arguments.contains("--route-ui-preview") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        let controller = SettingsWindowController(appDelegate: delegate)
        controller.presentRoutePreview()
        app.run()
    }
} else if CommandLine.arguments.contains("--version-update-ui-preview") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        let controller = SettingsWindowController(appDelegate: delegate)
        controller.presentVersionUpdatePreview()
        app.run()
    }
} else if CommandLine.arguments.contains("--self-test") {
    let sanitizedFixture = SensitiveConfigSanitizer.sanitize("""
    api_key = "secret-value"
    env_key = "OPENAI_API_KEY"
    http_headers = { Authorization = "Bearer hidden" }
    """)
    precondition(!sanitizedFixture.contains("secret-value"))
    precondition(!sanitizedFixture.contains("Bearer hidden"))
    precondition(sanitizedFixture.contains("OPENAI_API_KEY"))
    let previousWarningThreshold = UsageAlertPreferences.warningThreshold
    let previousCriticalThreshold = UsageAlertPreferences.criticalThreshold
    UsageAlertPreferences.warningThreshold = 20
    UsageAlertPreferences.criticalThreshold = 10
    precondition(UsageAlertManager.level(for: 25) == nil)
    precondition(UsageAlertManager.level(for: 15) == "warning")
    precondition(UsageAlertManager.level(for: 5) == "critical")
    let previousBalanceWarning = UsageAlertPreferences.balanceWarningThreshold
    let previousBalanceCritical = UsageAlertPreferences.balanceCriticalThreshold
    UsageAlertPreferences.balanceWarningThreshold = 10
    UsageAlertPreferences.balanceCriticalThreshold = 3
    precondition(UsageAlertManager.balanceLevel(for: 20) == nil)
    precondition(UsageAlertManager.balanceLevel(for: 7) == "warning")
    precondition(UsageAlertManager.balanceLevel(for: 2) == "critical")
    UsageAlertPreferences.warningThreshold = previousWarningThreshold
    UsageAlertPreferences.criticalThreshold = previousCriticalThreshold
    UsageAlertPreferences.balanceWarningThreshold = previousBalanceWarning
    UsageAlertPreferences.balanceCriticalThreshold = previousBalanceCritical
    let sample = """
    model = "gpt-5.6-sol"
    model_provider = "legacy"

    [mcp_servers.example]
    command = "example"
    """
    let provider = ProviderProfile(
        id: "test-provider",
        name: "Test \"Provider\"",
        baseURL: "https://api.example.com/v1",
        model: "custom-model"
    )
    let updateFixture = AppUpdateStatus(currentVersion: "3.0.1", latestVersion: "3.1.0")
    guard updateFixture.updateAvailable,
          updateFixture.installerURL.absoluteString.hasSuffix("/dist/Agent-Pulse-3.1.0.dmg") else {
        print("SELF_TEST_ERROR update metadata")
        exit(EXIT_FAILURE)
    }
    try! AppUpdateInstaller.validateHelperScriptForTesting()
    let balanceRefreshNow = Date(timeIntervalSince1970: 10_000)
    precondition(ProviderBalanceRefreshPolicy.shouldRefresh(lastUpdated: nil, now: balanceRefreshNow))
    precondition(!ProviderBalanceRefreshPolicy.shouldRefresh(
        lastUpdated: balanceRefreshNow.addingTimeInterval(-44),
        now: balanceRefreshNow
    ))
    precondition(ProviderBalanceRefreshPolicy.shouldRefresh(
        lastUpdated: balanceRefreshNow.addingTimeInterval(-45),
        now: balanceRefreshNow
    ))
    precondition(AgentKind.codex.supportsModelProviderConfiguration)
    precondition(!AgentKind.cursor.supportsModelProviderConfiguration)
    precondition(!AgentKind.hermes.supportsModelProviderConfiguration)
    for vendor in ProviderVendor.presetChoices where vendor != .custom {
        precondition(vendor.defaultBaseURL?.hasPrefix("https://") == true)
        precondition(vendor.defaultModel?.isEmpty == false)
    }
    precondition(ProviderVendor.presetChoices.contains(.miMo))
    precondition(ProviderVendor.presetChoices.contains(.bailian))
    precondition(!ProviderVendor.presetChoices.contains(.xAI))
    precondition(ProviderVendor.infer(from: "https://api.deepseek.com/v1") == .deepSeek)
    precondition(ProviderVendor.infer(from: "https://open.bigmodel.cn/api/paas/v4") == .zhipuAI)
    let zhipuFixture = ProviderProfile(
        id: "zhipu-fixture",
        name: "智谱 AI",
        baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
        model: "glm-5.2",
        vendor: .zhipuAI
    )
    precondition(
        try! ProviderConnectionTester.endpointURL(profile: zhipuFixture).absoluteString
            == "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
    )
    precondition(ProviderVendor.infer(from: "https://api.moonshot.cn/v1") == .moonshot)
    precondition(ProviderVendor.infer(from: "https://api.minimaxi.com/v1") == .miniMax)
    precondition(ProviderVendor.infer(from: "https://api.stepfun.ai/v1") == .stepFun)
    precondition(ProviderVendor.infer(from: "https://api.xiaomimimo.com/v1") == .miMo)
    precondition(
        ProviderVendor.infer(from: "https://dashscope.aliyuncs.com/compatible-mode/v1") == .bailian
    )
    precondition(ProviderVendor.infer(from: "https://api.x.ai/v1") == .xAI)
    precondition(ProviderVendor.infer(from: "https://api.example.com/v1") == .custom)
    let custom = RouteConfigManager.render(sample, route: .provider(provider.id), profile: provider)
    precondition(custom.hasPrefix("model_provider = \"openai\""))
    precondition(custom.contains("model = \"custom-model\""))
    precondition(custom.contains("openai_base_url = \"https://api.example.com/v1\""))
    precondition(custom.contains("forced_login_method = \"api\""))
    precondition(custom.contains("cli_auth_credentials_store = \"file\""))
    precondition(custom.contains("name = \"Test \\\"Provider\\\"\""))
    precondition(custom.contains("base_url = \"https://api.example.com/v1\""))
    precondition(custom.contains("[mcp_servers.example]"))
    precondition(custom.contains("command = \"/bin/cat\""))
    precondition(custom.contains("test-provider.key"))
    precondition(custom.contains("[model_providers.codeapi_status_custom]"))
    precondition(!custom.contains("model_provider = \"legacy\""))

    let preservedModelProvider = RouteConfigManager.render(
        sample,
        route: .provider(provider.id),
        profile: provider,
        modelProvider: "custom_runtime"
    )
    precondition(preservedModelProvider.hasPrefix("model_provider = \"custom_runtime\""))

    let sameNameProvider = ProviderProfile(
        id: "same-name-provider",
        name: provider.name,
        baseURL: "https://second.example.com/v1",
        model: "second-model"
    )
    precondition(ProviderStore.hasNameCollision(
        "  TEST \"PROVIDER\"  ",
        excluding: sameNameProvider.id,
        in: [provider]
    ))
    let duplicateTitles = ProviderStore.popupTitles(for: [provider, sameNameProvider])
    precondition(duplicateTitles.count == 2)
    precondition(duplicateTitles[0] != duplicateTitles[1])

    let cursorOnlyProvider = ProviderProfile(
        id: "cursor-only-provider",
        name: provider.name,
        baseURL: "https://cursor.example.com/v1",
        model: "cursor-model",
        agents: [.cursor]
    )
    precondition(cursorOnlyProvider.supports(.cursor))
    precondition(!cursorOnlyProvider.supports(.codex))
    precondition(provider.supports(.codex) && provider.supports(.cursor))
    precondition(!ProviderStore.hasNameCollision(
        provider.name,
        excluding: cursorOnlyProvider.id,
        in: [ProviderProfile(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL,
            model: provider.model,
            agents: [.codex]
        )],
        agent: .cursor
    ))
    let sameNameConfig = RouteConfigManager.render(
        sample,
        route: .provider(sameNameProvider.id),
        profile: sameNameProvider,
        profiles: [provider, sameNameProvider],
        legacyProfile: sameNameProvider
    )
    precondition(sameNameConfig.hasPrefix("model_provider = \"openai\""))
    precondition(sameNameConfig.contains(
        "openai_base_url = \"https://second.example.com/v1\""
    ))
    precondition(sameNameConfig.contains(
        "[model_providers.codeapi_status_provider_test-provider]"
    ))
    precondition(sameNameConfig.contains(
        "[model_providers.codeapi_status_provider_same-name-provider]"
    ))
    try! RouteConfigManager.validate(sameNameConfig)

    let official = RouteConfigManager.render(
        custom,
        route: .official,
        profiles: [provider],
        legacyProfile: provider,
        officialModel: "gpt-5.6-sol"
    )
    precondition(official.hasPrefix("model_provider = \"openai\""))
    precondition(official.contains("model = \"gpt-5.6-sol\""))
    precondition(!official.contains("openai_base_url ="))
    precondition(!official.contains("forced_login_method ="))
    precondition(!official.contains("cli_auth_credentials_store ="))
    precondition(official.contains(RouteConfigManager.beginMarker))
    precondition(official.contains("[model_providers.codeapi_status_provider_test-provider]"))
    precondition(official.contains("[mcp_servers.example]"))

    let codeAPIConfig = RouteConfigManager.render(
        sample,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI,
        compatibilityModelCatalogJSON: "/tmp/provider-model-catalog.json"
    )
    precondition(codeAPIConfig.hasPrefix("model_provider = \"openai\""))
    precondition(codeAPIConfig.contains("openai_base_url = \"https://codeapi.nexita.net/v1\""))
    precondition(codeAPIConfig.contains(
        "model_catalog_json = \"/tmp/provider-model-catalog.json\""
    ))
    precondition(codeAPIConfig.contains("[model_providers.codeapi_status_custom]"))
    precondition(codeAPIConfig.contains("[model_providers.codeapi]"))
    precondition(codeAPIConfig.components(separatedBy: "[model_providers.codeapi]").count == 2)
    precondition(codeAPIConfig.components(separatedBy: "[model_providers.codeapi.auth]").count == 2)
    try! RouteConfigManager.validate(codeAPIConfig)

    let legacyCodeAPIConfig = """
    model_provider = "codeapi"
    model = "gpt-5.6-sol"

    [model_providers.codeapi]
    name = "codeapi"
    base_url = "https://codeapi.nexita.net"
    wire_api = "responses"
    requires_openai_auth = true

    [mcp_servers.example]
    command = "example"
    """
    let repairedCodeAPIConfig = RouteConfigManager.render(
        legacyCodeAPIConfig,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI,
        compatibilityModelCatalogJSON: "/tmp/provider-model-catalog.json"
    )
    precondition(repairedCodeAPIConfig.components(separatedBy: "[model_providers.codeapi]").count == 2)
    precondition(repairedCodeAPIConfig.components(separatedBy: "[model_providers.codeapi.auth]").count == 2)
    precondition(!repairedCodeAPIConfig.contains("requires_openai_auth"))
    precondition(repairedCodeAPIConfig.contains("[mcp_servers.example]"))
    try! RouteConfigManager.validate(repairedCodeAPIConfig)
    let rerenderedCodeAPIConfig = RouteConfigManager.render(
        repairedCodeAPIConfig,
        route: .provider("codeapi"),
        profile: .codeAPI,
        profiles: [.codeAPI],
        legacyProfile: .codeAPI,
        compatibilityModelCatalogJSON: "/tmp/provider-model-catalog.json"
    )
    precondition(rerenderedCodeAPIConfig == repairedCodeAPIConfig)

    let deepSeek = ProviderProfile(
        id: "deepseek-test",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        model: "deepseek-v4-pro"
    )
    let deepSeekConfig = RouteConfigManager.render(
        sample,
        route: .provider(deepSeek.id),
        profile: deepSeek,
        profiles: [deepSeek],
        legacyProfile: deepSeek
    )
    precondition(deepSeek.effectiveAPIFormat == .responses)
    precondition(deepSeekConfig.hasPrefix("model_provider = \"openai\""))
    precondition(deepSeekConfig.contains(
        "openai_base_url = \"https://api.deepseek.com\""
    ))
    precondition(deepSeekConfig.contains(
        "base_url = \"https://api.deepseek.com\""
    ))
    precondition(deepSeekConfig.contains("wire_api = \"responses\""))
    precondition(RouteConfigManager.detectedRoute(
        in: deepSeekConfig,
        profiles: [deepSeek],
        selectedProviderID: deepSeek.id
    ) == .provider(deepSeek.id))
    precondition(RouteConfigManager.detectedRoute(
        in: official,
        profiles: [provider],
        selectedProviderID: provider.id
    ) == .official)
    let legacyNamedProviderConfig = """
    model_provider = "codeapi_status_provider_test-provider"
    model = "custom-model"

    \(RouteConfigManager.beginMarker)

    [model_providers.codeapi_status_provider_test-provider]
    name = "Test Provider"
    base_url = "https://api.example.com/v1"
    wire_api = "responses"

    [model_providers.codeapi_status_provider_test-provider.auth]
    command = "/bin/cat"
    args = ["/tmp/test-provider.key"]

    [model_providers.codeapi_status_custom]
    name = "Test Provider"
    base_url = "https://api.example.com/v1"
    wire_api = "responses"

    \(RouteConfigManager.endMarker)
    """
    precondition(RouteConfigManager.needsUpgradeReconciliation(
        in: legacyNamedProviderConfig,
        profiles: [provider],
        selectedProviderID: provider.id
    ) == false)
    precondition(!RouteConfigManager.needsUpgradeReconciliation(
        in: custom,
        profiles: [provider],
        selectedProviderID: provider.id
    ))

    let catalogFixture = try! JSONSerialization.data(withJSONObject: [
        "models": [
            [
                "slug": "gpt-5.6-sol",
                "use_responses_lite": true,
                "multi_agent_version": "v2"
            ],
            [
                "slug": "gpt-5.5",
                "use_responses_lite": false
            ]
        ]
    ])
    let patchedCatalogData = try! CodexModelCatalog.patchedCatalog(
        catalogFixture,
        selectedModel: "gpt-5.6-sol"
    )
    let patchedCatalog = try! JSONSerialization.jsonObject(
        with: patchedCatalogData
    ) as! [String: Any]
    let patchedModels = patchedCatalog["models"] as! [[String: Any]]
    let patchedSol = patchedModels.first { $0["slug"] as? String == "gpt-5.6-sol" }!
    precondition(patchedSol["use_responses_lite"] as? Bool == false)
    precondition(patchedSol["multi_agent_version"] as? String == "v1")

    let providerKey = "provider-test-key"
    let providerAuth = try! JSONSerialization.data(withJSONObject: ["OPENAI_API_KEY": providerKey])
    let chatGPTAuth = try! JSONSerialization.data(withJSONObject: [
        "auth_mode": "chatgpt",
        "OPENAI_API_KEY": providerKey,
        "tokens": ["access_token": "official-access-token"]
    ])
    precondition(CodexAuthStore.kind(
        of: providerAuth,
        configuredProviderKeys: [providerKey]
    ) == .configuredProviderAPIKey)
    precondition(CodexAuthStore.kind(
        of: chatGPTAuth,
        configuredProviderKeys: [providerKey]
    ) == .chatGPT)
    let restorePlan = CodexAuthStore.officialPlan(
        currentData: providerAuth,
        backupData: chatGPTAuth,
        configuredProviderKeys: [providerKey]
    )
    guard case let .restoreBackup(restoredAuth) = restorePlan else {
        preconditionFailure("Expected official auth backup to be restored")
    }
    let restoredObject = try! JSONSerialization.jsonObject(with: restoredAuth) as! [String: Any]
    precondition(restoredObject["OPENAI_API_KEY"] is NSNull)
    precondition(CodexAuthStore.officialPlan(
        currentData: providerAuth,
        backupData: nil,
        configuredProviderKeys: [providerKey]
    ) == .removeCurrentAndRequireLogin)
    precondition(!OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Logged in using an API key",
        terminationStatus: 0
    ))
    precondition(OfficialUsageClient.loginStatusUsesAPIKey("Logged in using an API key"))
    precondition(OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Logged in using ChatGPT",
        terminationStatus: 0
    ))
    precondition(!OfficialUsageClient.loginStatusIndicatesChatGPT(
        "Not logged in",
        terminationStatus: 1
    ))

    var upgradeEvents: [String] = []
    let upgradeChanged = try! RouteUpgradeCoordinator.reconcileIfNeeded(
        needsReconciliation: { true },
        currentRoute: { .provider(provider.id) },
        snapshotAuth: {
            upgradeEvents.append("snapshot-auth")
            return "auth-before-upgrade"
        },
        prepareAuth: { route in
            precondition(route == .provider(provider.id))
            upgradeEvents.append("prepare-auth")
        },
        restoreAuth: { _ in upgradeEvents.append("restore-auth") },
        applyConfig: { route in
            precondition(route == .provider(provider.id))
            upgradeEvents.append("apply-config")
        }
    )
    precondition(upgradeChanged)
    precondition(upgradeEvents == ["snapshot-auth", "prepare-auth", "apply-config"])

    enum UpgradeTestError: Error { case cannotPrepareAuth }
    upgradeEvents.removeAll()
    do {
        _ = try RouteUpgradeCoordinator.reconcileIfNeeded(
            needsReconciliation: { true },
            currentRoute: { .provider(provider.id) },
            snapshotAuth: {
                upgradeEvents.append("snapshot-auth")
                return "auth-before-upgrade"
            },
            prepareAuth: { _ in
                upgradeEvents.append("prepare-auth")
                throw UpgradeTestError.cannotPrepareAuth
            },
            restoreAuth: { snapshot in
                precondition(snapshot == "auth-before-upgrade")
                upgradeEvents.append("restore-auth")
            },
            applyConfig: { _ in upgradeEvents.append("apply-config") }
        )
        preconditionFailure("Expected provider authentication migration to fail")
    } catch UpgradeTestError.cannotPrepareAuth {
        precondition(upgradeEvents == ["snapshot-auth", "prepare-auth", "restore-auth"])
    } catch {
        preconditionFailure("Unexpected upgrade error: \(error)")
    }

    for style in StatusIconStyle.allCases {
        for signal in TrafficSignal.allCases {
            for frame in [0, 6, 12, 18] {
                let icon = StatusIconRenderer.image(style: style, active: signal, frame: frame)
                precondition(icon.size.height == 18)
                precondition(icon.tiffRepresentation != nil)
            }
        }
    }
    let compositeStatusImage = StatusIconRenderer.statusItemImage(
        style: .pinwheel,
        active: .green,
        frame: 12,
        title: "Codex · $100.00",
        font: .systemFont(ofSize: 12, weight: .medium)
    )
    precondition(compositeStatusImage.size.height == 18)
    precondition(compositeStatusImage.size.width > StatusIconRenderer.image(
        style: .pinwheel,
        active: .green,
        frame: 12
    ).size.width)
    precondition(compositeStatusImage.tiffRepresentation != nil)
    precondition(StatusIconStyle.gears.usesCompositeStatusItemImage)
    let gearRedPhase = StatusIconRenderer.animationPhase(style: .gears, active: .red, frame: 18)
    let gearYellowPhase = StatusIconRenderer.animationPhase(style: .gears, active: .yellow, frame: 18)
    let gearGreenPhase = StatusIconRenderer.animationPhase(style: .gears, active: .green, frame: 18)
    precondition(gearRedPhase > gearYellowPhase)
    precondition(gearYellowPhase > gearGreenPhase)
    let gearStatusImage = StatusIconRenderer.statusItemImage(
        style: .gears,
        active: .red,
        frame: 18,
        title: "Hermes · ¥88.00",
        font: .systemFont(ofSize: 12, weight: .medium)
    )
    precondition(gearStatusImage.size.height == 18)
    precondition(gearStatusImage.size.width > StatusIconRenderer.image(
        style: .gears,
        active: .red,
        frame: 18
    ).size.width)
    precondition(gearStatusImage.tiffRepresentation != nil)

    let taskRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pulse-task-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: taskRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: taskRoot) }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    func event(_ type: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}\n"
    }
    func responseItem(_ type: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"response_item\",\"payload\":{\"type\":\"\(type)\"}}\n"
    }

    let completedSession = taskRoot.appendingPathComponent("completed.jsonl")
    try! Data(event("task_started").utf8).write(to: completedSession)
    precondition(TaskActivityReader.read(root: taskRoot).state == .running(1))
    let completedHandle = try! FileHandle(forWritingTo: completedSession)
    _ = try! completedHandle.seekToEnd()
    try! completedHandle.write(contentsOf: Data(responseItem("custom_tool_call").utf8))
    try! completedHandle.synchronize()
    precondition(TaskActivityReader.read(root: taskRoot, forceFileScan: false).state == .waiting(1))
    try! completedHandle.write(contentsOf: Data(responseItem("custom_tool_call_output").utf8))
    try! completedHandle.synchronize()
    precondition(TaskActivityReader.read(root: taskRoot, forceFileScan: false).state == .running(1))
    try! completedHandle.write(contentsOf: Data(event("task_complete").utf8))
    try! completedHandle.synchronize()
    try! completedHandle.close()
    precondition(TaskActivityReader.read(root: taskRoot, forceFileScan: false).state == .ready)

    let indexedEventSession = taskRoot.appendingPathComponent("event-indexed.jsonl")
    try! Data(event("task_started").utf8).write(to: indexedEventSession)
    let indexedEvent = TaskActivityFileEvent(path: indexedEventSession.path, flags: 0)
    precondition(TaskActivityReader.read(
        root: taskRoot,
        fileEvents: [indexedEvent],
        forceFileScan: false
    ).state == .running(1))
    try! Data((event("task_started") + event("task_complete")).utf8).write(to: indexedEventSession)
    precondition(TaskActivityReader.read(
        root: taskRoot,
        fileEvents: [indexedEvent],
        forceFileScan: false
    ).state == .ready)

    let instantToolSession = taskRoot.appendingPathComponent("instant-tool.jsonl")
    try! Data((
        event("task_started")
        + responseItem("custom_tool_call")
        + responseItem("custom_tool_call_output")
    ).utf8).write(to: instantToolSession)
    let instantFirst = TaskActivityReader.read(root: taskRoot).state
    let instantSecond = TaskActivityReader.read(root: taskRoot).state
    precondition(instantFirst == .waiting(1))
    precondition(instantSecond == .running(1))
    let instantHandle = try! FileHandle(forWritingTo: instantToolSession)
    _ = try! instantHandle.seekToEnd()
    try! instantHandle.write(contentsOf: Data(event("task_complete").utf8))
    try! instantHandle.close()
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)

    let abortedSession = taskRoot.appendingPathComponent("aborted.jsonl")
    try! Data((event("task_started") + event("turn_aborted")).utf8).write(to: abortedSession)
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)

    let staleFormatter = ISO8601DateFormatter()
    staleFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let staleTimestamp = staleFormatter.string(from: Date().addingTimeInterval(-2 * 60 * 60))
    let staleSession = taskRoot.appendingPathComponent("stale-tool-call.jsonl")
    let staleEvents = """
    {"timestamp":"\(staleTimestamp)","type":"event_msg","payload":{"type":"task_started"}}
    {"timestamp":"\(staleTimestamp)","type":"response_item","payload":{"type":"custom_tool_call"}}

    """
    try! Data(staleEvents.utf8).write(to: staleSession)
    precondition(TaskActivityReader.read(root: taskRoot).state == .ready)

    let monitorRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pulse-monitor-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: monitorRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: monitorRoot) }
    let monitorSignal = DispatchSemaphore(value: 0)
    let normalizedMonitorRoot = monitorRoot.standardizedFileURL.resolvingSymlinksInPath().path
    let monitor = TaskActivityMonitor(paths: [monitorRoot]) { events in
        if events.contains(where: { $0.path.hasPrefix(normalizedMonitorRoot) }) {
            monitorSignal.signal()
        }
    }
    let monitorStarted = monitor.start()
    if monitorStarted {
        Thread.sleep(forTimeInterval: 0.5)
        try! Data(event("task_started").utf8).write(
            to: monitorRoot.appendingPathComponent("event.jsonl")
        )
        let monitorResult = monitorSignal.wait(timeout: .now() + 5)
        precondition(monitorResult == .success)
    } else {
        print("SELF_TEST_SKIP FSEvents unavailable; polling fallback remains active")
    }
    monitor.stop()

    let migrationRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pulse-session-migration-\(UUID().uuidString)", isDirectory: true)
    let migrationSessions = migrationRoot
        .appendingPathComponent("sessions/2026/07/29", isDirectory: true)
    try! FileManager.default.createDirectory(
        at: migrationSessions,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: migrationRoot) }
    let migrationConfig = """
    model_provider = "openai"

    [model_providers.codeapi]
    name = "CodeAPI"
    base_url = "https://codeapi.nexita.net/v1"

    [model_providers.codeapi_status_custom]
    name = "CodeAPI Legacy"
    base_url = "https://codeapi.nexita.net/v1"

    [model_providers.deepseek]
    name = "DeepSeek"
    base_url = "https://api.deepseek.com/v1"
    """
    try! Data(migrationConfig.utf8).write(
        to: migrationRoot.appendingPathComponent("config.toml")
    )
    let legacyCodeAPIID = "11111111-1111-4111-8111-111111111111"
    let legacyDeepSeekID = "22222222-2222-4222-8222-222222222222"
    let currentOpenAIID = "33333333-3333-4333-8333-333333333333"
    func migrationFixtureURL(_ id: String) -> URL {
        migrationSessions.appendingPathComponent("rollout-2026-07-29T10-00-00-\(id).jsonl")
    }
    func migrationFixtureData(id: String, provider: String) -> Data {
        Data("""
        {"timestamp":"2026-07-29T02:00:00Z","type":"session_meta","payload":{"id":"\(id)","session_id":"\(id)","model_provider":"\(provider)","cwd":"/tmp"}}
        {"timestamp":"2026-07-29T02:00:01Z","type":"event_msg","payload":{"type":"task_complete"}}

        """.utf8)
    }
    try! migrationFixtureData(id: legacyCodeAPIID, provider: "codeapi")
        .write(to: migrationFixtureURL(legacyCodeAPIID))
    try! migrationFixtureData(id: legacyDeepSeekID, provider: "deepseek")
        .write(to: migrationFixtureURL(legacyDeepSeekID))
    try! migrationFixtureData(id: currentOpenAIID, provider: "openai")
        .write(to: migrationFixtureURL(currentOpenAIID))
    let migrationDatabase = migrationRoot.appendingPathComponent("state_5.sqlite")
    func runMigrationFixtureSQLite(_ sql: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [migrationDatabase.path, sql]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try! process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        return String(data: data, encoding: .utf8) ?? ""
    }
    func sqliteFixtureLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
    let migrationFixtureSQL = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      rollout_path TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      model_provider TEXT NOT NULL,
      title TEXT NOT NULL
    );
    CREATE TABLE thread_dynamic_tools (
      thread_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      name TEXT NOT NULL,
      description TEXT NOT NULL,
      input_schema TEXT NOT NULL,
      defer_loading INTEGER NOT NULL DEFAULT 0,
      namespace TEXT,
      PRIMARY KEY(thread_id, position),
      FOREIGN KEY(thread_id) REFERENCES threads(id) ON DELETE CASCADE
    );
    CREATE TABLE thread_spawn_edges (
      parent_thread_id TEXT NOT NULL,
      child_thread_id TEXT NOT NULL PRIMARY KEY,
      status TEXT NOT NULL
    );
    INSERT INTO threads VALUES (
      \(sqliteFixtureLiteral(legacyCodeAPIID)),
      \(sqliteFixtureLiteral(migrationFixtureURL(legacyCodeAPIID).path)),
      1, 3, 'codeapi', 'CodeAPI legacy'
    );
    INSERT INTO threads VALUES (
      \(sqliteFixtureLiteral(legacyDeepSeekID)),
      \(sqliteFixtureLiteral(migrationFixtureURL(legacyDeepSeekID).path)),
      1, 2, 'deepseek', 'DeepSeek legacy'
    );
    INSERT INTO threads VALUES (
      \(sqliteFixtureLiteral(currentOpenAIID)),
      \(sqliteFixtureLiteral(migrationFixtureURL(currentOpenAIID).path)),
      1, 1, 'openai', 'OpenAI current'
    );
    INSERT INTO thread_dynamic_tools VALUES (
      \(sqliteFixtureLiteral(legacyCodeAPIID)),
      0, 'fixture_tool', 'Fixture', '{}', 0, 'fixture'
    );
    INSERT INTO thread_spawn_edges VALUES (
      \(sqliteFixtureLiteral(legacyCodeAPIID)),
      \(sqliteFixtureLiteral(legacyDeepSeekID)),
      'completed'
    );
    """
    _ = runMigrationFixtureSQLite(migrationFixtureSQL)
    let migrationScan = try! LegacySessionMigration.scan(codexHome: migrationRoot)
    precondition(migrationScan?.providerCount == 2)
    precondition(migrationScan?.sessionCount == 2)
    let migrationResult = try! LegacySessionMigration.migrate(
        migrationScan!,
        codexHome: migrationRoot
    )
    precondition(migrationResult.copiedSessions == 2)
    precondition(FileManager.default.fileExists(
        atPath: migrationResult.backupDirectory
            .appendingPathComponent("state_5.sqlite").path
    ))
    let migrationCounts = runMigrationFixtureSQLite(
        "SELECT model_provider || ':' || COUNT(*) FROM threads GROUP BY model_provider ORDER BY model_provider;"
    )
    precondition(migrationCounts.contains("codeapi:1"))
    precondition(migrationCounts.contains("deepseek:1"))
    precondition(migrationCounts.contains("openai:3"))
    let copiedDynamicTools = runMigrationFixtureSQLite(
        "SELECT COUNT(*) FROM thread_dynamic_tools WHERE thread_id != \(sqliteFixtureLiteral(legacyCodeAPIID));"
    )
    precondition(copiedDynamicTools.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    let copiedSpawnEdges = runMigrationFixtureSQLite(
        """
        SELECT COUNT(*) FROM thread_spawn_edges edge
        JOIN threads parent ON parent.id = edge.parent_thread_id
        JOIN threads child ON child.id = edge.child_thread_id
        WHERE parent.model_provider = 'openai' AND child.model_provider = 'openai';
        """
    )
    precondition(copiedSpawnEdges.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    let migrationReportURL = migrationRoot
        .appendingPathComponent("agent-pulse/legacy-session-migration-v1.json")
    let migrationReportData = try! Data(contentsOf: migrationReportURL)
    let migrationReport = try! JSONSerialization.jsonObject(
        with: migrationReportData
    ) as! [String: Any]
    let migrationCopies = migrationReport["copies"] as! [[String: Any]]
    precondition(migrationCopies.count == 2)
    for copy in migrationCopies {
        let copiedID = copy["copiedID"] as! String
        let copiedPath = copy["copiedPath"] as! String
        let copiedFirstLine = try! String(
            contentsOf: URL(fileURLWithPath: copiedPath),
            encoding: .utf8
        ).components(separatedBy: .newlines)[0]
        let copiedMetadata = try! JSONSerialization.jsonObject(
            with: Data(copiedFirstLine.utf8)
        ) as! [String: Any]
        let copiedPayload = copiedMetadata["payload"] as! [String: Any]
        precondition(copiedPayload["id"] as? String == copiedID)
        precondition(copiedPayload["session_id"] as? String == copiedID)
        precondition(copiedPayload["model_provider"] as? String == "openai")
    }
    precondition(try! LegacySessionMigration.scan(codexHome: migrationRoot) == nil)

    let cursorTestRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pulse-cursor-test-\(UUID().uuidString)", isDirectory: true)
    let cursorConfig = cursorTestRoot.appendingPathComponent(".cursor", isDirectory: true)
    let cursorSupport = cursorTestRoot.appendingPathComponent("support", isDirectory: true)
    try! FileManager.default.createDirectory(at: cursorConfig, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: cursorTestRoot) }
    let existingHooks = """
    {
      "version": 1,
      "hooks": {
        "beforeShellCommand": [
          {"command": "/usr/bin/true"},
          {"command": "\\\"\(cursorSupport.appendingPathComponent("cursor-hook.sh").path)\\\" waiting"}
        ]
      }
    }
    """
    try! Data(existingHooks.utf8).write(to: cursorConfig.appendingPathComponent("hooks.json"))
    let firstHooksInstallChanged = try! CursorIntegration.installHooks(
        cursorDirectory: cursorConfig,
        supportDirectory: cursorSupport
    )
    let secondHooksInstallChanged = try! CursorIntegration.installHooks(
        cursorDirectory: cursorConfig,
        supportDirectory: cursorSupport
    )
    precondition(firstHooksInstallChanged)
    precondition(!secondHooksInstallChanged)
    let installedHooksData = try! Data(contentsOf: cursorConfig.appendingPathComponent("hooks.json"))
    let installedHooksRoot = try! JSONSerialization.jsonObject(with: installedHooksData) as! [String: Any]
    let installedHooks = installedHooksRoot["hooks"] as! [String: Any]
    let beforeShellHooks = installedHooks["beforeShellCommand"] as! [[String: String]]
    precondition(beforeShellHooks.contains { $0["command"] == "/usr/bin/true" })
    precondition(installedHooks["beforeShellExecution"] != nil)
    precondition(installedHooks["afterShellExecution"] != nil)
    precondition(installedHooks["preToolUse"] != nil)
    precondition(installedHooks["postToolUse"] != nil)
    let pulseHookCount = installedHooks.values.reduce(0) { count, value in
        let entries = value as? [[String: String]] ?? []
        return count + entries.filter { $0["command"]?.contains("cursor-hook.sh") == true }.count
    }
    precondition(pulseHookCount == 14)

    let cursorState = cursorTestRoot.appendingPathComponent("cursor-state.json")
    let cursorTimestamp = Date().timeIntervalSince1970
    try! Data("{\"state\":\"running\",\"timestamp\":\(cursorTimestamp)}".utf8)
        .write(to: cursorState)
    precondition(CursorActivityReader.read(stateURL: cursorState).state == .running(1))
    try! Data("{\"state\":\"waiting\",\"timestamp\":\(cursorTimestamp)}".utf8)
        .write(to: cursorState)
    precondition(CursorActivityReader.read(stateURL: cursorState).state == .waiting(1))
    try! Data("{\"state\":\"ready\",\"timestamp\":\(cursorTimestamp)}".utf8)
        .write(to: cursorState)
    precondition(CursorActivityReader.read(stateURL: cursorState).state == .ready)

    let cursorUsageFixture = Data("""
    {
      "billingCycleStart": "1785196800",
      "billingCycleEnd": "1787875200",
      "planUsage": {
        "totalSpend": 725,
        "remaining": 1275,
        "limit": 2000,
        "remainingBonus": 100
      }
    }
    """.utf8)
    let cursorUsage = try! CursorOfficialUsageClient.parse(cursorUsageFixture)
    precondition(cursorUsage.usedCents == 725)
    precondition(cursorUsage.remainingCents == 1275)
    precondition(cursorUsage.limitCents == 2000)
    precondition(abs((cursorUsage.remainingPercent ?? 0) - 63.75) < 0.001)
    let cursorSplitUsageFixture = Data("""
    {
      "billingCycleEnd": 1787875200000,
      "autoLimit": 1000,
      "apiLimit": 2000,
      "autoPercentUsed": 100,
      "apiPercentUsed": 25,
      "totalPercentUsed": 50
    }
    """.utf8)
    let cursorSplitUsage = try! CursorOfficialUsageClient.parse(cursorSplitUsageFixture)
    precondition(cursorSplitUsage.autoRemainingPercent == 0)
    precondition(cursorSplitUsage.apiRemainingPercent == 75)
    precondition(cursorSplitUsage.remainingPercent == 75)
    precondition(cursorSplitUsage.compactUsageText == "A 0% · API 75%")
    let cursorRatioFixture = Data("""
    {"planUsage":{"autoPercentUsed":0.25,"apiPercentUsed":1}}
    """.utf8)
    let cursorRatioUsage = try! CursorOfficialUsageClient.parse(cursorRatioFixture)
    precondition(cursorRatioUsage.autoRemainingPercent == 75)
    precondition(cursorRatioUsage.apiRemainingPercent == 0)
    let cursorTeamUsageFixture = Data("""
    {"spendLimitUsage":{"overallUsed":300,"overallLimit":1000,"overallRemaining":700}}
    """.utf8)
    let cursorTeamUsage = try! CursorOfficialUsageClient.parse(cursorTeamUsageFixture)
    precondition(cursorTeamUsage.usedCents == 300)
    precondition(cursorTeamUsage.remainingCents == 700)
    precondition(cursorTeamUsage.remainingPercent == 70)

    precondition(AgentKind.allCases.contains(.hermes))
    let legacyAgentBinding = ProviderProfile(
        id: "legacy-agent-binding",
        name: "Legacy",
        baseURL: "https://example.com/v1",
        model: "example-model"
    )
    precondition(legacyAgentBinding.supports(.codex))
    precondition(legacyAgentBinding.supports(.cursor))
    precondition(!legacyAgentBinding.supports(.hermes))
    var emptyLegacyAgentBinding = legacyAgentBinding
    emptyLegacyAgentBinding.agents = []
    precondition(!emptyLegacyAgentBinding.supports(.hermes))

    let hermesTestRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("agent-pulse-hermes-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: hermesTestRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: hermesTestRoot) }
    let hermesConfigURL = hermesTestRoot.appendingPathComponent("config.yaml")
    try! Data("""
    model:
      default: deepseek-chat
      provider: custom
      base_url: https://api.deepseek.com/v1
      api_mode: responses
    terminal: true
    """.utf8).write(to: hermesConfigURL)
    let hermesConfig = HermesIntegration.readModelConfig(at: hermesConfigURL)
    precondition(hermesConfig.model == "deepseek-chat")
    precondition(hermesConfig.provider == "custom")
    precondition(hermesConfig.baseURL == "https://api.deepseek.com/v1")
    precondition(hermesConfig.apiMode == "responses")

    let hermesGatewayURL = hermesTestRoot.appendingPathComponent("gateway_state.json")
    try! Data("{\"active_agents\":0,\"updated_at\":\"2026-08-03T12:00:00Z\"}".utf8)
        .write(to: hermesGatewayURL)
    precondition(HermesActivityReader.read(gatewayStateURL: hermesGatewayURL).state == .ready)

    let hermesDatabaseURL = hermesTestRoot.appendingPathComponent("state.db")
    let hermesFixtureTimestamp = Date().timeIntervalSince1970
    let hermesSQL = """
    CREATE TABLE messages (
      role TEXT NOT NULL,
      tool_name TEXT,
      tool_calls TEXT,
      timestamp REAL NOT NULL
    );
    INSERT INTO messages VALUES ('tool', 'shell', NULL, \(hermesFixtureTimestamp));
    CREATE TABLE session_model_usage (
      input_tokens INTEGER NOT NULL,
      output_tokens INTEGER NOT NULL,
      cache_read_tokens INTEGER NOT NULL,
      reasoning_tokens INTEGER NOT NULL,
      api_call_count INTEGER NOT NULL,
      estimated_cost_usd REAL NOT NULL,
      actual_cost_usd REAL NOT NULL,
      last_seen REAL
    );
    INSERT INTO session_model_usage VALUES (100, 50, 25, 10, 3, 0.12, 0.10, \(hermesFixtureTimestamp));
    """
    let hermesSQLite = Process()
    hermesSQLite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    hermesSQLite.arguments = [hermesDatabaseURL.path, hermesSQL]
    try! hermesSQLite.run()
    hermesSQLite.waitUntilExit()
    precondition(hermesSQLite.terminationStatus == 0)
    try! Data("{\"active_agents\":1,\"updated_at\":\"2026-08-03T12:00:00Z\"}".utf8)
        .write(to: hermesGatewayURL)
    precondition(HermesActivityReader.read(
        gatewayStateURL: hermesGatewayURL,
        stateDatabaseURL: hermesDatabaseURL
    ).state == .waiting(1))
    let hermesUsage = HermesUsageReader.readToday(databaseURL: hermesDatabaseURL)!
    precondition(hermesUsage.inputTokens == 100)
    precondition(hermesUsage.outputTokens == 50)
    precondition(hermesUsage.totalTokens == 185)
    precondition(hermesUsage.apiCalls == 3)
    precondition(abs(hermesUsage.displayCostUSD - 0.10) < 0.0001)
    let hermesBalancePresentation = HermesDashboardPresentation.make(
        providerName: "DeepSeek",
        config: hermesConfig,
        usage: hermesUsage,
        codeBalance: nil,
        providerBalance: ProviderBalanceSnapshot(
            displayText: "余额 ¥88.00",
            detail: "充值余额，不含赠送额度"
        )
    )
    precondition(hermesBalancePresentation.usageLabel == "提供商余额")
    precondition(hermesBalancePresentation.usageValue == "¥88.00")
    precondition(hermesBalancePresentation.usageDetail.contains("185 Token"))
    precondition(hermesBalancePresentation.statusValue == "¥88.00")
    let hermesCodeBalancePresentation = HermesDashboardPresentation.make(
        providerName: "自定义提供商",
        config: hermesConfig,
        usage: hermesUsage,
        codeBalance: 42.5,
        providerBalance: nil
    )
    precondition(hermesCodeBalancePresentation.usageLabel == "提供商余额")
    precondition(hermesCodeBalancePresentation.usageValue == "$42.50")
    let hermesTokenFallback = HermesDashboardPresentation.make(
        providerName: "无余额接口",
        config: hermesConfig,
        usage: hermesUsage,
        codeBalance: nil,
        providerBalance: nil
    )
    precondition(hermesTokenFallback.usageLabel == "今日 Token")
    precondition(hermesTokenFallback.usageValue == "185")
    precondition(hermesTokenFallback.statusValue == "185 Token")
    print("SELF_TEST_OK")
} else {
    MainActor.assumeIsolated {
        AppIdentity.migrateLegacyPreferencesIfNeeded()
        _ = try? CredentialStore.migrateLegacyDirectoryIfNeeded()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
