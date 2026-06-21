import XCTest
@testable import Vifty

final class AgentWorkflowSupportTests: XCTestCase {
    func testAgentRuleExplainsGuardedLocalCoolingContract() {
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("AGENTS.md"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("viftyctl diagnose"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("guarded-run"))
        XCTAssertTrue(AgentWorkflowSupport.copiedMessage.contains("Copied"))

        let rule = AgentWorkflowSupport.agentRule()

        XCTAssertTrue(rule.contains("diagnose --json"))
        XCTAssertTrue(rule.contains("safeToRequestCooling"))
        XCTAssertTrue(rule.contains("daemonControlPathReady"))
        XCTAssertTrue(rule.contains("manualControlActive"))
        XCTAssertTrue(rule.contains("coolingBlockerIDs"))
        XCTAssertTrue(rule.contains("guarded-run.sh"))
        XCTAssertTrue(rule.contains("--preflight-only"))
        XCTAssertTrue(rule.contains("test 20m 70 'swift test' -- swift test"))
        XCTAssertTrue(rule.contains("Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` and `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset"))
        XCTAssertTrue(rule.contains("Do not catch a guarded-run failure and rerun the same workload without Vifty"))
        XCTAssertTrue(rule.contains("Never call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, direct fan RPM writes, or unguarded `viftyctl prepare` from an agent."))
    }

    func testAgentRuleUsesBundledViftyCtlAndGuardedRunWhenAvailable() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let wrappersURL = appURL.appendingPathComponent("Contents/Resources/viftyctl-wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' diagnose --json"))
        XCTAssertTrue(rule.contains("'\(guardedRunURL.path)' test 20m 70 'swift test' -- swift test"))
        XCTAssertTrue(rule.contains("'\(guardedRunURL.path)' --preflight-only test 20m 70 'swift test' -- swift test"))
    }

    func testAgentRuleShellQuotesBundledPaths() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty's Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let wrappersURL = appURL.appendingPathComponent("Contents/Resources/viftyctl-wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' diagnose --json"))
        XCTAssertTrue(rule.contains("'\(guardedRunURL.path.replacingOccurrences(of: "'", with: "'\\''"))' test 20m 70 'swift test' -- swift test"))
    }

    func testAgentRuleFallsBackToCanonicalInstalledAppPaths() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json"))
        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh' test 20m 70 'swift test' -- swift test"))
        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh' --preflight-only test 20m 70 'swift test' -- swift test"))
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
