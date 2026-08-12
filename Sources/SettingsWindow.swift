import AppKit
import Foundation
import UniformTypeIdentifiers

private final class SettingsSidebarView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(calibratedWhite: 0.105, alpha: 1) : .white).cgColor
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.08)).cgColor
        layer?.borderWidth = 0.5
    }
}

private final class SettingsPageView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func makeBackingLayer() -> CALayer {
        CAGradientLayer()
    }

    override func updateLayer() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        gradient.colors = dark
            ? [NSColor(calibratedWhite: 0.095, alpha: 1).cgColor,
               NSColor(calibratedWhite: 0.125, alpha: 1).cgColor]
            : [NSColor.white.cgColor,
               NSColor(calibratedWhite: 0.975, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.15, y: 1)
        gradient.endPoint = CGPoint(x: 0.95, y: 0)
    }
}

private class TasteCardView: NSBox {
    var respondsToHover = false
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        guard respondsToHover else { return }
        animateHover(scale: 1.008, shadow: 0.12)
    }

    override func mouseExited(with event: NSEvent) {
        guard respondsToHover else { return }
        animateHover(scale: 1, shadow: 0.04)
    }

    private func animateHover(scale: CGFloat, shadow: Float) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        layer.shadowOpacity = shadow
        CATransaction.commit()
    }

    func setSelectedAppearance(_ selected: Bool) {
        borderWidth = selected ? 1.6 : 0.7
        borderColor = selected
            ? .labelColor
            : NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor.white.withAlphaComponent(0.12)
                    : NSColor.black.withAlphaComponent(0.10)
            }
    }
}

private final class ModelBannerView: TasteCardView {
    var providerID: String?
    var representsOfficial = false
    weak var actionTarget: AnyObject?
    var bannerAction: Selector?
    private let flowLayer = CALayer()
    private let flowGradientLayer = CAGradientLayer()
    private let flowMask = CAShapeLayer()
    private var selected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureFlowLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFlowLayer()
    }

    private func configureFlowLayer() {
        wantsLayer = true
        flowLayer.masksToBounds = true
        flowLayer.zPosition = 100
        flowLayer.isHidden = true
        flowGradientLayer.type = .conic
        flowGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        flowGradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        flowGradientLayer.locations = [0, 0.18, 0.42, 0.68, 1]
        flowLayer.addSublayer(flowGradientLayer)
        flowMask.fillColor = NSColor.clear.cgColor
        flowMask.strokeColor = NSColor.black.cgColor
        flowMask.lineWidth = 2.2
        flowMask.lineCap = .round
        flowLayer.mask = flowMask
        attachFlowLayerIfNeeded()
    }

    func setSelectedFlow(_ selected: Bool) {
        self.selected = selected
        if selected {
            borderWidth = 0.8
            borderColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor.white.withAlphaComponent(0.20)
                    : NSColor.black.withAlphaComponent(0.22)
            }
        } else {
            setSelectedAppearance(false)
        }
        flowLayer.isHidden = !selected
        guard selected else {
            flowGradientLayer.removeAnimation(forKey: "borderFlow")
            return
        }
        refreshFlowColor()
        needsLayout = true
        if flowGradientLayer.animation(forKey: "borderFlow") == nil {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = Double.pi * 2
            animation.duration = 2.2
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            flowGradientLayer.add(animation, forKey: "borderFlow")
        }
    }

    override func layout() {
        super.layout()
        attachFlowLayerIfNeeded()
        flowLayer.frame = bounds
        flowMask.frame = flowLayer.bounds
        let gradientSide = hypot(flowLayer.bounds.width, flowLayer.bounds.height)
        flowGradientLayer.frame = NSRect(
            x: (flowLayer.bounds.width - gradientSide) / 2,
            y: (flowLayer.bounds.height - gradientSide) / 2,
            width: gradientSide,
            height: gradientSide
        )
        flowMask.path = CGPath(
            roundedRect: flowMask.bounds.insetBy(dx: 1.4, dy: 1.4),
            cornerWidth: max(1, cornerRadius - 1.2),
            cornerHeight: max(1, cornerRadius - 1.2),
            transform: nil
        )
    }

    private func attachFlowLayerIfNeeded() {
        guard let layer, flowLayer.superlayer !== layer else { return }
        flowLayer.removeFromSuperlayer()
        layer.addSublayer(flowLayer)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFlowColor()
    }

    private func refreshFlowColor() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = dark ? NSColor.white : NSColor.black
        flowGradientLayer.colors = [
            accent.withAlphaComponent(0.08).cgColor,
            accent.withAlphaComponent(0.96).cgColor,
            accent.withAlphaComponent(0.10).cgColor,
            accent.withAlphaComponent(0.62).cgColor,
            accent.withAlphaComponent(0.08).cgColor
        ]
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard bounds.contains(convert(event.locationInWindow, from: nil)),
              let bannerAction else { return }
        NSApp.sendAction(bannerAction, to: actionTarget, from: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var current: NSView? = hit
        while let view = current, view !== self {
            if view is NSButton { return hit }
            current = view.superview
        }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class TastePopUpButton: NSPopUpButton {
    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        configureAppearance()
    }

    convenience init() { self.init(frame: .zero, pullsDown: false) }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        font = .systemFont(ofSize: 12.5, weight: .medium)
        contentTintColor = .labelColor
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 9
        layer?.borderWidth = 0.8
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.16)).cgColor
        layer?.backgroundColor = (dark
            ? NSColor.white.withAlphaComponent(0.065)
            : NSColor.black.withAlphaComponent(0.035)).cgColor
        contentTintColor = .labelColor
    }
}

private final class TasteValueStepper: NSControl {
    private let decrementButton = NSButton()
    private let incrementButton = NSButton()
    private let valueLabel = NSTextField(labelWithString: "—")
    private var values: [String] = []
    private var selectedIndex = 0
    private var unavailableTitle: String?

    override var wantsUpdateLayer: Bool { true }

    override var isEnabled: Bool {
        didSet {
            updateControlState()
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    var selectedTitle: String? {
        guard values.indices.contains(selectedIndex) else { return nil }
        return values[selectedIndex]
    }

    func setOptions(_ values: [String], selected: String?) {
        self.values = values
        unavailableTitle = nil
        if let selected, let index = values.firstIndex(of: selected) {
            selectedIndex = index
        } else {
            selectedIndex = min(3, max(0, values.count - 1))
        }
        isEnabled = !values.isEmpty
        updateControlState()
    }

    func setUnavailable(_ title: String) {
        values = []
        selectedIndex = 0
        unavailableTitle = title
        isEnabled = false
        updateControlState()
    }

    private func configureAppearance() {
        wantsLayer = true
        focusRingType = .none

        valueLabel.alignment = .center
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14.5, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureButton(decrementButton, symbol: "minus", action: #selector(decrementValue))
        configureButton(incrementButton, symbol: "plus", action: #selector(incrementValue))

        let leftSeparator = NSBox()
        leftSeparator.boxType = .separator
        let rightSeparator = NSBox()
        rightSeparator.boxType = .separator

        let stack = NSStackView(views: [decrementButton, leftSeparator, valueLabel, rightSeparator, incrementButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 178),
            decrementButton.widthAnchor.constraint(equalToConstant: 40),
            incrementButton.widthAnchor.constraint(equalToConstant: 40),
            leftSeparator.widthAnchor.constraint(equalToConstant: 1),
            rightSeparator.widthAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        updateControlState()
    }

    private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: symbol == "minus" ? "减小阈值" : "增大阈值"
        )?.withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.focusRingType = .none
        button.target = self
        button.action = action
    }

    @objc private func decrementValue() { moveSelection(by: -1) }

    @objc private func incrementValue() { moveSelection(by: 1) }

    private func moveSelection(by delta: Int) {
        let nextIndex = selectedIndex + delta
        guard values.indices.contains(nextIndex) else { return }
        selectedIndex = nextIndex
        updateControlState()
        sendAction(action, to: target)
    }

    private func updateControlState() {
        valueLabel.stringValue = selectedTitle ?? unavailableTitle ?? "—"
        decrementButton.isEnabled = isEnabled && selectedIndex > 0
        incrementButton.isEnabled = isEnabled && selectedIndex < values.count - 1
        decrementButton.contentTintColor = decrementButton.isEnabled ? .labelColor : .tertiaryLabelColor
        incrementButton.contentTintColor = incrementButton.isEnabled ? .labelColor : .tertiaryLabelColor
        valueLabel.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        alphaValue = isEnabled ? 1 : 0.72
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 11
        layer?.borderWidth = 0.8
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.20)
            : NSColor.black.withAlphaComponent(0.18)).cgColor
        layer?.backgroundColor = (dark
            ? NSColor.white.withAlphaComponent(0.075)
            : NSColor.black.withAlphaComponent(0.035)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

private class TasteActionButton: NSButton {
    enum Role {
        case primary
        case secondary
        case icon
    }

    var role: Role = .secondary {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var wantsUpdateLayer: Bool { true }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if role != .icon { size.width += 22 }
        return size
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 12.5, weight: .semibold)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
        animateScale(1.025)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
        animateScale(1)
    }

    override func mouseDown(with event: NSEvent) {
        animateScale(0.965, duration: 0.08)
        super.mouseDown(with: event)
        animateScale(hovered ? 1.025 : 1, duration: 0.14)
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = dark ? NSColor.white : NSColor.black
        let foreground = dark ? NSColor.black : NSColor.white
        layer?.cornerRadius = role == .icon ? 9 : 8
        layer?.borderWidth = role == .primary ? 0 : 0.8
        layer?.borderColor = (dark
            ? NSColor.white.withAlphaComponent(hovered ? 0.34 : 0.16)
            : NSColor.black.withAlphaComponent(hovered ? 0.28 : 0.13)).cgColor
        switch role {
        case .primary:
            layer?.backgroundColor = accent.withAlphaComponent(hovered ? 0.84 : 1).cgColor
            contentTintColor = foreground
        case .secondary, .icon:
            layer?.backgroundColor = (dark
                ? NSColor.white.withAlphaComponent(hovered ? 0.13 : 0.06)
                : NSColor.black.withAlphaComponent(hovered ? 0.08 : 0.025)).cgColor
            contentTintColor = .labelColor
        }
        alphaValue = isEnabled ? 1 : 0.45
    }

    private func animateScale(_ scale: CGFloat, duration: CFTimeInterval = 0.16) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
}

private final class ProviderActionButton: TasteActionButton {
    var providerID: String?
    var representsOfficial = false
}

private final class VendorChoiceButton: NSButton {
    var vendor: ProviderVendor = .custom
    private var choiceSelected = false

    override var wantsUpdateLayer: Bool { true }

    func setChoiceSelected(_ selected: Bool) {
        choiceSelected = selected
        needsDisplay = true
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 12
        layer?.borderWidth = choiceSelected ? 1.6 : 0.7
        layer?.borderColor = choiceSelected
            ? NSColor.labelColor.cgColor
            : (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.10)).cgColor
        layer?.backgroundColor = choiceSelected
            ? NSColor.labelColor.withAlphaComponent(dark ? 0.16 : 0.07).cgColor
            : (dark ? NSColor(calibratedWhite: 0.17, alpha: 1) : NSColor.white).cgColor
        contentTintColor = .labelColor
    }
}

private final class StatusStyleButton: NSButton {
    var style: StatusIconStyle = .trafficLight
    private var choiceSelected = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var wantsUpdateLayer: Bool { true }

    func setChoiceSelected(_ selected: Bool) {
        choiceSelected = selected
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
        animateScale(1.015)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
        animateScale(1)
    }

    override func mouseDown(with event: NSEvent) {
        animateScale(0.975, duration: 0.08)
        super.mouseDown(with: event)
        animateScale(hovered ? 1.015 : 1, duration: 0.14)
    }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 14
        layer?.borderWidth = choiceSelected ? 1.5 : 0.7
        layer?.borderColor = choiceSelected
            ? (dark
                ? NSColor.white.withAlphaComponent(0.76)
                : NSColor.black.withAlphaComponent(0.66)).cgColor
            : (dark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)).cgColor
        layer?.backgroundColor = choiceSelected
            ? (dark
                ? NSColor.white.withAlphaComponent(0.13)
                : NSColor.black.withAlphaComponent(0.055)).cgColor
            : (dark
                ? NSColor(calibratedWhite: hovered ? 0.22 : 0.18, alpha: 1)
                : NSColor(calibratedWhite: hovered ? 0.965 : 0.985, alpha: 1)).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = hovered || choiceSelected ? 8 : 4
        layer?.shadowOpacity = hovered ? 0.10 : (choiceSelected ? 0.07 : 0.025)
        contentTintColor = .labelColor
    }

