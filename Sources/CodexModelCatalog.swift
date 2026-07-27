import Foundation

enum CodexModelCatalogError: LocalizedError {
    case codexNotFound
    case generationFailed(String)
    case invalidCatalog
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未找到 Codex 命令，无法生成第三方模型兼容配置。"
        case let .generationFailed(message):
            return "读取 Codex 模型目录失败：\(message)"
        case .invalidCatalog:
            return "Codex 返回了无法识别的模型目录。"
        case let .modelNotFound(model):
            return "Codex 模型目录中没有 \(model)，无法应用 Responses Lite 兼容修复。"
        }
    }
}

enum CodexModelCatalog {
    static var catalogURL: URL {
        CredentialStore.directoryURL.appendingPathComponent("provider-model-catalog.json")
    }

    static func needsCompatibilityOverride(model: String) -> Bool {
        model.lowercased().hasPrefix("gpt-5.6")
    }

    static func prepareIfNeeded(model: String) throws -> URL? {
        guard needsCompatibilityOverride(model: model) else { return nil }
        guard let executable = codexURL() else {
            throw CodexModelCatalogError.codexNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["debug", "models", "--bundled"]
        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw CodexModelCatalogError.generationFailed(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexModelCatalogError.generationFailed(message ?? "Codex 命令退出异常")
        }

        let patched = try patchedCatalog(data, selectedModel: model)
        try CredentialStore.prepareDirectory()
        try patched.write(to: catalogURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: catalogURL.path
        )
        return catalogURL
    }

    static func patchedCatalog(_ data: Data, selectedModel: String) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var models = root["models"] as? [[String: Any]] else {
            throw CodexModelCatalogError.invalidCatalog
        }

        var foundSelectedModel = false
        for index in models.indices {
            guard let slug = models[index]["slug"] as? String else { continue }
            if slug.caseInsensitiveCompare(selectedModel) == .orderedSame {
                foundSelectedModel = true
            }
            if (models[index]["use_responses_lite"] as? Bool) == true {
                models[index]["use_responses_lite"] = false
                if (models[index]["multi_agent_version"] as? String) == "v2" {
                    models[index]["multi_agent_version"] = "v1"
                }
            }
        }
        guard foundSelectedModel else {
            throw CodexModelCatalogError.modelNotFound(selectedModel)
        }

        root["models"] = models
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func codexURL() -> URL? {
        [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        .map(URL.init(fileURLWithPath:))
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
