import Foundation
import WidgetKit

enum WidgetRegistration {
    private static let launchServicesURL = URL(
        fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    )
    private static let pluginKitURL = URL(fileURLWithPath: "/usr/bin/pluginkit")

    static func ensureRegistered() {
        let appURL = Bundle.main.bundleURL
        let extensionURL = appURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent("CodexPulseWidget.appex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: extensionURL.path) else { return }

        DispatchQueue.global(qos: .utility).async {
            run(launchServicesURL, arguments: ["-f", appURL.path])
            run(pluginKitURL, arguments: ["-a", extensionURL.path])
            DispatchQueue.main.async {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    private static func run(_ executableURL: URL, arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}
