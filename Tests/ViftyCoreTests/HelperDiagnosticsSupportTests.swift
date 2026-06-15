import XCTest
@testable import Vifty

final class HelperDiagnosticsSupportTests: XCTestCase {
    func testSupportEvidenceCopyExplainsTerminalAndReadOnlyScope() {
        XCTAssertEqual(HelperDiagnosticsSupport.copiedMessage, "Copied Terminal support command")
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("Terminal command"))
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("read-only support evidence"))
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("richest available viftyctl evidence"))
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("current Vifty UI context"))
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("without requesting cooling"))
        XCTAssertTrue(HelperDiagnosticsSupport.copyHelp.contains("writing fan state"))
    }

    func testSupportEvidenceCommandUsesBundledCollectorAndViftyCtlWhenAvailable() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let collectorURL = resourcesURL.appendingPathComponent("collect-agent-cooling-evidence.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: collectorURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: collectorURL.path)

        let command = HelperDiagnosticsSupport.supportEvidenceCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertEqual(
            command,
            "umask 077; '\(collectorURL.path)' --viftyctl '\(viftyCtlURL.path)' --output \"$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)\""
        )
        XCTAssertFalse(command.contains(" sudo "))
        XCTAssertFalse(command.contains(" prepare"))
        XCTAssertFalse(command.contains(" run "))
        XCTAssertFalse(command.contains(" restore-auto"))
        XCTAssertFalse(command.contains("ViftyHelper"))
        XCTAssertFalse(command.contains("setFixed"))
    }

    func testSupportEvidenceCommandCanCaptureUIContextBesideCollectorOutput() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let collectorURL = resourcesURL.appendingPathComponent("collect-agent-cooling-evidence.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: collectorURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: collectorURL.path)
        let context = HelperSupportEvidenceContext(lines: [
            "selectedMode=Curve",
            "helper=reader's daemon unavailable"
        ])

        let command = HelperDiagnosticsSupport.supportEvidenceCommand(
            bundleURL: appURL,
            executableURL: nil,
            context: context
        )

        XCTAssertTrue(command.contains("umask 077; context=\"$(mktemp \"${TMPDIR:-/tmp}/vifty-ui-context.XXXXXXXX\")\""))
        XCTAssertTrue(command.contains("trap 'rm -f \"$context\"' EXIT"))
        XCTAssertTrue(command.contains("> \"$context\""))
        XCTAssertTrue(command.contains("out=\"$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)\""))
        XCTAssertTrue(command.contains("'selectedMode=Curve'"))
        XCTAssertTrue(command.contains("'helper=reader'\\''s daemon unavailable'"))
        XCTAssertTrue(command.contains("'\(collectorURL.path)' --viftyctl '\(viftyCtlURL.path)' --output \"$out\" --ui-context-file \"$context\""))
        XCTAssertFalse(command.contains("mkdir -p \"$out\""))
        XCTAssertFalse(command.contains("> \"$out/ui-context.txt\""))
        XCTAssertFalse(command.contains(" prepare"))
        XCTAssertFalse(command.contains(" restore-auto"))
        XCTAssertFalse(command.contains("setFixed"))
    }

    func testSupportEvidenceCommandFallsBackToDiagnoseWhenCollectorIsMissing() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)

        let command = HelperDiagnosticsSupport.supportEvidenceCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertEqual(command, "'\(viftyCtlURL.path)' diagnose --json")
    }

    func testSupportEvidenceCommandShellQuotesBundledCollectorAndToolPaths() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty's Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let collectorURL = resourcesURL.appendingPathComponent("collect-agent-cooling-evidence.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: collectorURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: collectorURL.path)

        let command = HelperDiagnosticsSupport.supportEvidenceCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertTrue(command.hasPrefix("umask 077; '\(collectorURL.path.replacingOccurrences(of: "'", with: "'\\''"))' --viftyctl '\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))'"))
    }

    func testDiagnoseCommandUsesBundledViftyCtlWhenExecutableExists() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)

        let command = HelperDiagnosticsSupport.diagnoseCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertEqual(command, "'\(viftyCtlURL.path)' diagnose --json")
    }

    func testDiagnoseCommandShellQuotesSingleQuotesInBundledPath() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty's Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)

        let command = HelperDiagnosticsSupport.diagnoseCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertEqual(command, "'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' diagnose --json")
    }

    func testDiagnoseCommandFallsBackToCanonicalInstalledPathWhenToolIsMissing() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let command = HelperDiagnosticsSupport.diagnoseCommand(bundleURL: appURL, executableURL: nil)

        XCTAssertEqual(command, "/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json")
    }

    func testDiagnoseCommandUsesAdjacentSwiftPMViftyCtlForSourceRuns() throws {
        let root = try temporaryDirectory()
        let buildURL = root.appendingPathComponent("debug", isDirectory: true)
        try FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true)
        let executableURL = buildURL.appendingPathComponent("Vifty", isDirectory: false)
        let viftyCtlURL = buildURL.appendingPathComponent("ViftyCtl", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)

        let command = HelperDiagnosticsSupport.diagnoseCommand(
            bundleURL: executableURL,
            executableURL: executableURL
        )

        XCTAssertEqual(command, "'\(viftyCtlURL.path)' diagnose --json")
    }

    func testDiagnoseCommandUsesAdjacentLowercaseViftyCtlForDevelopmentAppLayouts() throws {
        let root = try temporaryDirectory()
        let buildURL = root.appendingPathComponent("debug", isDirectory: true)
        try FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true)
        let executableURL = buildURL.appendingPathComponent("Vifty", isDirectory: false)
        let viftyCtlURL = buildURL.appendingPathComponent("viftyctl", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)

        let command = HelperDiagnosticsSupport.diagnoseCommand(
            bundleURL: executableURL,
            executableURL: executableURL
        )

        XCTAssertEqual(command, "'\(viftyCtlURL.path)' diagnose --json")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViftyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
