import SwiftUI
import WidgetKit
import Darwin

let widgetKind = "AgentPulseUsageWidget"
let widgetDataRelativePath = "Library/Application Support/Agent Pulse/widget-data.json"

struct WidgetBalanceItem: Codable {
    let name: String
    let value: String
    let detail: String
    let isOfficial: Bool
}

struct WidgetData: Codable {
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
    let balances: [WidgetBalanceItem]?

    static let placeholder = WidgetData(
        updatedAt: Date(), routeName: "OpenAI 官方", modelName: "Codex",
        primaryValue: "82%", primaryLabel: "官方用量剩余", detail: "5 小时 · 自动刷新",
        inputTokens: 12840, outputTokens: 3980, totalTokens: 16820,
        taskText: "可以继续对话", taskColor: "green",
        balances: [
            WidgetBalanceItem(name: "OpenAI 官方", value: "82%", detail: "5 小时剩余", isOfficial: true),
            WidgetBalanceItem(name: "DeepSeek", value: "$18.42", detail: "第三方提供商", isOfficial: false),
            WidgetBalanceItem(name: "智谱 AI", value: "71%", detail: "Coding Plan 配额", isOfficial: false),
            WidgetBalanceItem(name: "月之暗面", value: "$26.08", detail: "第三方提供商", isOfficial: false)
        ]
    )

    static func current() -> WidgetData {
        guard let passwordEntry = getpwuid(getuid()),
              let homePointer = passwordEntry.pointee.pw_dir else {
            return placeholder
        }
        let home = URL(fileURLWithPath: String(cString: homePointer), isDirectory: true)
        let url = home.appendingPathComponent(widgetDataRelativePath)
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return placeholder
        }
        return value
    }
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: Date(), data: context.isPreview ? .placeholder : .current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        completion(Timeline(
            entries: [PulseEntry(date: now, data: .current())],
            policy: .after(now.addingTimeInterval(15 * 60))
        ))
    }
}

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    private var statusColor: Color {
        switch entry.data.taskColor {
        case "red": return Color(red: 1, green: 0.27, blue: 0.25)
        case "yellow": return Color(red: 1, green: 0.78, blue: 0.17)
        default: return Color(red: 0.27, green: 0.82, blue: 0.45)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                Text("AGENT PULSE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.7)
                Spacer(minLength: 0)
                Circle().fill(statusColor).frame(width: 7, height: 7)
            }
            .foregroundStyle(.secondary)

            if family == .systemMedium, !balanceItems.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(Array(balanceItems.prefix(4).enumerated()), id: \.offset) { _, item in
                        balanceCard(item)
                    }
                }
            } else {
                let item = balanceItems.first
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.value ?? entry.data.primaryValue)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(item?.name ?? entry.data.primaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(item?.detail ?? entry.data.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(entry.data.routeName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(entry.data.taskText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(15)
        .containerBackground(Color(nsColor: .windowBackgroundColor), for: .widget)
    }

    private var balanceItems: [WidgetBalanceItem] {
        entry.data.balances ?? []
    }

    private func balanceCard(_ item: WidgetBalanceItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: item.isOfficial ? "checkmark.seal.fill" : "server.rack")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(item.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(item.value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

}

@main
struct AgentPulseUsageWidget: Widget {
    let kind = widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Pulse")
        .description("在桌面查看当前 Agent、路由、用量、Token 与任务状态。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
