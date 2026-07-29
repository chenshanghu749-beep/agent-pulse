import Foundation

struct LegacySessionMigrationScan: Sendable {
    let providerCount: Int
    let providerIDs: [String]
    let sessionCount: Int
    let totalBytes: Int64
    fileprivate let databaseURL: URL
    fileprivate let sessions: [LegacySessionCandidate]
}

struct LegacySessionMigrationResult: Sendable {
    let copiedSessions: Int
    let backupDirectory: URL
}

enum LegacySessionMigrationError: LocalizedError {
    case databaseNotFound
    case invalidDatabase(String)
    case invalidSession(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "未找到 Codex 本地会话数据库。"
        case let .invalidDatabase(message):
            return "无法读取 Codex 本地会话数据库：\(message)"
        case let .invalidSession(message):
            return "无法复制旧会话：\(message)"
        case let .commandFailed(message):
            return "会话迁移失败：\(message)"
        }
    }
}

private struct LegacySessionCandidate: @unchecked Sendable {
    let id: String
    let providerID: String
    let rolloutURL: URL
    let databaseRow: [String: Any]
    let size: Int64
}

private struct LegacyProviderSpec {
    let id: String
    let baseURL: String?
}

private struct LegacySessionMigrationReport: Codable {
    struct Copy: Codable {
        let sourceID: String
        let copiedID: String
        let sourceProvider: String
        let sourcePath: String
        let copiedPath: String
    }

    let version: Int
    let completedAt: Date
    let databasePath: String
    let providerIDs: [String]
    let copies: [Copy]
}

enum LegacySessionMigration {
    static let promptMarkerKey = "legacyThirdPartySessionMigrationPromptV1"
    private static let reportName = "legacy-session-migration-v1.json"