    private func animateScale(_ scale: CGFloat, duration: CFTimeInterval = 0.16) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum AppThemePreference {
    private static let key = "appTheme"

    static var selected: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let theme = AppTheme(rawValue: raw) else { return .system }
            return theme
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    @MainActor
    static func apply(_ theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private struct AlertThresholdContext {
        let modelKey: String
        let title: String
        let metric: UsageAlertMetricKind?
    }

    private enum Section: Int {
        case dashboard, route, providerEditor, monitoring, security, appearance, version

        static let navigation: [Section] = [.dashboard, .route, .monitoring, .security, .appearance, .version]

        var title: String {
            switch self {
            case .dashboard: return "仪表盘"
            case .route: return "模型与路由"
            case .providerEditor: return "提供商配置"
            case .monitoring: return "监控与历史"
            case .security: return "配置与安全"
            case .appearance: return "状态与外观"
            case .version: return "版本"
            }
        }

        var symbol: String {
            switch self {
            case .dashboard: return "chart.bar.xaxis"
            case .route: return "arrow.triangle.branch"
            case .providerEditor: return "server.rack"
            case .monitoring: return "waveform.path.ecg"
            case .security: return "lock.shield"
            case .appearance: return "circle.lefthalf.filled"
            case .version: return "arrow.triangle.2.circlepath"
            }
        }
    }

    weak var appDelegate: AppDelegate?
    private var providers: [ProviderProfile] = []
    private var selectedProviderID: String?
    private var pages: [Section: NSView] = [:]
    private var sidebarButtons: [Section: NSButton] = [:]
    private var selectedSection = Section.dashboard
    private var providerRows: [String: TasteCardView] = [:]
    private var providerBalanceLabels: [String: NSTextField] = [:]
    private var modelTestLabels: [String: NSTextField] = [:]
    private var modelTestMessages: [String: (text: String, color: NSColor, detail: String?)] = [:]
    private var providerBalances: [String: String] = [:]
    private var providerBalanceUpdatedAt: [String: Date] = [:]
    private var providerBalanceRefreshesInFlight: Set<String> = []
    private weak var officialBalanceLabel: NSTextField?
    private let pageHost = NSView()
    private let modelListStack = NSStackView()
    private let addProviderButton = TasteActionButton()
    private let editorAgentLabel = NSTextField(labelWithString: "")
    private let dashboardAgentValue = NSTextField(labelWithString: "—")
    private let dashboardRouteValue = NSTextField(labelWithString: "—")
    private let dashboardTaskValue = NSTextField(labelWithString: "—")
    private let dashboardTaskIndicator = NSImageView()
    private let dashboardUsageTitle = NSTextField(labelWithString: "用量")
    private let dashboardUsageValue = NSTextField(labelWithString: "—")
    private let dashboardUsageDetail = NSTextField(wrappingLabelWithString: "正在等待数据")
    private let dashboardUpdatedLabel = NSTextField(labelWithString: "等待首次刷新")
    private let dashboardVersionLabel = NSTextField(labelWithString: AppUpdateChecker.currentVersion)
    private let dashboardMessageLabel = NSTextField(wrappingLabelWithString: "运行状态正常")
    private let dashboardRefreshButton = TasteActionButton(title: "立即刷新", target: nil, action: nil)
    private let usageAlertSwitch = NSSwitch()
    private let alertThresholdControl = TasteValueStepper()
    private let alertContextLabel = NSTextField(wrappingLabelWithString: "尚未读取当前模型")
    private let historySummaryLabel = NSTextField(wrappingLabelWithString: "尚无本地历史")
    private let resetCountdownLabel = NSTextField(labelWithString: "当前数据暂无重置时间")
    private let historyChart = UsageHistoryChartView()
    private let exportHistoryButton = TasteActionButton(title: "导出 CSV", target: nil, action: nil)
    private let healthStack = NSStackView()
    private let checkRoutesButton = TasteActionButton(title: "检测全部", target: nil, action: nil)
    private let backupPopup = TastePopUpButton()
    private let backupSummaryLabel = NSTextField(wrappingLabelWithString: "尚无配置备份")
    private let backupDiffText = NSTextView()
    private let createBackupButton = TasteActionButton(title: "创建备份", target: nil, action: nil)
    private let restoreBackupButton = TasteActionButton(title: "恢复", target: nil, action: nil)
    private let exportConfigButton = TasteActionButton(title: "脱敏导出", target: nil, action: nil)
    private let importConfigButton = TasteActionButton(title: "导入", target: nil, action: nil)
    private var backupRecords: [ConfigBackupRecord] = []

    private let agentControl = NSSegmentedControl(
        labels: AgentKind.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let routeControl = NSSegmentedControl(
        labels: ["OpenAI 官方", "第三方提供商"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let routeDescription = NSTextField(wrappingLabelWithString: "")
    private let routeProviderPopup = NSPopUpButton()
    private let modelProviderField = NSTextField()
    private let saveModelProviderButton = TasteActionButton(title: "保存", target: nil, action: nil)
    private let resetModelProviderButton = TasteActionButton(title: "恢复 openai", target: nil, action: nil)
    private let cursorBalanceProviderPopup = NSPopUpButton()
    private let cursorOfficialUsageSwitch = NSSwitch()
    private let providerPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let keyField = NSSecureTextField()
    private let protocolPopup = NSPopUpButton()
    private let testProviderButton = TasteActionButton(title: "测试连接", target: nil, action: nil)
    private var selectedVendor: ProviderVendor = .deepSeek
    private var vendorButtons: [ProviderVendor: VendorChoiceButton] = [:]
    private let customProviderFields = NSStackView()
    private let providerPresetSummary = NSTextField(wrappingLabelWithString: "")
    private let balanceCapabilityLabel = NSTextField(wrappingLabelWithString: "")
    private let themeControl = NSSegmentedControl(
        labels: AppTheme.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private var statusStyleButtons: [StatusIconStyle: StatusStyleButton] = [:]
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let cursorModelsButton = TasteActionButton(title: "打开模型设置", target: nil, action: nil)
    private let confirmButton = TasteActionButton(title: "应用并打开", target: nil, action: nil)
    private let currentVersionLabel = NSTextField(labelWithString: AppUpdateChecker.currentVersion)
    private let updateStatusLabel = NSTextField(wrappingLabelWithString: "尚未检查更新")
    private let checkUpdateButton = TasteActionButton(title: "检查更新", target: nil, action: nil)
    private let installUpdateButton = TasteActionButton(title: "立即更新", target: nil, action: nil)
    private let openProjectButton = TasteActionButton(title: "打开项目主页", target: nil, action: nil)
    private var availableUpdate: AppUpdateStatus?
    private weak var codexRouteCard: NSView?
    private weak var cursorRouteCard: NSView?
    private weak var modelProviderCard: NSView?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Pulse"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .windowBackgroundColor
                : .white
        }
        window.minSize = NSSize(width: 900, height: 680)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let sidebar = SettingsSidebarView()
        sidebar.wantsLayer = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let appMark = NSImageView(image: NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: nil)!)
        appMark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        appMark.contentTintColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        }
        let markBox = NSBox()
        markBox.boxType = .custom
        markBox.borderWidth = 0
        markBox.cornerRadius = 9
        markBox.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
        }
        appMark.translatesAutoresizingMaskIntoConstraints = false
        markBox.contentView?.addSubview(appMark)
        NSLayoutConstraint.activate([
            markBox.widthAnchor.constraint(equalToConstant: 34),
            markBox.heightAnchor.constraint(equalToConstant: 34),
            appMark.centerXAnchor.constraint(equalTo: markBox.contentView!.centerXAnchor),
            appMark.centerYAnchor.constraint(equalTo: markBox.contentView!.centerYAnchor)
        ])
        let appName = NSTextField(labelWithString: "Agent Pulse")
        appName.font = displayFont(size: 15, weight: .semibold)
        let appSubtitle = NSTextField(labelWithString: "Agent control center")
        appSubtitle.font = .systemFont(ofSize: 10.5, weight: .regular)
        appSubtitle.textColor = .secondaryLabelColor
        let brandText = NSStackView(views: [appName, appSubtitle])
        brandText.orientation = .vertical
        brandText.alignment = .leading
        brandText.spacing = 2
        let appRow = NSStackView(views: [markBox, brandText])
        appRow.orientation = .horizontal
        appRow.alignment = .centerY
        appRow.spacing = 11

        let navigation = NSStackView()
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 6
        for section in Section.navigation {
            let button = makeSidebarButton(section)
            sidebarButtons[section] = button
            navigation.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
        }
        let sidebarStack = NSStackView(views: [appRow, navigation, NSView()])
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 23
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)
        navigation.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true

        let main = SettingsPageView()
        main.wantsLayer = true
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)

        pageHost.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(pageHost)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.isSelectable = true
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.keyEquivalent = "\r"
        confirmButton.role = .primary
        confirmButton.font = .systemFont(ofSize: 13, weight: .semibold)
        confirmButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        confirmButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        stylePrimaryButton()
        let cancelButton = TasteActionButton(title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.role = .secondary
        cancelButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let footer = NSStackView(views: [statusLabel, NSView(), cancelButton, confirmButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 9
        footer.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(footer)

        let footerLine = NSBox()
        footerLine.boxType = .separator
        footerLine.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(footerLine)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 52),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),

            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            main.topAnchor.constraint(equalTo: content.topAnchor),
            main.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            pageHost.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: main.topAnchor),
            pageHost.bottomAnchor.constraint(equalTo: footerLine.topAnchor),

