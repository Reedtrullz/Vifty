import AppKit
import Foundation

struct HelperSupportEvidenceContext: Equatable, Sendable {
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines
            .map { line in
                line
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}

enum HelperDiagnosticsSupport {
    static let copyHelp = "Copy a Terminal command for read-only support evidence. It captures the richest available viftyctl evidence plus current Vifty UI context without requesting cooling, restoring Auto, or writing fan state."
    static let copiedMessage = "Copied Terminal support command"

    private static let collectorResourceName = "collect-agent-cooling-evidence.sh"
    private static let supportEvidenceOutputPath = "$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)"

    static func supportEvidenceCommand(
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default,
        context: HelperSupportEvidenceContext? = nil
    ) -> String {
        let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
        let bundledCollector = bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent(collectorResourceName, isDirectory: false)
        if bundleURL.pathExtension == "app",
           fileManager.isExecutableFile(atPath: bundledTool.path),
           fileManager.isExecutableFile(atPath: bundledCollector.path) {
            if let context, !context.lines.isEmpty {
                let contextLines = context.lines.map(shellQuote).joined(separator: " ")
                return "umask 077; context=\"$(mktemp \"${TMPDIR:-/tmp}/vifty-ui-context.XXXXXXXX\")\"; trap 'rm -f \"$context\"' EXIT; printf '%s\\n' \(contextLines) > \"$context\"; out=\"\(supportEvidenceOutputPath)\"; \(shellQuote(bundledCollector.path)) --viftyctl \(shellQuote(bundledTool.path)) --output \"$out\" --ui-context-file \"$context\""
            }
            return "umask 077; \(shellQuote(bundledCollector.path)) --viftyctl \(shellQuote(bundledTool.path)) --output \"\(supportEvidenceOutputPath)\""
        }
        return diagnoseCommand(
            bundleURL: bundleURL,
            executableURL: executableURL,
            fileManager: fileManager
        )
    }

    static func diagnoseCommand(
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> String {
        let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
        if bundleURL.pathExtension == "app",
           fileManager.isExecutableFile(atPath: bundledTool.path) {
            return "\(shellQuote(bundledTool.path)) diagnose --json"
        }
        if let devTool = developmentToolURL(beside: executableURL, fileManager: fileManager) {
            return "\(shellQuote(devTool.path)) diagnose --json"
        }
        return "/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json"
    }

    @discardableResult
    @MainActor
    static func copySupportEvidenceCommand(
        context: HelperSupportEvidenceContext? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        pasteboard: NSPasteboard = .general
    ) -> String {
        let command = supportEvidenceCommand(bundleURL: bundleURL, context: context)
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        return command
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

    private static func developmentToolURL(
        beside executableURL: URL?,
        fileManager: FileManager
    ) -> URL? {
        guard let executableURL else { return nil }
        let directory = executableURL.deletingLastPathComponent()
        let preferredNames = ["ViftyCtl", "viftyctl"]
        let directoryEntries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let exactNames = preferredNames.filter { directoryEntries.contains($0) }
        let names = exactNames.isEmpty ? preferredNames : exactNames
        for name in names {
            let candidate = directory.appendingPathComponent(name, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
