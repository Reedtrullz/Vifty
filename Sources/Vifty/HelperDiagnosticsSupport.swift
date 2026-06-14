import AppKit
import Foundation

enum HelperDiagnosticsSupport {
    static let copyHelp = "Copy a read-only viftyctl diagnose command. It does not request cooling or write fan state."
    static let copiedMessage = "Copied read-only diagnose command"

    static func diagnoseCommand(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
        if bundleURL.pathExtension == "app",
           fileManager.isExecutableFile(atPath: bundledTool.path) {
            return "\(shellQuote(bundledTool.path)) diagnose --json"
        }
        return "/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json"
    }

    @discardableResult
    @MainActor
    static func copyDiagnoseCommand(
        bundleURL: URL = Bundle.main.bundleURL,
        pasteboard: NSPasteboard = .general
    ) -> String {
        let command = diagnoseCommand(bundleURL: bundleURL)
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        return command
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
