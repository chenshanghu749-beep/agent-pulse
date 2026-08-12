import CoreServices
import Foundation

enum TaskRunState: Sendable, Equatable {
    case running(Int)
    case waiting(Int)
    case ready
}

struct TaskActivitySnapshot: Sendable, Equatable {
    let state: TaskRunState
    let changedAt: Date?
}

struct TaskActivityCompatibilityInfo: Sendable {
    let rootExists: Bool
    let recentSessionCount: Int
    let latestEventAt: Date?
    let summary: String
}

struct TaskActivityFileEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags

    init(path: String, flags: FSEventStreamEventFlags) {
        self.path = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        self.flags = flags
    }

    var requiresFullScan: Bool {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagMount
                | kFSEventStreamEventFlagUnmount
        )
        let isDirectory = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
        return flags & rescanFlags != 0 || isDirectory
    }
}

final class TaskActivityMonitor {
    typealias Handler = ([TaskActivityFileEvent]) -> Void

    private let paths: [URL]
    private let handler: Handler
    private let queue = DispatchQueue(label: "net.nexita.agent-pulse.task-events", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingEvents: [String: TaskActivityFileEvent] = [:]
    private var pendingWorkItem: DispatchWorkItem?

    init(paths: [URL], handler: @escaping Handler) {
        self.paths = paths
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard stream == nil else { return true }
        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingPaths.isEmpty else { return false }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, clientInfo, eventCount, eventPaths, eventFlags, _ in
            guard let clientInfo else { return }
            let monitor = Unmanaged<TaskActivityMonitor>.fromOpaque(clientInfo).takeUnretainedValue()
            let paths = eventPaths.bindMemory(to: UnsafePointer<CChar>.self, capacity: eventCount)
            var events: [TaskActivityFileEvent] = []
            events.reserveCapacity(eventCount)
            for index in 0..<eventCount {
                events.append(TaskActivityFileEvent(
                    path: String(cString: paths[index]),
                    flags: eventFlags[index]
                ))
            }
            monitor.receive(events)
        }
        let createFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existingPaths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.12,
            createFlags
        ) else { return false }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            self.stream = nil
            return false
        }
        return true
    }

    func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingEvents.removeAll()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        self.stream = nil
    }

    deinit { stop() }

    private func receive(_ events: [TaskActivityFileEvent]) {
        for event in events {
            pendingEvents[event.path] = event
        }
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let events = Array(self.pendingEvents.values)
            self.pendingEvents.removeAll(keepingCapacity: true)
            self.pendingWorkItem = nil
            self.handler(events)
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }
}

enum TaskActivityReader {
    private static let abandonedSessionInterval: TimeInterval = 30 * 60

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private struct FileState {
        var state: TaskRunState
        var timestamp: Date
        var pendingTools: Int
    }

    private struct CacheEntry {
        let size: UInt64
        let fileState: FileState?
    }

    private struct FileReadResult {
        let fileState: FileState
        let sawToolCall: Bool
    }

    private struct FileIndex {
        let rootPath: String
        var files: [String: Date]
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: CacheEntry] = [:]
    private static var fileIndex: FileIndex?
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func read(
        root customRoot: URL? = nil,
        now: Date = Date(),
        fileEvents: [TaskActivityFileEvent] = [],
        forceFileScan: Bool = true
    ) -> TaskActivitySnapshot {
        let root = customRoot ?? defaultRootURL
        let files = indexedFiles(
            root: root,
            cutoff: now.addingTimeInterval(-48 * 60 * 60),
            fileEvents: fileEvents,
            forceFileScan: forceFileScan || fileEvents.contains(where: \.requiresFullScan)
        )

        let results = files
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .compactMap { readState(from: $0.0, fallbackDate: $0.1) }
        let activeResults = results.filter {
            $0.fileState.state == .ready
                || now.timeIntervalSince($0.fileState.timestamp) <= abandonedSessionInterval
        }
        let states = activeResults.map(\.fileState)

        let waiting = states.filter {
            if case .waiting = $0.state { return true }
            return false
        }
        if !waiting.isEmpty {
            return TaskActivitySnapshot(state: .waiting(waiting.count), changedAt: waiting.map(\.timestamp).max())
        }

        let recentToolActivity = activeResults.filter {
            $0.sawToolCall && $0.fileState.state != .ready
        }
        if !recentToolActivity.isEmpty {
            return TaskActivitySnapshot(
                state: .waiting(recentToolActivity.count),
                changedAt: recentToolActivity.map(\.fileState.timestamp).max()
            )
        }

        let running = states.filter {
            if case .running = $0.state { return true }
            return false
        }
        if !running.isEmpty {
            return TaskActivitySnapshot(state: .running(running.count), changedAt: running.map(\.timestamp).max())
        }

        if let ready = states
            .filter({ $0.state == .ready })
            .max(by: { $0.timestamp < $1.timestamp }) {
            return TaskActivitySnapshot(state: .ready, changedAt: ready.timestamp)
        }
        return TaskActivitySnapshot(state: .ready, changedAt: nil)
    }

