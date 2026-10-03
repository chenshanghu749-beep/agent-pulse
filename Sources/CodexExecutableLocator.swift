import AppKit
import Foundation

enum CodexExecutableLocator {
    static func url(for bundleIdentifier: String) -> URL? {
        let applications = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app")
        ].compactMap { $0 }
        return url(in: applications)
    }

    static func url(in applications: [URL]) -> URL? {
        let relativePaths = [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex"
        ]
        return applications
            .flatMap { application in
                relativePaths.map { application.appendingPathComponent($0) }
            }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