            footerLine.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            footerLine.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 34),
            footer.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -34),
            footer.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -17),
            footer.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 330)
        ])

        configureControls()
        pages[.dashboard] = buildDashboardPage()
        pages[.route] = buildRoutePage()
        pages[.providerEditor] = buildProvidersPage()
        pages[.monitoring] = buildMonitoringPage()
        pages[.security] = buildSecurityPage()
        pages[.appearance] = buildAppearancePage()
        pages[.version] = buildVersionPage()
        pages.values.forEach { enableTextInteraction(in: $0) }
        enableTextInteraction(in: footer)
        selectSection(.dashboard)
    }

    private func enableTextInteraction(in view: NSView) {
        if let field = view as? NSTextField {
            field.isSelectable = true
            if !field.isEditable {
                field.refusesFirstResponder = false
                field.focusRingType = .none
            }
        }
        view.subviews.forEach(enableTextInteraction)
    }

    private func configureControls() {
        agentControl.target = self
        agentControl.action = #selector(agentChanged)
        agentControl.controlSize = .large
        agentControl.font = .systemFont(ofSize: 14.5, weight: .semibold)
        agentControl.heightAnchor.constraint(equalToConstant: 52).isActive = true
        for index in AgentKind.allCases.indices {
            agentControl.setWidth(150, forSegment: index)
        }
        routeControl.target = self
        routeControl.action = #selector(routeChanged)
        routeControl.setWidth(142, forSegment: 0)
        routeControl.setWidth(142, forSegment: 1)
        routeProviderPopup.target = self
        routeProviderPopup.action = #selector(routeProviderChanged)
        routeProviderPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        modelProviderField.placeholderString = "openai"
        modelProviderField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        modelProviderField.toolTip = "Codex config.toml 的顶层 model_provider"
        saveModelProviderButton.target = self
        saveModelProviderButton.action = #selector(saveModelProvider)
        saveModelProviderButton.role = .secondary
        saveModelProviderButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        resetModelProviderButton.target = self
        resetModelProviderButton.action = #selector(resetModelProvider)
        resetModelProviderButton.role = .secondary
        resetModelProviderButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        cursorBalanceProviderPopup.target = self
        cursorBalanceProviderPopup.action = #selector(cursorBalanceProviderChanged)
        cursorBalanceProviderPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        cursorOfficialUsageSwitch.target = self
        cursorOfficialUsageSwitch.action = #selector(cursorOfficialUsageChanged)
        usageAlertSwitch.target = self
        usageAlertSwitch.action = #selector(usageAlertsChanged)
        alertThresholdControl.target = self
        alertThresholdControl.action = #selector(alertThresholdChanged)
        exportHistoryButton.target = self
        exportHistoryButton.action = #selector(exportUsageHistory)
        exportHistoryButton.role = .secondary
        checkRoutesButton.target = self
        checkRoutesButton.action = #selector(checkAllRoutes)
        checkRoutesButton.role = .primary
        backupPopup.target = self
        backupPopup.action = #selector(backupSelectionChanged)
        createBackupButton.target = self
        createBackupButton.action = #selector(createConfigBackup)
        restoreBackupButton.target = self
        restoreBackupButton.action = #selector(restoreConfigBackup)
        exportConfigButton.target = self
        exportConfigButton.action = #selector(exportSanitizedConfig)
        importConfigButton.target = self
        importConfigButton.action = #selector(importSanitizedConfig)
        [createBackupButton, restoreBackupButton, exportConfigButton, importConfigButton, exportHistoryButton, checkRoutesButton].forEach {
            $0.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        configureActionButton(createBackupButton, symbol: "plus", role: .primary)
        configureActionButton(restoreBackupButton, symbol: "arrow.counterclockwise", role: .secondary)
        configureActionButton(exportConfigButton, symbol: "square.and.arrow.up", role: .secondary)
        configureActionButton(importConfigButton, symbol: "square.and.arrow.down", role: .secondary)
        configureActionButton(exportHistoryButton, symbol: "tablecells", role: .secondary)
        configureActionButton(checkRoutesButton, symbol: "bolt.horizontal.circle", role: .primary)
        backupPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true
        checkUpdateButton.target = self
        checkUpdateButton.action = #selector(checkForUpdates)
        installUpdateButton.target = self
        installUpdateButton.action = #selector(installAvailableUpdate)
        installUpdateButton.role = .primary
        installUpdateButton.isHidden = true
        openProjectButton.target = self
        openProjectButton.action = #selector(openProjectPage)
        openProjectButton.role = .secondary
        checkUpdateButton.role = .secondary
        [openProjectButton, checkUpdateButton, installUpdateButton].forEach {
            $0.heightAnchor.constraint(equalToConstant: 34).isActive = true
        }
        routeDescription.textColor = .secondaryLabelColor
        routeDescription.font = .systemFont(ofSize: 12)
        routeDescription.isSelectable = true

        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        nameField.placeholderString = "例如：公司代理"
        baseURLField.placeholderString = "https://api.example.com"
        modelField.placeholderString = "例如：gpt-5.6-sol"
        keyField.placeholderString = "sk-…"
        protocolPopup.addItem(withTitle: ProviderAPIFormat.responses.displayName)
        protocolPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        testProviderButton.target = self
        testProviderButton.action = #selector(testProviderConnection)
        testProviderButton.role = .secondary
        testProviderButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        providerPresetSummary.font = .systemFont(ofSize: 11.5)
        providerPresetSummary.textColor = .secondaryLabelColor
        providerPresetSummary.maximumNumberOfLines = 2
        providerPresetSummary.isSelectable = true
        balanceCapabilityLabel.font = .systemFont(ofSize: 11.5)
        balanceCapabilityLabel.textColor = .secondaryLabelColor
        balanceCapabilityLabel.maximumNumberOfLines = 2
        balanceCapabilityLabel.isSelectable = true
        cursorModelsButton.target = self
        cursorModelsButton.action = #selector(openCursorModels)

        themeControl.target = self
        themeControl.action = #selector(themeChanged)
        for index in AppTheme.allCases.indices {
            themeControl.setWidth(112, forSegment: index)
        }

        dashboardRefreshButton.target = self
        dashboardRefreshButton.action = #selector(refreshDashboardData)
        dashboardRefreshButton.role = .secondary
        dashboardRefreshButton.imageHugsTitle = true
        dashboardRefreshButton.imageScaling = .scaleProportionallyDown
        dashboardRefreshButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        addProviderButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "添加提供商"
        )?.withSymbolConfiguration(.init(pointSize: 13.5, weight: .semibold))
        addProviderButton.toolTip = "添加提供商"
        addProviderButton.target = self
        addProviderButton.action = #selector(openAddProviderPage)
        addProviderButton.role = .primary
        addProviderButton.isBordered = false
        addProviderButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        addProviderButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        cursorModelsButton.image = NSImage(
            systemSymbolName: "arrow.up.right.square",
            accessibilityDescription: "打开 Cursor Models 设置"
        )
        cursorModelsButton.imagePosition = .imageLeading
        cursorModelsButton.imageHugsTitle = true
        cursorModelsButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        cursorModelsButton.role = .secondary
        cursorModelsButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        styleSegmentedControls()

        modelListStack.orientation = .vertical
        modelListStack.alignment = .leading
        modelListStack.distribution = .fill
        modelListStack.spacing = 10

        editorAgentLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        editorAgentLabel.textColor = .secondaryLabelColor

    }

    private func buildDashboardPage() -> NSView {
        let metricCells = [
            metricCell(title: "当前 Agent", symbol: "terminal", value: dashboardAgentValue),
            metricCell(title: "当前路由", symbol: "arrow.triangle.branch", value: dashboardRouteValue),
            metricCell(
                title: "任务状态",
                symbol: "circle.fill",
                value: dashboardTaskValue,
                iconView: dashboardTaskIndicator
            )
        ]
        let metrics = NSStackView(views: [
            metricCells[0], verticalSeparator(),
            metricCells[1], verticalSeparator(),
            metricCells[2]
        ])
        metrics.orientation = .horizontal
        metrics.alignment = .centerY
        metrics.spacing = 0
        metricCells[0].widthAnchor.constraint(equalTo: metricCells[1].widthAnchor).isActive = true
        metricCells[1].widthAnchor.constraint(equalTo: metricCells[2].widthAnchor).isActive = true
        let metricsCard = card([padded(metrics, horizontal: 0, vertical: 0)])
        metricsCard.heightAnchor.constraint(equalToConstant: 126).isActive = true

        dashboardUsageTitle.font = .systemFont(ofSize: 12, weight: .medium)
        dashboardUsageTitle.textColor = featureSecondaryColor()
        dashboardUsageValue.font = displayFont(size: 36, weight: .bold)
        dashboardUsageValue.textColor = featurePrimaryColor()
        dashboardUsageValue.maximumNumberOfLines = 1
        dashboardUsageValue.lineBreakMode = .byTruncatingTail
        dashboardUsageValue.isSelectable = true
        dashboardUsageDetail.font = .systemFont(ofSize: 12)
        dashboardUsageDetail.textColor = featureSecondaryColor()
        dashboardUsageDetail.maximumNumberOfLines = 2
        dashboardUsageDetail.isSelectable = true
        let usageText = NSStackView(views: [dashboardUsageTitle, dashboardUsageValue, dashboardUsageDetail])
        usageText.orientation = .vertical
        usageText.alignment = .leading
        usageText.spacing = 8
        let usageSymbol = NSImageView(image: NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis",
            accessibilityDescription: nil
        )!)
        usageSymbol.symbolConfiguration = .init(pointSize: 32, weight: .light)
        usageSymbol.contentTintColor = featureSecondaryColor()
        let usageRow = NSStackView(views: [usageText, NSView(), usageSymbol])
        usageRow.orientation = .horizontal
        usageRow.alignment = .centerY
        usageRow.spacing = 22
        let usageCard = featureCard([padded(usageRow, horizontal: 24, vertical: 21)])
        usageCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 138).isActive = true

        dashboardUpdatedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dashboardUpdatedLabel.textColor = .secondaryLabelColor
        dashboardUpdatedLabel.isSelectable = true
        dashboardVersionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        dashboardVersionLabel.isSelectable = true
        dashboardMessageLabel.font = .systemFont(ofSize: 12)
        dashboardMessageLabel.maximumNumberOfLines = 2
        dashboardMessageLabel.isSelectable = true
        dashboardRefreshButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "立即刷新"
        )?.withSymbolConfiguration(.init(pointSize: 12.5, weight: .semibold))
        dashboardRefreshButton.image?.isTemplate = true
        dashboardRefreshButton.imagePosition = .imageLeading
        dashboardRefreshButton.imageHugsTitle = true
        dashboardRefreshButton.imageScaling = .scaleProportionallyDown

        return page(
            title: "仪表盘",
            subtitle: "在一个清晰的视图中掌握 Agent、路由、用量与任务进度。",
            cards: [
                metricsCard,
                usageCard,
                card([
                    settingRow(
                        title: "运行状态",
                        detail: "连接、鉴权与状态同步反馈。",
                        control: dashboardMessageLabel
                    ),
                    separator(),
                    settingRow(title: "最近更新", detail: "仪表盘数据更新时间。", control: dashboardUpdatedLabel),
                    separator(),
                    settingRow(
                        title: "Agent Pulse \(AppUpdateChecker.currentVersion)",
                        detail: "用量每分钟自动更新，也可以立即刷新。",
                        control: dashboardRefreshButton
                    )
                ], interactive: true)
            ]
        )
    }

    private func metricCell(
        title: String,
        symbol: String,
        value: NSTextField,
        iconView: NSImageView? = nil
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        let icon = iconView ?? NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        let heading = NSStackView(views: [icon, titleLabel, NSView()])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 7
        value.font = .systemFont(ofSize: 17, weight: .semibold)
        value.maximumNumberOfLines = 2
        value.lineBreakMode = .byTruncatingTail
        value.isSelectable = true
        let content = NSStackView(views: [heading, value, NSView()])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 11
        return padded(content, horizontal: 20, vertical: 17)
    }

    private func buildRoutePage() -> NSView {
        let agentRow = settingRow(
            title: "Agent",
            detail: "模型列表会随 Agent 切换，每个配置只出现在绑定的 Agent 下。",
            control: agentControl
        )

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        modelListStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(modelListStack)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            modelListStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            modelListStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            modelListStack.topAnchor.constraint(equalTo: document.topAnchor),
            modelListStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 390)
        ])

        let modelProviderActions = NSStackView(
            views: [modelProviderField, saveModelProviderButton, resetModelProviderButton]
        )
        modelProviderActions.orientation = .horizontal
        modelProviderActions.alignment = .centerY
        modelProviderActions.spacing = 8
        let modelProviderRow = settingRow(
            title: "Model Provider",
            detail: "读取并编辑 Codex config.toml 中的 model_provider 字段。只修改配置，不修改会话数据库。",
            control: modelProviderActions
        )
        let modelProviderCard = card([modelProviderRow], interactive: true)
        self.modelProviderCard = modelProviderCard

        return page(
            title: "模型与路由",
            subtitle: "选择 Agent，管理 Agent Pulse 当前能够连接的模型与路由。",
            headerAccessory: addProviderButton,
            cards: [
                card([agentRow], interactive: true),
                modelProviderCard,
                scroll
            ]
        )
    }

    private func reloadModelList() {
        modelListStack.arrangedSubviews.forEach {
            modelListStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        providerRows.removeAll(keepingCapacity: true)
        providerBalanceLabels.removeAll(keepingCapacity: true)
        modelTestLabels.removeAll(keepingCapacity: true)
        officialBalanceLabel = nil

        let agent = selectedAgent()
        modelProviderCard?.isHidden = !agent.supportsModelProviderConfiguration
        addProviderButton.isHidden = agent == .cursor
        let official = makeModelRow(provider: nil, agent: agent)
        modelListStack.addArrangedSubview(official)
        official.widthAnchor.constraint(equalTo: modelListStack.widthAnchor).isActive = true

        if agent == .cursor {
            let guidance = makeCursorManagementCard()
            modelListStack.addArrangedSubview(guidance)
            guidance.widthAnchor.constraint(equalTo: modelListStack.widthAnchor).isActive = true
            addModelListSpacer()
            return
        }

        let visibleProviders = providers.filter { $0.supports(agent) }
        for provider in visibleProviders {
            let row = makeModelRow(provider: provider, agent: agent)
            modelListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: modelListStack.widthAnchor).isActive = true
        }
        addModelListSpacer()
        refreshProviderBalances(visibleProviders, agent: agent)
    }

    private func addModelListSpacer() {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        modelListStack.addArrangedSubview(spacer)
        spacer.widthAnchor.constraint(equalTo: modelListStack.widthAnchor).isActive = true
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
    }

    private func makeCursorManagementCard() -> TasteCardView {
        let card = TasteCardView()
        card.boxType = .custom
        card.respondsToHover = true
        card.cornerRadius = 14
        card.borderWidth = 0.7
        card.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)
        }
        card.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : .white
        }

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "slider.horizontal.3",
            accessibilityDescription: nil
        )!)
        icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let title = NSTextField(labelWithString: "第三方模型由 Cursor 管理")
        title.font = displayFont(size: 14, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString:
            "Agent Pulse 目前支持 Cursor 官方用量与任务状态；自定义模型请前往 Cursor Settings → Models 配置。"
        )
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5

        let content = NSStackView(views: [icon, text, NSView(), cursorModelsButton])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 13
        content.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 92),
            content.leadingAnchor.constraint(equalTo: card.contentView!.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: card.contentView!.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.contentView!.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.contentView!.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeModelRow(provider: ProviderProfile?, agent: AgentKind) -> TasteCardView {
        let key = provider?.id ?? "official"
        let row = ModelBannerView()
        row.boxType = .custom
        row.respondsToHover = true
        row.wantsLayer = true
        row.cornerRadius = 14
        row.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : .white
        }
        row.providerID = provider?.id
        row.representsOfficial = provider == nil
        row.actionTarget = self
        row.bannerAction = #selector(modelBannerSelected(_:))
        row.setSelectedFlow(isModelSelected(key, agent: agent))
        row.heightAnchor.constraint(equalToConstant: 80).isActive = true
        providerRows[key] = row

        let icon = routeIconView(provider: provider, agent: agent)

        let name = NSTextField(labelWithString: provider?.name ?? officialProviderName(for: agent))
        name.font = displayFont(size: 14, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        let model = NSTextField(labelWithString: provider?.model ?? officialModelDescription(for: agent))
        model.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        model.textColor = .secondaryLabelColor
        model.lineBreakMode = .byTruncatingMiddle
        let identity = NSStackView(views: [name, model])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 5
        identity.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        let left = NSStackView(views: [icon, identity])
        left.orientation = .horizontal
        left.alignment = .centerY
        left.spacing = 12

        let balance = NSTextField(labelWithString: balanceText(for: provider, agent: agent))
        balance.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        balance.textColor = .labelColor
        balance.alignment = .right
        balance.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        if let provider {
            providerBalanceLabels[provider.id] = balance
        } else {
            officialBalanceLabel = balance
        }

        let testPresentation = modelTestPresentation(key: key, provider: provider)
        let testStatus = NSTextField(labelWithString: testPresentation.text)
        testStatus.font = .systemFont(ofSize: 10.5, weight: .medium)
        testStatus.textColor = testPresentation.color
        testStatus.alignment = .right
        testStatus.toolTip = testPresentation.detail
        testStatus.lineBreakMode = .byTruncatingTail
        testStatus.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        modelTestLabels[key] = testStatus
        let metrics = NSStackView(views: [balance, testStatus])
        metrics.orientation = .vertical
        metrics.alignment = .trailing
        metrics.spacing = 5

        let testButton = modelActionButton(
            symbol: "bolt.horizontal.circle",
            toolTip: "测试连接",
            action: #selector(testModelRow(_:)),
            provider: provider
        )
        var actionViews: [NSView] = [metrics, testButton]
        if let provider {
            let editButton = modelActionButton(
                symbol: "pencil",
                toolTip: "编辑提供商",
                action: #selector(editModelRow(_:)),
                provider: provider
            )
            actionViews.append(editButton)
            let deleteButton = modelActionButton(
                symbol: "trash",
                toolTip: "删除提供商",
                action: #selector(deleteModelRow(_:)),
                provider: provider
            )
            actionViews.append(deleteButton)
        }
        let actions = NSStackView(views: actionViews)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 7

        let content = NSStackView(views: [left, NSView(), actions])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        row.contentView?.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.contentView!.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: row.contentView!.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: row.contentView!.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: row.contentView!.bottomAnchor, constant: -14)
        ])
        return row
    }

    private func modelTestPresentation(
        key: String,
        provider: ProviderProfile?
    ) -> (text: String, color: NSColor, detail: String?) {
        if let value = modelTestMessages[key] { return value }
        guard let provider, let snapshot = RouteHealthStore.snapshot(for: provider.id) else {
            return ("未检测", .secondaryLabelColor, nil)
        }
        switch snapshot.state {
        case .healthy:
            let latency = snapshot.latencyMilliseconds.map { " · \($0) ms" } ?? ""
            return ("连接正常\(latency)", .systemGreen, snapshot.message)
        case .degraded:
            return ("服务可达", .systemOrange, snapshot.message)
        case .offline:
            return ("连接异常", .systemRed, snapshot.message)
        case .checking:
            return ("检测中…", .systemOrange, snapshot.message)
        case .unknown:
            return ("未检测", .secondaryLabelColor, snapshot.message)
        }
    }

    private func setModelTestPresentation(
        key: String,
        text: String,
        color: NSColor,
        detail: String? = nil
    ) {
        modelTestMessages[key] = (text, color, detail)
        modelTestLabels[key]?.stringValue = text
        modelTestLabels[key]?.textColor = color
        modelTestLabels[key]?.toolTip = detail
    }

    private func modelActionButton(
        symbol: String,
        toolTip: String,
        action: Selector,
        provider: ProviderProfile?
    ) -> ProviderActionButton {
        let button = ProviderActionButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.toolTip = toolTip
        button.target = self
        button.action = action
        button.providerID = provider?.id
        button.representsOfficial = provider == nil
        button.role = .icon
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func routeIconView(provider: ProviderProfile?, agent: AgentKind) -> NSView {
        let image: NSImage
        if let provider {
            if let logo = vendorLogoImage(provider.effectiveVendor) {
                image = logo
            } else {
                image = NSImage(
                    systemSymbolName: provider.effectiveVendor == .custom
                        ? "slider.horizontal.3"
                        : provider.effectiveVendor.symbolName,
                    accessibilityDescription: provider.name
                ) ?? NSImage(systemSymbolName: "server.rack", accessibilityDescription: provider.name)!
            }
        } else {
            let applicationURL: URL?
            switch agent {
            case .codex:
                applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: CodexLauncher.bundleIdentifier
                )
            case .cursor:
                applicationURL = CursorLauncher.applicationURL()
            case .hermes:
                applicationURL = HermesLauncher.applicationURL()
            }
            if let applicationURL {
                image = NSWorkspace.shared.icon(forFile: applicationURL.path)
            } else {
                let symbol: String
                switch agent {
                case .codex: symbol = "terminal.fill"
                case .cursor: symbol = "cursorarrow.rays"
                case .hermes: symbol = "sparkles"
                }
                image = NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: agent.displayName
                )!
            }
        }
        image.size = NSSize(width: 23, height: 23)

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let container = NSBox()
        container.boxType = .custom
        container.borderWidth = 0.7
        container.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)
        }
        container.cornerRadius = 10
        container.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.055)
                : NSColor.black.withAlphaComponent(0.025)
        }
        container.contentView?.addSubview(imageView)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 38),
            container.heightAnchor.constraint(equalToConstant: 38),
            imageView.widthAnchor.constraint(equalToConstant: 23),
            imageView.heightAnchor.constraint(equalToConstant: 23),
            imageView.centerXAnchor.constraint(equalTo: container.contentView!.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.contentView!.centerYAnchor)
        ])
        return container
    }

    private func officialProviderName(for agent: AgentKind) -> String {
        switch agent {
        case .codex: return "OpenAI 官方"
        case .cursor: return "Cursor 官方"
        case .hermes: return "Hermes 当前配置"
        }
    }

    private func officialModelDescription(for agent: AgentKind) -> String {
        switch agent {
        case .codex:
            return ProviderStore.officialModel() ?? "ChatGPT 登录模型"
        case .cursor:
            return "Cursor 官方模型"
        case .hermes:
            let config = HermesIntegration.readModelConfig()
            return "\(config.provider) · \(config.model)"
        }
    }

    private func balanceText(for provider: ProviderProfile?, agent: AgentKind) -> String {
        guard let provider else {
            if agent == .hermes {
                guard AgentPreference.selected == .hermes,
                      let snapshot = appDelegate?.dashboardSnapshot() else { return "应用后读取" }
                return snapshot.usageValue == "—" ? "Token —" : "Token \(snapshot.usageValue)"
            }
            if agent == .cursor && AgentPreference.selected != .cursor {
                return "应用后读取"
            }
            guard AgentPreference.selected == agent,
                  let snapshot = appDelegate?.dashboardSnapshot(),
                  snapshot.usageLabel.contains("官方") else { return "余额 —" }
            return "余额 \(snapshot.usageValue)"
        }
        if let value = providerBalances[provider.id] { return value }
        switch provider.effectiveVendor {
        case .zhipuAI, .miniMax: return "配额读取中"
        case .miMo: return "余额 控制台查看"
        case .custom: return provider.isCodeAPI ? "余额读取中" : "余额 —"
        default: return "余额读取中"
        }
    }

    private func isModelSelected(_ key: String, agent: AgentKind) -> Bool {
        if agent == .codex {
            if key == "official" { return routeControl.selectedSegment == 0 }
            return routeControl.selectedSegment == 1 && selectedProviderID == key
        }
        if agent == .hermes {
            if key == "official" { return selectedProviderID == nil }
            return selectedProviderID == key
        }
        return key == "official"
    }

    private func refreshProviderBalances(_ visibleProviders: [ProviderProfile], agent: AgentKind) {
        let now = Date()
        for provider in visibleProviders {
            if !provider.effectiveVendor.supportsBalanceLookup && !provider.isCodeAPI { continue }
            guard !providerBalanceRefreshesInFlight.contains(provider.id),
                  ProviderBalanceRefreshPolicy.shouldRefresh(
                      lastUpdated: providerBalanceUpdatedAt[provider.id],
                      now: now
                  ) else { continue }
            guard let key = CredentialStore.load(providerID: provider.id), !key.isEmpty else {
                storeProviderBalance("余额 未配置", providerID: provider.id, toolTip: nil)
                continue
            }
            let loadingText: String
            switch provider.effectiveVendor {
            case .zhipuAI, .miniMax: loadingText = "配额读取中"
            default: loadingText = "余额读取中"
            }
            if providerBalances[provider.id] == nil {
                providerBalances[provider.id] = loadingText
                providerBalanceLabels[provider.id]?.stringValue = loadingText
            }
            providerBalanceRefreshesInFlight.insert(provider.id)
            Task {
                defer { providerBalanceRefreshesInFlight.remove(provider.id) }
                do {
                    let managementKey = CredentialStore.load(
                        providerID: ProviderBalanceClient.managementCredentialID(for: provider.id)
                    )
                    let snapshot = try await ProviderBalanceClient.fetch(
                        profile: provider,
                        apiKey: key,
                        managementKey: managementKey
                    )
                    storeProviderBalance(
                        snapshot.displayText,
                        providerID: provider.id,
                        toolTip: snapshot.detail,
                        expectedAgent: agent
                    )
                } catch {
                    let unavailable = provider.effectiveVendor == .zhipuAI || provider.effectiveVendor == .miniMax
                        ? "配额不可用" : "余额不可用"
                    storeProviderBalance(
                        unavailable,
                        providerID: provider.id,
                        toolTip: error.localizedDescription,
                        expectedAgent: agent
                    )
                }
            }
        }
    }

    private func storeProviderBalance(
        _ text: String,
        providerID: String,
        toolTip: String?,
        expectedAgent: AgentKind? = nil
    ) {
        providerBalances[providerID] = text
        providerBalanceUpdatedAt[providerID] = Date()
        guard expectedAgent == nil || selectedAgent() == expectedAgent else { return }
        providerBalanceLabels[providerID]?.stringValue = text
        providerBalanceLabels[providerID]?.toolTip = toolTip
    }

    func providerBalanceDidRefresh(providerID: String, snapshot: ProviderBalanceSnapshot) {
        storeProviderBalance(
            snapshot.displayText,
            providerID: providerID,
            toolTip: snapshot.detail
        )
    }

    func refreshBalanceDisplaysIfVisible() {
        guard window?.isVisible == true, selectedSection == .route else { return }
        let agent = selectedAgent()
        officialBalanceLabel?.stringValue = balanceText(for: nil, agent: agent)
        refreshProviderBalances(providers.filter { $0.supports(agent) }, agent: agent)
    }

    @objc private func modelBannerSelected(_ sender: ModelBannerView) {
        let agent = selectedAgent()
        if agent == .cursor {
            selectedProviderID = nil
            cursorOfficialUsageSwitch.state = .on
            reloadModelList()
            statusLabel.stringValue = "Cursor 已使用官方连接；自定义模型请在 Cursor Models 中配置。"
            return
        }
        if agent == .hermes {
            selectedProviderID = sender.representsOfficial ? nil : sender.providerID
            reloadProviderPopups()
            reloadModelList()
            statusLabel.stringValue = "已选择模型，点击“应用并打开”使配置生效；运行中的任务不会重启。"
            return
        }
        if sender.representsOfficial {
            selectedProviderID = nil
            routeControl.selectedSegment = 0
        } else if let id = sender.providerID {
            selectedProviderID = id
            routeControl.selectedSegment = 1
        }
        reloadProviderPopups()
        reloadModelList()
        statusLabel.stringValue = "已选择模型，点击“应用并打开”使配置生效。"
    }

    @objc private func testModelRow(_ sender: ProviderActionButton) {
        sender.isEnabled = false
        let key = sender.providerID ?? "official"
        setModelTestPresentation(key: key, text: "检测中…", color: .systemOrange)
        let agent = selectedAgent()
        Task {
            defer { sender.isEnabled = true }
            do {
                if sender.representsOfficial {
                    if agent == .codex {
                        let usage = try await OfficialUsageClient.fetch()
                        guard usage.isLoggedIn else { throw SettingsError.officialNotLoggedIn }
                    } else if agent == .cursor {
                        _ = try await CursorOfficialUsageClient.fetch()
                    } else {
                        let status = HermesIntegration.readStatus()
                        guard status.isInstalled, status.cliAvailable,
                              status.modelConfig != .unavailable else {
                            throw HermesIntegrationError.invalidConfiguration
                        }
                    }
                    setModelTestPresentation(
                        key: key,
                        text: "连接正常",
                        color: .systemGreen,
                        detail: "\(officialProviderName(for: agent))连接正常。"
                    )
                    return
                }
                guard let id = sender.providerID,
                      let provider = providers.first(where: { $0.id == id }),
                      let key = CredentialStore.load(providerID: id), !key.isEmpty else {
                    throw SettingsError.missingCredential
                }
                let snapshot = await RouteHealthChecker.check(profile: provider, key: key)
                RouteHealthStore.save(snapshot)
                switch snapshot.state {
                case .healthy:
                    let latency = snapshot.latencyMilliseconds.map { " · \($0) ms" } ?? ""
                    setModelTestPresentation(
                        key: provider.id,
                        text: "连接正常\(latency)",
                        color: .systemGreen,
                        detail: snapshot.message
                    )
                case .degraded:
                    setModelTestPresentation(
                        key: provider.id,
                        text: "服务可达",
                        color: .systemOrange,
                        detail: snapshot.message
                    )
                case .offline:
                    setModelTestPresentation(
                        key: provider.id,
                        text: "连接异常",
                        color: .systemRed,
                        detail: snapshot.message
                    )
                case .checking, .unknown:
                    setModelTestPresentation(
                        key: provider.id,
                        text: snapshot.state.title,
                        color: .secondaryLabelColor,
                        detail: snapshot.message
                    )
                }
            } catch {
                setModelTestPresentation(
                    key: key,
                    text: "连接异常",
                    color: .systemRed,
                    detail: error.localizedDescription
                )
            }
        }
    }

    @objc private func editModelRow(_ sender: ProviderActionButton) {
        guard let id = sender.providerID else { return }
        selectedProviderID = id
        reloadProviderPopups()
        loadSelectedProvider()
        editorAgentLabel.stringValue = selectedAgent().displayName
        selectSection(.providerEditor)
    }

    @objc private func deleteModelRow(_ sender: ProviderActionButton) {
        guard let id = sender.providerID else { return }
        selectedProviderID = id
        deleteProvider()
    }

    @objc private func openAddProviderPage() {
        guard selectedAgent() != .cursor else {
            statusLabel.stringValue = "Cursor 的第三方模型请在 Cursor Models 中配置。"
            return
        }
        addProvider()
        editorAgentLabel.stringValue = selectedAgent().displayName
        selectSection(.providerEditor)
        window?.makeFirstResponder(nameField)
    }

    @objc private func returnToModelList() {
        reloadModelList()
        selectSection(.route)
    }

    private func buildProvidersPage() -> NSView {
        let backButton = TasteActionButton()
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "返回模型列表")
        backButton.toolTip = "返回模型列表"
        backButton.target = self
        backButton.action = #selector(returnToModelList)
        backButton.role = .icon
        backButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        backButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let deleteButton = TasteActionButton()
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除提供商")
        deleteButton.toolTip = "删除提供商"
        deleteButton.target = self
        deleteButton.action = #selector(deleteProvider)
        deleteButton.role = .icon
        deleteButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let headerActions = NSStackView(views: [deleteButton, backButton])
        headerActions.orientation = .horizontal
        headerActions.alignment = .centerY
        headerActions.spacing = 8
        let agentRow = settingRow(
            title: "绑定 Agent",
            detail: "保存后只会出现在当前 Agent 的模型列表中。",
            control: editorAgentLabel
        )

        vendorButtons.removeAll(keepingCapacity: true)
        let choices = ProviderVendor.presetChoices.map(makeVendorChoiceButton)
        let vendorGrid = NSGridView(views: stride(from: 0, to: choices.count, by: 4).map { index in
            (0..<4).map { offset in
                index + offset < choices.count ? choices[index + offset] : NSView()
            }
        })
        let vendorCells: [NSView] = choices
        for cell in vendorCells.dropFirst() {
            cell.widthAnchor.constraint(equalTo: vendorCells[0].widthAnchor).isActive = true
        }
        vendorGrid.rowSpacing = 12
        vendorGrid.columnSpacing = 12
        for index in 0..<4 { vendorGrid.column(at: index).xPlacement = .fill }
        for index in 0..<vendorGrid.numberOfRows { vendorGrid.row(at: index).yPlacement = .fill }
        let vendorHeading = sectionHeading(
            title: "选择厂商",
            detail: "预设已内置服务地址与推荐模型；图标靠左排列，选中项使用黑白高对比边框。"
        )
        let vendorSection = NSStackView(views: [vendorHeading, vendorGrid])
        vendorSection.orientation = .vertical
        vendorSection.alignment = .leading
        vendorSection.spacing = 16
        vendorGrid.widthAnchor.constraint(equalTo: vendorSection.widthAnchor).isActive = true

        let commonForm = makeEditorGrid([
            ("配置名", nameField),
            ("模型 ID", modelField),
            ("API Key", keyField)
        ])
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true

        let customGrid = makeEditorGrid([
            ("Base URL", baseURLField)
        ])
        customProviderFields.orientation = .vertical
        customProviderFields.alignment = .leading
        customProviderFields.spacing = 12
        customProviderFields.addArrangedSubview(separator())
        customProviderFields.addArrangedSubview(customGrid)
        customGrid.widthAnchor.constraint(equalTo: customProviderFields.widthAnchor).isActive = true

        let form = NSStackView(views: [
            commonForm,
            providerPresetSummary,
            customProviderFields,
            balanceCapabilityLabel
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 13
        commonForm.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        providerPresetSummary.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        customProviderFields.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        balanceCapabilityLabel.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        let formContainer = padded(form, horizontal: 24, vertical: 21)
        let saveButton = TasteActionButton(title: "保存提供商", target: self, action: #selector(saveProvider))
        saveButton.role = .primary
        saveButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let actions = NSStackView(views: [testProviderButton, saveButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        let footer = settingRow(
            title: "连接验证",
            detail: "发送一条最小请求验证地址、模型和 API Key。Key 只保存在本机。",
            control: actions
        )
        return page(
            title: "提供商配置",
            subtitle: "配置模型地址、协议和本地凭据，然后返回模型列表启用。",
            headerAccessory: headerActions,
            cards: [
                card([agentRow], interactive: true),
                card([padded(vendorSection, horizontal: 24, vertical: 21)], interactive: true),
                card([formContainer, separator(), footer], interactive: true)
            ]
        )
    }

    private func makeVendorChoiceButton(_ vendor: ProviderVendor) -> VendorChoiceButton {
        let button = VendorChoiceButton()
        button.vendor = vendor
        button.title = vendor.displayName
        let image: NSImage?
        if let logo = vendorLogoImage(vendor) {
            image = logo
        } else {
            let symbol = NSImage(systemSymbolName: vendor.symbolName, accessibilityDescription: vendor.displayName)
            image = symbol?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        }
        button.image = image.map { vendorImageWithLeadingPadding($0) }
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.isBordered = false
        button.wantsLayer = true
        button.target = self
        button.action = #selector(vendorChoiceChanged(_:))
        button.heightAnchor.constraint(equalToConstant: 62).isActive = true
        vendorButtons[vendor] = button
        return button
    }

    private func vendorImageWithLeadingPadding(_ source: NSImage) -> NSImage {
        let padding: CGFloat = 20
        let height = max(18, source.size.height)
        return NSImage(
            size: NSSize(width: source.size.width + padding, height: height),
            flipped: false
        ) { _ in
            source.draw(
                in: NSRect(
                    x: padding,
                    y: (height - source.size.height) / 2,
                    width: source.size.width,
                    height: source.size.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
    }

    private func vendorLogoImage(_ vendor: ProviderVendor) -> NSImage? {
        guard let resourceName = vendor.logoResourceName,
              let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: "VendorIcons"
              ),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = vendor == .miMo
            ? NSSize(width: 28, height: 12)
            : NSSize(width: 18, height: 18)
        image.isTemplate = false
        image.accessibilityDescription = vendor.displayName
        return image
    }

    private func makeVendorInfoCell() -> NSView {
        let symbol = NSImageView(image: NSImage(
            systemSymbolName: "checkmark.seal.fill",
            accessibilityDescription: nil
        )!)
        symbol.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        symbol.contentTintColor = .secondaryLabelColor
        let label = NSTextField(wrappingLabelWithString: "6 个预设\n开箱即用")
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        let row = NSStackView(views: [symbol, label, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let cell = padded(row, horizontal: 20, vertical: 12)
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 12
        cell.layer?.borderWidth = 0.7
        cell.layer?.borderColor = NSColor.separatorColor.cgColor
        cell.heightAnchor.constraint(equalToConstant: 62).isActive = true
        return cell
    }

    private func makeEditorGrid(_ fields: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: fields.map { [fieldLabel($0.0), $0.1] })
        grid.rowSpacing = 13
        grid.columnSpacing = 16
        grid.column(at: 0).width = 104
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func sectionHeading(title: String, detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = displayFont(size: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func buildMonitoringPage() -> NSView {
        historySummaryLabel.font = .systemFont(ofSize: 12)
        historySummaryLabel.textColor = .secondaryLabelColor
        historySummaryLabel.maximumNumberOfLines = 2
        historyChart.heightAnchor.constraint(equalToConstant: 92).isActive = true
        historyChart.wantsLayer = true
        historyChart.layer?.cornerRadius = 10
        historyChart.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor

        alertContextLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        alertContextLabel.textColor = .secondaryLabelColor
        alertContextLabel.maximumNumberOfLines = 3
        let alertsCard = card([
            settingRow(
                title: "用量预警",
                detail: "在剩余用量跨过阈值时发送一次本地通知，不上传账户信息。",
                control: usageAlertSwitch
            ),
            separator(),
            settingRow(
                title: "当前 Agent 与模型",
                detail: "阈值按模型分别保存，切换模型后自动读取对应设置。",
                control: alertContextLabel
            ),
            separator(),
            settingRow(
                title: "提醒阈值",
                detail: "官方配额使用剩余百分比；支持余额接口的提供商使用可用余额。",
                control: alertThresholdControl
            ),
            separator(),
            settingRow(
                title: "重置倒计时",
                detail: "跟随当前 Agent 与路由，用量刷新后自动更新。",
                control: resetCountdownLabel
            )
        ], interactive: true)

        healthStack.orientation = .vertical
        healthStack.alignment = .leading
        healthStack.spacing = 0
        let healthCard = card([
            settingRow(
                title: "路由健康",
                detail: "主动发送最小请求，检查地址、鉴权、模型与响应延迟。不会自动切换路由。",
                control: checkRoutesButton
            ),
            separator(),
            padded(healthStack, horizontal: 22, vertical: 8)
        ], interactive: true)

        let historyHeader = NSStackView(views: [historySummaryLabel, NSView(), exportHistoryButton])
        historyHeader.orientation = .horizontal
        historyHeader.alignment = .centerY
        historyHeader.spacing = 12
        let historyContent = NSStackView(views: [historyHeader, historyChart])
        historyContent.orientation = .vertical
        historyContent.alignment = .leading
        historyContent.spacing = 14
        historyHeader.widthAnchor.constraint(equalTo: historyContent.widthAnchor).isActive = true
        historyChart.widthAnchor.constraint(equalTo: historyContent.widthAnchor).isActive = true
        let historyCard = card([padded(historyContent, horizontal: 22, vertical: 18)], interactive: true)

        return page(
            title: "监控与历史",
            subtitle: "关注额度、重置时间与路由可用性，并把趋势保存在本机。",
            cards: [alertsCard, healthCard, historyCard]
        )
    }

    private func buildSecurityPage() -> NSView {
        backupSummaryLabel.font = .systemFont(ofSize: 12)
        backupSummaryLabel.textColor = .secondaryLabelColor
        backupSummaryLabel.maximumNumberOfLines = 2
        backupPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

        let selectionControls = NSStackView(views: [backupPopup, restoreBackupButton])
        selectionControls.orientation = .horizontal
        selectionControls.alignment = .centerY
        selectionControls.spacing = 8
        let backupActions = NSStackView(views: [createBackupButton, exportConfigButton, importConfigButton])
        backupActions.orientation = .horizontal
        backupActions.alignment = .centerY
        backupActions.spacing = 8

        backupDiffText.isEditable = false
        backupDiffText.isSelectable = true
        backupDiffText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        backupDiffText.textColor = .labelColor
        backupDiffText.backgroundColor = .clear
        backupDiffText.textContainerInset = NSSize(width: 12, height: 10)
        backupDiffText.isVerticallyResizable = true
        backupDiffText.isHorizontallyResizable = false
        backupDiffText.autoresizingMask = [.width]
        backupDiffText.textContainer?.widthTracksTextView = true
        backupDiffText.textContainer?.containerSize = NSSize(
            width: 10_000,
            height: CGFloat.greatestFiniteMagnitude
        )
        backupDiffText.frame = NSRect(x: 0, y: 0, width: 560, height: 190)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = backupDiffText
        scroll.heightAnchor.constraint(equalToConstant: 190).isActive = true

        return page(
            title: "配置与安全",
            subtitle: "备份路由配置、预览差异，并以不包含 API Key 的格式导入导出。",
            cards: [
                card([
                    settingRow(
                        title: "本地快照",
                        detail: "最多保留 20 份。恢复前会再次自动备份当前配置。",
                        control: backupActions
                    ),
                    separator(),
                    settingRow(
                        title: "选择备份",
                        detail: "只处理 config.toml 与提供商元数据，不读取或修改会话数据库。",
                        control: selectionControls
                    ),
                    separator(),
                    padded(backupSummaryLabel, horizontal: 22, vertical: 13)
                ], interactive: true),
                card([
                    padded(sectionHeading(title: "配置差异", detail: "敏感字段在预览与导出中始终脱敏。"), horizontal: 22, vertical: 15),
                    separator(),
                    padded(scroll, horizontal: 12, vertical: 8)
                ], interactive: true)
            ]
        )
    }

    private func buildAppearancePage() -> NSView {
        let themeRow = settingRow(
            title: "界面主题",
            detail: "选择跟随系统、浅色或深色，切换后立即生效。",
            control: themeControl
        )

        statusStyleButtons.removeAll(keepingCapacity: true)
        let buttons = StatusIconStyle.allCases.map(makeStatusStyleButton)
        let splitIndex = min(4, buttons.count)
        let topRow = NSStackView(views: Array(buttons.prefix(splitIndex)))
        let bottomRow = NSStackView(views: Array(buttons.dropFirst(splitIndex)))
        [topRow, bottomRow].forEach {
            $0.orientation = .horizontal
            $0.alignment = .centerY
            $0.distribution = .fillEqually
            $0.spacing = 9
        }
        let gallery = NSStackView(views: bottomRow.arrangedSubviews.isEmpty ? [topRow] : [topRow, bottomRow])
        gallery.orientation = .vertical
        gallery.alignment = .leading
        gallery.spacing = 9
        topRow.widthAnchor.constraint(equalTo: gallery.widthAnchor).isActive = true
        if !bottomRow.arrangedSubviews.isEmpty {
            bottomRow.widthAnchor.constraint(equalTo: gallery.widthAnchor).isActive = true
        }

        let styleHeading = appearanceSectionHeading(
            title: "菜单栏状态样式",
            detail: "预览并选择一种状态图标；黑白高对比边框表示当前样式。"
        )
        let styleGallery = padded(gallery, horizontal: 16, vertical: 14)
        let legend = NSStackView(views: [
            signalLegend(color: .systemRed, title: "执行中", detail: "正在请求模型"),
            verticalSeparator(),
            signalLegend(color: .systemYellow, title: "等待中", detail: "工具或命令运行"),
            verticalSeparator(),
            signalLegend(color: .systemGreen, title: "已就绪", detail: "可以继续输入")
        ])
        legend.orientation = .horizontal
        legend.alignment = .centerY
        legend.distribution = .fillEqually
        legend.spacing = 12

        return page(
            title: "状态与外观",
            subtitle: "调整界面主题与菜单栏状态反馈。",
            cards: [
                card([themeRow], interactive: true),
                card([styleHeading, separator(), styleGallery], interactive: true),
                card([padded(legend, horizontal: 18, vertical: 12)])
            ]
        )
    }

    private func makeStatusStyleButton(_ style: StatusIconStyle) -> StatusStyleButton {
        let button = StatusStyleButton(title: style.displayName, target: self, action: #selector(iconStyleChanged(_:)))
        button.style = style
        button.image = statusStyleImageWithTextSpacing(
            StatusIconRenderer.image(style: style, active: .green),
            spacing: 6
        )
        button.imagePosition = .imageAbove
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.alignment = .center
        button.isBordered = false
        button.wantsLayer = true
        button.font = displayFont(size: 12, weight: .semibold)
        button.toolTip = "切换为\(style.displayName)"
        button.heightAnchor.constraint(equalToConstant: 78).isActive = true
        button.setChoiceSelected(style == StatusIconPreference.selected)
        statusStyleButtons[style] = button
        return button
    }

    private func statusStyleImageWithTextSpacing(_ source: NSImage, spacing: CGFloat) -> NSImage {
        let size = NSSize(width: source.size.width, height: source.size.height + spacing)
        return NSImage(size: size, flipped: false) { _ in
            source.draw(
                in: NSRect(
                    x: 0,
                    y: spacing,
                    width: source.size.width,
                    height: source.size.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
    }

    private func appearanceSectionHeading(title: String, detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return padded(stack, horizontal: 18, vertical: 14)
    }

    private func signalLegend(color: NSColor, title: String, detail: String) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = color.cgColor
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [dot, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }

    private func buildVersionPage() -> NSView {
        currentVersionLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        currentVersionLabel.isSelectable = true
        updateStatusLabel.font = .systemFont(ofSize: 12)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.maximumNumberOfLines = 3
        updateStatusLabel.isSelectable = true
        let currentRow = settingRow(
            title: "当前版本",
            detail: "已安装的 Agent Pulse 版本。",
            control: currentVersionLabel
        )
        let actions = NSStackView(views: [openProjectButton, checkUpdateButton, installUpdateButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        let updateRow = settingRow(
            title: "软件更新",
            detail: "从 Agent Pulse 官方 GitHub 仓库检查最新版本。",
            control: actions
        )
        return page(
            title: "版本",
            subtitle: "查看当前版本并检查是否有可用更新。",
            cards: [
                card([currentRow, separator(), updateRow], interactive: true),
                card([padded(updateStatusLabel, vertical: 13)])
            ]
        )
    }

    private func page(
        title: String,
        subtitle: String,
        headerAccessory: NSView? = nil,
        cards: [NSView]
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = displayFont(size: 30, weight: .bold)
        titleLabel.isSelectable = true
        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.isSelectable = true
        let header = NSStackView(views: [titleLabel, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        let headerRow = NSStackView(views: [header, NSView()] + (headerAccessory.map { [$0] } ?? []))
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 14

        let stack = NSStackView(views: [headerRow] + cards + [NSView()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        ([headerRow] + cards).forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 38),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -38),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 48),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        return view
    }

    private func card(_ rows: [NSView], interactive: Bool = false) -> NSView {
        let box = TasteCardView()
        box.boxType = .custom
        box.respondsToHover = interactive
        box.wantsLayer = true
        box.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)
        }
        box.borderWidth = 0.7
        box.cornerRadius = 15
        box.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : .white
        }
        box.layer?.shadowColor = NSColor.black.cgColor
        box.layer?.shadowOffset = CGSize(width: 0, height: -2)
        box.layer?.shadowRadius = 10
        box.layer?.shadowOpacity = 0.04
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        return box
    }

    private func featureCard(_ rows: [NSView]) -> NSView {
        let box = TasteCardView()
        box.boxType = .custom
        box.wantsLayer = true
        box.cornerRadius = 17
        box.borderWidth = 0
        box.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.94, alpha: 1)
                : NSColor(calibratedWhite: 0.055, alpha: 1)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        return box
    }

    private func settingRow(title: String, detail: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.isSelectable = true
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.isSelectable = true
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return padded(row, horizontal: 22, vertical: 16)
    }

    private func padded(_ child: NSView, horizontal: CGFloat = 18, vertical: CGFloat = 10) -> NSView {
        let view = NSView()
        child.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontal),
            child.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontal),
            child.topAnchor.constraint(equalTo: view.topAnchor, constant: vertical),
            child.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -vertical)
        ])
        return view
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func verticalSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return box
    }

    private func displayFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: "Cabinet Grotesk", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private func featurePrimaryColor() -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        }
    }

    private func featureSecondaryColor() -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.black.withAlphaComponent(0.58)
                : NSColor.white.withAlphaComponent(0.62)
        }
    }

    private func stylePrimaryButton() {
        confirmButton.role = .primary
        confirmButton.needsDisplay = true
    }

    private func configureActionButton(
        _ button: TasteActionButton,
        symbol: String,
        role: TasteActionButton.Role
    ) {
        button.role = role
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: button.title
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
    }

    private func styleSegmentedControls() {
        let selectedColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
        }
        [agentControl, routeControl, themeControl].forEach { control in
            control.segmentStyle = .rounded
            control.selectedSegmentBezelColor = selectedColor
        }
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.isSelectable = true
        return label
    }

    private func makeSidebarButton(_ section: Section) -> NSButton {
        let button = NSButton(title: section.title, target: self, action: #selector(sidebarClicked(_:)))
        button.tag = section.rawValue
        button.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    @objc private func sidebarClicked(_ sender: NSButton) {
        guard let section = Section(rawValue: sender.tag) else { return }
        selectSection(section)
    }

    private func selectSection(_ section: Section) {
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        guard let page = pages[section] else { return }
        selectedSection = section
        page.alphaValue = 0
        page.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageHost.topAnchor),
            page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
        ])
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            page.animator().alphaValue = 1
        }
        let dark = window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for (key, button) in sidebarButtons {
            let visibleSection = section == .providerEditor ? Section.route : section
            let selected = key == visibleSection
            button.layer?.backgroundColor = selected
                ? (dark ? NSColor.white : NSColor.black).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = selected
                ? (dark ? .black : .white)
                : .secondaryLabelColor
            button.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        }
        if section == .dashboard { refreshDashboard() }
        if section == .route { reloadModelList() }
        if section == .monitoring { refreshMonitoring() }
        if section == .security { reloadBackups() }
    }

    func present() {
        providers = ProviderStore.providers()
        let selectedAgent = AgentPreference.selected
        agentControl.selectedSegment = AgentKind.allCases.firstIndex(of: selectedAgent) ?? 0
        let route = RouteConfigManager.currentRoute()
        routeControl.selectedSegment = route == .official ? 0 : 1
        cursorOfficialUsageSwitch.state = .on
        if selectedAgent == .codex {
            if case let .provider(id) = route,
               providers.contains(where: { $0.id == id && $0.supports(.codex) }) {
                selectedProviderID = id
            } else {
                selectedProviderID = nil
            }
        } else if selectedAgent == .hermes,
                  let id = HermesPreference.providerID,
                  providers.contains(where: { $0.id == id && $0.supports(.hermes) }) {
            selectedProviderID = id
        } else {
            selectedProviderID = nil
        }
        reloadProviderPopups()
        loadSelectedProvider()
        modelProviderField.stringValue = RouteConfigManager.currentModelProvider()
        statusLabel.stringValue = ""
        confirmButton.isEnabled = true
        updateConfirmButtonTitle()
        if let index = AppTheme.allCases.firstIndex(of: AppThemePreference.selected) {
            themeControl.selectedSegment = index
        }
        updateAppearanceSelectionStates()
        updateRouteFields()
        refreshDashboard()
        refreshMonitoring()
        reloadBackups()
        selectSection(.dashboard)
        currentVersionLabel.stringValue = AppUpdateChecker.currentVersion
        checkForUpdates()

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func presentProviderPreview() {
        providers = []
        selectedProviderID = nil
        agentControl.selectedSegment = AgentKind.allCases.firstIndex(of: .codex) ?? 0
        addProvider()
        editorAgentLabel.stringValue = AgentKind.codex.displayName
        statusLabel.stringValue = "界面预览模式"
        selectSection(.providerEditor)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func presentAppearancePreview() {
        statusLabel.stringValue = "界面预览模式"
        if let index = AppTheme.allCases.firstIndex(of: AppThemePreference.selected) {
            themeControl.selectedSegment = index
        }
        updateAppearanceSelectionStates()
        selectSection(.appearance)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func presentRoutePreview() {
        providers = [
            ProviderProfile(
                id: "preview-deepseek",
                name: "DeepSeek",
                baseURL: "https://api.deepseek.com",
                model: "deepseek-v4-flash",
                apiFormat: .responses,
                agents: [.codex],
                vendor: .deepSeek
            ),
            ProviderProfile(
                id: "preview-custom",
                name: "研发代理",
                baseURL: "https://api.example.com/v1",
                model: "company-code-model",
                apiFormat: .responses,
                agents: [.codex],
                vendor: .custom
            )
        ]
        selectedProviderID = "preview-deepseek"
        agentControl.selectedSegment = AgentKind.allCases.firstIndex(of: .codex) ?? 0
        routeControl.selectedSegment = 1
        reloadModelList()
        statusLabel.stringValue = "界面预览模式"
        selectSection(.route)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func presentVersionUpdatePreview() {
        let status = AppUpdateStatus(currentVersion: "3.0.1", latestVersion: "3.1.0")
        availableUpdate = status
        installUpdateButton.title = "更新到 \(status.latestVersion)"
        installUpdateButton.isHidden = false
        updateStatusLabel.textColor = .systemOrange
        updateStatusLabel.stringValue = "发现新版本 \(status.latestVersion)。点击立即更新后，Agent Pulse 将退出，由更新助手在后台下载、安装并自动重新打开。"
        statusLabel.stringValue = "界面预览模式"
        selectSection(.version)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshDashboard() {
        guard let snapshot = appDelegate?.dashboardSnapshot() else { return }
        dashboardAgentValue.stringValue = snapshot.agentName
        dashboardRouteValue.stringValue = snapshot.routeName
        dashboardTaskValue.stringValue = snapshot.taskStatus
        dashboardUsageTitle.stringValue = snapshot.usageLabel
        dashboardUsageValue.stringValue = snapshot.usageValue
        dashboardUsageDetail.stringValue = snapshot.usageDetail
        dashboardUpdatedLabel.stringValue = snapshot.updatedText
        dashboardVersionLabel.stringValue = snapshot.version
        switch snapshot.taskSignal {
        case .red: dashboardTaskIndicator.contentTintColor = .systemRed
        case .yellow: dashboardTaskIndicator.contentTintColor = .systemOrange
        case .green: dashboardTaskIndicator.contentTintColor = .systemGreen
        }
        if let message = snapshot.message, !message.isEmpty {
            dashboardMessageLabel.stringValue = "需要注意：\(message)"
            dashboardMessageLabel.textColor = .systemOrange
        } else {
            dashboardMessageLabel.stringValue = "Agent Pulse 运行正常"
            dashboardMessageLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func refreshDashboardData() {
        dashboardRefreshButton.isEnabled = false
        dashboardRefreshButton.title = "正在刷新…"
        Task {
            await appDelegate?.refreshDashboardData()
            refreshDashboard()
            dashboardRefreshButton.isEnabled = true
            dashboardRefreshButton.title = "立即刷新"
        }
    }

    func refreshMonitoringIfVisible() {
        guard selectedSection == .monitoring else { return }
        refreshMonitoring()
    }

    private func refreshMonitoring() {
        usageAlertSwitch.state = UsageAlertPreferences.enabled ? .on : .off
        refreshAlertThresholdContext()
        let summaries = UsageHistoryStore.dailySummaries(days: 7)
        historyChart.summaries = summaries
        let samples = summaries.reduce(0) { $0 + $1.sampleCount }
        if let latest = UsageHistoryStore.observations().last {
            historySummaryLabel.stringValue = "近 7 天记录 \(samples) 个采样 · 最近 \(latest.route) \(latest.displayValue)"
        } else {
            historySummaryLabel.stringValue = "尚无本地历史；下一次成功刷新后开始记录。"
        }
        if let resetAt = appDelegate?.currentUsageObservation()?.resetAt {
            let relative = RelativeDateTimeFormatter()
            relative.locale = Locale(identifier: "zh_CN")
            relative.unitsStyle = .full
            resetCountdownLabel.stringValue = relative.localizedString(for: resetAt, relativeTo: Date())
            resetCountdownLabel.textColor = resetAt > Date() ? .labelColor : .secondaryLabelColor
        } else {
            resetCountdownLabel.stringValue = "当前数据暂无重置时间"
            resetCountdownLabel.textColor = .secondaryLabelColor
        }
        reloadHealthRows()
    }

    private func selectedAlertThresholdContext() -> AlertThresholdContext {
        let agent = selectedAgent()
        let provider: ProviderProfile?
        if agent == .cursor {
            provider = nil
        } else if agent == .codex {
            provider = routeControl.selectedSegment == 1
                ? selectedProviderID.flatMap { ProviderStore.provider(id: $0) }
                : nil
        } else {
            provider = selectedProviderID.flatMap { ProviderStore.provider(id: $0) }
        }

        if let provider {
            let metric: UsageAlertMetricKind?
            switch provider.effectiveVendor {
            case .zhipuAI, .miniMax:
                metric = .percentage
            default:
                metric = provider.isCodeAPI || provider.effectiveVendor.supportsBalanceLookup
                    ? .balance
                    : nil
            }
            return AlertThresholdContext(
                modelKey: "\(agent.rawValue):\(provider.id)",
                title: "\(agent.displayName) · \(provider.name) · \(provider.model)",
                metric: metric
            )
        }

        let model = officialModelDescription(for: agent)
        let metric: UsageAlertMetricKind? = agent == .hermes
            ? appDelegate?.currentUsageObservation().flatMap {
                $0.remainingPercent != nil ? .percentage : ($0.balance != nil ? .balance : nil)
            }
            : .percentage
        return AlertThresholdContext(
            modelKey: "\(agent.rawValue):official",
            title: "\(agent.displayName) · \(model)",
            metric: metric
        )
    }

    private func refreshAlertThresholdContext() {
        let context = selectedAlertThresholdContext()
        if let active = appDelegate?.currentUsageObservation() {
            let activeModel = active.modelName ?? active.route
            alertContextLabel.stringValue = "当前生效：\(active.agent) · \(activeModel)\n阈值设置：\(context.title)"
        } else {
            alertContextLabel.stringValue = "阈值设置：\(context.title)\n当前生效模型的数据尚未读取。"
        }

        guard let metric = context.metric else {
            alertThresholdControl.setUnavailable("当前模型不支持")
            return
        }
        let titles = metric == .percentage
            ? ["5%", "10%", "15%", "20%", "25%", "30%"]
            : ["$1", "$3", "$5", "$10", "$20", "$50"]
        let rule = UsageAlertRuleStore.rule(for: context.modelKey, metric: metric)
        let title = metric == .percentage
            ? "\(Int(rule.threshold))%"
            : "$\(Int(rule.threshold))"
        alertThresholdControl.setOptions(titles, selected: title)
    }

    private func reloadHealthRows() {
        healthStack.arrangedSubviews.forEach {
            healthStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let candidates = ProviderStore.providers(for: selectedAgent())
        guard !candidates.isEmpty else {
            let empty = NSTextField(labelWithString: "当前 Agent 尚未配置第三方提供商。")
            empty.textColor = .secondaryLabelColor
            healthStack.addArrangedSubview(padded(empty, horizontal: 0, vertical: 8))
            return
        }
        for (index, provider) in candidates.enumerated() {
            let snapshot = RouteHealthStore.snapshot(for: provider.id)
            let state = snapshot?.state ?? .unknown
            let dot = NSImageView(image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: state.title)!)
            dot.symbolConfiguration = .init(pointSize: 9, weight: .medium)
            switch state {
            case .healthy: dot.contentTintColor = .systemGreen
            case .degraded, .checking: dot.contentTintColor = .systemOrange
            case .offline: dot.contentTintColor = .systemRed
            case .unknown: dot.contentTintColor = .tertiaryLabelColor
            }
            let name = NSTextField(labelWithString: provider.name)
            name.font = .systemFont(ofSize: 12.5, weight: .semibold)
            let detailText: String
            if let snapshot {
                let latency = snapshot.latencyMilliseconds.map { " · \($0) ms" } ?? ""
                detailText = "\(state.title)\(latency) · \(snapshot.message)"
            } else {
                detailText = "未检测 · \(provider.model)"
            }
            let detail = NSTextField(wrappingLabelWithString: detailText)
            detail.font = .systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.maximumNumberOfLines = 2
            let text = NSStackView(views: [name, detail])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 3
            let row = NSStackView(views: [dot, text, NSView()])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            healthStack.addArrangedSubview(padded(row, horizontal: 0, vertical: 10))
            row.widthAnchor.constraint(equalTo: healthStack.widthAnchor).isActive = true
            if index < candidates.count - 1 {
                let line = separator()
                healthStack.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: healthStack.widthAnchor).isActive = true
            }
        }
    }

    @objc private func usageAlertsChanged() {
        let enabled = usageAlertSwitch.state == .on
        guard enabled else {
            UsageAlertPreferences.enabled = false
            return
        }
        Task {
            let authorized = await UsageAlertManager.requestAuthorization()
            UsageAlertPreferences.enabled = authorized
            usageAlertSwitch.state = authorized ? .on : .off
            if authorized {
                showSuccess("已启用本地用量预警。")
            } else {
                showError("系统未授予通知权限，可在系统设置中重新开启。")
            }
        }
    }

    @objc private func alertThresholdChanged() {
        let context = selectedAlertThresholdContext()
        guard let metric = context.metric,
              let title = alertThresholdControl.selectedTitle,
              let value = Double(title.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "$", with: "")) else {
            return
        }
        UsageAlertRuleStore.save(
            UsageAlertRule(metric: metric, threshold: value),
            for: context.modelKey
        )
        alertContextLabel.stringValue += "\n已保存：\(metric.displayName)达到 \(title) 时提醒"
    }

    @objc private func checkAllRoutes() {
        let candidates = ProviderStore.providers(for: selectedAgent())
        guard !candidates.isEmpty else {
            showError("当前 Agent 尚未配置第三方提供商。")
            return
        }
        checkRoutesButton.isEnabled = false
        checkRoutesButton.title = "检测中…"
        Task {
            for provider in candidates {
                let snapshot: RouteHealthSnapshot
                if let key = CredentialStore.load(providerID: provider.id), !key.isEmpty {
                    snapshot = await RouteHealthChecker.check(profile: provider, key: key)
                } else {
                    snapshot = RouteHealthSnapshot(
                        providerID: provider.id,
                        state: .offline,
                        latencyMilliseconds: nil,
                        checkedAt: Date(),
                        message: "未配置 API Key"
                    )
                }
                RouteHealthStore.save(snapshot)
                reloadHealthRows()
            }
            checkRoutesButton.isEnabled = true
            checkRoutesButton.title = "检测全部"
        }
    }

    @objc private func exportUsageHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "agent-pulse-usage-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try UsageHistoryStore.csvData().write(to: url, options: .atomic)
                self.showSuccess("用量历史已导出。")
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    private func reloadBackups() {
        backupRecords = ConfigBackupCenter.records()
        backupPopup.removeAllItems()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        backupPopup.addItems(withTitles: backupRecords.map { "\(formatter.string(from: $0.createdAt)) · \($0.reason)" })
        restoreBackupButton.isEnabled = !backupRecords.isEmpty
        backupSelectionChanged()
    }

    @objc private func backupSelectionChanged() {
        guard backupPopup.indexOfSelectedItem >= 0,
              backupPopup.indexOfSelectedItem < backupRecords.count else {
            backupSummaryLabel.stringValue = "尚无配置备份。"
            backupDiffText.string = "创建第一份本地配置快照后，这里会显示差异。"
            return
        }
        let record = backupRecords[backupPopup.indexOfSelectedItem]
        backupSummaryLabel.stringValue = "model_provider: \(record.modelProvider) · \(record.reason)"
        backupDiffText.string = ConfigBackupCenter.diff(record: record)
    }

    @objc private func createConfigBackup() {
        do {
            _ = try ConfigBackupCenter.create(reason: "手动备份")
            reloadBackups()
            showSuccess("配置快照已创建。")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func restoreConfigBackup() {
        guard backupPopup.indexOfSelectedItem >= 0,
              backupPopup.indexOfSelectedItem < backupRecords.count else { return }
        let record = backupRecords[backupPopup.indexOfSelectedItem]
        let alert = NSAlert()
        alert.messageText = "恢复所选配置？"
        alert.informativeText = "恢复前会自动备份当前配置。此操作不会修改会话数据库，Codex 需重新启动后读取新配置。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ConfigBackupCenter.restore(record)
            providers = ProviderStore.providers()
            reloadProviderPopups()
            reloadModelList()
            reloadBackups()
            showSuccess("配置已恢复，请重新启动对应 Agent。")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func exportSanitizedConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "agent-pulse-config.json"
        panel.allowedContentTypes = [.json]
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try ConfigBackupCenter.exportData().write(to: url, options: .atomic)
                self.showSuccess("脱敏配置已导出，不包含钥匙串中的 API Key。")
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func importSanitizedConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let bundle = try ConfigBackupCenter.decodeImport(Data(contentsOf: url))
                let alert = NSAlert()
                alert.messageText = "导入配置？"
                alert.informativeText = "将导入 \(bundle.providers.count) 个提供商元数据。脱敏文件不会覆盖现有 API Key 或含敏感字段的 config.toml。"
                alert.addButton(withTitle: "导入")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try ConfigBackupCenter.importBundle(bundle)
                self.providers = ProviderStore.providers()
                self.reloadProviderPopups()
                self.reloadModelList()
                self.reloadBackups()
                self.showSuccess("配置已安全导入；API Key 请在本机重新填写。")
            } catch {
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func routeChanged() {
        statusLabel.stringValue = ""
        updateRouteFields()
    }

    @objc private func saveModelProvider() {
        let value = modelProviderField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            showError("model_provider 不能为空。")
            modelProviderField.stringValue = RouteConfigManager.currentModelProvider()
            return
        }
        do {
            try RouteConfigManager.setModelProvider(value)
            modelProviderField.stringValue = RouteConfigManager.currentModelProvider()
            statusLabel.textColor = .secondaryLabelColor
            if RouteConfigManager.configuredModelProviderIDs().contains(value) {
                statusLabel.stringValue = "已保存 model_provider=\(value)。重启 Codex 后生效；会话数据库未修改。"
            } else {
                statusLabel.stringValue = "已保存，但 config.toml 未找到对应的 model_providers.\(value) 配置；请先补充该配置。"
            }
        } catch {
            showError(error.localizedDescription)
            modelProviderField.stringValue = RouteConfigManager.currentModelProvider()
        }
    }

    @objc private func resetModelProvider() {
        modelProviderField.stringValue = "openai"
        saveModelProvider()
    }

    @objc private func agentChanged() {
        statusLabel.stringValue = ""
        let agent = selectedAgent()
        if agent == .codex {
            let route = RouteConfigManager.currentRoute()
            routeControl.selectedSegment = route == .official ? 0 : 1
            if case let .provider(id) = route,
               providers.contains(where: { $0.id == id && $0.supports(.codex) }) {
                selectedProviderID = id
            } else {
                selectedProviderID = nil
            }
        } else if agent == .hermes {
            if let id = HermesPreference.providerID,
               providers.contains(where: { $0.id == id && $0.supports(.hermes) }) {
                selectedProviderID = id
            } else {
                selectedProviderID = nil
            }
        } else {
            cursorOfficialUsageSwitch.state = .on
            selectedProviderID = nil
        }
        reloadProviderPopups()
        reloadModelList()
        updateRouteFields()
        updateConfirmButtonTitle()
    }

    @objc private func routeProviderChanged() {
        guard let id = selectedProviderID(from: routeProviderPopup) else { return }
        selectedProviderID = id
        selectProvider(id, in: providerPopup)
        loadSelectedProvider()
        routeControl.selectedSegment = 1
        updateRouteFields()
    }

    @objc private func cursorBalanceProviderChanged() {
        guard let id = selectedProviderID(from: cursorBalanceProviderPopup) else { return }
        selectedProviderID = id
        selectProvider(id, in: providerPopup)
        loadSelectedProvider()
        statusLabel.stringValue = ""
    }

    @objc private func cursorOfficialUsageChanged() {
        statusLabel.stringValue = cursorOfficialUsageSwitch.state == .on
            ? "启用后，Agent Pulse 会使用 Cursor 本地登录状态查询官方用量，不会保存登录令牌。"
            : ""
    }

    @objc private func iconStyleChanged(_ sender: StatusStyleButton) {
        let style = sender.style
        StatusIconPreference.selected = style
        appDelegate?.statusIconStyleDidChange(to: style)
        updateAppearanceSelectionStates()
        showSuccess("已切换为\(style.displayName)。")
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegment
        guard AppTheme.allCases.indices.contains(index) else { return }
        let theme = AppTheme.allCases[index]
        AppThemePreference.selected = theme
        AppThemePreference.apply(theme)
        stylePrimaryButton()
        styleSegmentedControls()
        updateAppearanceSelectionStates()
        selectSection(selectedSection)
        showSuccess("已切换为\(theme.displayName)主题。")
    }

    private func updateAppearanceSelectionStates() {
        for (style, button) in statusStyleButtons {
            button.setChoiceSelected(style == StatusIconPreference.selected)
        }
        if let index = AppTheme.allCases.firstIndex(of: AppThemePreference.selected) {
            themeControl.selectedSegment = index
        }
    }

    @objc private func openProjectPage() {
        NSWorkspace.shared.open(AppIdentity.repositoryURL)
    }

    @objc private func checkForUpdates() {
        guard checkUpdateButton.isEnabled else { return }
        availableUpdate = nil
        installUpdateButton.isHidden = true
        checkUpdateButton.isEnabled = false
        checkUpdateButton.title = "正在检查…"
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.stringValue = "正在连接 GitHub 检查最新版本…"
        Task {
            defer {
                checkUpdateButton.isEnabled = true
                checkUpdateButton.title = "检查更新"
            }
            do {
                let status = try await AppUpdateChecker.check()
                if status.updateAvailable {
                    updateStatusLabel.textColor = .systemOrange
                    updateStatusLabel.stringValue = "发现新版本 \(status.latestVersion)。点击立即更新后，Agent Pulse 将退出，由更新助手在后台下载、安装并自动重新打开。"
                    availableUpdate = status
                    installUpdateButton.title = "更新到 \(status.latestVersion)"
                    installUpdateButton.isHidden = false
                } else {
                    updateStatusLabel.textColor = .systemGreen
                    updateStatusLabel.stringValue = "当前已是最新版本 \(status.currentVersion)。"
                    installUpdateButton.isHidden = true
                }
            } catch {
                updateStatusLabel.textColor = .systemRed
                updateStatusLabel.stringValue = "检查失败：\(error.localizedDescription)"
                installUpdateButton.isHidden = true
            }
        }
    }

    @objc private func installAvailableUpdate() {
        guard let status = availableUpdate, status.updateAvailable else { return }
        let alert = NSAlert()
        alert.messageText = "更新到 Agent Pulse \(status.latestVersion)？"
        alert.informativeText = "Agent Pulse 将立即退出，由独立更新助手在后台下载、校验并安装新版，完成后自动重新打开。旧版会移到废纸篓。"
        alert.addButton(withTitle: "退出并更新")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        installUpdateButton.isEnabled = false
        checkUpdateButton.isEnabled = false
        installUpdateButton.title = "正在退出…"
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.stringValue = "正在启动更新助手…"
        Task {
            do {
                let prepared = try await AppUpdateInstaller.prepare(status)
                updateStatusLabel.stringValue = "更新助手已启动，正在退出 Agent Pulse。"
                try prepared.launch()
                NSApp.terminate(nil)
            } catch {
                installUpdateButton.isEnabled = true
                checkUpdateButton.isEnabled = true
                installUpdateButton.title = "重新更新"
                updateStatusLabel.textColor = .systemRed
                updateStatusLabel.stringValue = "更新失败：\(error.localizedDescription)"
            }
        }
    }

    private func updateRouteFields() {
        editorAgentLabel.stringValue = selectedAgent().displayName
        updateConfirmButtonTitle()
    }

    private func selectedAgent() -> AgentKind {
        let index = agentControl.selectedSegment
        return AgentKind.allCases.indices.contains(index) ? AgentKind.allCases[index] : .codex
    }

    private func updateConfirmButtonTitle() {
        confirmButton.title = "应用并打开 \(selectedAgent().displayName)"
    }

    private func reloadProviderPopups() {
        providerPopup.removeAllItems()
        routeProviderPopup.removeAllItems()
        cursorBalanceProviderPopup.removeAllItems()
        let visibleProviders = providers.filter { $0.supports(selectedAgent()) }
        let titles = ProviderStore.popupTitles(for: visibleProviders)
        for (provider, title) in zip(visibleProviders, titles) {
            addProviderItem(title: title, providerID: provider.id, to: providerPopup)
            addProviderItem(title: title, providerID: provider.id, to: routeProviderPopup)
            addProviderItem(title: title, providerID: provider.id, to: cursorBalanceProviderPopup)
        }
        if let id = selectedProviderID, visibleProviders.contains(where: { $0.id == id }) {
            selectProvider(id, in: providerPopup)
            selectProvider(id, in: routeProviderPopup)
            selectProvider(id, in: cursorBalanceProviderPopup)
        }
        updateRouteFields()
    }

    private func addProviderItem(title: String, providerID: String, to popup: NSPopUpButton) {
        popup.addItem(withTitle: title)
        popup.lastItem?.representedObject = providerID
    }

    private func selectedProviderID(from popup: NSPopUpButton) -> String? {
        popup.selectedItem?.representedObject as? String
    }

    private func selectProvider(_ providerID: String, in popup: NSPopUpButton) {
        guard let index = popup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == providerID
        }) else { return }
        popup.selectItem(at: index)
    }

    private func loadSelectedProvider() {
        guard let id = selectedProviderID, let provider = providers.first(where: { $0.id == id }) else {
            nameField.stringValue = ""
            baseURLField.stringValue = ""
            modelField.stringValue = ""
            keyField.stringValue = ""
            protocolPopup.selectItem(at: 0)
            selectedVendor = .deepSeek
            updateVendorEditor(animated: false)
            return
        }
        nameField.stringValue = provider.name
        baseURLField.stringValue = provider.baseURL
        modelField.stringValue = provider.model
        keyField.stringValue = CredentialStore.load(providerID: id) ?? ""
        protocolPopup.selectItem(at: 0)
        selectedVendor = provider.effectiveVendor == .xAI ? .custom : provider.effectiveVendor
        updateVendorEditor(animated: false)
    }

    @objc private func vendorChoiceChanged(_ sender: VendorChoiceButton) {
        let previous = selectedVendor
        let existing = selectedProviderID.flatMap { id in providers.first(where: { $0.id == id }) }
        selectedVendor = sender.vendor
        if let baseURL = selectedVendor.defaultBaseURL,
           let model = selectedVendor.defaultModel {
            baseURLField.stringValue = baseURL
            modelField.stringValue = model
            protocolPopup.selectItem(at: 0)
        } else if existing == nil {
            baseURLField.stringValue = ""
            modelField.stringValue = ""
            protocolPopup.selectItem(at: ProviderAPIFormat.allCases.firstIndex(of: .automatic) ?? 0)
        }
        if existing == nil || nameField.stringValue == "新提供商" || nameField.stringValue == previous.displayName {
            nameField.stringValue = selectedVendor.displayName
        }
        updateVendorEditor(animated: true)
        window?.makeFirstResponder(nameField)
    }

    private func updateVendorEditor(animated: Bool) {
        vendorButtons.forEach { vendor, button in
            button.setChoiceSelected(vendor == selectedVendor)
        }
        let applyState = {
            self.customProviderFields.isHidden = self.selectedVendor != .custom
            self.providerPresetSummary.isHidden = self.selectedVendor == .custom
            if let baseURL = self.selectedVendor.defaultBaseURL,
               let format = self.selectedVendor.defaultAPIFormat {
                self.providerPresetSummary.stringValue = "已内置  \(baseURL)   ·   \(format.displayName)"
            } else {
                self.providerPresetSummary.stringValue = ""
            }
            self.balanceCapabilityLabel.stringValue = self.selectedVendor.balanceDescription
            self.window?.contentView?.layoutSubtreeIfNeeded()
        }
        guard animated else {
            applyState()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyState()
        }
    }

    @objc private func providerChanged() {
        guard let id = selectedProviderID(from: providerPopup) else { return }
        selectedProviderID = id
        selectProvider(id, in: routeProviderPopup)
        loadSelectedProvider()
        statusLabel.stringValue = ""
    }

    @objc private func addProvider() {
        selectedProviderID = ProviderStore.makeProviderID(existing: providers)
        reloadProviderPopups()
        providerPopup.insertItem(withTitle: "新提供商", at: 0)
        providerPopup.item(at: 0)?.representedObject = selectedProviderID
        providerPopup.selectItem(at: 0)
        selectedVendor = .deepSeek
        nameField.stringValue = selectedVendor.displayName
        baseURLField.stringValue = selectedVendor.defaultBaseURL ?? ""
        modelField.stringValue = selectedVendor.defaultModel ?? ""
        keyField.stringValue = ""
        protocolPopup.selectItem(at: 0)
        updateVendorEditor(animated: false)
        updateRouteFields()
        window?.makeFirstResponder(nameField)
    }

    @objc private func deleteProvider() {
        guard let id = selectedProviderID else { return }
        guard let index = providers.firstIndex(where: { $0.id == id }) else {
            selectedProviderID = providers.first?.id
            reloadProviderPopups()
            loadSelectedProvider()
            return
        }
        if RouteConfigManager.currentRoute() == .provider(id) {
            showError("当前正在使用该提供商，请先切换到其他路由。")
            return
        }
        if HermesPreference.providerID == id {
            showError("Hermes 当前正在使用该提供商，请先切换到 Hermes 当前配置或其他模型。")
            return
        }
        let alert = NSAlert()
        alert.messageText = "删除 \(providers[index].name)？"
        alert.informativeText = "对应的本地 API Key 也会被删除。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try CredentialStore.delete(providerID: id)
            try CredentialStore.delete(
                providerID: ProviderBalanceClient.managementCredentialID(for: id)
            )
            providers.remove(at: index)
            providerBalances.removeValue(forKey: id)
            providerBalanceUpdatedAt.removeValue(forKey: id)
            providerBalanceRefreshesInFlight.remove(id)
            selectedProviderID = nil
            if CursorUsagePreference.providerID == id {
                CursorUsagePreference.providerID = nil
            }
            try ProviderStore.saveProviders(providers, selectedProviderID: selectedProviderID)
            reloadProviderPopups()
            reloadModelList()
            showSuccess("已删除提供商。")
            selectSection(.route)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func saveProvider() {
        do {
            let profile = try persistCurrentProvider()
            providerBalances.removeValue(forKey: profile.id)
            providerBalanceUpdatedAt.removeValue(forKey: profile.id)
            reloadModelList()
            showSuccess("已保存 \(profile.name)。")
            selectSection(.route)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func testProviderConnection() {
        let draft: (profile: ProviderProfile, key: String)
        do {
            draft = try currentProviderDraft()
        } catch {
            showError(error.localizedDescription)
            return
        }
        testProviderButton.isEnabled = false
        testProviderButton.title = "正在测试…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = draft.profile.isCodeAPI
            ? "正在验证账户与模型…"
            : "正在发送最小模型请求…"
        Task {
            defer {
                testProviderButton.isEnabled = true
                testProviderButton.title = "测试连接"
            }
            do {
                let result = try await ProviderConnectionTester.test(profile: draft.profile, key: draft.key)
                if draft.profile.effectiveVendor.supportsBalanceLookup || draft.profile.isCodeAPI {
                    do {
                        let balance = try await ProviderBalanceClient.fetch(
                            profile: draft.profile,
                            apiKey: draft.key
                        )
                        showSuccess("\(result) · \(balance.displayText)")
                    } catch {
                        showSuccess("\(result) · 余额查询不可用")
                    }
                } else {
                    showSuccess(result)
                }
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func persistCurrentProvider() throws -> ProviderProfile {
        let draft = try currentProviderDraft()
        let profile = draft.profile
        let key = draft.key
        let id = profile.id
        if let index = providers.firstIndex(where: { $0.id == id }) {
            providers[index] = profile
        } else {
            providers.append(profile)
        }
        selectedProviderID = id
        try ProviderStore.saveProviders(providers, selectedProviderID: id)
        try CredentialStore.save(key, providerID: id)
        let managementCredentialID = ProviderBalanceClient.managementCredentialID(for: id)
        try CredentialStore.delete(providerID: managementCredentialID)
        reloadProviderPopups()
        return profile
    }

    private func currentProviderDraft() throws -> (profile: ProviderProfile, key: String) {
        guard let id = selectedProviderID else { throw SettingsError.noProvider }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = (selectedVendor.defaultBaseURL ?? baseURLField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !model.isEmpty, !key.isEmpty else { throw SettingsError.incomplete }
        if ProviderStore.hasNameCollision(
            name,
            excluding: id,
            in: providers,
            agent: selectedAgent()
        ) {
            throw SettingsError.duplicateName(name)
        }
        guard let url = URL(string: baseURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw SettingsError.invalidURL
        }
        let boundAgents: [AgentKind]?
        if let existing = providers.first(where: { $0.id == id }) {
            boundAgents = existing.agents
        } else {
            boundAgents = [selectedAgent()]
        }
        let profile = ProviderProfile(
            id: id,
            name: name,
            baseURL: baseURL,
            model: model,
            apiFormat: .responses,
            agents: boundAgents,
            vendor: selectedVendor,
            balanceTeamID: nil
        )
        return (profile, key)
    }

    @objc private func closeWindow() { window?.close() }

    @objc private func openCursorModels() {
        Task {
            do {
                try await CursorLauncher.openModelSettings()
                showSuccess("已打开 Cursor Models 设置。")
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func confirmSelection() {
        if selectedAgent() == .cursor {
            confirmCursorSelection()
            return
        }
        if selectedAgent() == .hermes {
            confirmHermesSelection()
            return
        }
        confirmButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在更新路由…"
        confirmButton.title = "正在切换…"

        Task {
            let route: RouteChoice
            var usage: UsageResponse?
            do {
                if routeControl.selectedSegment == 1 {
                    guard let id = selectedProviderID,
                          let profile = providers.first(where: {
                              $0.id == id && $0.supports(.codex)
                          }) else { throw SettingsError.noProvider }
                    route = .provider(profile.id)
                    if profile.isCodeAPI, let key = CredentialStore.load(providerID: profile.id) {
                        statusLabel.stringValue = "正在验证 CodeAPI Key…"
                        usage = try await CodeAPIClient.fetch(key: key)
                    }
                } else {
                    route = .official
                }
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                updateConfirmButtonTitle()
                return
            }

            let authSnapshot: CodexAuthSnapshot
            do {
                authSnapshot = try CodexAuthStore.snapshot()
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                updateConfirmButtonTitle()
                return
            }

            statusLabel.stringValue = "正在关闭 Codex…"
            var codexWasStopped = false
            var authPreparation = CodexAuthPreparation.ready
            do {
                try await CodexLauncher.terminate()
                codexWasStopped = true
                statusLabel.stringValue = "正在切换认证状态…"
                authPreparation = try CodexAuthStore.prepareForSwitch(to: route)
                statusLabel.stringValue = "正在更新路由配置…"
                try RouteConfigManager.apply(route)
            } catch {
                try? CodexAuthStore.restore(authSnapshot)
                if codexWasStopped {
                    try? await CodexLauncher.launch()
                }
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                updateConfirmButtonTitle()
                return
            }

            AgentPreference.selected = .codex
            appDelegate?.agentDidChange(to: .codex)
            appDelegate?.routeDidChange(to: route, validatedCodeUsage: usage)
            if authPreparation.requiresOfficialLogin {
                showSuccess("已切换到官方路由，请在 Codex 中重新登录官方账号。")
            } else {
                showSuccess("已切换到 \(route.displayName)。")
            }
            confirmButton.title = "切换成功"
            window?.close()

            do {
                try await CodexLauncher.launch()
                if authPreparation.requiresOfficialLogin {
                    appDelegate?.presentOfficialLoginRequired()
                }
            } catch {
                appDelegate?.presentLaunchWarning(error.localizedDescription)
            }
        }
    }

    private func confirmCursorSelection() {
        confirmButton.isEnabled = false
        confirmButton.title = "正在配置…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在安装 Cursor 状态 Hooks…"

        Task {
            do {
                let cursorWasRunning = CursorLauncher.isRunning
                let hooksChanged = try CursorIntegration.installHooks()
                CursorUsagePreference.officialUsageEnabled = true
                CursorUsagePreference.providerID = nil
                AgentPreference.selected = .cursor
                appDelegate?.agentDidChange(to: .cursor)
                statusLabel.stringValue = "正在打开 Cursor…"
                try await CursorLauncher.launch()
                let restartRequired = hooksChanged && cursorWasRunning
                appDelegate?.cursorHooksDidChange(restartRequired: restartRequired)
                showSuccess(restartRequired
                    ? "Cursor 已连接；Hooks 将在下次手动重启 Cursor 后生效。"
                    : "Cursor 已连接，用量与状态同步已启用。")
                confirmButton.title = "连接成功"
                window?.close()
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                updateConfirmButtonTitle()
            }
        }
    }

    private func confirmHermesSelection() {
        confirmButton.isEnabled = false
        confirmButton.title = "正在配置…"
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "正在更新 Hermes 模型配置…"

        Task {
            do {
                if let id = selectedProviderID {
                    guard let profile = providers.first(where: {
                        $0.id == id && $0.supports(.hermes)
                    }) else { throw SettingsError.noProvider }
                    guard let key = CredentialStore.load(providerID: id), !key.isEmpty else {
                        throw SettingsError.missingCredential
                    }
                    try HermesIntegration.apply(profile: profile, apiKey: key)
                    HermesPreference.providerID = id
                } else {
                    try HermesIntegration.restoreOriginalConfiguration()
                    HermesPreference.providerID = nil
                }
                AgentPreference.selected = .hermes
                appDelegate?.agentDidChange(to: .hermes)
                statusLabel.stringValue = "正在打开 Hermes…"
                try await HermesLauncher.launch()
                showSuccess("Hermes 已连接；新模型将在下一次请求中生效，运行中的任务保持不变。")
                confirmButton.title = "连接成功"
                window?.close()
            } catch {
                showError(error.localizedDescription)
                confirmButton.isEnabled = true
                updateConfirmButtonTitle()
            }
        }
    }

    private func showSuccess(_ message: String) {
        statusLabel.textColor = .systemGreen
        statusLabel.stringValue = message
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }
}

private enum SettingsError: LocalizedError {
    case noProvider
    case incomplete
    case invalidURL
    case duplicateName(String)
    case missingCredential
    case officialNotLoggedIn

    var errorDescription: String? {
        switch self {
        case .noProvider: return "请先新增一个第三方提供商。"
        case .incomplete: return "请完整填写名称、Base URL、模型 ID 和 API Key。"
        case .invalidURL: return "Base URL 必须是有效的 http 或 https 地址。"
        case let .duplicateName(name): return "路由名称“\(name)”已存在，请换一个名称。"
        case .missingCredential: return "该提供商尚未保存 API Key。"
        case .officialNotLoggedIn: return "官方账号尚未登录。"
        }
    }
}
