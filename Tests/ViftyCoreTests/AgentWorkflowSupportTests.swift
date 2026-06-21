import XCTest
@testable import Vifty

final class AgentWorkflowSupportTests: XCTestCase {
    func testAgentRuleExplainsGuardedLocalCoolingContract() {
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("AGENTS.md"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("viftyctl capabilities"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("viftyctl diagnose"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("guarded-run"))
        XCTAssertTrue(AgentWorkflowSupport.copyCommandHelp.contains("audited guarded-run"))
        XCTAssertTrue(AgentWorkflowSupport.copiedMessage.contains("Copied"))
        XCTAssertTrue(AgentWorkflowSupport.copiedCommandMessage.contains("Copied"))
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "swift-test" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "swift-release-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "make-verify" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "local-model-template" })

        let rule = AgentWorkflowSupport.agentRule()

        XCTAssertTrue(rule.contains("capabilities --json"))
        XCTAssertTrue(rule.contains("diagnose --json"))
        XCTAssertTrue(rule.contains("schemaVersion: 1"))
        XCTAssertTrue(rule.contains("schemaIDs.diagnose"))
        XCTAssertTrue(rule.contains("schemaIDs.commandError"))
        XCTAssertTrue(rule.contains("schemaIDs.run"))
        XCTAssertTrue(rule.contains("wrapperResources"))
        XCTAssertTrue(rule.contains("runLifecycle.resolvedChildExecutableReported: true"))
        XCTAssertTrue(rule.contains("policyStatusAvailable: true"))
        XCTAssertTrue(rule.contains("policy.enabled: true"))
        XCTAssertTrue(rule.contains("support for the requested workload"))
        XCTAssertTrue(rule.contains("wrapperResources.bundleDirectory"))
        XCTAssertTrue(rule.contains("wrapperResources.sourceDirectory"))
        XCTAssertTrue(rule.contains("wrapperResources.guardedRunScript"))
        XCTAssertTrue(rule.contains("wrapperResources.workloadScripts"))
        XCTAssertTrue(rule.contains("instead of inventing unaudited fan-control commands"))
        XCTAssertTrue(rule.contains("safeToRequestCooling"))
        XCTAssertTrue(rule.contains("daemonControlPathReady"))
        XCTAssertTrue(rule.contains("manualControlActive"))
        XCTAssertTrue(rule.contains("coolingBlockerIDs"))
        XCTAssertTrue(rule.contains("guarded-run.sh"))
        XCTAssertTrue(rule.contains("--preflight-only"))
        XCTAssertTrue(rule.contains("swift-test.sh"))
        XCTAssertTrue(rule.contains("'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
        XCTAssertTrue(rule.contains("extract only the JSON payload between"))
        XCTAssertTrue(rule.contains("guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON"))
        XCTAssertTrue(rule.contains("guarded-run: END_VIFTY_CAPABILITIES_JSON"))
        XCTAssertTrue(rule.contains("guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON"))
        XCTAssertTrue(rule.contains("guarded-run: END_VIFTY_DIAGNOSE_JSON"))
        XCTAssertTrue(rule.contains("guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON"))
        XCTAssertTrue(rule.contains("guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON"))
        XCTAssertTrue(rule.contains("https://vifty.local/schemas/guarded-run-decision.schema.json"))
        XCTAssertTrue(rule.contains("decisionReason"))
        XCTAssertTrue(rule.contains("coolingRequested: false"))
        XCTAssertTrue(rule.contains("Do not parse surrounding recovery prose"))
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
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try Data("#!/bin/sh\n".utf8).write(to: swiftTestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: swiftTestURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' capabilities --json"))
        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' diagnose --json"))
        XCTAssertTrue(rule.contains("'\(swiftTestURL.path)'"))
        XCTAssertTrue(rule.contains("'\(guardedRunURL.path)' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
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
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try Data("#!/bin/sh\n".utf8).write(to: swiftTestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: swiftTestURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' capabilities --json"))
        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' diagnose --json"))
        XCTAssertTrue(rule.contains("'\(swiftTestURL.path.replacingOccurrences(of: "'", with: "'\\''"))'"))
        XCTAssertTrue(rule.contains("'\(guardedRunURL.path.replacingOccurrences(of: "'", with: "'\\''"))' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
    }

    func testAgentRuleFallsBackToCanonicalInstalledAppPaths() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/MacOS/viftyctl' capabilities --json"))
        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json"))
        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-test.sh'"))
        XCTAssertTrue(rule.contains("'/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
    }

    func testWorkloadCommandTemplatesCopyAuditedRunAndReadOnlyPreflightCommands() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let wrappersURL = appURL.appendingPathComponent("Contents/Resources/viftyctl-wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)

        for relativePath in [
            "Contents/MacOS/viftyctl",
            "Contents/Resources/viftyctl-wrappers/guarded-run.sh",
            "Contents/Resources/viftyctl-wrappers/swift-test.sh",
            "Contents/Resources/viftyctl-wrappers/local-model.sh"
        ] {
            let url = appURL.appendingPathComponent(relativePath, isDirectory: false)
            try Data("#!/bin/sh\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: url.path)
        }

        let swiftTest = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "swift-test" })
        let localModel = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "local-model-template" })

        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(swiftTest, mode: .run, bundleURL: appURL),
            "'\(wrappersURL.appendingPathComponent("swift-test.sh").path)'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(swiftTest, mode: .preflight, bundleURL: appURL),
            "'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(localModel, mode: .run, bundleURL: appURL),
            "'\(wrappersURL.appendingPathComponent("local-model.sh").path)' '--' './run-local-model.sh'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(localModel, mode: .preflight, bundleURL: appURL),
            "'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'localModel' '30m' '75' 'local model run' '--' './run-local-model.sh'"
        )
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
