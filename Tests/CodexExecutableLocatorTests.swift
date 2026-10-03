import Foundation

@main
struct CodexExecutableLocatorTests {
    struct Failure: Error {
        let message: String
    }

    static func main() {
        do {
            try run()
        } catch {
            print("失败：\(error)")
            exit(1)
        }
    }

    static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let application = root.appendingPathComponent("ChatGPT.app")
        let wrapper = application.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try createExecutable(at: wrapper)
        try expect(CodexExecutableLocator.url(in: [application]), wrapper, "发现新版 CLI 启动脚本")

        let codexApplication = root.appendingPathComponent("Codex.app")
        let bundled = codexApplication.appendingPathComponent(
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        )
        try createExecutable(at: bundled)
        try expect(CodexExecutableLocator.url(in: [codexApplication]), bundled, "启动脚本缺失时发现内置 CLI")

        let legacyApplication = root.appendingPathComponent("Legacy.app")
        let legacy = legacyApplication.appendingPathComponent("Contents/Resources/codex")
        try createExecutable(at: legacy)
        try expect(CodexExecutableLocator.url(in: [legacyApplication]), legacy, "兼容旧版 CLI 路径")

        let missingApplication = root.appendingPathComponent("Missing.app")
        try expect(CodexExecutableLocator.url(in: [missingApplication]), nil, "CLI 缺失时返回 nil")
        try expect(
            CodexExecutableLocator.url(in: [missingApplication, legacyApplication]),
            legacy,
            "首个应用没有 CLI 时继续检查备用应用"
        )

        let disabledApplication = root.appendingPathComponent("Disabled.app")
        let disabled = disabledApplication.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try createExecutable(at: disabled, permissions: 0o600)
        try expect(CodexExecutableLocator.url(in: [disabledApplication]), nil, "忽略不可执行的 CLI 文件")

        let disabledWrapper = codexApplication.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        try createExecutable(at: disabledWrapper, permissions: 0o600)
        try expect(
            CodexExecutableLocator.url(in: [codexApplication]),
            bundled,
            "启动脚本不可执行时回退到内置 CLI"
        )

        try createExecutable(at: application.appendingPathComponent(
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ))
        try createExecutable(at: application.appendingPathComponent("Contents/Resources/codex"))
        try expect(CodexExecutableLocator.url(in: [application]), wrapper, "优先使用新版 CLI 启动脚本")
        try expect(
            CodexExecutableLocator.url(in: [legacyApplication, application]),
            legacy,
            "优先使用已识别应用中的 CLI"
        )
    }

    static func createExecutable(at url: URL, permissions: Int = 0o700) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    static func expect(_ actual: URL?, _ expected: URL?, _ label: String) throws {
        guard actual == expected else {
            throw Failure(message: "\(label)：期望 \(expected?.path ?? "nil")，实际 \(actual?.path ?? "nil")")
        }
        print("通过：\(label)")
    }
}