    static func shouldPrompt(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: promptMarkerKey)
    }

    static func markPromptHandled(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: promptMarkerKey)
    }

    static func scan(codexHome customCodexHome: URL? = nil) throws -> LegacySessionMigrationScan? {
        let codexHome = customCodexHome ?? defaultCodexHome
        if FileManager.default.fileExists(atPath: reportURL(codexHome: codexHome).path) {
            return nil
        }
        guard let databaseURL = sessionDatabaseURL(codexHome: codexHome) else {
            return nil
        }

        let configURL = codexHome.appendingPathComponent("config.toml")
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let providerSpecs = thirdPartyProviders(in: config)
        let configuredIDs = Set(providerSpecs.map { $0.id.lowercased() })

        let rows = try sqliteJSON(
            databaseURL: databaseURL,
            sql: "SELECT * FROM threads WHERE model_provider != 'openai' ORDER BY updated_at DESC;"
        )
        let candidates = rows.compactMap { row -> LegacySessionCandidate? in
            guard let id = row["id"] as? String,
                  let providerID = row["model_provider"] as? String,
                  let rolloutPath = row["rollout_path"] as? String else {
                return nil
            }
            let normalizedProvider = providerID.lowercased()
            let isManagedLegacyProvider = normalizedProvider == "codeapi"
                || normalizedProvider == RouteConfigManager.legacyManagedProviderID
                || normalizedProvider.hasPrefix("codeapi_status_provider_")
            guard configuredIDs.contains(normalizedProvider) || isManagedLegacyProvider else {
                return nil
            }
            let rolloutURL = URL(fileURLWithPath: rolloutPath)
            guard FileManager.default.fileExists(atPath: rolloutURL.path) else { return nil }
            let size = (try? rolloutURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
            return LegacySessionCandidate(
                id: id,
                providerID: providerID,
                rolloutURL: rolloutURL,
                databaseRow: row,
                size: size
            )
        }
        guard !candidates.isEmpty else { return nil }

        let candidateIDs = Set(candidates.map { $0.providerID.lowercased() })
        let configuredProviderKeys = Set(providerSpecs.map { spec -> String in
            let baseURL = spec.baseURL?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            if let baseURL, !baseURL.isEmpty { return baseURL }
            return spec.id.lowercased()
        })
        let unmatchedIDs = candidateIDs.subtracting(Set(providerSpecs.map { $0.id.lowercased() }))
        let providerCount = configuredProviderKeys.count + unmatchedIDs.count

        return LegacySessionMigrationScan(
            providerCount: max(1, providerCount),
            providerIDs: candidateIDs.sorted(),
            sessionCount: candidates.count,
            totalBytes: candidates.reduce(0) { $0 + $1.size },
            databaseURL: databaseURL,
            sessions: candidates
        )
    }

    static func migrate(
        _ scan: LegacySessionMigrationScan,
        codexHome customCodexHome: URL? = nil
    ) throws -> LegacySessionMigrationResult {
        let codexHome = customCodexHome ?? defaultCodexHome
        let fileManager = FileManager.default
        let backupDirectory = migrationBackupDirectory(codexHome: codexHome)
        let sessionBackupDirectory = backupDirectory.appendingPathComponent(
            "original-sessions",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: sessionBackupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let databaseBackupURL = backupDirectory.appendingPathComponent(
            scan.databaseURL.lastPathComponent
        )
        try sqliteBackup(databaseURL: scan.databaseURL, destinationURL: databaseBackupURL)
        let configURL = codexHome.appendingPathComponent("config.toml")
        if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.copyItem(
                at: configURL,
                to: backupDirectory.appendingPathComponent("config.toml")
            )
        }

        var copiedFiles: [URL] = []
        var copiedRows: [([String: Any], sourceID: String, copiedID: String)] = []
        var reportCopies: [LegacySessionMigrationReport.Copy] = []
        var databaseCommitted = false
        do {
            for candidate in scan.sessions {
                let providerBackup = sessionBackupDirectory.appendingPathComponent(
                    safePathComponent(candidate.providerID),
                    isDirectory: true
                )
                try fileManager.createDirectory(
                    at: providerBackup,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let sourceBackup = providerBackup.appendingPathComponent(
                    candidate.rolloutURL.lastPathComponent
                )
                if !fileManager.fileExists(atPath: sourceBackup.path) {
                    try fileManager.copyItem(at: candidate.rolloutURL, to: sourceBackup)
                }

                let copiedID = UUID().uuidString.lowercased()
                let copiedURL = copiedRolloutURL(
                    sourceURL: candidate.rolloutURL,
                    sourceID: candidate.id,
                    copiedID: copiedID
                )
                let copiedData = try copiedRolloutData(
                    sourceURL: candidate.rolloutURL,
                    sourceID: candidate.id,
                    copiedID: copiedID
                )
                try copiedData.write(to: copiedURL, options: [.atomic])
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: copiedURL.path
                )
                copiedFiles.append(copiedURL)

                var copiedRow = candidate.databaseRow
                copiedRow["id"] = copiedID
                copiedRow["rollout_path"] = copiedURL.path
                copiedRow["model_provider"] = "openai"
                copiedRows.append((copiedRow, candidate.id, copiedID))
                reportCopies.append(.init(
                    sourceID: candidate.id,
                    copiedID: copiedID,
                    sourceProvider: candidate.providerID,
                    sourcePath: candidate.rolloutURL.path,
                    copiedPath: copiedURL.path
                ))
            }

            try insertCopiedRows(copiedRows, databaseURL: scan.databaseURL)
            databaseCommitted = true
            let report = LegacySessionMigrationReport(
                version: 1,
                completedAt: Date(),
                databasePath: scan.databaseURL.path,
                providerIDs: scan.providerIDs,
                copies: reportCopies
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let reportData = try encoder.encode(report)
            try reportData.write(to: reportURL(codexHome: codexHome), options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: reportURL(codexHome: codexHome).path
            )
        } catch {
            if !databaseCommitted {
                for copiedFile in copiedFiles {
                    try? fileManager.removeItem(at: copiedFile)
                }
            }
            throw error
        }
        return LegacySessionMigrationResult(
            copiedSessions: reportCopies.count,
            backupDirectory: backupDirectory
        )
    }

    private static var defaultCodexHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func sessionDatabaseURL(codexHome: URL) -> URL? {
        let fileManager = FileManager.default
        let preferred = codexHome.appendingPathComponent("state_5.sqlite")
        if fileManager.fileExists(atPath: preferred.path) { return preferred }
        guard let files = try? fileManager.contentsOfDirectory(
            at: codexHome,
            includingPropertiesForKeys: nil
        ) else { return nil }
        return files
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    private static func reportURL(codexHome: URL) -> URL {
        codexHome
            .appendingPathComponent("agent-pulse", isDirectory: true)
            .appendingPathComponent(reportName)
    }

    private static func migrationBackupDirectory(codexHome: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return codexHome
            .appendingPathComponent("agent-pulse/session-migration-backups", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
    }

    private static func thirdPartyProviders(in config: String) -> [LegacyProviderSpec] {
        var providers: [LegacyProviderSpec] = []
        var currentID: String?
        var currentBaseURL: String?

        func finishCurrent() {
            guard let providerID = currentID, providerID.lowercased() != "openai" else {
                currentID = nil
                currentBaseURL = nil
                return
            }
            providers.append(.init(id: providerID, baseURL: currentBaseURL))
            currentID = nil
            currentBaseURL = nil
        }

        for line in config.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                finishCurrent()
                guard trimmed.hasPrefix("[model_providers."),
                      trimmed.hasSuffix("]"),
                      !trimmed.hasSuffix(".auth]") else { continue }
                let start = trimmed.index(
                    trimmed.startIndex,
                    offsetBy: "[model_providers.".count
                )
                let end = trimmed.index(before: trimmed.endIndex)
                let id = String(trimmed[start..<end])
                if !id.isEmpty { currentID = id }
                continue
            }
            guard currentID != nil,
                  let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            guard key == "base_url" else { continue }
            currentBaseURL = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        finishCurrent()
        return providers
    }

    private static func copiedRolloutURL(
        sourceURL: URL,
        sourceID: String,
        copiedID: String
    ) -> URL {
        let sourceName = sourceURL.lastPathComponent
        let copiedName: String
        if let range = sourceName.range(of: sourceID, options: [.backwards]) {
            copiedName = sourceName.replacingCharacters(in: range, with: copiedID)
        } else {
            copiedName = sourceURL.deletingPathExtension().lastPathComponent
                + "-\(copiedID).jsonl"
        }
        return sourceURL.deletingLastPathComponent().appendingPathComponent(copiedName)
    }

    private static func copiedRolloutData(
        sourceURL: URL,
        sourceID: String,
        copiedID: String
    ) throws -> Data {
        let data = try Data(contentsOf: sourceURL)
        guard let newline = data.firstIndex(of: 0x0A) else {
            throw LegacySessionMigrationError.invalidSession(sourceURL.lastPathComponent)
        }
        let firstLine = data.subdata(in: 0..<newline)
        guard var object = try JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
              object["type"] as? String == "session_meta",
              var payload = object["payload"] as? [String: Any] else {
            throw LegacySessionMigrationError.invalidSession(sourceURL.lastPathComponent)
        }
        if payload["id"] as? String == sourceID { payload["id"] = copiedID }
        if payload["session_id"] as? String == sourceID { payload["session_id"] = copiedID }
        payload["model_provider"] = "openai"
        object["payload"] = payload
        var rendered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        rendered.append(0x0A)
        rendered.append(data.subdata(in: data.index(after: newline)..<data.endIndex))
        return rendered
    }

    private static func insertCopiedRows(
        _ rows: [([String: Any], sourceID: String, copiedID: String)],
        databaseURL: URL
    ) throws {
        guard !rows.isEmpty else { return }
        let tableNames = try sqliteText(
            databaseURL: databaseURL,
            sql: "SELECT name FROM sqlite_master WHERE type='table';",
            readOnly: true
        )
        .components(separatedBy: .newlines)
        let hasDynamicTools = tableNames.contains("thread_dynamic_tools")
        let dynamicToolColumns = hasDynamicTools
            ? try tableColumns(databaseURL: databaseURL, table: "thread_dynamic_tools")
            : []
        let copiedDynamicColumns = dynamicToolColumns.filter { $0 != "thread_id" }
        let hasSpawnEdges = tableNames.contains("thread_spawn_edges")

        var statements = ["PRAGMA foreign_keys=ON;", "BEGIN IMMEDIATE;"]
        for item in rows {
            let columns = item.0.keys.sorted()
            let values = columns.map { sqlLiteral(item.0[$0] ?? NSNull()) }
            statements.append(
                "INSERT INTO threads (\(columns.map(sqlIdentifier).joined(separator: ","))) "
                    + "VALUES (\(values.joined(separator: ",")));"
            )
            if hasDynamicTools, !copiedDynamicColumns.isEmpty {
                let insertedColumns = ["thread_id"] + copiedDynamicColumns
                statements.append(
                    "INSERT INTO thread_dynamic_tools "
                        + "(\(insertedColumns.map(sqlIdentifier).joined(separator: ","))) "
                        + "SELECT \(sqlLiteral(item.copiedID)),"
                        + copiedDynamicColumns.map(sqlIdentifier).joined(separator: ",")
                        + " FROM thread_dynamic_tools "
                        + "WHERE thread_id=\(sqlLiteral(item.sourceID));"
                )
            }
        }
        if hasSpawnEdges {
            let parentMapping = rows.map {
                "WHEN \(sqlLiteral($0.sourceID)) THEN \(sqlLiteral($0.copiedID))"
            }.joined(separator: " ")
            for item in rows {
                statements.append(
                    "INSERT INTO thread_spawn_edges (parent_thread_id,child_thread_id,status) "
                        + "SELECT CASE parent_thread_id \(parentMapping) ELSE parent_thread_id END,"
                        + "\(sqlLiteral(item.copiedID)),status FROM thread_spawn_edges "
                        + "WHERE child_thread_id=\(sqlLiteral(item.sourceID));"
                )
            }
        }
        statements.append("COMMIT;")
        _ = try sqliteText(
            databaseURL: databaseURL,
            sql: statements.joined(separator: "\n"),
            readOnly: false
        )
    }

    private static func tableColumns(databaseURL: URL, table: String) throws -> [String] {
        let text = try sqliteText(
            databaseURL: databaseURL,
            sql: "PRAGMA table_info(\(sqlIdentifier(table)));",
            readOnly: true
        )
        return text.components(separatedBy: .newlines).compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count > 1 else { return nil }
            return String(fields[1])
        }
    }

    private static func sqliteBackup(databaseURL: URL, destinationURL: URL) throws {
        let command = ".backup \(sqliteDotQuoted(destinationURL.path))"
        _ = try runSQLite(
            arguments: [databaseURL.path, command],
            errorPrefix: "无法备份会话数据库"
        )
    }

    private static func sqliteJSON(databaseURL: URL, sql: String) throws -> [[String: Any]] {
        let data = try runSQLite(
            arguments: ["-readonly", "-json", databaseURL.path, sql],
            errorPrefix: "无法读取会话索引"
        )
        guard !data.isEmpty else { return [] }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LegacySessionMigrationError.invalidDatabase("SQLite 返回格式无法识别")
        }
        return rows
    }

    private static func sqliteText(
        databaseURL: URL,
        sql: String,
        readOnly: Bool
    ) throws -> String {
        var arguments: [String] = []
        if readOnly { arguments.append("-readonly") }
        arguments.append(contentsOf: [databaseURL.path, sql])
        let data = try runSQLite(arguments: arguments, errorPrefix: "SQLite 执行失败")
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runSQLite(arguments: [String], errorPrefix: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw LegacySessionMigrationError.commandFailed(
                "\(errorPrefix)：\(error.localizedDescription)"
            )
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorData,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知错误"
            throw LegacySessionMigrationError.commandFailed("\(errorPrefix)：\(message)")
        }
        return outputData
    }

    private static func sqlLiteral(_ value: Any) -> String {
        if value is NSNull { return "NULL" }
        if let value = value as? String {
            return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }
        if let value = value as? NSNumber { return value.stringValue }
        return "'" + String(describing: value)
            .replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func sqlIdentifier(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func sqliteDotQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func safePathComponent(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
                ? Character(String(scalar)) : "_"
        })
    }
}