    static func compatibilityInfo(root customRoot: URL? = nil, now: Date = Date()) -> TaskActivityCompatibilityInfo {
        let root = customRoot ?? defaultRootURL
        let exists = FileManager.default.fileExists(atPath: root.path)
        let files = indexedFiles(
            root: root,
            cutoff: now.addingTimeInterval(-48 * 60 * 60),
            fileEvents: [],
            forceFileScan: true
        )
        let latest = files.map(\.1).max()
        let summary: String
        if !exists {
            summary = "监听目录不存在"
        } else if files.isEmpty {
            summary = "监听正常，近 48 小时没有会话事件"
        } else {
            summary = "监听正常，已兼容任务、回合与工具事件"
        }
        return TaskActivityCompatibilityInfo(
            rootExists: exists,
            recentSessionCount: files.count,
            latestEventAt: latest,
            summary: summary
        )
    }

    private static func indexedFiles(
        root: URL,
        cutoff: Date,
        fileEvents: [TaskActivityFileEvent],
        forceFileScan: Bool
    ) -> [(URL, Date)] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        cacheLock.lock()
        var index = fileIndex?.rootPath == root.path ? fileIndex : nil
        cacheLock.unlock()

        if forceFileScan || index == nil {
            var files: [String: Date] = [:]
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    guard let modified = regularFileModificationDate(url), modified >= cutoff else { continue }
                    files[url.path] = modified
                }
            }
            index = FileIndex(rootPath: root.path, files: files)
        } else if var updatedIndex = index {
            for event in fileEvents {
                guard event.path.hasPrefix(root.path) else { continue }
                let url = URL(fileURLWithPath: event.path)
                guard url.pathExtension == "jsonl" else { continue }
                if let modified = regularFileModificationDate(url), modified >= cutoff {
                    updatedIndex.files[url.path] = modified
                } else {
                    updatedIndex.files.removeValue(forKey: url.path)
                }
            }
            updatedIndex.files = updatedIndex.files.filter { $0.value >= cutoff }
            index = updatedIndex
        }

        let resolved = index ?? FileIndex(rootPath: root.path, files: [:])
        cacheLock.lock()
        fileIndex = resolved
        cacheLock.unlock()
        return resolved.files.map { (URL(fileURLWithPath: $0.key), $0.value) }
    }

    private static func regularFileModificationDate(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        return values.contentModificationDate
    }

    private static func readState(from url: URL, fallbackDate: Date) -> FileReadResult? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        cacheLock.lock()
        let cached = cache[url.path]
        cacheLock.unlock()

        let canContinue = cached != nil && size >= cached!.size
        let offset = canContinue ? cached!.size : 0
        try? handle.seek(toOffset: offset)
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }

        let completeLength: Int
        if let lastNewline = data.lastIndex(of: 0x0A) {
            completeLength = data.distance(from: data.startIndex, to: lastNewline) + 1
        } else {
            completeLength = 0
        }
        let completeData = data.prefix(completeLength)
        guard let text = String(data: completeData, encoding: .utf8) else { return nil }

        var latest = canContinue ? cached?.fileState : nil
        var sawToolCall = false
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }

            let timestamp = (object["timestamp"] as? String).flatMap(parseDate) ?? fallbackDate
            if var state = latest, state.state != .ready, timestamp > state.timestamp {
                state.timestamp = timestamp
                latest = state
            }
            switch object["type"] as? String {
            case "event_msg":
                switch type {
                case "task_started", "turn_started", "agent_turn_started", "response_started":
                    latest = FileState(state: .running(1), timestamp: timestamp, pendingTools: 0)
                case "task_complete", "turn_complete", "task_completed", "response_completed",
                     "task_cancelled", "turn_aborted", "turn_cancelled":
                    latest = FileState(state: .ready, timestamp: timestamp, pendingTools: 0)
                default:
                    continue
                }
            case "response_item":
                guard var state = latest else { continue }
                switch type {
                case "custom_tool_call", "function_call", "local_shell_call", "shell_call",
                     "mcp_tool_call", "computer_tool_call", "web_search_call":
                    guard state.state != .ready else { continue }
                    sawToolCall = true
                    state.pendingTools += 1
                    state.state = .waiting(1)
                    state.timestamp = timestamp
                    latest = state
                case "custom_tool_call_output", "function_call_output", "local_shell_call_output",
                     "shell_call_output", "mcp_tool_call_output", "computer_tool_call_output",
                     "web_search_call_output":
                    guard state.state != .ready else { continue }
                    state.pendingTools = max(0, state.pendingTools - 1)
                    state.state = state.pendingTools > 0 ? .waiting(1) : .running(1)
                    state.timestamp = timestamp
                    latest = state
                default:
                    continue
                }
            default:
                continue
            }
        }

        cacheLock.lock()
        cache[url.path] = CacheEntry(size: offset + UInt64(completeLength), fileState: latest)
        cacheLock.unlock()
        guard let latest else { return nil }
        return FileReadResult(fileState: latest, sawToolCall: sawToolCall)
    }

    private static func parseDate(_ value: String) -> Date? {
        timestampFormatter.date(from: value)
    }
}
