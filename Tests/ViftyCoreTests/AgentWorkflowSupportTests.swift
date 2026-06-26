import XCTest
@testable import Vifty
import ViftyCore

final class AgentWorkflowSupportTests: XCTestCase {
    func testAgentRuleExplainsGuardedLocalCoolingContract() {
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("AGENTS.md"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("viftyctl capabilities"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("viftyctl diagnose"))
        XCTAssertTrue(AgentWorkflowSupport.copyHelp.contains("guarded-run"))
        XCTAssertTrue(AgentWorkflowSupport.copyCommandHelp.contains("audited guarded-run"))
        XCTAssertTrue(AgentWorkflowSupport.copiedMessage.contains("Copied"))
        XCTAssertTrue(AgentWorkflowSupport.copiedCommandMessage.contains("Copied"))
        XCTAssertEqual(
            Set(AgentWorkflowSupport.safeWorkloadCommandTemplates.map(\.shortcutScript)),
            Set(ViftyCtlWrapperResources.workloadScriptNames)
        )
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "swift-test" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "swift-release-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "xcode-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "make-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "make-verify" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "npm-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "pnpm-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "bun-test" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "go-test" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "cargo-build" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "uv-test" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "pytest" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "local-model-template" })
        XCTAssertTrue(AgentWorkflowSupport.safeWorkloadCommandTemplates.contains { $0.id == "custom-workload-template" })

        let rule = AgentWorkflowSupport.agentRule()

        XCTAssertTrue(rule.contains("capabilities --json"))
        XCTAssertTrue(rule.contains("diagnose --json"))
        XCTAssertTrue(rule.contains("schemaVersion: 1"))
        XCTAssertTrue(rule.contains("schemaIDs.capabilities"))
        XCTAssertTrue(rule.contains("schemaIDs.diagnose"))
        XCTAssertTrue(rule.contains("schemaIDs.commandError"))
        XCTAssertTrue(rule.contains("schemaIDs.run"))
        XCTAssertTrue(rule.contains("wrapperResources"))
        XCTAssertTrue(rule.contains("workloadTemplates"))
        XCTAssertTrue(rule.contains("runLifecycle.resolvedChildExecutableReported: true"))
        XCTAssertTrue(rule.contains("policyStatusAvailable: true"))
        XCTAssertTrue(rule.contains("policy.enabled: true"))
        XCTAssertTrue(rule.contains("support for the requested workload"))
        XCTAssertTrue(rule.contains("wrapperResources.bundleDirectory"))
        XCTAssertTrue(rule.contains("wrapperResources.sourceDirectory"))
        XCTAssertTrue(rule.contains("wrapperResources.guardedRunScript"))
        XCTAssertTrue(rule.contains("wrapperResources.workloadScripts"))
        XCTAssertTrue(rule.contains("copied command templates"))
        XCTAssertTrue(rule.contains("audited workload defaults"))
        XCTAssertTrue(rule.contains("instead of inventing unaudited fan-control commands"))
        XCTAssertTrue(rule.contains("safeToRequestCooling"))
        XCTAssertTrue(rule.contains("daemonControlPathReady"))
        XCTAssertTrue(rule.contains("manualControlActive"))
        XCTAssertTrue(rule.contains("daemonRuntime.matchRequired"))
        XCTAssertTrue(rule.contains("daemonRuntime.matchesExpectedDaemon"))
        XCTAssertTrue(rule.contains("coolingBlockerIDs"))
        XCTAssertTrue(rule.contains("guarded-run.sh"))
        XCTAssertTrue(rule.contains("--preflight-only"))
        XCTAssertTrue(rule.contains("swift-test.sh"))
        XCTAssertTrue(rule.contains("'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
        XCTAssertTrue(rule.contains("extract only the JSON payload between"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.capabilities.begin"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.diagnose.begin"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.decision.begin"))
        XCTAssertTrue(rule.contains("instead of hardcoding marker strings"))
        XCTAssertTrue(rule.contains("guardedRunDecisionSchemaID"))
        XCTAssertTrue(rule.contains("decisionReason"))
        XCTAssertTrue(rule.contains("coolingRequested: false"))
        XCTAssertTrue(rule.contains("Do not parse surrounding recovery prose"))
        XCTAssertTrue(rule.contains("agentCoolingEvidenceCommand"))
        XCTAssertTrue(rule.contains("agentCoolingPreflightEvidenceCommand"))
        XCTAssertTrue(rule.contains("collect capabilities, diagnose, status, audit, launchd/helper evidence, privacy review, and optional guarded-run preflight evidence only"))
        XCTAssertTrue(rule.contains("they are not cooling authorization"))
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
        let evidenceCollectorURL = appURL.appendingPathComponent("Contents/Resources/collect-agent-cooling-evidence.sh", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: evidenceCollectorURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try Data("#!/bin/sh\n".utf8).write(to: swiftTestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: evidenceCollectorURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: swiftTestURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' capabilities --json"))
        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' diagnose --json"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(swiftTestURL.path)'"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(guardedRunURL.path)' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
    }

    func testAgentRuleShellQuotesBundledPaths() throws {
        let root = try temporaryDirectory()
        let appURL = root.appendingPathComponent("Vifty's Dev.app", isDirectory: true)
        let macOSURL = appURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let wrappersURL = appURL.appendingPathComponent("Contents/Resources/viftyctl-wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
        let viftyCtlURL = macOSURL.appendingPathComponent("viftyctl", isDirectory: false)
        let evidenceCollectorURL = appURL.appendingPathComponent("Contents/Resources/collect-agent-cooling-evidence.sh", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: evidenceCollectorURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try Data("#!/bin/sh\n".utf8).write(to: swiftTestURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: evidenceCollectorURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: swiftTestURL.path)

        let rule = AgentWorkflowSupport.agentRule(bundleURL: appURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' capabilities --json"))
        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' diagnose --json"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' '\(swiftTestURL.path.replacingOccurrences(of: "'", with: "'\\''"))'"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path.replacingOccurrences(of: "'", with: "'\\''"))' '\(guardedRunURL.path.replacingOccurrences(of: "'", with: "'\\''"))' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
    }

    func testAgentRuleUsesSourceCheckoutWrappersWhenRunFromSwiftPMBuildDirectory() throws {
        let root = try temporaryDirectory()
        try Data("swift-tools-version: 6.0\n".utf8).write(to: root.appendingPathComponent("Package.swift"))

        let buildURL = root.appendingPathComponent(".build/debug", isDirectory: true)
        let wrappersURL = root.appendingPathComponent("examples/viftyctl", isDirectory: true)
        let scriptsURL = root.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)

        let viftyCtlURL = buildURL.appendingPathComponent("ViftyCtl", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        let evidenceCollectorURL = scriptsURL.appendingPathComponent("collect-agent-cooling-evidence.sh", isDirectory: false)
        try Data("#!/bin/sh\n".utf8).write(to: viftyCtlURL)
        try Data("#!/bin/sh\n".utf8).write(to: guardedRunURL)
        try Data("#!/bin/sh\n".utf8).write(to: swiftTestURL)
        try Data("#!/bin/sh\n".utf8).write(to: evidenceCollectorURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: viftyCtlURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: guardedRunURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: swiftTestURL.path)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: evidenceCollectorURL.path)

        let rule = ViftyAgentRule.rule(bundleURL: buildURL)

        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' capabilities --json"))
        XCTAssertTrue(rule.contains("'\(viftyCtlURL.path)' diagnose --json"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(swiftTestURL.path)'"))
        XCTAssertTrue(rule.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(guardedRunURL.path)' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"))
        XCTAssertFalse(rule.contains("'/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-test.sh'"))
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

        let relativeExecutablePaths = [
            "Contents/MacOS/viftyctl",
            "Contents/Resources/collect-agent-cooling-evidence.sh",
            "Contents/Resources/viftyctl-wrappers/guarded-run.sh"
        ] + AgentWorkflowSupport.safeWorkloadCommandTemplates.map { template in
            "Contents/Resources/viftyctl-wrappers/\(template.shortcutScript)"
        }
        for relativePath in relativeExecutablePaths {
            let url = appURL.appendingPathComponent(relativePath, isDirectory: false)
            try Data("#!/bin/sh\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: url.path)
        }

        let swiftTest = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "swift-test" })
        let xcodeBuild = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "xcode-build" })
        let goTest = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "go-test" })
        let uvTest = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "uv-test" })
        let localModel = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "local-model-template" })
        let customWorkload = try XCTUnwrap(AgentWorkflowSupport.safeWorkloadCommandTemplates.first { $0.id == "custom-workload-template" })
        let explicitViftyCtlPrefix = "VIFTYCTL='\(appURL.appendingPathComponent("Contents/MacOS/viftyctl").path)' "

        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(swiftTest, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("swift-test.sh").path)'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(swiftTest, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(xcodeBuild, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("xcode-build.sh").path)'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(xcodeBuild, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'build' '30m' '75' 'xcodebuild build' '--' 'xcodebuild' 'build'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(goTest, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("go-test.sh").path)'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(goTest, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'test' '20m' '70' 'go test' '--' 'go' 'test'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(uvTest, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("uv-test.sh").path)'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(uvTest, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'test' '20m' '70' 'uv pytest' '--' 'uv' 'run' 'pytest'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(localModel, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("local-model.sh").path)' '--' './run-local-model.sh'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(localModel, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'localModel' '30m' '75' 'local model run' '--' './run-local-model.sh'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(customWorkload, mode: .run, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("custom-workload.sh").path)' '15m' '65' 'custom workload' '--' './scripts/smoke-test.sh'"
        )
        XCTAssertEqual(
            AgentWorkflowSupport.workloadCommand(customWorkload, mode: .preflight, bundleURL: appURL),
            "\(explicitViftyCtlPrefix)'\(wrappersURL.appendingPathComponent("guarded-run.sh").path)' '--preflight-only' 'custom' '15m' '65' 'custom workload' '--' './scripts/smoke-test.sh'"
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
