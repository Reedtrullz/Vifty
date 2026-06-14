import XCTest
@testable import Vifty

final class HelperDiagnosticsSupportTests: XCTestCase {
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
