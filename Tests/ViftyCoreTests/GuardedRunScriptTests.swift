import Foundation
import XCTest

final class GuardedRunScriptTests: XCTestCase {
    func testGuardedRunDelegatesToJSONViftyCtlRunWhenReady() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "run",
                "--json",
                "--workload", "test",
                "--duration", "20m",
                "--max-rpm-percent", "70",
                "--reason", "swift test",
                "--",
                "swift", "test"
            ]
        )
    }

    func testGuardedRunRejectsCapabilitiesUnavailableEvenWhenRunLifecycleIsSafe() throws {
        let harness = try ScriptHarness(state: "ready", capabilitiesExitCode: 69)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("policyStatusAvailable=true"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsUnavailableCapabilitiesEvenIfPayloadClaimsPolicyStatusAvailable() throws {
        let harness = try ScriptHarness(
            state: "ready",
            capabilitiesExitCode: 69,
            capabilitiesOutputOverride: #"{"schemaVersion":1,"daemonStatusAvailable":false,"policyStatusAvailable":true,"policySource":"fallbackUnavailable","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","localModel","custom"],"supportsForceRetry":true,"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"exitCodes":{"unavailable":69}}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("daemon-backed policy status"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsFallbackPolicySourceEvenWithSuccessfulCapabilitiesExit() throws {
        let harness = try ScriptHarness(
            state: "ready",
            capabilitiesOutputOverride: #"{"schemaVersion":1,"daemonStatusAvailable":false,"policyStatusAvailable":true,"policySource":"fallbackUnavailable","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","localModel","custom"],"supportsForceRetry":true,"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"exitCodes":{"unavailable":69}}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("daemon-backed policy status"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresPolicyStatusBeforeTrustingPolicyLimits() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyStatusAvailable: false
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("policyStatusAvailable=true"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresPolicyStatusFieldBeforeTrustingPolicyLimits() throws {
        let harness = try ScriptHarness(
            state: "ready",
            includePolicyStatusAvailable: false
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("policyStatusAvailable=true"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsUnexpectedCapabilitiesFailureEvenWhenContractLooksSafe() throws {
        let harness = try ScriptHarness(state: "ready", capabilitiesExitCode: 42)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("capabilities exited 42 instead of advertised unavailable exit 69"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedWhenRunLifecycleIsUnsafe() throws {
        let harness = try ScriptHarness(
            state: "ready",
            runLifecycleOverride: #""runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":false,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("safe run lifecycle"), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"autoRestoreAfterChildExit\":false"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresCapabilitiesRunCommandSupport() throws {
        let harness = try ScriptHarness(
            state: "ready",
            capabilityCommands: ["status", "capabilities", "diagnose", "audit", "prepare", "restore-auto"]
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise run command support"), result.stderr)
        XCTAssertTrue(result.stderr.contains(#""commands":["status","capabilities","diagnose","audit","prepare","restore-auto"]"#), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresRequestedWorkloadSupport() throws {
        let harness = try ScriptHarness(
            state: "ready",
            capabilityWorkloads: ["build", "localModel", "custom"]
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise workload 'test'"), result.stderr)
        XCTAssertTrue(result.stderr.contains(#""workloads":["build","localModel","custom"]"#), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunForceRetryIsOptIn() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "1"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "run",
                "--json",
                "--workload", "test",
                "--duration", "20m",
                "--max-rpm-percent", "70",
                "--force",
                "--reason", "swift test",
                "--",
                "swift", "test"
            ]
        )
    }

    func testGuardedRunForceRetryRequiresCapabilitySupport() throws {
        let harness = try ScriptHarness(state: "ready", supportsForceRetry: false)

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "1"
        )

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("force retry support"), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"supportsForceRetry\":false"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsInvalidForceRetryEnvironmentBeforeDiagnose() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "maybe"
        )

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_FORCE_RETRY"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsInvalidAllowUncooledEnvironmentBeforeDiagnose() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            allowUncooled: "maybe"
        )

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_ALLOW_UNCOOLED"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsForceRetryCombinedWithUncooledFallbackBeforeDiagnose() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "1",
            allowUncooled: "1"
        )

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_FORCE_RETRY"), result.stderr)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_ALLOW_UNCOOLED"), result.stderr)
        XCTAssertTrue(result.stderr.contains("mutually exclusive"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsInvalidDurationBeforeViftyCtl() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "0m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("duration must be greater than zero"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsMalformedDurationBeforeViftyCtl() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20s", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("duration must be a positive integer"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsInvalidRPMPercentBeforeViftyCtl() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20m", "101", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("max-rpm-percent must be an integer from 1 through 100"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresAdvertisedRPMPolicyLimits() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyOverride: #""policy":{"enabled":true,"maxDurationSeconds":1800,"prepareCooldownSeconds":30}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise usable RPM policy limits"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsDisabledAdvertisedAgentPolicyBeforeDiagnose() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyOverride: #""policy":{"enabled":false,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise enabled agent policy"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsRPMPercentOutsideAdvertisedPolicyRange() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyOverride: #""policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":60,"maxDurationSeconds":1800,"prepareCooldownSeconds":30}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("max-rpm-percent 70 is outside advertised policy range 35...60"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresAdvertisedDurationPolicyLimit() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyOverride: #""policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"prepareCooldownSeconds":30}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise a usable duration policy limit"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsDurationOutsideAdvertisedPolicyLimit() throws {
        let harness = try ScriptHarness(
            state: "ready",
            policyOverride: #""policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":600,"prepareCooldownSeconds":30}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("duration 20m exceeds advertised policy maximum 600 seconds"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsEmptyReasonBeforeViftyCtl() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("reason must not be empty"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsBlankReasonBeforeViftyCtl() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "   ", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("reason must not be blank"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRequiresMetadataLimitsSupport() throws {
        let harness = try ScriptHarness(
            state: "ready",
            metadataLimitsOverride: #""metadataLimits":null"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("does not advertise metadata limits"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsOversizedReasonFromAdvertisedMetadataLimit() throws {
        let harness = try ScriptHarness(
            state: "ready",
            metadataLimitsOverride: #""metadataLimits":{"maximumReasonLength":10,"maximumIdempotencyKeyLength":256}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test too long", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("reason is 19 characters after trimming; maximum is 10"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsMissingChildCommandBeforeViftyRun() throws {
        let harness = try ScriptHarness(state: "ready")
        let missingCommand = "vifty-missing-child-\(UUID().uuidString)"

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "missing child", "--", missingCommand
        ])

        XCTAssertEqual(result.exitCode, 127)
        XCTAssertTrue(result.stderr.contains("child command was not found on PATH"), result.stderr)
        XCTAssertTrue(result.stderr.contains(missingCommand), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsMissingChildPathBeforeViftyRun() throws {
        let harness = try ScriptHarness(state: "ready")
        let missingPath = harness.rootURL.appendingPathComponent("missing-child").path

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "missing child path", "--", missingPath
        ])

        XCTAssertEqual(result.exitCode, 127)
        XCTAssertTrue(result.stderr.contains("child command path does not exist"), result.stderr)
        XCTAssertTrue(result.stderr.contains(missingPath), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunRejectsNonExecutableChildPathBeforeViftyRun() throws {
        let harness = try ScriptHarness(state: "ready")
        let childURL = harness.rootURL.appendingPathComponent("not-executable")
        XCTAssertTrue(FileManager.default.createFile(atPath: childURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8)))

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "bad child", "--", childURL.path
        ])

        XCTAssertEqual(result.exitCode, 126)
        XCTAssertTrue(result.stderr.contains("child command is not executable"), result.stderr)
        XCTAssertTrue(result.stderr.contains(childURL.path), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunWarnsAndDelegatesWhenDegraded() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            recommendedAction: "requestCoolingWithCaution",
            safeToRequestCooling: true
        )

        let result = try harness.runGuardedRun([
            "build", "15m", "60", "cautious build", "--", "swift", "build"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("recommends caution"))
        let loggedArguments = try harness.loggedArguments()
        XCTAssertTrue(loggedArguments.contains("run"))
        XCTAssertTrue(loggedArguments.contains("--json"))
    }

    func testGuardedRunBlocksBeforeRunWhenDiagnoseRecommendsRestoreAutoFirst() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            recommendedAction: "restoreAutoBeforeRequestingCooling",
            recommendedRecoveryAction: "restoreAutoBeforeRetry",
            safeToRequestCooling: false
        )

        let result = try harness.runGuardedRun([
            "build", "15m", "60", "cautious build", "--", "swift", "build"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("restoring Auto before requesting new cooling"))
        XCTAssertTrue(result.stderr.contains("recovery action is restoreAutoBeforeRetry"))
        XCTAssertTrue(result.stderr.contains("\"recommendedAgentAction\":\"restoreAutoBeforeRequestingCooling\""))
        XCTAssertTrue(result.stderr.contains("\"recommendedRecoveryAction\":\"restoreAutoBeforeRetry\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunBlocksBeforeRunWhenDiagnoseBlocks() throws {
        let harness = try ScriptHarness(
            state: "blocked",
            recommendedRecoveryAction: "repairHelper",
            daemonControlPathReady: false
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("readiness is blocked"))
        XCTAssertTrue(result.stderr.contains("recovery action is repairHelper"))
        XCTAssertTrue(result.stderr.contains("Repair/Reinstall Helper"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunCanRunChildWithoutViftyCoolingWhenUserAllowsUncooledFallback() throws {
        let harness = try ScriptHarness(
            state: "blocked",
            recommendedRecoveryAction: "collectHardwareEvidence"
        )
        let markerURL = harness.rootURL.appendingPathComponent("uncooled-child-ran.txt")

        let result = try harness.runGuardedRun(
            [
                "test", "20m", "70", "swift test",
                "--", "/bin/sh", "-c", "printf child-ran > '\(markerURL.path)'"
            ],
            allowUncooled: "1"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("readiness is blocked"), result.stderr)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_ALLOW_UNCOOLED is set; running child without Vifty cooling"), result.stderr)
        XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), "child-ran")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunDoesNotRunUncooledWhenViftyRecommendsBackingOffWorkload() throws {
        let harness = try ScriptHarness(
            state: "blocked",
            recommendedRecoveryAction: "backOffWorkload"
        )
        let markerURL = harness.rootURL.appendingPathComponent("should-not-run.txt")

        let result = try harness.runGuardedRun(
            [
                "test", "20m", "70", "swift test",
                "--", "/bin/sh", "-c", "printf child-ran > '\(markerURL.path)'"
            ],
            allowUncooled: "1"
        )

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("recovery action is backOffWorkload"), result.stderr)
        XCTAssertTrue(result.stderr.contains("not running workload without cooling"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunDoesNotRunUncooledWhenViftyRecommendsHelperRepair() throws {
        let harness = try ScriptHarness(
            state: "blocked",
            recommendedRecoveryAction: "repairHelper",
            daemonControlPathReady: false
        )
        let markerURL = harness.rootURL.appendingPathComponent("should-not-run-helper-repair.txt")

        let result = try harness.runGuardedRun(
            [
                "test", "20m", "70", "swift test",
                "--", "/bin/sh", "-c", "printf child-ran > '\(markerURL.path)'"
            ],
            allowUncooled: "1"
        )

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("recovery action is repairHelper"), result.stderr)
        XCTAssertTrue(result.stderr.contains("not running workload without cooling"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunDoesNotRunUncooledWhenDaemonControlPathIsNotReady() throws {
        let harness = try ScriptHarness(
            state: "ready",
            safeToRequestCooling: true,
            daemonControlPathReady: false
        )
        let markerURL = harness.rootURL.appendingPathComponent("should-not-run-daemon-control.txt")

        let result = try harness.runGuardedRun(
            [
                "test", "20m", "70", "swift test",
                "--", "/bin/sh", "-c", "printf child-ran > '\(markerURL.path)'"
            ],
            allowUncooled: "1"
        )

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("daemon control path is not ready"), result.stderr)
        XCTAssertTrue(result.stderr.contains("daemonControlPathReady is false; not running workload without cooling"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunBlocksBeforeRunWhenDaemonControlPathIsNotReady() throws {
        let harness = try ScriptHarness(
            state: "ready",
            recommendedRecoveryAction: "repairHelper",
            safeToRequestCooling: true,
            daemonControlPathReady: false
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("daemon control path is not ready"), result.stderr)
        XCTAssertTrue(result.stderr.contains("Repair/Reinstall Helper"), result.stderr)
        XCTAssertTrue(result.stderr.contains(#""daemonControlPathReady":false"#), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedWhenReadinessRecoveryActionIsMissing() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            decisionFieldsOverride: #","recommendedAgentAction":"requestCoolingWithCaution","safeToRequestCooling":true"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("missing agent decision fields"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunTreatsNonzeroBlockedDiagnoseAsReadinessBlock() throws {
        let harness = try ScriptHarness(state: "blocked", diagnoseExitCode: 75, emitReadinessOnDiagnoseFailure: true)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("readiness is blocked"))
        XCTAssertFalse(result.stderr.contains("diagnose failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedWhenAgentDecisionFieldsAreMissing() throws {
        let harness = try ScriptHarness(state: "degraded", includeDecisionFields: false)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("missing agent decision fields"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunTreatsNullAgentDecisionFieldsAsMissing() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            decisionFieldsOverride: #","recommendedAgentAction":null,"recommendedRecoveryAction":null,"safeToRequestCooling":null"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("missing agent decision fields"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunTreatsNullStateAsDiagnoseFailureWhenDiagnoseFails() throws {
        let harness = try ScriptHarness(
            state: "ready",
            diagnoseExitCode: 1,
            commandErrorOverride: #"{"state":null,"command":"diagnose","safeToProceed":false,"message":"daemon unavailable"}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("diagnose failed"), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"command\":\"diagnose\""), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"safeToProceed\":false"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedAndPreservesDiagnoseJSONWhenDiagnoseFails() throws {
        let harness = try ScriptHarness(state: "ready", diagnoseExitCode: 1)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("diagnose failed"))
        XCTAssertTrue(result.stderr.contains("\"command\":\"diagnose\""))
        XCTAssertTrue(result.stderr.contains("\"safeToProceed\":false"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsWhenViftyCtlIsMissing() throws {
        let harness = try ScriptHarness(state: "ready", createFakeViftyCtl: false)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertTrue(result.stderr.contains("viftyctl is not executable"))
    }

    func testWorkloadExampleScriptsDelegateThroughGuardedRun() throws {
        let cases: [(script: String, arguments: [String], expected: [String])] = [
            (
                "examples/viftyctl/swift-test.sh",
                ["--filter", "AgentTests"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "swift test", "--", "swift", "test", "--filter", "AgentTests"]
            ),
            (
                "examples/viftyctl/swift-release-build.sh",
                ["--product", "Vifty"],
                ["run", "--json", "--workload", "build", "--duration", "25m", "--max-rpm-percent", "75", "--reason", "swift release build", "--", "swift", "build", "-c", "release", "--product", "Vifty"]
            ),
            (
                "examples/viftyctl/xcode-build.sh",
                ["-scheme", "MyApp", "-destination", "platform=macOS"],
                ["run", "--json", "--workload", "build", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "xcodebuild build", "--", "xcodebuild", "build", "-scheme", "MyApp", "-destination", "platform=macOS"]
            ),
            (
                "examples/viftyctl/xcode-test.sh",
                ["-scheme", "MyApp", "-destination", "platform=macOS"],
                ["run", "--json", "--workload", "test", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "xcodebuild test", "--", "xcodebuild", "test", "-scheme", "MyApp", "-destination", "platform=macOS"]
            ),
            (
                "examples/viftyctl/make-test.sh",
                ["TEST_FILTER=AgentTests"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "make test", "--", "make", "test", "TEST_FILTER=AgentTests"]
            ),
            (
                "examples/viftyctl/make-verify.sh",
                ["RELEASE_VERSION=1.1.0"],
                ["run", "--json", "--workload", "test", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "make verify", "--", "make", "verify", "RELEASE_VERSION=1.1.0"]
            ),
            (
                "examples/viftyctl/npm-build.sh",
                ["--", "--mode=production"],
                ["run", "--json", "--workload", "build", "--duration", "25m", "--max-rpm-percent", "75", "--reason", "npm run build", "--", "npm", "run", "build", "--", "--mode=production"]
            ),
            (
                "examples/viftyctl/npm-test.sh",
                ["--", "--watch=false"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "npm test", "--", "npm", "test", "--", "--watch=false"]
            ),
            (
                "examples/viftyctl/cargo-build.sh",
                ["--release"],
                ["run", "--json", "--workload", "build", "--duration", "25m", "--max-rpm-percent", "75", "--reason", "cargo build", "--", "cargo", "build", "--release"]
            ),
            (
                "examples/viftyctl/cargo-test.sh",
                ["--locked"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "cargo test", "--", "cargo", "test", "--locked"]
            ),
            (
                "examples/viftyctl/pytest.sh",
                ["Tests"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "pytest", "--", "python3", "-m", "pytest", "Tests"]
            ),
            (
                "examples/viftyctl/local-model.sh",
                ["--", "./run-local-model.sh", "--prompt", "smoke"],
                ["run", "--json", "--workload", "localModel", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "local model run", "--", "./run-local-model.sh", "--prompt", "smoke"]
            ),
            (
                "examples/viftyctl/custom-workload.sh",
                ["15m", "65", "project smoke test", "--", "./scripts/smoke-test.sh"],
                ["run", "--json", "--workload", "custom", "--duration", "15m", "--max-rpm-percent", "65", "--reason", "project smoke test", "--", "./scripts/smoke-test.sh"]
            )
        ]

        for testCase in cases {
            let harness = try ScriptHarness(state: "ready")

            let result = try harness.runScript(testCase.script, arguments: testCase.arguments)

            XCTAssertEqual(result.exitCode, 0, testCase.script)
            XCTAssertEqual(try harness.loggedArguments(), testCase.expected, testCase.script)
        }
    }

    func testWorkloadExampleScriptsStayOnGuardedRunPath() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("examples/viftyctl")
        let scripts = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sh" }

        XCTAssertGreaterThanOrEqual(scripts.count, 14)

        for script in scripts {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path), script.lastPathComponent)
            let contents = try String(contentsOf: script, encoding: .utf8)
            XCTAssertFalse(contents.contains("ViftyHelper setFixed"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("ViftyHelper auto"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("sudo"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("smc"), script.lastPathComponent)
            if script.lastPathComponent != "guarded-run.sh" {
                XCTAssertTrue(contents.contains("guarded-run.sh"), script.lastPathComponent)
            }
        }
    }
}

private struct ProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class ScriptHarness {
    let rootURL: URL
    let binURL: URL
    let fakeViftyCtlURL: URL
    let logURL: URL

    init(
        state: String,
        recommendedAction: String? = nil,
        recommendedRecoveryAction: String? = nil,
        safeToRequestCooling: Bool? = nil,
        daemonControlPathReady: Bool = true,
        diagnoseExitCode: Int = 0,
        emitReadinessOnDiagnoseFailure: Bool = false,
        includeDecisionFields: Bool = true,
        decisionFieldsOverride: String? = nil,
        commandErrorOverride: String? = nil,
        capabilitiesExitCode: Int = 0,
        includeRunLifecycle: Bool = true,
        includePolicyStatusAvailable: Bool = true,
        policyStatusAvailable: Bool? = nil,
        supportsForceRetry: Bool = true,
        capabilityCommands: [String] = ["status", "capabilities", "diagnose", "audit", "prepare", "restore-auto", "run"],
        capabilityWorkloads: [String] = ["build", "test", "localModel", "custom"],
        runLifecycleOverride: String? = nil,
        policyOverride: String? = nil,
        metadataLimitsOverride: String? = nil,
        capabilitiesOutputOverride: String? = nil,
        createFakeViftyCtl: Bool = true
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-guarded-run-\(UUID().uuidString)", isDirectory: true)
        binURL = rootURL.appendingPathComponent("fake-bin", isDirectory: true)
        fakeViftyCtlURL = rootURL.appendingPathComponent("viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl-args.log")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        try writeFakeChildTools()
        if createFakeViftyCtl {
            try writeFakeViftyCtl(
                state: state,
                recommendedAction: recommendedAction ?? Self.defaultRecommendedAction(for: state),
                recommendedRecoveryAction: recommendedRecoveryAction
                    ?? Self.defaultRecommendedRecoveryAction(
                        for: state,
                        recommendedAction: recommendedAction ?? Self.defaultRecommendedAction(for: state)
                    ),
                safeToRequestCooling: safeToRequestCooling ?? Self.defaultSafeToRequestCooling(for: state),
                daemonControlPathReady: daemonControlPathReady,
                diagnoseExitCode: diagnoseExitCode,
                emitReadinessOnDiagnoseFailure: emitReadinessOnDiagnoseFailure,
                includeDecisionFields: includeDecisionFields,
                decisionFieldsOverride: decisionFieldsOverride,
                commandErrorOverride: commandErrorOverride,
                capabilitiesExitCode: capabilitiesExitCode,
                includeRunLifecycle: includeRunLifecycle,
                includePolicyStatusAvailable: includePolicyStatusAvailable,
                policyStatusAvailable: policyStatusAvailable ?? (capabilitiesExitCode == 0),
                supportsForceRetry: supportsForceRetry,
                capabilityCommands: capabilityCommands,
                capabilityWorkloads: capabilityWorkloads,
                runLifecycleOverride: runLifecycleOverride,
                policyOverride: policyOverride,
                metadataLimitsOverride: metadataLimitsOverride,
                capabilitiesOutputOverride: capabilitiesOutputOverride
            )
        }
    }

    func runGuardedRun(
        _ arguments: [String],
        forceRetry: String? = nil,
        allowUncooled: String? = nil
    ) throws -> ProcessResult {
        try runScript(
            "examples/viftyctl/guarded-run.sh",
            arguments: arguments,
            forceRetry: forceRetry,
            allowUncooled: allowUncooled
        )
    }

    func runScript(
        _ relativePath: String,
        arguments: [String],
        forceRetry: String? = nil,
        allowUncooled: String? = nil
    ) throws -> ProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.currentDirectoryURL = rootURL

        var environment = ProcessInfo.processInfo.environment
        environment["VIFTYCTL"] = fakeViftyCtlURL.path
        environment["FAKE_VIFTYCTL_LOG"] = logURL.path
        environment["PATH"] = "\(binURL.path):\(environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")"
        if let forceRetry {
            environment["VIFTY_GUARDED_RUN_FORCE_RETRY"] = forceRetry
        }
        if let allowUncooled {
            environment["VIFTY_GUARDED_RUN_ALLOW_UNCOOLED"] = allowUncooled
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func loggedArguments() throws -> [String] {
        let data = try Data(contentsOf: logURL)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeFakeChildTools() throws {
        for tool in ["swift", "xcodebuild", "make", "npm", "cargo", "python3", "local-model-runner", "custom-runner"] {
            try writeFakeExecutable(named: tool, in: binURL)
        }

        let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
        try writeFakeExecutable(named: "smoke-test.sh", in: scriptsURL)
        try writeFakeExecutable(named: "run-local-model.sh", in: rootURL)
    }

    private func writeFakeExecutable(named name: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func writeFakeViftyCtl(
        state: String,
        recommendedAction: String,
        recommendedRecoveryAction: String,
        safeToRequestCooling: Bool,
        daemonControlPathReady: Bool,
        diagnoseExitCode: Int,
        emitReadinessOnDiagnoseFailure: Bool,
        includeDecisionFields: Bool,
        decisionFieldsOverride: String?,
        commandErrorOverride: String?,
        capabilitiesExitCode: Int,
        includeRunLifecycle: Bool,
        includePolicyStatusAvailable: Bool,
        policyStatusAvailable: Bool,
        supportsForceRetry: Bool,
        capabilityCommands: [String],
        capabilityWorkloads: [String],
        runLifecycleOverride: String?,
        policyOverride: String?,
        metadataLimitsOverride: String?,
        capabilitiesOutputOverride: String?
    ) throws {
        let emitReadinessOnDiagnoseFailureValue = emitReadinessOnDiagnoseFailure ? "1" : "0"
        let decisionFields = decisionFieldsOverride ?? (includeDecisionFields
            ? #","recommendedAgentAction":"\#(recommendedAction)","recommendedRecoveryAction":"\#(recommendedRecoveryAction)","safeToRequestCooling":\#(safeToRequestCooling),"daemonControlPathReady":\#(daemonControlPathReady)"#
            : "")
        let commandError = commandErrorOverride ?? #"{"command":"diagnose","safeToProceed":false,"message":"daemon unavailable"}"#
        let runLifecycle = runLifecycleOverride ?? (includeRunLifecycle
            ? #""runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true}"#
            : "")
        let policyStatus = includePolicyStatusAvailable ? #""policyStatusAvailable":\#(policyStatusAvailable),"# : ""
        let supportsForceRetryValue = supportsForceRetry ? "true" : "false"
        let commandsJSON = Self.jsonStringArray(capabilityCommands)
        let workloadsJSON = Self.jsonStringArray(capabilityWorkloads)
        let exitCodes = #""exitCodes":{"unavailable":69}"#
        let policy = policyOverride
            ?? #""policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30}"#
        let metadataLimits = metadataLimitsOverride
            ?? #""metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}"#
        let capabilitiesOutput = capabilitiesOutputOverride ?? (runLifecycle.isEmpty
            ? #"{"schemaVersion":1,"commands":\#(commandsJSON),"workloads":\#(workloadsJSON),"daemonStatusAvailable":true,"policySource":"daemonStatus",\#(policyStatus)"supportsForceRetry":\#(supportsForceRetryValue),\#(policy),\#(metadataLimits),\#(exitCodes)}"#
            : #"{"schemaVersion":1,"commands":\#(commandsJSON),"workloads":\#(workloadsJSON),"daemonStatusAvailable":true,"policySource":"daemonStatus",\#(policyStatus)"supportsForceRetry":\#(supportsForceRetryValue),\#(runLifecycle),\#(policy),\#(metadataLimits),\#(exitCodes)}"#)
        let script = """
        #!/bin/sh
        set -eu

        if [ "$#" -ge 2 ] && [ "$1" = "capabilities" ] && [ "$2" = "--json" ]; then
          printf '\(capabilitiesOutput)\n'
          exit \(capabilitiesExitCode)
        fi

        if [ "$#" -ge 2 ] && [ "$1" = "diagnose" ] && [ "$2" = "--json" ]; then
          if [ "\(diagnoseExitCode)" -eq 0 ] || [ "\(emitReadinessOnDiagnoseFailureValue)" -eq 1 ]; then
            printf '{"state":"\(state)"\(decisionFields),"checks":[]}\n'
          else
            printf '\(commandError)\n'
          fi
          exit \(diagnoseExitCode)
        fi

        if [ "$#" -ge 1 ] && [ "$1" = "run" ]; then
          for arg in "$@"; do
            printf '%s\n' "$arg"
          done > "${FAKE_VIFTYCTL_LOG:?}"
          exit 0
        fi

        echo "unexpected fake viftyctl invocation: $*" >&2
        exit 99
        """

        try script.write(to: fakeViftyCtlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeViftyCtlURL.path
        )
    }

    private static func defaultRecommendedAction(for state: String) -> String {
        switch state {
        case "ready":
            return "requestCooling"
        case "degraded":
            return "requestCoolingWithCaution"
        default:
            return "doNotRequestCooling"
        }
    }

    private static func defaultRecommendedRecoveryAction(for state: String, recommendedAction: String) -> String {
        if recommendedAction == "restoreAutoBeforeRequestingCooling" {
            return "restoreAutoBeforeRetry"
        }

        switch state {
        case "ready", "degraded":
            return "none"
        default:
            return "collectHardwareEvidence"
        }
    }

    private static func defaultSafeToRequestCooling(for state: String) -> Bool {
        state == "ready" || state == "degraded"
    }

    private static func jsonStringArray(_ values: [String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: values)
        return String(decoding: data, as: UTF8.self)
    }
}
