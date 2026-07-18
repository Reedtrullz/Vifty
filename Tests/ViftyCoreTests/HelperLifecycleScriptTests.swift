import Darwin
import Foundation
import XCTest

final class HelperLifecycleScriptTests: XCTestCase {
    func testRepairDryRunRecordsRequiredOrderButRemainsBlocked() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(operation: "repair", dryRun: true)

        XCTAssertEqual(result.exitCode, 75, result.output)
        let report = try fixture.readRecord()
        XCTAssertEqual(report["status"] as? String, "blocked")
        XCTAssertEqual(report["commandsExecuted"] as? Bool, false)
        XCTAssertEqual(
            report["plannedPhases"] as? [String],
            [
                "inspect-ownership",
                "quiesce-restore-confirm",
                "consume-single-use-token",
                "unregister-smappservice-and-verify",
                "disable-service-and-confirm-offline",
                "post-freeze-offline-auto-confirm",
                "remove-legacy-helper-plist-and-logs",
                "reenable-service-after-cleanup",
                "register-smappservice-and-verify"
            ]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.forbiddenInvocationLog.path))
    }

    func testUninstallDryRunRecordsUnregisterAndPreservationOrder() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(operation: "uninstall", dryRun: true)

        XCTAssertEqual(result.exitCode, 75, result.output)
        let report = try fixture.readRecord()
        XCTAssertEqual(
            report["plannedPhases"] as? [String],
            [
                "inspect-ownership",
                "quiesce-restore-confirm",
                "consume-single-use-token",
                "unregister-smappservice-and-verify",
                "disable-service-and-confirm-offline",
                "post-freeze-offline-auto-confirm",
                "remove-legacy-helper-plist-and-logs",
                "preserve-agentcontrol-and-fancontrol-recovery-state"
            ]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.forbiddenInvocationLog.path))
    }

    func testPlausibleReportCannotEnableMutationBeforeContractIsImplemented() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let report = fixture.root.appendingPathComponent("unimplemented-maintenance-report.json")
        try Data("""
        {"safeToStop":true,"quiesced":true,"restoreSucceeded":true,"token":{"id":"not-authoritative"}}
        """.utf8).write(to: report)

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            maintenanceReport: report
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("Caller-supplied maintenance reports cannot authorize"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.forbiddenInvocationLog.path))
    }

    func testSuccessfulRepairOrdersAuthorizationBeforeLegacyCleanupAndServiceRegistration() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(operation: "repair", dryRun: false)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            [
                "viftyctl prepare repair",
                "Vifty unregister repair",
                "launchctl disable",
                "launchctl bootout",
                "ViftyHelper authorizeLegacyTeardown repair",
                "launchctl enable",
                "Vifty register"
            ]
        )
        XCTAssertEqual(
            try fixture.readRecord()["executedPhases"] as? [String],
            [
                "inspect-ownership",
                "quiesce-restore-confirm",
                "consume-single-use-token",
                "unregister-smappservice-and-verify",
                "disable-service-and-confirm-offline",
                "post-freeze-offline-auto-confirm",
                "remove-legacy-helper-plist-and-logs",
                "reenable-service-after-cleanup",
                "register-smappservice-and-verify"
            ]
        )
        XCTAssertTrue(try fixture.workerScratchDirectories().isEmpty)
    }

    func testSuccessfulUninstallNeverRegistersAndPreservesRecoveryState() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(operation: "uninstall", dryRun: false)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            [
                "viftyctl prepare uninstall",
                "Vifty unregister uninstall",
                "launchctl disable",
                "launchctl bootout",
                "ViftyHelper authorizeLegacyTeardown uninstall"
            ]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.recoveryState.path))
    }

    func testUnregisterFailureCancelsUnconsumedPreparationAndRunsNoBootout() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_UNREGISTER_FAIL": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            ["viftyctl prepare repair", "Vifty unregister repair", "viftyctl cancel"]
        )
        XCTAssertFalse(try fixture.readInvocations().contains("launchctl bootout"))
    }

    func testLoadedLegacyServiceBootoutFailurePreservesEveryLegacyFile() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_BOOTOUT_FAIL": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse((try fixture.readRecord()["executedPhases"] as? [String])?.contains("remove-legacy-helper-plist-and-logs") == true)
    }

    func testLegacyServiceStillLoadedAfterBootoutPreservesEveryLegacyFile() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_STILL_LOADED": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertFalse(try fixture.readInvocations().contains("Vifty register"))
    }

    func testProtocolV1FixtureUsesLiveFreshAutoSystemGateBeforeBootout() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_PROTOCOL_V1": "1"]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            [
                "viftyctl prepare repair",
                "viftyctl cancel",
                "launchctl disable",
                "launchctl bootout",
                "ViftyHelper authorizeLegacyTeardown repair",
                "launchctl enable",
                "Vifty register"
            ]
        )
        XCTAssertTrue((try fixture.readRecord()["executedPhases"] as? [String])?.contains("post-freeze-offline-auto-confirm") == true)
    }

    func testCurrentSchemaProtocolMismatchStillUsesOfflineRecovery() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_PROTOCOL_MISMATCH": "1"]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(try fixture.readInvocations().contains(
            "ViftyHelper authorizeLegacyTeardown repair"
        ))
    }

    func testSelectorMissingV132LookalikeBlocksBeforeServiceFreeze() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_LEGACY_LOOKALIKE": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        let invocations = try fixture.readInvocations()
        XCTAssertEqual(invocations, ["viftyctl prepare uninstall", "viftyctl cancel"])
        XCTAssertFalse(invocations.contains("launchctl disable"))
        XCTAssertFalse(invocations.contains("ViftyHelper authorizeLegacyTeardown uninstall"))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "blocked")
    }

    func testOnlyExplicitProtocolMismatchCanEnterOfflineRecovery() throws {
        for environment in [
            ["VIFTY_FIXTURE_PREPARE_FAILURE": "1"],
            ["VIFTY_FIXTURE_SAFETY_BLOCK": "1"],
            ["VIFTY_FIXTURE_MALFORMED_BLOCK": "1"]
        ] {
            let fixture = try LifecycleFixture()
            defer { fixture.remove() }

            let result = try fixture.runLifecycle(
                operation: "repair",
                dryRun: false,
                extraEnvironment: environment
            )

            XCTAssertEqual(result.exitCode, 75, result.output)
            let invocations = try fixture.readInvocations()
            XCTAssertEqual(invocations, ["viftyctl prepare repair", "viftyctl cancel"])
            XCTAssertFalse(invocations.contains("launchctl disable"))
            XCTAssertFalse(invocations.contains("ViftyHelper authorizeLegacyTeardown repair"))
            XCTAssertFalse(invocations.contains("Vifty register"))
            XCTAssertTrue(fixture.legacyFiles.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })
        }
    }

    func testProtocolV1UnsafeEvidenceBlocksBeforeBootout() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_LEGACY_UNSAFE": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(try fixture.readInvocations().contains("launchctl bootout"))
        XCTAssertTrue(try fixture.readInvocations().contains("ViftyHelper authorizeLegacyTeardown uninstall"))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testProtocolV1OneFanOfflineAuthorityIsAccepted() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_ONE_FAN": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(try fixture.readInvocations().contains("ViftyHelper authorizeLegacyTeardown repair"))
    }

    func testProtocolV1UninstallFinalizesSMAppServiceOnlyAfterRootOfflineProof() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_PROTOCOL_V1": "1"]
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let invocations = try fixture.readInvocations()
        let helperIndex = try XCTUnwrap(invocations.firstIndex(of: "ViftyHelper authorizeLegacyTeardown uninstall"))
        let unregisterIndex = try XCTUnwrap(invocations.firstIndex(of: "Vifty unregister-legacy uninstall"))
        XCTAssertLessThan(helperIndex, unregisterIndex)
        XCTAssertTrue(invocations.contains("launchctl disable"))
        XCTAssertFalse(invocations.contains("launchctl enable"))
    }

    func testProtocolV1AdminCancelDoesNotStopServiceOrChangeManualState() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let manualState = fixture.root.appendingPathComponent("manual-state")
        try Data("forced".utf8).write(to: manualState)

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_ADMIN_CANCEL": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.readInvocations(), ["viftyctl prepare uninstall", "viftyctl cancel"])
        XCTAssertEqual(try String(contentsOf: manualState, encoding: .utf8), "forced")
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testProtocolV2AdminCancelPreservesReceiptForFailClosedRetry() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let cancelled = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_ADMIN_CANCEL": "1"]
        )

        XCTAssertEqual(cancelled.exitCode, 75, cancelled.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            ["viftyctl prepare uninstall", "Vifty unregister uninstall"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.authorityReceipt.path))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        let retried = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_PREPARE_FAILURE": "1"]
        )

        XCTAssertEqual(retried.exitCode, 0, retried.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.authorityReceipt.path))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testExpiredDaemonReceiptFromSuccessfulProtocolV2PrepareBlocksWithoutDowngrade() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_EXPIRED_RECEIPT": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(try fixture.readInvocations().contains("ViftyHelper authorizeLegacyTeardown uninstall"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.authorityReceipt.path))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testMalformedRootOwnedReceiptBlocksWithoutOfflineFallbackOrRemoval() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_MALFORMED_RECEIPT": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(try fixture.readInvocations().contains("ViftyHelper authorizeLegacyTeardown repair"))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "blocked")
        let phases = try XCTUnwrap(privileged["phases"] as? [[String: Any]])
        XCTAssertEqual(phases.first?["phase"] as? String, "verify-privileged-authority")
        XCTAssertEqual(phases.first?["attempted"] as? Bool, true)
        XCTAssertEqual(phases.first?["succeeded"] as? Bool, false)
    }

    func testProtocolV2SuccessWithoutPersistedReceiptCannotDowngradeToOfflineRecovery() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_OMIT_RECEIPT": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            ["viftyctl prepare repair", "Vifty unregister repair"]
        )
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "blocked")
        XCTAssertFalse((privileged["phases"] as? [[String: Any]])?.contains {
            $0["phase"] as? String == "disable-service-and-confirm-offline"
                && $0["attempted"] as? Bool == true
        } == true)
    }

    func testCrossBootOrChangedHelperReceiptFromProtocolV2NeverDowngrades() throws {
        for environment in [
            ["VIFTY_FIXTURE_CROSS_BOOT_RECEIPT": "1"],
            ["VIFTY_FIXTURE_HELPER_CHANGED_RECEIPT": "1"]
        ] {
            let fixture = try LifecycleFixture()
            defer { fixture.remove() }

            let result = try fixture.runLifecycle(
                operation: "uninstall",
                dryRun: false,
                extraEnvironment: environment
            )

            XCTAssertEqual(result.exitCode, 75, result.output)
            XCTAssertFalse(try fixture.readInvocations().contains("ViftyHelper authorizeLegacyTeardown uninstall"))
            XCTAssertTrue(fixture.legacyFiles.allSatisfy {
                FileManager.default.fileExists(atPath: $0.path)
            })
            let privileged = try fixture.readPrivilegedRecord()
            XCTAssertEqual(privileged["status"] as? String, "blocked")
        }
    }

    func testStaleReferenceDateHelperUnavailableErrorCannotEnterRootBoundary() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_STALE_ERROR": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(
            try fixture.readInvocations(),
            ["viftyctl prepare repair", "viftyctl cancel"]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.privilegedRecord.path))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testPartialBootoutFailurePersistsAuthenticatedAttemptState() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "uninstall",
            dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_BOOTOUT_FAIL": "1"]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "blocked")
        let phases = try XCTUnwrap(privileged["phases"] as? [[String: Any]])
        let offline = try XCTUnwrap(phases.first { $0["phase"] as? String == "disable-service-and-confirm-offline" })
        XCTAssertEqual(offline["attempted"] as? Bool, true)
        XCTAssertEqual(offline["succeeded"] as? Bool, false)
    }

    func testDisabledDecoyLabelCannotProveExactServiceFreeze() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_DECOY_DISABLED": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        let invocations = try fixture.readInvocations()
        XCTAssertTrue(invocations.contains("launchctl disable"))
        XCTAssertFalse(invocations.contains("launchctl bootout"))
        XCTAssertFalse(invocations.contains("ViftyHelper authorizeLegacyTeardown repair"))
        XCTAssertFalse(invocations.contains("Vifty register"))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testRootTermSignalPersistsBlockedEvidenceAndRepairNeverRegisters() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_ROOT_SIGNAL": "TERM"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        let invocations = try fixture.readInvocations()
        XCTAssertTrue(invocations.contains("launchctl bootout"))
        XCTAssertFalse(invocations.contains("ViftyHelper authorizeLegacyTeardown repair"))
        XCTAssertFalse(invocations.contains("Vifty register"))
        XCTAssertTrue(fixture.legacyFiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "blocked")
        XCTAssertFalse((privileged["blocker"] as? String)?.isEmpty ?? true)
        XCTAssertTrue(try fixture.workerScratchDirectories().isEmpty)
    }

    func testIncompleteRootSuccessCannotRegisterRepair() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let result = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            extraEnvironment: [
                "VIFTY_FIXTURE_PROTOCOL_V1": "1",
                "VIFTY_FIXTURE_ROOT_RETURN_INCOMPLETE": "1"
            ]
        )

        XCTAssertEqual(result.exitCode, 75, result.output)
        let invocations = try fixture.readInvocations()
        XCTAssertTrue(invocations.contains("ViftyHelper authorizeLegacyTeardown repair"))
        XCTAssertFalse(invocations.contains("launchctl enable"))
        XCTAssertFalse(invocations.contains("Vifty register"))
        let privileged = try fixture.readPrivilegedRecord()
        XCTAssertEqual(privileged["status"] as? String, "in-progress")
        XCTAssertFalse((privileged["phases"] as? [[String: Any]])?.contains {
            $0["phase"] as? String == "reenable-service-after-cleanup"
                && $0["succeeded"] as? Bool == true
        } == true)
    }

    func testReplacementPrepareLeavesVerifiedAuthorityFrozenUntilBoundFinish() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app
        )

        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        let prepareInvocations = try fixture.readInvocations()
        XCTAssertTrue(prepareInvocations.contains("viftyctl prepare repair"), prepared.output)
        XCTAssertTrue(prepareInvocations.contains("Vifty unregister repair"), prepared.output)
        XCTAssertTrue(prepareInvocations.contains("launchctl disable"), prepared.output)
        XCTAssertFalse(prepareInvocations.contains("launchctl enable"), prepared.output)
        XCTAssertFalse(prepareInvocations.contains("Vifty register"), prepared.output)
        let prepareRecord = try fixture.readPrivilegedRecord()
        XCTAssertEqual(prepareRecord["status"] as? String, "replacement-prepared")
        XCTAssertEqual(
            prepareRecord["replacementTransactionID"] as? String,
            fixture.replacementTransactionID
        )
        XCTAssertNotNil(prepareRecord["requestingProcessStartID"] as? String)
        XCTAssertNil(prepareRecord["replacementResult"])
        let candidateBinding = try XCTUnwrap(
            prepareRecord["replacementCandidateBinding"] as? [String: Any]
        )
        let previousBinding = try XCTUnwrap(
            prepareRecord["replacementPreviousBinding"] as? [String: Any]
        )
        XCTAssertEqual(candidateBinding["sourcePath"] as? String, fixture.candidateSnapshot.path)
        XCTAssertTrue(
            (previousBinding["sourcePath"] as? String)?.hasSuffix(
                "/\(fixture.root.lastPathComponent)/Vifty.app"
            ) == true
        )
        XCTAssertNotNil(candidateBinding["manifestSHA256"] as? String)
        let manifest = try XCTUnwrap(candidateBinding["manifest"] as? [[String: Any]])
        XCTAssertEqual(manifest.first?["path"] as? String, ".")
        XCTAssertEqual(manifest.first?["type"] as? String, "directory")
        XCTAssertTrue(manifest.allSatisfy {
            $0["uid"] is Int && $0["gid"] is Int && $0["mode"] is Int && $0["nlink"] is Int
        })
        XCTAssertTrue(manifest.filter { $0["type"] as? String == "file" }.allSatisfy {
            $0["size"] is Int && ($0["sha256"] as? String)?.count == 64
        })
        let candidateIdentity = try XCTUnwrap(candidateBinding["identity"] as? [String: Any])
        XCTAssertEqual(candidateIdentity["kind"] as? String, "adhoc")
        XCTAssertEqual(candidateIdentity["ownerUID"] as? Int, Int(geteuid()))
        XCTAssertTrue(candidateIdentity["teamID"] is NSNull)
        XCTAssertEqual(
            candidateIdentity["componentIdentifiers"] as? [String: String],
            [
                "Vifty": "tech.reidar.vifty",
                "viftyctl": "tech.reidar.vifty.ctl",
                "ViftyDaemon": "tech.reidar.vifty.daemon",
                "ViftyHelper": "tech.reidar.vifty.helper"
            ]
        )
        let componentHashes = try XCTUnwrap(
            candidateIdentity["componentSHA256"] as? [String: String]
        )
        XCTAssertEqual(
            Set(componentHashes.keys),
            Set(["Vifty", "viftyctl", "ViftyDaemon", "ViftyHelper"])
        )
        XCTAssertTrue(componentHashes.values.allSatisfy { $0.count == 64 })
        XCTAssertNil(prepareRecord["replacementNonce"])
        XCTAssertTrue(
            (prepareRecord["replacementAppPath"] as? String)?.hasSuffix(
                "/\(fixture.root.lastPathComponent)/Vifty.app"
            ) == true
        )

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app
        )

        XCTAssertEqual(finished.exitCode, 0, finished.output)
        let finishedInvocations = try fixture.readInvocations()
        let registerIndex = try XCTUnwrap(finishedInvocations.firstIndex(of: "Vifty register"))
        let enableIndex = try XCTUnwrap(finishedInvocations.lastIndex(of: "launchctl enable"))
        XCTAssertLessThan(registerIndex, enableIndex, finished.output)
        let finishedRecord = try fixture.readPrivilegedRecord()
        XCTAssertEqual(finishedRecord["status"] as? String, "completed")
    }

    func testPublishedV132OfflineReplacementLaneAlsoStaysFrozenUntilBoundFinish() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_PROTOCOL_V1": "1"]
        )

        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        let prepareInvocations = try fixture.readInvocations()
        XCTAssertTrue(prepareInvocations.contains("ViftyHelper authorizeLegacyTeardown repair"))
        XCTAssertFalse(prepareInvocations.contains("launchctl enable"))
        XCTAssertFalse(prepareInvocations.contains("Vifty register"))

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app
        )

        XCTAssertEqual(finished.exitCode, 0, finished.output)
        let invocations = try fixture.readInvocations()
        let registerIndex = try XCTUnwrap(invocations.firstIndex(of: "Vifty register"))
        let enableIndex = try XCTUnwrap(invocations.lastIndex(of: "launchctl enable"))
        XCTAssertLessThan(registerIndex, enableIndex)
    }

    func testReplacementFinishRejectsDifferentParentProcessBeforeRegistering() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        let before = try fixture.readInvocations()

        let replay = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            viaWrapper: true
        )

        XCTAssertEqual(replay.exitCode, 75, replay.output)
        XCTAssertTrue(replay.output.contains("not bound to this caller and destination"), replay.output)
        XCTAssertEqual(try fixture.readInvocations(), before, replay.output)
    }

    func testReplacementRegisterFailureThatLosesFreezeReturnsUncertain() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_REGISTER_FAIL_ACTIVE": "1"]
        )

        XCTAssertEqual(finished.exitCode, 76, finished.output)
        XCTAssertTrue(finished.output.contains("without proving the helper frozen"), finished.output)
        XCTAssertTrue(try fixture.readInvocations().contains("Vifty register"), finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("launchctl enable"), finished.output)
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "replacement-locked")
    }

    func testReplacementCompletedEvidenceFailureAfterEnableReturnsUncertain() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_CORRUPT_COMPLETION": "1"]
        )

        XCTAssertEqual(finished.exitCode, 76, finished.output)
        XCTAssertTrue(finished.output.contains("preserve the verified destination"), finished.output)
        XCTAssertTrue(try fixture.readInvocations().contains("launchctl enable"), finished.output)
    }

    func testReplacementFinishReturnsUncertainWhenAuthorityReactivatesBeforeRegister() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.simulateHelperAuthorityActive()
        let before = try fixture.readInvocations()

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app
        )

        XCTAssertEqual(finished.exitCode, 76, finished.output)
        XCTAssertTrue(finished.output.contains("authority is active or unknown"), finished.output)
        XCTAssertEqual(try fixture.readInvocations(), before, finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("Vifty register"), finished.output)
    }

    func testAlternateCandidateAfterPrepareCannotFinishAsInstalled() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate")
        let alternate = try fixture.cloneApp(in: "alternate")
        try fixture.mutateBundle(alternate, marker: "valid-resigned-alternate")

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: alternate)
        let before = try fixture.readInvocations()

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed"
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertEqual(try fixture.readInvocations(), before, finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("Vifty register"), finished.output)
    }

    func testDestinationMutationAfterExactCandidateCopyBlocksFinish() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate")

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)
        try fixture.mutateBundle(fixture.app, marker: "post-copy-mutation")
        let before = try fixture.readInvocations()

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed"
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertEqual(try fixture.readInvocations(), before, finished.output)
    }

    func testRolledBackFinishAcceptsOnlyExactSavedPreviousBundle() throws {
        let exact = try LifecycleFixture()
        defer { exact.remove() }
        let exactCandidate = try exact.cloneApp(in: "candidate")
        let exactPrepared = try exact.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: exact.app,
            replacementCandidate: exactCandidate,
            replacementPrevious: exact.app
        )
        XCTAssertEqual(exactPrepared.exitCode, 0, exactPrepared.output)
        let exactFinished = try exact.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: exact.app,
            replacementResult: "rolled-back"
        )
        XCTAssertEqual(exactFinished.exitCode, 0, exactFinished.output)

        let substituted = try LifecycleFixture()
        defer { substituted.remove() }
        let substitutedCandidate = try substituted.cloneApp(in: "candidate")
        let substitutedPrepared = try substituted.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: substituted.app,
            replacementCandidate: substitutedCandidate,
            replacementPrevious: substituted.app
        )
        XCTAssertEqual(substitutedPrepared.exitCode, 0, substitutedPrepared.output)
        try substituted.mutateBundle(substituted.app, marker: "substituted-old")
        let before = try substituted.readInvocations()
        let substitutedFinish = try substituted.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: substituted.app,
            replacementResult: "rolled-back"
        )
        XCTAssertEqual(substitutedFinish.exitCode, 75, substitutedFinish.output)
        XCTAssertEqual(try substituted.readInvocations(), before, substitutedFinish.output)
    }

    func testReplacementFinishRejectsTransactionOrParentStartReuseBeforeRegistering() throws {
        for mismatch in ["transaction", "parent-start"] {
            let fixture = try LifecycleFixture()
            defer { fixture.remove() }
            let prepared = try fixture.runLifecycle(
                operation: "repair",
                dryRun: false,
                replacementPhase: "prepare",
                replacementDestination: fixture.app,
                extraEnvironment: ["VIFTY_FIXTURE_PARENT_START_ID": "fixture-start-a"]
            )
            XCTAssertEqual(prepared.exitCode, 0, "\(mismatch): \(prepared.output)")
            let before = try fixture.readInvocations()
            let finished = try fixture.runLifecycle(
                operation: "repair",
                dryRun: false,
                replacementPhase: "finish",
                replacementDestination: fixture.app,
                replacementTransactionID: mismatch == "transaction"
                    ? "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
                    : fixture.replacementTransactionID,
                extraEnvironment: [
                    "VIFTY_FIXTURE_PARENT_START_ID": mismatch == "parent-start"
                        ? "fixture-start-b"
                        : "fixture-start-a"
                ]
            )
            XCTAssertEqual(finished.exitCode, 75, "\(mismatch): \(finished.output)")
            XCTAssertEqual(try fixture.readInvocations(), before, "\(mismatch): \(finished.output)")
        }
    }

    func testReplacementPrepareStagesAndBindsImmutableLifecycleCopy() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }

        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_PARENT_START_ID": "100.000001"]
        )

        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        let record = try fixture.readPrivilegedRecord()
        let stagedPath = try XCTUnwrap(record["replacementLifecyclePath"] as? String)
        let stagedSHA = try XCTUnwrap(record["replacementLifecycleSHA256"] as? String)
        XCTAssertEqual(stagedPath, fixture.stagedReplacementLifecycle.path)
        XCTAssertEqual(stagedSHA.count, 64)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: stagedPath))
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(URL(fileURLWithPath: stagedPath)))
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(fixture.stagedReplacementLifecycle.deletingLastPathComponent()))
    }

    func testDedicatedReplacementLedgerSurvivesOrdinaryRepairUntilNextAuthorizedPrepareAndUninstall() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let firstCandidate = try fixture.cloneApp(in: "candidate-ledger-first")
        let secondCandidate = try fixture.cloneApp(in: "candidate-ledger-second")

        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: firstCandidate,
            replacementPrevious: fixture.app
        ).exitCode, 0)
        try fixture.replaceDestination(with: firstCandidate)
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "finish",
            replacementDestination: fixture.app, replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle
        ).exitCode, 0)

        let completedLedger = try Data(contentsOf: fixture.replacementRecord)
        let ordinaryRepair = try fixture.runLifecycle(operation: "repair", dryRun: false)
        XCTAssertEqual(ordinaryRepair.exitCode, 0, ordinaryRepair.output)
        XCTAssertEqual(try Data(contentsOf: fixture.replacementRecord), completedLedger)
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "completed")
        XCTAssertNil(try fixture.readPrivilegedRecord()["replacementTransactionID"])

        let nextID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let nextPrepare = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementTransactionID: nextID,
            replacementCandidate: secondCandidate, replacementPrevious: fixture.app
        )
        XCTAssertEqual(nextPrepare.exitCode, 0, nextPrepare.output)
        XCTAssertEqual(try fixture.readReplacementRecord()["replacementTransactionID"] as? String, nextID)

        let uninstall = try fixture.runLifecycle(operation: "uninstall", dryRun: false)
        XCTAssertEqual(uninstall.exitCode, 0, uninstall.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.replacementRecord.path))
    }

    func testPreUnlockOrdinaryRepairFailurePreservesCompletedReplacementLedgerAndLock() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-ledger-failure")
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app
        ).exitCode, 0)
        try fixture.replaceDestination(with: candidate)
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "finish",
            replacementDestination: fixture.app, executable: fixture.stagedReplacementLifecycle
        ).exitCode, 0)
        let before = try Data(contentsOf: fixture.replacementRecord)

        let failed = try fixture.runLifecycle(
            operation: "repair", dryRun: false,
            extraEnvironment: ["VIFTY_FIXTURE_PREPARE_FAILURE": "1"]
        )
        XCTAssertEqual(failed.exitCode, 75, failed.output)
        XCTAssertEqual(try Data(contentsOf: fixture.replacementRecord), before)
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(fixture.app))

        let uninstall = try fixture.runLifecycle(operation: "uninstall", dryRun: false)
        XCTAssertEqual(uninstall.exitCode, 0, uninstall.output)
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.replacementRecord.path))
    }

    func testPartialLockConvergesToPreparedUnlockedLedger() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-partial-lock")
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app
        ).exitCode, 0)
        try fixture.replaceDestination(with: candidate)

        let finished = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "finish",
            replacementDestination: fixture.app, executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_PARTIAL_LOCK": "1"]
        )
        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        let ledger = try fixture.readReplacementRecord()
        XCTAssertEqual(ledger["status"] as? String, "replacement-prepared")
        XCTAssertNil(ledger["replacementFlagTransition"])
    }

    func testPartialUnlockConvergesBackToLockedLedger() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-partial-unlock")
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app
        ).exitCode, 0)
        try fixture.replaceDestination(with: candidate)
        let failedFinish = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "finish",
            replacementDestination: fixture.app, executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_REGISTER_FAIL_FROZEN": "1"]
        )
        XCTAssertEqual(failedFinish.exitCode, 75, failedFinish.output)

        let release = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "release-lock",
            replacementDestination: fixture.app, executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_PARTIAL_UNLOCK": "1"]
        )
        XCTAssertEqual(release.exitCode, 75, release.output)
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        let ledger = try fixture.readReplacementRecord()
        XCTAssertEqual(ledger["status"] as? String, "replacement-locked")
        XCTAssertNil(ledger["replacementFlagTransition"])
    }

    func testPostRenamePreFsyncTransitionFailureIsReconciledFromLedgerAndFlags() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-record-ambiguity")
        XCTAssertEqual(try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app
        ).exitCode, 0)
        try fixture.replaceDestination(with: candidate)

        let finished = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "finish",
            replacementDestination: fixture.app, executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_RECORD_POST_RENAME_FAILURE": "locking"]
        )
        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        let ledger = try fixture.readReplacementRecord()
        XCTAssertEqual(ledger["status"] as? String, "replacement-prepared")
        XCTAssertNil(ledger["replacementFlagTransition"])
    }

    func testRootSnapshotRemainsCandidateAuthorityAfterCallerSourceMutation() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-snapshot-source")
        let prepared = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT": "1"]
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("Contents/Resources/post-snapshot-source-mutation").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.candidateSnapshot.appendingPathComponent("Contents/Resources/post-snapshot-source-mutation").path
        ))
        let ledgerBinding = try XCTUnwrap(
            try fixture.readReplacementRecord()["replacementCandidateBinding"] as? [String: Any]
        )
        let mirrorBinding = try XCTUnwrap(
            try fixture.readPrivilegedRecord()["replacementCandidateBinding"] as? [String: Any]
        )
        XCTAssertEqual(ledgerBinding["manifestSHA256"] as? String, mirrorBinding["manifestSHA256"] as? String)
    }

    func testCallerCandidateMutationDuringSnapshotFailsBeforeAuthorityTeardown() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-snapshot-race")
        let prepared = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app, replacementCandidate: candidate,
            replacementPrevious: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT": "1"]
        )
        XCTAssertEqual(prepared.exitCode, 76, prepared.output)
        XCTAssertTrue(prepared.output.contains("active or unknown"), prepared.output)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("Contents/Resources/mid-snapshot-source-mutation").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.replacementRecord.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.stagedReplacementLifecycle.deletingLastPathComponent().path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent("launchctl-disabled").path
        ))
    }

    func testReplacementPrepareFailureUses76UntilExactLabelIsProvenFrozen() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let cancelled = try fixture.runLifecycle(
            operation: "repair", dryRun: false, replacementPhase: "prepare",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_ADMIN_CANCEL": "1"]
        )
        XCTAssertEqual(cancelled.exitCode, 76, cancelled.output)
        XCTAssertTrue(cancelled.output.contains("active or unknown"), cancelled.output)
    }

    func testPathSwapImmediatelyBeforeRegistrarFailsClosedWithoutExecutingAlternate() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate")
        let alternate = try fixture.cloneApp(in: "alternate-before-register")
        try fixture.installAlternateRegistrarMarker(in: alternate)
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: [
                "VIFTY_FIXTURE_SWAP_BEFORE_REGISTER": "1",
                "VIFTY_FIXTURE_ALTERNATE_APP": alternate.path
            ]
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("alternate Vifty register"), finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("launchctl enable"), finished.output)
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "replacement-locked")
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), finished.output)
    }

    func testLockFailureBeforeDurableRecordUnlocksDestinationAndKeepsAuthorityFrozen() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-lock-record-failure")
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_LOCK_RECORD_FAILURE": "1"]
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app), finished.output)
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "replacement-prepared")
        XCTAssertFalse(try fixture.readInvocations().contains("Vifty register"), finished.output)
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), finished.output)
    }

    func testNextAuthorizedUninstallReleasesCompletedLocksOnlyAfterQuiesceAndAutoProof() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-completed-lock")
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)
        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle
        )
        XCTAssertEqual(finished.exitCode, 0, finished.output)
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(fixture.app))

        let uninstalled = try fixture.runLifecycle(operation: "uninstall", dryRun: false)

        XCTAssertEqual(uninstalled.exitCode, 0, uninstalled.output)
        let invocations = try fixture.readInvocations()
        let autoIndex = try XCTUnwrap(invocations.firstIndex(of: "ViftyHelper authorizeLegacyTeardown uninstall"))
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.stagedReplacementLifecycle.path))
        XCTAssertGreaterThan(autoIndex, 0)
    }

    func testExactFrozenRegistrationFailureCanReleaseLockForInstallerRollback() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate-release-for-rollback")
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)
        let failedFinish = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_REGISTER_FAIL_FROZEN": "1"]
        )
        XCTAssertEqual(failedFinish.exitCode, 75, failedFinish.output)
        XCTAssertTrue(try fixture.pathHasFixtureImmutableFlag(fixture.app))

        let released = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "release-lock",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle
        )

        XCTAssertEqual(released.exitCode, 0, released.output)
        XCTAssertFalse(try fixture.pathHasFixtureImmutableFlag(fixture.app))
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "replacement-prepared")
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen())
    }

    func testPathSwapImmediatelyBeforeEnableFailsClosedWithoutExecutingAlternate() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let candidate = try fixture.cloneApp(in: "candidate")
        let alternate = try fixture.cloneApp(in: "alternate-before-enable")
        try fixture.installAlternateRegistrarMarker(in: alternate)
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            replacementCandidate: candidate,
            replacementPrevious: fixture.app
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)
        try fixture.replaceDestination(with: candidate)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            replacementResult: "installed",
            executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: [
                "VIFTY_FIXTURE_SWAP_BEFORE_ENABLE": "1",
                "VIFTY_FIXTURE_ALTERNATE_APP": alternate.path
            ]
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertTrue(try fixture.readInvocations().contains("Vifty register"), finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("alternate Vifty register"), finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("launchctl enable"), finished.output)
        XCTAssertEqual(try fixture.readPrivilegedRecord()["status"] as? String, "replacement-locked")
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), finished.output)
    }

    func testReplacementParentStartBindingUsesMicrosecondsAndRejectsSameSecondReplay() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let prepared = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "prepare",
            replacementDestination: fixture.app,
            extraEnvironment: ["VIFTY_FIXTURE_PARENT_START_ID": "100.000001"]
        )
        XCTAssertEqual(prepared.exitCode, 0, prepared.output)

        let finished = try fixture.runLifecycle(
            operation: "repair",
            dryRun: false,
            replacementPhase: "finish",
            replacementDestination: fixture.app,
            executable: fixture.stagedReplacementLifecycle,
            extraEnvironment: ["VIFTY_FIXTURE_PARENT_START_ID": "100.000002"]
        )

        XCTAssertEqual(finished.exitCode, 75, finished.output)
        XCTAssertFalse(try fixture.readInvocations().contains("Vifty register"), finished.output)
        let lifecycle = try read("scripts/vifty-helper-lifecycle.sh")
        XCTAssertTrue(lifecycle.contains("proc_pidinfo"))
        XCTAssertTrue(lifecycle.contains("pbi_start_tvusec"))
        XCTAssertFalse(lifecycle.contains("-o lstart="))
    }

    func testDarwinProcPIDTBSDInfoLayoutReturnsLiveSelfStartMicroseconds() throws {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        probe.arguments = [
            "-rfiddle/import",
            "-e",
            """
            module LibProc
              extend Fiddle::Importer
              dlload "/usr/lib/libproc.dylib"
              ProcBSDInfo = struct [
                "unsigned int pbi_flags", "unsigned int pbi_status", "unsigned int pbi_xstatus",
                "unsigned int pbi_pid", "unsigned int pbi_ppid", "unsigned int pbi_uid",
                "unsigned int pbi_gid", "unsigned int pbi_ruid", "unsigned int pbi_rgid",
                "unsigned int pbi_svuid", "unsigned int pbi_svgid", "unsigned int rfu_1",
                "char pbi_comm[16]", "char pbi_name[32]", "unsigned int pbi_nfiles",
                "unsigned int pbi_pgid", "unsigned int pbi_pjobc", "unsigned int e_tdev",
                "unsigned int e_tpgid", "int pbi_nice", "unsigned long long pbi_start_tvsec",
                "unsigned long long pbi_start_tvusec"
              ]
              extern "int proc_pidinfo(int, int, unsigned long long, void *, int)"
            end
            info = LibProc::ProcBSDInfo.malloc
            bytes = LibProc.proc_pidinfo(Process.pid, 3, 0, info, LibProc::ProcBSDInfo.size)
            abort "short proc_pidinfo" unless bytes == LibProc::ProcBSDInfo.size
            abort "bad usec" unless info.pbi_start_tvusec.between?(0, 999_999)
            puts "#{LibProc::ProcBSDInfo.size} #{info.pbi_start_tvsec}.#{info.pbi_start_tvusec.to_s.rjust(6, "0")}"
            """
        ]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = pipe
        try probe.run()
        probe.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(probe.terminationStatus, 0, output)
        XCTAssertTrue(output.range(of: #"^136 [0-9]+\.[0-9]{6}\n$"#, options: .regularExpression) != nil, output)
    }

    func testRepairAndUninstallWrappersDelegateOnlyToSharedLifecycle() throws {
        let repair = try read("scripts/repair-vifty-helper.sh")
        let uninstall = try read("scripts/uninstall-vifty.sh")

        XCTAssertTrue(repair.contains("vifty-helper-lifecycle.sh"))
        XCTAssertTrue(repair.contains("--operation repair"))
        XCTAssertFalse(repair.contains("launchctl"))
        XCTAssertFalse(repair.contains("osascript"))
        XCTAssertTrue(uninstall.contains("vifty-helper-lifecycle.sh"))
        XCTAssertTrue(uninstall.contains("--operation uninstall"))
        XCTAssertFalse(uninstall.contains("launchctl"))
        XCTAssertFalse(uninstall.contains("osascript"))
    }

    func testShellWrappersClearBashEnvironmentBeforeLifecycleParsing() throws {
        let fixture = try LifecycleFixture()
        defer { fixture.remove() }
        let marker = fixture.root.appendingPathComponent("bash-environment-injection-marker")
        let bashEnvironment = fixture.root.appendingPathComponent("malicious-bash-env.sh")
        try Data("/usr/bin/touch \"${VIFTY_INJECTION_MARKER}\"\n".utf8).write(to: bashEnvironment)

        for wrapper in ["scripts/repair-vifty-helper.sh", "scripts/uninstall-vifty.sh"] {
            let process = Process()
            process.executableURL = repositoryRoot.appendingPathComponent(wrapper)
            process.arguments = [
                "--dry-run",
                "--app", fixture.app.path,
                "--record", fixture.record.path
            ]
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "BASH_ENV": bashEnvironment.path,
                "VIFTY_INJECTION_MARKER": marker.path,
                "BASH_FUNC_declare%%": "() { /usr/bin/touch \"${VIFTY_INJECTION_MARKER}\"; builtin declare \"$@\"; }"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(process.terminationStatus, 75)
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    func testAdministratorAuthorizationExecutesOnlyAVerifiedRootOwnedWorkerSnapshot() throws {
        let lifecycle = try read("scripts/vifty-helper-lifecycle.sh")

        XCTAssertFalse(lifecycle.contains("BASH_SOURCE"))
        XCTAssertFalse(lifecycle.contains("SCRIPT_PATH"))
        XCTAssertFalse(lifecycle.contains("--root-worker"))
        XCTAssertTrue(lifecycle.contains("build_root_program"))
        XCTAssertTrue(lifecycle.contains("/private/tmp/vifty-lifecycle-root.XXXXXX"))
        XCTAssertTrue(lifecycle.contains("actual_digest="))
        XCTAssertTrue(lifecycle.contains("[[ \"${actual_digest}\" == \"${expected_digest}\" ]] || exit 78"))
        XCTAssertTrue(lifecycle.contains("/bin/chmod 500 \"${worker_path}\""))
        XCTAssertTrue(lifecycle.contains("/bin/bash --noprofile --norc \"${worker_path}\""))
        XCTAssertTrue(lifecycle.contains("/usr/bin/env -i HOME=/var/root PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        XCTAssertTrue(lifecycle.contains("/bin/bash --noprofile --norc -c"))
        XCTAssertTrue(lifecycle.contains("certificate 1[field.1.2.840.113635.100.6.2.6] exists"))
        XCTAssertTrue(lifecycle.contains("certificate leaf[field.1.2.840.113635.100.6.1.13] exists"))
        XCTAssertTrue(lifecycle.contains("certificate leaf[subject.OU] = \\\"${RELEASE_TEAM_ID}\\\""))
        XCTAssertTrue(lifecycle.contains("case \"${CALLER_UID}\" in ''|*[!0-9]*)"))
        XCTAssertTrue(lifecycle.contains("MAINTENANCE_DIR=\"/Library/Application Support/Vifty/Maintenance\""))
        XCTAssertTrue(lifecycle.contains("EXECUTION_DIR=\"/Library/Application Support/ViftyMaintenanceEvidence\""))
        XCTAssertTrue(lifecycle.contains("Dir.mkdir(dir, 0755)"))
        XCTAssertTrue(lifecycle.contains("File.open(tmp, flags, mode)"))
        XCTAssertTrue(lifecycle.contains("atomic_write.call(replacement_record_path, 0600)"))
        XCTAssertTrue(lifecycle.contains("atomic_write.call(path, 0644)"))
        let callerUIDInitialization = try XCTUnwrap(lifecycle.range(of: "CALLER_UID=\"$(/usr/bin/id -u)\""))
        let fixtureOwnerInitialization = try XCTUnwrap(lifecycle.range(of: "EXPECTED_OWNER_UID=\"${CALLER_UID}\""))
        XCTAssertLessThan(callerUIDInitialization.lowerBound, fixtureOwnerInitialization.lowerBound)
        XCTAssertFalse(lifecycle.contains("do shell script quoted form of"))
        let rootWorker = try XCTUnwrap(
            lifecycle.range(of: "root_worker() {").flatMap { start in
                lifecycle.range(of: "\nbuild_root_program()", range: start.upperBound..<lifecycle.endIndex)
                    .map { String(lifecycle[start.lowerBound..<$0.lowerBound]) }
            }
        )
        XCTAssertFalse(rootWorker.contains("VIFTY_MAIN"))
        XCTAssertFalse(rootWorker.contains("VIFTY_CTL"))
        XCTAssertFalse(rootWorker.contains("MAINTENANCE_REPORT"))
        XCTAssertTrue(rootWorker.contains("validate_root_authority"))
        XCTAssertTrue(rootWorker.contains("stage_trusted_helper"))
        XCTAssertTrue(rootWorker.contains("stage_verified_legacy_v132_daemon"))
        XCTAssertTrue(rootWorker.contains("disable_and_confirm_service"))
        let scratchAssignment = try XCTUnwrap(rootWorker.range(of: "ROOT_WORKER_TMP=\"${local_tmp}\""))
        let setupCleanupTrap = try XCTUnwrap(rootWorker.range(of: "trap root_worker_scratch_cleanup EXIT"))
        let setupOwnership = try XCTUnwrap(rootWorker.range(of: "/usr/sbin/chown 0:0 \"${local_tmp}\""))
        let authenticatedCleanupTrap = try XCTUnwrap(rootWorker.range(of: "trap root_worker_exit EXIT"))
        XCTAssertLessThan(scratchAssignment.lowerBound, setupCleanupTrap.lowerBound)
        XCTAssertLessThan(setupCleanupTrap.lowerBound, setupOwnership.lowerBound)
        XCTAssertLessThan(setupOwnership.lowerBound, authenticatedCleanupTrap.lowerBound)
        let legacyVerification = try XCTUnwrap(
            rootWorker.range(of: "stage_verified_legacy_v132_daemon \"${local_tmp}\"")
        )
        let serviceDisable = try XCTUnwrap(
            rootWorker.range(of: "disable_and_confirm_service || root_fail")
        )
        XCTAssertLessThan(legacyVerification.lowerBound, serviceDisable.lowerBound)
        XCTAssertTrue(lifecycle.contains("7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac"))
        XCTAssertTrue(lifecycle.contains("c5613e3020d94de1d141917d7b950fc367a6e61a"))
        XCTAssertTrue(lifecycle.contains("DAEMON_SIGNING_ID=\"tech.reidar.vifty.daemon\""))
        XCTAssertTrue(lifecycle.contains("/usr/bin/printf '%s\\n' 'root_worker'"))
        XCTAssertFalse(lifecycle.contains("if ! root_worker"))
    }

    func testPublicReplacementBindingUsesCanonicalRootSnapshotContentBeforeTeardown() throws {
        let lifecycle = try read("scripts/vifty-helper-lifecycle.sh")
        for option in [
            "--replacement-public-content-manifest-sha256",
            "--replacement-public-previous-content-manifest-sha256",
            "--replacement-public-version",
            "--replacement-public-build",
            "--replacement-public-team-id",
            "--replacement-public-archive-sha256"
        ] {
            XCTAssertTrue(lifecycle.contains(option), option)
        }
        XCTAssertTrue(lifecycle.contains("\"contentManifestSHA256\""))
        XCTAssertTrue(lifecycle.contains("[\"uid\", \"gid\", \"nlink\"].include?(key)"))
        XCTAssertTrue(lifecycle.contains("row[\"type\"] == \"symlink\" && key == \"size\""))
        XCTAssertTrue(lifecycle.contains("replacementPublicCandidateExpectation"))
        XCTAssertTrue(lifecycle.contains("previousContentManifestSHA256"))
        XCTAssertTrue(lifecycle.contains("bind_replacement_public_previous_snapshot"))

        let rootWorker = try XCTUnwrap(
            lifecycle.range(of: "root_worker() {").flatMap { start in
                lifecycle.range(of: "\nbuild_root_program()", range: start.upperBound..<lifecycle.endIndex)
                    .map { String(lifecycle[start.lowerBound..<$0.lowerBound]) }
            }
        )
        let snapshot = try XCTUnwrap(rootWorker.range(of: "stage_replacement_candidate_snapshot || root_fail"))
        let teardown = try XCTUnwrap(rootWorker.range(of: "disable_and_confirm_service || root_fail"))
        XCTAssertLessThan(snapshot.lowerBound, teardown.lowerBound)
        XCTAssertTrue(lifecycle.contains("bind_replacement_public_candidate_snapshot \"${snapshot_binding}\" || return 1"))
        XCTAssertTrue(lifecycle.contains("identity[\"bundleVersion\"] == expected_version"))
        XCTAssertTrue(lifecycle.contains("identity[\"bundleBuild\"] == expected_build"))
        XCTAssertTrue(lifecycle.contains("identity[\"kind\"] == \"developer-id\" && identity[\"teamID\"] == expected_team"))
        XCTAssertTrue(lifecycle.contains("if ! bundle_version=\"$(/usr/bin/plutil -extract CFBundleShortVersionString"))
        XCTAssertTrue(lifecycle.contains("if ! bundle_build=\"$(/usr/bin/plutil -extract CFBundleVersion"))
        XCTAssertFalse(lifecycle.contains("CFBundleShortVersionString raw -o - \"${app}/Contents/Info.plist\" 2>/dev/null || true"))
        XCTAssertFalse(lifecycle.contains("CFBundleVersion raw -o - \"${app}/Contents/Info.plist\" 2>/dev/null || true"))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class LifecycleFixture {
    let root: URL
    let app: URL
    let record: URL
    let forbiddenInvocationLog: URL
    let recoveryState: URL
    let authorityReceipt: URL
    let privilegedRecord: URL
    let replacementRecord: URL
    let legacyFiles: [URL]
    let replacementTransactionID = "11111111-2222-4333-8444-555555555555"

    var stagedReplacementLifecycle: URL {
        root.appendingPathComponent(
            "Library/Application Support/ViftyMaintenanceEvidence/ReplacementTransactions/\(replacementTransactionID)/vifty-helper-lifecycle.sh"
        )
    }

    var candidateSnapshot: URL {
        stagedReplacementLifecycle.deletingLastPathComponent()
            .appendingPathComponent("CandidateSnapshot/Vifty.app", isDirectory: true)
    }

    private let repositoryRoot: URL

    init() throws {
        repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = try canonicalHelperLifecycleTemporaryDirectory()
            .appendingPathComponent("vifty-helper-lifecycle-tests-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("Vifty.app", isDirectory: true)
        record = root.appendingPathComponent("command-record.json")
        forbiddenInvocationLog = root.appendingPathComponent("forbidden-invocations.log")
        recoveryState = root.appendingPathComponent("Library/Application Support/Vifty/FanControl/journal.json")
        authorityReceipt = root.appendingPathComponent("Library/Application Support/Vifty/Maintenance/authorized-v1.json")
        privilegedRecord = root.appendingPathComponent("Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json")
        replacementRecord = root.appendingPathComponent("Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json")
        legacyFiles = [
            root.appendingPathComponent("Library/PrivilegedHelperTools/tech.reidar.vifty.daemon"),
            root.appendingPathComponent("Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"),
            root.appendingPathComponent("var/log/tech.reidar.vifty.daemon.out.log"),
            root.appendingPathComponent("var/log/tech.reidar.vifty.daemon.err.log")
        ]
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Library/LaunchDaemons", isDirectory: true),
            withIntermediateDirectories: true
        )
        let lifecycleResource = app.appendingPathComponent(
            "Contents/Resources/vifty-helper-lifecycle.sh"
        )
        try FileManager.default.createDirectory(
            at: lifecycleResource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/vifty-helper-lifecycle.sh"),
            to: lifecycleResource
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: lifecycleResource.path
        )
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "tech.reidar.vifty",
                "CFBundleExecutable": "Vifty",
                "CFBundlePackageType": "APPL"
            ],
            format: .xml,
            options: 0
        )
        try infoData.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: recoveryState.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("preserve".utf8).write(to: recoveryState)
        for legacyFile in legacyFiles {
            try FileManager.default.createDirectory(
                at: legacyFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("legacy".utf8).write(to: legacyFile)
        }
        try writeFixtureExecutables()
    }

    func remove() {
        try? clearFixtureImmutableFlags(at: root)
        try? FileManager.default.removeItem(at: root)
    }

    func cloneApp(in directoryName: String) throws -> URL {
        let parent = root.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let clone = parent.appendingPathComponent("Vifty.app", isDirectory: true)
        try FileManager.default.copyItem(at: app, to: clone)
        return clone
    }

    func replaceDestination(with source: URL) throws {
        try FileManager.default.removeItem(at: app)
        try FileManager.default.copyItem(at: source, to: app)
    }

    func mutateBundle(_ bundle: URL, marker: String) throws {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: resources.appendingPathComponent("binding-mutation"))
    }

    func installAlternateRegistrarMarker(in bundle: URL) throws {
        try writeExecutable(
            "#!/bin/bash\nprintf 'alternate Vifty register\\n' >> \"${VIFTY_FIXTURE_INVOCATION_LOG}\"\nexit 99\n",
            to: bundle.appendingPathComponent("Contents/MacOS/Vifty")
        )
    }

    func pathHasFixtureImmutableFlag(_ url: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
        process.arguments = ["-f", "%f", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        let value = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let flags = UInt32(value) else { return false }
        return (flags & 0x2) == 0x2
    }

    func replacementAuthorityIsFrozen() throws -> Bool {
        let process = Process()
        process.executableURL = root.appendingPathComponent("bin/launchctl")
        process.arguments = ["print-disabled", "system"]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "VIFTY_LIFECYCLE_TEST_ROOT": root.path,
            "VIFTY_FIXTURE_INVOCATION_LOG": forbiddenInvocationLog.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && output.contains("tech.reidar.vifty.daemon") &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent("launchctl-state").path)
    }

    private func clearFixtureImmutableFlags(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["-R", "nouchg", url.path]
        try process.run()
        process.waitUntilExit()
    }

    func runLifecycle(
        operation: String,
        dryRun: Bool,
        maintenanceReport: URL? = nil,
        replacementPhase: String? = nil,
        replacementDestination: URL? = nil,
        replacementResult: String? = nil,
        replacementTransactionID: String? = nil,
        replacementCandidate: URL? = nil,
        replacementPrevious: URL? = nil,
        viaWrapper: Bool = false,
        executable: URL? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> (exitCode: Int32, output: String) {
        var arguments = [
            (executable ?? repositoryRoot.appendingPathComponent("scripts/vifty-helper-lifecycle.sh")).path,
            "--operation", operation,
            "--app", app.path,
            "--record", record.path
        ]
        if dryRun { arguments.append("--dry-run") }
        if let maintenanceReport {
            arguments.append(contentsOf: ["--maintenance-report", maintenanceReport.path])
        }
        if let replacementPhase {
            arguments.append(contentsOf: ["--replacement-phase", replacementPhase])
        }
        if let replacementDestination {
            arguments.append(contentsOf: ["--replacement-destination", replacementDestination.path])
        }
        if let replacementPhase {
            arguments.append(contentsOf: [
                "--replacement-transaction-id",
                replacementTransactionID ?? self.replacementTransactionID
            ])
            if replacementPhase == "prepare" {
                let lifecycleSource = (replacementCandidate ?? app).appendingPathComponent(
                    "Contents/Resources/vifty-helper-lifecycle.sh"
                )
                arguments.append(contentsOf: [
                    "--replacement-candidate", (replacementCandidate ?? app).path,
                    "--replacement-previous", (replacementPrevious ?? app).path,
                    "--replacement-lifecycle-source", lifecycleSource.path,
                    "--replacement-lifecycle-sha256", try sha256(lifecycleSource)
                ])
            } else if replacementPhase == "finish" || replacementPhase == "release-lock" {
                arguments.append(contentsOf: [
                    "--replacement-result", replacementResult ?? "installed"
                ])
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var fixtureEnvironment = [
            "TMPDIR": root.path,
            "VIFTY_TEST_FORBIDDEN_LOG": forbiddenInvocationLog.path,
            "VIFTY_LIFECYCLE_TEST_ROOT": root.path,
            "VIFTY_FIXTURE_INVOCATION_LOG": forbiddenInvocationLog.path
        ]
        let allowedExtraEnvironment = Set([
            "VIFTY_FIXTURE_UNREGISTER_FAIL",
            "VIFTY_FIXTURE_BOOTOUT_FAIL",
            "VIFTY_FIXTURE_STILL_LOADED",
            "VIFTY_FIXTURE_PROTOCOL_V1",
            "VIFTY_FIXTURE_PROTOCOL_MISMATCH",
            "VIFTY_FIXTURE_LEGACY_LOOKALIKE",
            "VIFTY_FIXTURE_STALE_ERROR",
            "VIFTY_FIXTURE_LEGACY_UNSAFE",
            "VIFTY_FIXTURE_ONE_FAN",
            "VIFTY_FIXTURE_ADMIN_CANCEL",
            "VIFTY_FIXTURE_EXPIRED_RECEIPT",
            "VIFTY_FIXTURE_MALFORMED_RECEIPT",
            "VIFTY_FIXTURE_CROSS_BOOT_RECEIPT",
            "VIFTY_FIXTURE_HELPER_CHANGED_RECEIPT",
            "VIFTY_FIXTURE_OMIT_RECEIPT",
            "VIFTY_FIXTURE_ROOT_SIGNAL",
            "VIFTY_FIXTURE_ROOT_RETURN_INCOMPLETE",
            "VIFTY_FIXTURE_CORRUPT_COMPLETION",
            "VIFTY_FIXTURE_DECOY_DISABLED",
            "VIFTY_FIXTURE_REGISTER_FAIL_ACTIVE",
            "VIFTY_FIXTURE_REGISTER_FAIL_FROZEN",
            "VIFTY_FIXTURE_PARENT_START_ID",
            "VIFTY_FIXTURE_PREPARE_FAILURE",
            "VIFTY_FIXTURE_SAFETY_BLOCK",
            "VIFTY_FIXTURE_MALFORMED_BLOCK"
            ,"VIFTY_FIXTURE_SWAP_BEFORE_REGISTER"
            ,"VIFTY_FIXTURE_SWAP_BEFORE_ENABLE"
            ,"VIFTY_FIXTURE_ALTERNATE_APP"
            ,"VIFTY_FIXTURE_LOCK_RECORD_FAILURE"
            ,"VIFTY_FIXTURE_PARTIAL_LOCK"
            ,"VIFTY_FIXTURE_PARTIAL_UNLOCK"
            ,"VIFTY_FIXTURE_RECORD_POST_RENAME_FAILURE"
            ,"VIFTY_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT"
            ,"VIFTY_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT"
        ])
        for (key, value) in extraEnvironment where allowedExtraEnvironment.contains(key) {
            fixtureEnvironment[key] = value
        }
        let environmentArguments = [
            "-i",
            "HOME=/var/empty",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        ] + fixtureEnvironment.map { "\($0.key)=\($0.value)" }.sorted()
        if viaWrapper {
            process.arguments = environmentArguments + [
                "/bin/bash", "--noprofile", "--norc", "-c",
                "/bin/bash --noprofile --norc \"$@\" & child=$!; wait \"$child\"",
                "lifecycle-wrapper"
            ] + arguments
        } else {
            process.arguments = environmentArguments + [
                "/bin/bash", "--noprofile", "--norc"
            ] + arguments
        }
        process.environment = [:]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func sha256(_ url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0, let digest = output.split(separator: " ").first else {
            throw NSError(domain: "LifecycleFixture", code: 1)
        }
        return String(digest)
    }

    func readRecord() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any]
        )
    }

    func readInvocations() throws -> [String] {
        guard FileManager.default.fileExists(atPath: forbiddenInvocationLog.path) else { return [] }
        return try String(contentsOf: forbiddenInvocationLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func readPrivilegedRecord() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: privilegedRecord)) as? [String: Any]
        )
    }

    func readReplacementRecord() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: replacementRecord)) as? [String: Any]
        )
    }

    func workerScratchDirectories() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("vifty-lifecycle-worker.") }
    }

    func simulateHelperAuthorityActive() throws {
        for marker in ["launchctl-disabled", "launchctl-state"] {
            let url = root.appendingPathComponent(marker)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func writeFixtureExecutables() throws {
        let viftyctl = app.appendingPathComponent("Contents/MacOS/viftyctl")
        try writeExecutable(
            """
            #!/bin/bash
            set -euo pipefail
            log="${VIFTY_FIXTURE_INVOCATION_LOG}"
            if [[ "$1" == "helper-maintenance-prepare" ]]; then
              operation="$3"
              printf 'viftyctl prepare %s\\n' "$operation" >> "$log"
              if [[ "${VIFTY_FIXTURE_PREPARE_FAILURE:-0}" == "1" ]]; then
                now="$(( $(/bin/date +%s) - 978307200 ))"
                printf '{"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-command-error.schema.json","command":"helper-maintenance-prepare","errorCode":"HELPER_UNREACHABLE","message":"fixture","safeToProceed":false,"recommendedRecoveryAction":"repairHelper","recoverySteps":[],"coolingLeasePrepared":false,"autoRestoreAttempted":false,"autoRestoreSucceeded":null,"generatedAt":%s}\\n' "$now"
                exit 1
              fi
              if [[ "${VIFTY_FIXTURE_MALFORMED_BLOCK:-0}" == "1" ]]; then printf '{}\\n'; exit 75; fi
              if [[ "${VIFTY_FIXTURE_PROTOCOL_V1:-0}" == "1" ]]; then
                legacy_daemon="${VIFTY_LIFECYCLE_TEST_ROOT}/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon"
                if [[ "${VIFTY_FIXTURE_LEGACY_LOOKALIKE:-0}" == "1" ]]; then
                  printf 'fixture-lookalike-v1.3.2-daemon\\n' > "$legacy_daemon"
                else
                  printf 'fixture-canonical-v1.3.2-daemon\\n' > "$legacy_daemon"
                fi
                /bin/chmod 755 "$legacy_daemon"
                now="$(( $(/bin/date +%s) - 978307200 ))"
                if [[ "${VIFTY_FIXTURE_STALE_ERROR:-0}" == "1" ]]; then now=0; fi
                printf '{"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-command-error.schema.json","command":"helper-maintenance-prepare","errorCode":"HELPER_UNREACHABLE","message":"selector unavailable","safeToProceed":false,"recommendedRecoveryAction":"repairHelper","recoverySteps":[],"coolingLeasePrepared":false,"autoRestoreAttempted":false,"generatedAt":%s}\\n' "$now"
                exit 1
              fi
              if [[ "${VIFTY_FIXTURE_PROTOCOL_MISMATCH:-0}" == "1" || "${VIFTY_FIXTURE_SAFETY_BLOCK:-0}" == "1" ]]; then
                blocker="PROTOCOL_MISMATCH"
                if [[ "${VIFTY_FIXTURE_SAFETY_BLOCK:-0}" == "1" ]]; then blocker="RESTORE_FAILED"; fi
                printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"%s","safeToStop":false,"quiesced":true,"restoreAttempted":true,"restoreSucceeded":true,"completeExpectedSetConfirmed":false,"fanResults":[],"blockers":[{"code":"%s","message":"fixture","recommendedRecoveryAction":"fixture"}],"token":null,"tokenConsumed":false}\\n' "$operation" "$blocker"
                exit 75
              fi
              helper_sha="$(/usr/bin/shasum -a 256 "$(/usr/bin/dirname "$0")/ViftyHelper" | /usr/bin/awk '{print $1}')"
              cat <<JSON
            {"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"${operation}","safeToStop":true,"quiesced":true,"restoreAttempted":true,"restoreSucceeded":true,"completeExpectedSetConfirmed":true,"fanResults":[],"blockers":[],"token":{"schemaVersion":1,"tokenID":"fixture-token-${operation}","operation":"${operation}","issuedAt":1000,"expiresAt":1030,"bootSessionID":"boot","daemonSessionID":"daemon","journalGeneration":1,"expectedFanIDs":[0,1],"helperSHA256":"${helper_sha}","quiesceGeneration":1},"tokenConsumed":false}
            JSON
              exit 0
            fi
            if [[ "$1" == "helper-maintenance-cancel" ]]; then
              printf 'viftyctl cancel\\n' >> "$log"
              printf '{"cancelled":true}\\n'
              exit 0
            fi
            exit 64
            """,
            to: viftyctl
        )

        let vifty = app.appendingPathComponent("Contents/MacOS/Vifty")
        try writeExecutable(
            """
            #!/bin/bash
            set -euo pipefail
            log="${VIFTY_FIXTURE_INVOCATION_LOG}"
            action="$2"
            if [[ "$action" == "unregister" ]]; then
              operation="$4"; report="$6"
              printf 'Vifty unregister %s\\n' "$operation" >> "$log"
              if [[ "${VIFTY_FIXTURE_UNREGISTER_FAIL:-0}" == "1" ]]; then exit 75; fi
              token_id="$(/usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("token", "tokenID")' "$report")"
              helper_sha="$(/usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("token", "helperSHA256")' "$report")"
              if [[ "${VIFTY_FIXTURE_HELPER_CHANGED_RECEIPT:-0}" == "1" ]]; then helper_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"; fi
              if [[ "${VIFTY_FIXTURE_OMIT_RECEIPT:-0}" != "1" ]]; then
                authority_dir="${VIFTY_LIFECYCLE_TEST_ROOT}/Library/Application Support/Vifty/Maintenance"
                /bin/mkdir -p "$authority_dir"
                /bin/chmod 700 "$authority_dir"
                now="$(/bin/date +%s)"
                authorized="$now"
                expires="$((now + 300))"
                boot_id="boot"
                if [[ "${VIFTY_FIXTURE_EXPIRED_RECEIPT:-0}" == "1" ]]; then authorized="$((now - 301))"; expires="$((now - 1))"; fi
                if [[ "${VIFTY_FIXTURE_CROSS_BOOT_RECEIPT:-0}" == "1" ]]; then boot_id="older-boot"; fi
                if [[ "${VIFTY_FIXTURE_MALFORMED_RECEIPT:-0}" == "1" ]]; then
                  printf '{"schemaVersion":1,"operation":"%s"}\\n' "$operation" > "$authority_dir/authorized-v1.json"
                else
                  printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-authority-v1.json","recordKind":"daemon-authorized-helper-maintenance","operation":"%s","tokenID":"%s","tokenIssuedAt":%s,"authorizedAt":%s,"expiresAt":%s,"bootSessionID":"%s","daemonSessionID":"daemon","journalGeneration":1,"expectedFanIDs":[0,1],"helperSHA256":"%s","quiesceGeneration":1,"quiesced":true,"tokenConsumed":true}\\n' "$operation" "$token_id" "$authorized" "$authorized" "$expires" "$boot_id" "$helper_sha" > "$authority_dir/authorized-v1.json"
                fi
                /bin/chmod 600 "$authority_dir/authorized-v1.json"
              fi
              printf '{"action":"unregister","state":"notRegistered","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":true,"tokenID":"%s"}\\n' "$token_id"
              exit 0
            fi
            if [[ "$action" == "unregister-legacy" ]]; then
              operation="$4"
              printf 'Vifty unregister-legacy %s\\n' "$operation" >> "$log"
              printf '{"action":"unregister","state":"notRegistered","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":false,"tokenID":null,"legacyProtocolGateUsed":true,"legacyMarkerPresent":true}\\n'
              exit 0
            fi
            if [[ "$action" == "register" ]]; then
              printf 'Vifty register\\n' >> "$log"
              if [[ "${VIFTY_FIXTURE_REGISTER_FAIL_FROZEN:-0}" == "1" ]]; then exit 75; fi
              if [[ "${VIFTY_FIXTURE_REGISTER_FAIL_ACTIVE:-0}" == "1" ]]; then
                /bin/rm -f "${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-disabled"
                /bin/rm -f "${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-state"
                exit 75
              fi
              printf '{"action":"register","state":"enabled","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":false,"tokenID":null}\\n'
              exit 0
            fi
            exit 64
            """,
            to: vifty
        )

        try writeExecutable(
            """
            #!/bin/bash
            exit 0
            """,
            to: app.appendingPathComponent("Contents/MacOS/ViftyDaemon")
        )

        let helper = app.appendingPathComponent("Contents/MacOS/ViftyHelper")
        try writeExecutable(
            """
            #!/bin/bash
            set -euo pipefail
            log="${VIFTY_FIXTURE_INVOCATION_LOG}"
            [[ "$1" == "authorizeLegacyTeardown" && "$2" == "--operation" && "$4" == "--json" ]] || exit 64
            operation="$3"
            printf 'ViftyHelper authorizeLegacyTeardown %s\\n' "$operation" >> "$log"
            if [[ "${VIFTY_FIXTURE_LEGACY_UNSAFE:-0}" == "1" ]]; then
              printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"%s","safeToStop":false,"quiesced":false,"restoreAttempted":true,"restoreSucceeded":false,"completeExpectedSetConfirmed":false,"fanResults":[],"blockers":[{"code":"RESTORE_FAILED","message":"fixture","recommendedRecoveryAction":"fixture"}],"token":null,"tokenConsumed":false}\\n' "$operation"
              exit 75
            fi
            now="$(/bin/date +%s)"
            if [[ "${VIFTY_FIXTURE_ONE_FAN:-0}" == "1" ]]; then
              fans="[{\\\"fanID\\\":0,\\\"observedMode\\\":\\\"automatic\\\",\\\"confirmedOSManaged\\\":true,\\\"freshConfirmationAt\\\":${now},\\\"failure\\\":null}]"
            else
              fans="[{\\\"fanID\\\":0,\\\"observedMode\\\":\\\"automatic\\\",\\\"confirmedOSManaged\\\":true,\\\"freshConfirmationAt\\\":${now},\\\"failure\\\":null},{\\\"fanID\\\":1,\\\"observedMode\\\":\\\"system\\\",\\\"confirmedOSManaged\\\":true,\\\"freshConfirmationAt\\\":${now},\\\"failure\\\":null}]"
            fi
            printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"%s","safeToStop":true,"quiesced":true,"restoreAttempted":true,"restoreSucceeded":true,"completeExpectedSetConfirmed":true,"fanResults":%s,"blockers":[],"token":null,"tokenConsumed":false}\\n' "$operation" "$fans"
            """,
            to: helper
        )

        try writeExecutable(
            """
            #!/bin/bash
            set -euo pipefail
            state="${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-state"
            disabled="${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-disabled"
            if [[ "$1" == "print" ]]; then
              if [[ "${VIFTY_FIXTURE_STILL_LOADED:-0}" == "1" ]]; then exit 0; fi
              [[ ! -e "$state" ]]
              exit $?
            fi
            if [[ "$1" == "print-disabled" ]]; then
              if [[ "${VIFTY_FIXTURE_DECOY_DISABLED:-0}" == "1" ]]; then
                printf 'disabled services = {\\n  "techXreidarYviftyZdaemon" => true\\n}\\n'
              elif [[ -e "$disabled" ]]; then
                printf 'disabled services = {\\n  "tech.reidar.vifty.daemon" => true\\n}\\n'
              else
                printf 'disabled services = { }\\n'
              fi
              exit 0
            fi
            if [[ "$1" == "disable" ]]; then
              printf 'launchctl disable\\n' >> "${VIFTY_FIXTURE_INVOCATION_LOG}"
              if [[ "${VIFTY_FIXTURE_DECOY_DISABLED:-0}" != "1" ]]; then : > "$disabled"; fi
              exit 0
            fi
            if [[ "$1" == "enable" ]]; then
              printf 'launchctl enable\\n' >> "${VIFTY_FIXTURE_INVOCATION_LOG}"
              /bin/rm -f "$disabled"
              exit 0
            fi
            if [[ "$1" == "bootout" ]]; then
              printf 'launchctl bootout\\n' >> "${VIFTY_FIXTURE_INVOCATION_LOG}"
              if [[ "${VIFTY_FIXTURE_BOOTOUT_FAIL:-0}" == "1" ]]; then exit 1; fi
              : > "$state"
              exit 0
            fi
            exit 64
            """,
            to: root.appendingPathComponent("bin/launchctl")
        )
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}

private func canonicalHelperLifecycleTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    guard let resolved = realpath(temporaryDirectory.path, nil) else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
    }
    defer { free(resolved) }
    let bytes = UnsafeRawBufferPointer(start: resolved, count: strlen(resolved))
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
}
