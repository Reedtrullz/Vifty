import Darwin
import Foundation
import XCTest

final class InstallReplacementPreflightScriptTests: XCTestCase {
    func testCanonicalPublishedV132IdentityPinsAndDeveloperIDRequirementDoNotDrift() throws {
        let installer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-vifty.sh"),
            encoding: .utf8
        )
        let expectedPins = [
            #"PUBLISHED_V132_ARCHIVE_SHA256="8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0""#,
            #"PUBLISHED_V132_MAIN_SHA256="10e6ca95faa8167bf81df49bfa7407ad5f8ab3e55cf7720085ec61334897c55e""#,
            #"PUBLISHED_V132_CTL_SHA256="63d2837795f22a34f1833c9c38a49b2c95d87339262347cca89b0245f7068f3e""#,
            #"PUBLISHED_V132_DAEMON_SHA256="7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac""#,
            #"PUBLISHED_V132_HELPER_SHA256="f081eb5f0f3097d0baf8b96b8655cb038d6b5e8abb406e53192305af31a98cf0""#,
            #"PUBLISHED_V132_MAIN_CDHASH="666e4972fcb31fa3fcb3134c956daae0bdf62189""#,
            #"PUBLISHED_V132_CTL_CDHASH="95a55844ba7b4983712c69693ec4c4b80a7e1205""#,
            #"PUBLISHED_V132_DAEMON_CDHASH="c5613e3020d94de1d141917d7b950fc367a6e61a""#,
            #"PUBLISHED_V132_HELPER_CDHASH="c5802ef35c7cbeabad37db5657dd20fa95f727ba""#
        ]
        for pin in expectedPins {
            XCTAssertTrue(installer.contains(pin), "missing canonical identity pin: \(pin)")
        }
        XCTAssertTrue(installer.contains("anchor apple generic"))
        XCTAssertTrue(installer.contains("1.2.840.113635.100.6.1.13"))
        XCTAssertTrue(installer.contains("1.2.840.113635.100.6.2.6"))
        XCTAssertTrue(installer.contains(#"certificate leaf[subject.OU] = \"${PUBLISHED_V132_TEAM_ID}\""#))
    }

    func testCorruptStagedCandidatePreservesExistingAppBeforeSwap() throws {
        let fixture = try InstallReplacementFixture(report: .safe, dittoBehavior: .copyAndCorrupt)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing")
        XCTAssertTrue(try fixture.recoveryPreviousApps().isEmpty)
    }

    func testStageMktempFailurePreservesExistingApp() throws {
        let fixture = try InstallReplacementFixture(report: .safe, failStageMktemp: true)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing")
        XCTAssertEqual(try fixture.dittoCallCount(), 0)
    }

    func testHashFailureBlocksBeforeExecutingOrReplacingExistingApp() throws {
        let fixture = try InstallReplacementFixture(report: .safe, failSHA256: true)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing")
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        XCTAssertEqual(try fixture.dittoCallCount(), 0)
    }

    func testRollbackRestoreFailurePreservesPreviousAppAtExplicitRecoveryPath() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failRollbackRestore: true,
            failPostSwapVerification: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()
        let recoveryApps = try fixture.recoveryPreviousApps()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("HARD FAILURE"), result.output)
        XCTAssertTrue(
            result.output.contains("helper authority was last proven disabled and offline"),
            result.output
        )
        XCTAssertEqual(try fixture.dittoCallCount(), 1, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy"],
            result.output
        )
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), result.output)
        XCTAssertEqual(recoveryApps.count, 1, result.output)
        XCTAssertEqual(
            try String(
                contentsOf: recoveryApps[0].appendingPathComponent("Contents/Resources/preserve-me"),
                encoding: .utf8
            ),
            "existing"
        )
    }

    func testMissingStagedPreviousNeverAcceptsSubstitutedValidDestinationAsRollback() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority
        )
        defer { fixture.remove() }

        let result = try fixture.run(overrides: [
            "VIFTY_INSTALL_FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK": "1",
            "VIFTY_INSTALL_FIXTURE_POST_SWAP_VERIFICATION_FAILURE": "1"
        ])

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("staged previous app is missing"), result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy"],
            result.output
        )
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), result.output)
        XCTAssertNil(try fixture.existingSentinelContents(), result.output)
        XCTAssertEqual(try fixture.displacedPreviousApps().count, 1, result.output)
    }

    func testProtocolV2ValidJSONWithNonzeroDiagnoseExitIsRejected() throws {
        let fixture = try InstallReplacementFixture(report: .safe, existingCtlExitCode: 75)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testFixtureFlagsCannotEscapeThroughCallerControlledTMPDIR() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        for flag in [
            "VIFTY_INSTALL_FIXTURE_PUBLISHED_V132",
            "VIFTY_INSTALL_FIXTURE_PROTOCOL_V2",
            "VIFTY_INSTALL_FIXTURE_UNSIGNED_BUILD",
            "VIFTY_INSTALL_FIXTURE_SYSTEM_FALLBACK",
            "VIFTY_INSTALL_FIXTURE_STAGE_MKTEMP_FAILURE",
            "VIFTY_INSTALL_FIXTURE_SHA256_FAILURE",
            "VIFTY_INSTALL_FIXTURE_ROLLBACK_RESTORE_FAILURE",
            "VIFTY_INSTALL_FIXTURE_POST_SWAP_VERIFICATION_FAILURE",
            "VIFTY_INSTALL_FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK",
            "VIFTY_INSTALL_FIXTURE_NO_RUNNING_APP",
            "VIFTY_INSTALL_FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE"
        ] {
            let result = try fixture.run(overrides: [
                flag: "1",
                "TMPDIR": "/",
                "VIFTY_INSTALL_DIR": "/Applications"
            ])
            XCTAssertEqual(result.exitCode, 65, "\(flag): \(result.output)")
            XCTAssertTrue(result.output.contains("canonical owner-private"), result.output)
        }
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        XCTAssertEqual(try fixture.dittoCallCount(), 0)
    }

    func testExistingAppRootSymlinkBlocksBeforeExecutionOrCopy() throws {
        let fixture = try InstallReplacementFixture(report: .safe)
        defer { fixture.remove() }
        try fixture.replaceDestinationWithRelativeAppSymlink()

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("app root is a symbolic link"), result.output)
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        XCTAssertEqual(try fixture.dittoCallCount(), 0)
    }

    func testAutoSystemCompleteExistingInstallAllowsCopyAttempt() throws {
        let fixture = try InstallReplacementFixture(report: .safe)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("passed protocol-v2 Auto/System replacement preflight"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
        XCTAssertEqual(try fixture.probeInvocations(), [])
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), ["diagnose --json"])
    }

    func testProtocolV2ReplacementFreezesAuthorityBeforeCopyAndResumesOnlyAfterVerification() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:new"],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testPostSwapVerificationFailureRollsBackAndResumesTheOldBundleWhileStillFrozen() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failPostSwapVerification: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing", result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:old"],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testPostCopyResumeFailureRollsBackThenReRegistersTheOldBundle() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failNewReplacementFinish: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing", result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:new-failed", "finish:old"],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testFallbackDestinationGetsItsOwnFreezeAfterPrimaryRollbackAndResume() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            fallbackReport: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .failThenCopyRequiringFrozenAuthority
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            [
                "prepare",
                "copy:primary-failed",
                "finish:old",
                "prepare",
                "copy:fallback",
                "finish:new"
            ],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testCandidateMutationDuringPreflightBlocksBeforeLifecycleOrCopy() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            removeCandidateDaemonAfterDiagnose: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing", result.output)
        XCTAssertEqual(try fixture.replacementLifecycleInvocations(), [], result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 0, result.output)
    }

    func testLifecycleMutationAfterPrepareCannotReachCopyRegistrarRetryRollbackOrFallback() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .copyRequiringFrozenAuthority,
            mutateReplacementLifecycleAfterPrepare: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("lifecycle source changed after root staging"), result.output)
        XCTAssertEqual(try fixture.replacementLifecycleInvocations(), ["prepare"], result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 0, result.output)
        XCTAssertTrue(try fixture.replacementAuthorityIsFrozen(), result.output)
        XCTAssertEqual(try fixture.existingSentinelContents(), "existing", result.output)
    }

    func testUncertainActiveFinishNeverRollsBackTheVerifiedNewBundle() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failNewReplacementFinishWithActiveAuthority: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertNil(try fixture.existingSentinelContents(), result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:new-active-failed"],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testInterruptedFinishIsTreatedAsUncertainAndNeverRollsBackTheVerifiedNewBundle() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            interruptNewReplacementFinish: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertNil(try fixture.existingSentinelContents(), result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:new-interrupted"],
            result.output
        )
        XCTAssertFalse(try fixture.replacementAuthorityIsFrozen(), result.output)
    }

    func testCopyFailurePreservesUnknownActiveStatusWithoutRetryOrFallback() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .fail,
            failOldReplacementFinishWithActiveAuthority: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertFalse(result.output.contains("remains frozen"), result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 1, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "finish:old-active-failed"],
            result.output
        )
    }

    func testPostSwapRollbackPreservesUnknownActiveStatusWithoutSecondFinish() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failPostSwapVerification: true,
            failOldReplacementFinishWithActiveAuthority: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertFalse(result.output.contains("remains frozen"), result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 1, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:old-active-failed"],
            result.output
        )
    }

    func testNewFinishFailureThenOldFinishUnknownPreservesStatus76() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            dittoBehavior: .copyRequiringFrozenAuthority,
            failNewReplacementFinish: true,
            failOldReplacementFinishWithActiveAuthority: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertFalse(result.output.contains("remains frozen"), result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "copy", "finish:new-failed", "finish:old-active-failed"],
            result.output
        )
    }

    func testFallbackCopyFailurePreservesUnknownActiveStatusWithoutExitRetry() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            fallbackReport: .safe,
            emulateSystemFallback: true,
            dittoBehavior: .fail,
            failFallbackOldReplacementFinishWithActiveAuthority: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 76, result.output)
        XCTAssertFalse(result.output.contains("remains frozen"), result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 2, result.output)
        XCTAssertEqual(
            try fixture.replacementLifecycleInvocations(),
            ["prepare", "finish:old", "prepare", "finish:old-active-failed"],
            result.output
        )
    }

    func testCompleteSingleFanInventoryAllowsCopyAttemptWithoutAssumingTwoFans() throws {
        let fixture = try InstallReplacementFixture(report: .safeSingleFan)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("passed protocol-v2 Auto/System replacement preflight"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testPublishedV132UsesExactNewBundleReadOnlyLocalProbeBeforeCopyAttempt() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            localProbe: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("Published v1.3.2/build 7 passed the read-only migration preflight"), result.output)
        XCTAssertEqual(try fixture.probeInvocations(), ["probeLocal"])
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), ["diagnose --json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testCanonicalPublishedV132MigrationDoesNotDependOnCandidateXPCReachability() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            candidateReport: .unreachable,
            localProbe: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), ["diagnose --json"])
    }

    func testPublishedV132AllowsTrustedModeOnlyFanInventory() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            localProbe: .safeModeOnly,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.probeInvocations(), ["probeLocal"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testPublishedV132AllowsOneCompleteTrustedFanWithoutAssumingTwo() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132SafeSingleFan,
            localProbe: .safeSingleFan,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertNotEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.probeInvocations(), ["probeLocal"])
    }

    func testPublishedV132UnsafeLegacyStatesBlockBeforeCopy() throws {
        for report in [
            InstallReplacementReport.publishedV132Forced,
            .publishedV132Partial,
            .publishedV132Unreachable,
            .publishedV132ActiveLease,
            .publishedV132ManualMarker
        ] {
            let fixture = try InstallReplacementFixture(
                report: report,
                localProbe: .safe,
                allowPublishedV132Fixture: true
            )
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, "\(report): \(result.output)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
            XCTAssertEqual(try fixture.existingCtlInvocations(), ["diagnose --json"])
        }
    }

    func testPublishedV132LocalProbeRequiresCompleteRestoreEligibleMatchingInventory() throws {
        for probe in [
            InstallReplacementLocalProbe.forced,
            .partial,
            .missingFanCountTrust,
            .modeDisagreement,
            .failed
        ] {
            let fixture = try InstallReplacementFixture(
                report: .publishedV132Safe,
                localProbe: probe,
                allowPublishedV132Fixture: true
            )
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, "\(probe): \(result.output)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertEqual(try fixture.probeInvocations(), ["probeLocal"])
        }
    }

    func testPublishedV132AllowlistRejectsOtherVersionOrBuildBeforeProbe() throws {
        for identity in [("1.3.1", "7"), ("1.3.2", "8")] {
            let fixture = try InstallReplacementFixture(
                report: .publishedV132Safe,
                localProbe: .safe,
                installedVersion: identity.0,
                installedBuild: identity.1,
                allowPublishedV132Fixture: true
            )
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, result.output)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertEqual(try fixture.probeInvocations(), [])
            XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        }
    }

    func testPublishedV132FixtureBypassCannotBypassBundleOrTeamIdentity() throws {
        let identities = [
            (bundleID: "tech.example.not-vifty", teamID: "X88J3853S2"),
            (bundleID: "tech.reidar.vifty", teamID: "NOTVIFTYTEAM")
        ]
        for identity in identities {
            let fixture = try InstallReplacementFixture(
                report: .publishedV132Safe,
                localProbe: .safe,
                installedBundleID: identity.bundleID,
                installedTeamID: identity.teamID,
                allowPublishedV132Fixture: true
            )
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, result.output)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertEqual(try fixture.probeInvocations(), [])
            XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        }
    }

    func testProtocolV2UnsafeReportCannotDowngradeIntoPublishedV132Migration() throws {
        let fixture = try InstallReplacementFixture(
            report: .forced,
            localProbe: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), ["diagnose --json"])
    }

    func testForcedPartialUnreachableLeaseAndMarkerBlockBeforeCopy() throws {
        for report in [
            InstallReplacementReport.forced,
            .partial,
            .unreachable,
            .activeLease,
            .manualMarker
        ] {
            let fixture = try InstallReplacementFixture(report: report)
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, "\(report): \(result.output)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertTrue(result.output.contains("refusing replacement"), result.output)
        }
    }

    func testLegacyMigrationWithoutAuthenticatedExistingCtlBlocksWithoutExecution() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            localProbe: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.existingCtl)

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
        XCTAssertTrue(result.output.contains("refusing replacement without executing its CLI"), result.output)
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
    }

    func testUnauthenticatedMaliciousExistingCtlIsNeverExecuted() throws {
        let fixture = try InstallReplacementFixture(
            report: .forced,
            candidateReport: .safe,
            allowProtocolV2Fixture: false
        )
        defer { fixture.remove() }
        let maliciousLog = fixture.root.appendingPathComponent("malicious-existing-ctl.log")
        try fixture.replaceExistingCtl(
            with: "#!/bin/bash\nprintf 'executed\\n' >> '\(maliciousLog.path)'\nexit 99\n"
        )

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: maliciousLog.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testAdHocSignedSameMetadataV132LookalikeIsRejectedWithoutExecution() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            allowProtocolV2Fixture: false
        )
        defer { fixture.remove() }
        try fixture.signExistingAppAdHoc()

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.existingCtlInvocations(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testUnauthenticatedExistingCtlSymlinkIsNeverFollowed() throws {
        let fixture = try InstallReplacementFixture(
            report: .forced,
            candidateReport: .safe,
            allowProtocolV2Fixture: false
        )
        defer { fixture.remove() }
        let maliciousLog = fixture.root.appendingPathComponent("symlink-target.log")
        let target = fixture.root.appendingPathComponent("malicious-target")
        try fixture.writeExecutable(
            "#!/bin/bash\nprintf 'executed\\n' >> '\(maliciousLog.path)'\nexit 99\n",
            to: target
        )
        try FileManager.default.removeItem(at: fixture.existingCtl)
        try FileManager.default.createSymbolicLink(at: fixture.existingCtl, withDestinationURL: target)

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: maliciousLog.path))
    }

    func testLegacyMigrationRejectsExistingCtlSymlinkWithoutExecutingTarget() throws {
        let fixture = try InstallReplacementFixture(
            report: .publishedV132Safe,
            localProbe: .safe,
            allowPublishedV132Fixture: true
        )
        defer { fixture.remove() }
        let maliciousLog = fixture.root.appendingPathComponent("legacy-symlink-target.log")
        let target = fixture.root.appendingPathComponent("legacy-malicious-target")
        try fixture.writeExecutable(
            "#!/bin/bash\nprintf 'executed\\n' >> '\(maliciousLog.path)'\nexit 99\n",
            to: target
        )
        try FileManager.default.removeItem(at: fixture.existingCtl)
        try FileManager.default.createSymbolicLink(at: fixture.existingCtl, withDestinationURL: target)

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertEqual(try fixture.candidateCtlInvocations(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: maliciousLog.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    }

    func testExistingAppWithoutExecutableMainBlocksBeforeCopy() throws {
        let fixture = try InstallReplacementFixture(report: .safe)
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.existingMain)

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
        XCTAssertTrue(result.output.contains("no executable main app safety interface"))
    }

    func testSelfConsistentPartialLegacyReportBlocksBeforeCopy() throws {
        let fixture = try InstallReplacementFixture(report: .selfConsistentPartialLegacy)
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
        XCTAssertTrue(result.output.contains("refusing replacement"), result.output)
    }

    func testLegacyMissingOwnershipUnsupportedInvalidIDAndStaleReportsBlockBeforeCopy() throws {
        for report in [
            InstallReplacementReport.legacyProtocol,
            .missingOwnership,
            .unsupportedHardware,
            .invalidFanID,
            .stale
        ] {
            let fixture = try InstallReplacementFixture(report: report)
            defer { fixture.remove() }

            let result = try fixture.run()

            XCTAssertEqual(result.exitCode, 75, "\(report): \(result.output)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.dittoLog.path))
            XCTAssertTrue(result.output.contains("refusing replacement"), result.output)
        }
    }

    func testCopyFailureFallbackPreflightsUnsafeUserInstallBeforeSecondCopy() throws {
        let fixture = try InstallReplacementFixture(
            report: .safe,
            fallbackReport: .forced,
            emulateSystemFallback: true
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        XCTAssertEqual(result.exitCode, 75, result.output)
        XCTAssertTrue(result.output.contains("installing to ~/Applications instead"), result.output)
        XCTAssertTrue(result.output.contains("refusing replacement"), result.output)
        XCTAssertEqual(try fixture.dittoCallCount(), 1, result.output)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum InstallReplacementReport: Equatable, CustomStringConvertible {
    case safe
    case safeSingleFan
    case forced
    case partial
    case selfConsistentPartialLegacy
    case unreachable
    case activeLease
    case manualMarker
    case legacyProtocol
    case missingOwnership
    case unsupportedHardware
    case invalidFanID
    case stale
    case candidateObservesLegacyV132
    case publishedV132Safe
    case publishedV132SafeSingleFan
    case publishedV132Forced
    case publishedV132Partial
    case publishedV132Unreachable
    case publishedV132ActiveLease
    case publishedV132ManualMarker

    var description: String {
        switch self {
        case .safe: "safe"
        case .safeSingleFan: "safeSingleFan"
        case .forced: "forced"
        case .partial: "partial"
        case .selfConsistentPartialLegacy: "selfConsistentPartialLegacy"
        case .unreachable: "unreachable"
        case .activeLease: "activeLease"
        case .manualMarker: "manualMarker"
        case .legacyProtocol: "legacyProtocol"
        case .missingOwnership: "missingOwnership"
        case .unsupportedHardware: "unsupportedHardware"
        case .invalidFanID: "invalidFanID"
        case .stale: "stale"
        case .candidateObservesLegacyV132: "candidateObservesLegacyV132"
        case .publishedV132Safe: "publishedV132Safe"
        case .publishedV132SafeSingleFan: "publishedV132SafeSingleFan"
        case .publishedV132Forced: "publishedV132Forced"
        case .publishedV132Partial: "publishedV132Partial"
        case .publishedV132Unreachable: "publishedV132Unreachable"
        case .publishedV132ActiveLease: "publishedV132ActiveLease"
        case .publishedV132ManualMarker: "publishedV132ManualMarker"
        }
    }

    func json(
        expectedDaemonPath: String = "/fixture/Vifty.app/Contents/MacOS/ViftyDaemon",
        installedDaemonPath: String = "/fixture/installed/ViftyDaemon"
    ) -> String {
        let generatedAt = Date().timeIntervalSinceReferenceDate - (self == .stale ? 300 : 0)

        if self == .candidateObservesLegacyV132 {
            let checks = [
                ("daemonSnapshotAvailable", true),
                ("agentControlStatusAvailable", true),
                ("fanControlOwnershipStatusAvailable", false),
                ("daemonControlPathReady", false),
                ("supportedHardware", true),
                ("activeLeaseClear", true),
                ("manualControlClear", true),
                ("fanControlProtocolCurrent", false),
                ("fanControlOwnershipStateValid", false),
                ("fanControlRecoveryClear", false),
                ("fanControlOwnershipClear", false),
                ("fanControlHardwareConsistent", false)
            ].map { id, passed in
                "{\"id\":\"\(id)\",\"passed\":\(passed)}"
            }.joined(separator: ",")
            let fans = [0, 1].map { id in
                let mode = id == 0 ? "Auto" : "System"
                let raw = id == 0 ? 0 : 3
                let key = id == 0 ? "F0Md" : "F1md"
                return "{\"id\":\(id),\"hardwareMode\":\"\(mode)\",\"hardwareModeRawValue\":\(raw),\"hardwareModeKey\":\"\(key)\",\"canApplyFixedRPM\":false,\"canRestoreOSManagedMode\":false,\"controlIneligibilityReasons\":[\"legacyUnspecified\"]}"
            }.joined(separator: ",")
            return """
            {"schemaVersion":1,"generatedAt":\(generatedAt),"checks":[\(checks)],"daemonSnapshotError":null,"agentControlStatusError":null,"fanControlOwnershipStatusError":"legacy daemon has no ownership selector","isAppleSilicon":true,"isMacBookPro":true,"fanCount":2,"fans":[\(fans)],"agentControl":{"activeLease":null},"fanControlOwnership":null,"manualControlActive":false}
            """
        }

        if isPublishedV132Report {
            let forced = self == .publishedV132Forced
            let partial = self == .publishedV132Partial
            let singleFan = self == .publishedV132SafeSingleFan
            let unreachable = self == .publishedV132Unreachable
            let activeLease = self == .publishedV132ActiveLease
            let marker = self == .publishedV132ManualMarker
            let fanIDs = (partial || singleFan) ? [0] : [0, 1]
            let fans = fanIDs.map { fan(id: $0, forced: forced && $0 == 0, legacy: true) }
            let declaredCount = partial ? 2 : fans.count
            let lease = activeLease ? #"{"leaseID":"active"}"# : "null"
            let requiredChecks = [
                "daemonSnapshotAvailable",
                "agentControlStatusAvailable",
                "daemonControlPathReady",
                "supportedHardware",
                "activeLeaseClear",
                "manualControlClear"
            ]
            let checks = requiredChecks.map { id in
                let passed: Bool
                switch id {
                case "daemonSnapshotAvailable", "agentControlStatusAvailable", "daemonControlPathReady":
                    passed = !unreachable
                case "activeLeaseClear":
                    passed = !activeLease
                case "manualControlClear":
                    passed = !marker
                default:
                    passed = true
                }
                return "{\"id\":\"\(id)\",\"passed\":\(passed),\"severity\":\"info\",\"message\":\"fixture\"}"
            }.joined(separator: ",")
            let digest = String(repeating: "a", count: 64)
            return """
            {"schemaVersion":1,"generatedAt":\(generatedAt),"state":"\(unreachable ? "blocked" : "ready")","checks":[\(checks)],"daemonSnapshotError":\(unreachable ? "\"unreachable\"" : "null"),"agentControlStatusError":\(unreachable ? "\"unreachable\"" : "null"),"isAppleSilicon":true,"isMacBookPro":true,"modelIdentifier":"MacBookPro18,3","fanCount":\(declaredCount),"controllableFanCount":\(fans.count),"fans":[\(fans.joined(separator: ","))],"agentControl":{"activeLease":\(lease)},"manualControlActive":\(marker),"daemonRuntime":{"installedDaemonPath":"\(installedDaemonPath)","installedDaemonPresent":true,"installedDaemonSHA256":"\(digest)","expectedDaemonPath":"\(expectedDaemonPath)","expectedDaemonPresent":true,"expectedDaemonSHA256":"\(digest)","matchesExpectedDaemon":true,"matchRequired":true}}
            """
        }

        if self == .selfConsistentPartialLegacy {
            return """
            {"schemaVersion":1,"generatedAt":\(generatedAt),"checks":[{"id":"daemonSnapshotAvailable","passed":true}],"daemonSnapshotError":null,"agentControlStatusError":null,"fanControlOwnershipStatusError":null,"isAppleSilicon":true,"isMacBookPro":true,"fanCount":1,"fans":[\(fan(id: 0, forced: false, legacy: true))],"agentControl":{"activeLease":null},"fanControlOwnership":null,"manualControlActive":false}
            """
        }

        let forced = self == .forced
        let partial = self == .partial
        let unreachable = self == .unreachable
        let activeLease = self == .activeLease
        let marker = self == .manualMarker
        let legacyProtocol = self == .legacyProtocol
        let missingOwnership = self == .missingOwnership
        let supportedHardware = self != .unsupportedHardware
        let fanIDs: [Int]
        switch self {
        case .safeSingleFan, .partial:
            fanIDs = [0]
        case .invalidFanID:
            fanIDs = [10]
        default:
            fanIDs = [0, 1]
        }
        let fans = fanIDs.map { fan(id: $0, forced: forced && $0 == fanIDs.first) }
        let declaredCount = partial ? 2 : fans.count
        let lease = activeLease ? #"{"leaseID":"active"}"# : "null"
        let attested = [
            .safe,
            .safeSingleFan,
            .stale
        ].contains(self)
        let checkIDs = [
            "daemonSnapshotAvailable",
            "agentControlStatusAvailable",
            "fanControlOwnershipStatusAvailable",
            "daemonControlPathReady",
            "supportedHardware",
            "activeLeaseClear",
            "manualControlClear",
            "fanControlProtocolCurrent",
            "fanControlOwnershipStateValid",
            "fanControlRecoveryClear",
            "fanControlOwnershipClear",
            "fanControlHardwareConsistent",
            "replacementMaintenanceAttestation"
        ]
        let checks = checkIDs.map {
            "{\"id\":\"\($0)\",\"passed\":\(attested && !unreachable)}"
        }.joined(separator: ",")
        let ownership = missingOwnership ? "null" : """
        {"protocolVersion":\(legacyProtocol ? 1 : 2),"expectedFanIDs":[],"confirmedOSManagedFanIDs":[],"recoveryPending":false,"recoveryAttemptCount":0}
        """
        return """
        {"schemaVersion":1,"generatedAt":\(generatedAt),"checks":[\(checks)],"daemonSnapshotError":\(unreachable ? "\"unreachable\"" : "null"),"agentControlStatusError":null,"fanControlOwnershipStatusError":null,"isAppleSilicon":\(supportedHardware),"isMacBookPro":\(supportedHardware),"fanCount":\(declaredCount),"fans":[\(fans.joined(separator: ","))],"agentControl":{"activeLease":\(lease)},"fanControlOwnership":\(ownership),"manualControlActive":\(marker)}
        """
    }

    var isPublishedV132Report: Bool {
        switch self {
        case .publishedV132Safe,
             .publishedV132SafeSingleFan,
             .publishedV132Forced,
             .publishedV132Partial,
             .publishedV132Unreachable,
             .publishedV132ActiveLease,
             .publishedV132ManualMarker:
            true
        default:
            false
        }
    }

    private func fan(id: Int, forced: Bool, legacy: Bool = false) -> String {
        let mode = forced ? "Forced" : (id == 1 ? "System" : "Auto")
        let raw = forced ? 1 : (id == 1 ? 3 : 0)
        let key = id == 1 ? "F1md" : "F\(id)Md"
        let eligibility = legacy
            ? ""
            : ",\"canApplyFixedRPM\":true,\"canRestoreOSManagedMode\":true,\"controlIneligibilityReasons\":[]"
        return "{\"id\":\(id),\"name\":\"Fan \(id)\",\"currentRPM\":2200,\"minimumRPM\":1400,\"maximumRPM\":6800,\"controllable\":true,\"hardwareMode\":\"\(mode)\",\"hardwareModeRawValue\":\(raw),\"hardwareModeKey\":\"\(key)\",\"targetRPM\":2200\(eligibility)}"
    }
}

private enum InstallReplacementLocalProbe: CustomStringConvertible {
    case safe
    case safeModeOnly
    case safeSingleFan
    case forced
    case partial
    case missingFanCountTrust
    case modeDisagreement
    case failed

    var description: String {
        switch self {
        case .safe: "safe"
        case .safeModeOnly: "safeModeOnly"
        case .safeSingleFan: "safeSingleFan"
        case .forced: "forced"
        case .partial: "partial"
        case .missingFanCountTrust: "missingFanCountTrust"
        case .modeDisagreement: "modeDisagreement"
        case .failed: "failed"
        }
    }

    var exitCode: Int { self == .failed ? 1 : 0 }

    var output: String {
        guard self != .failed else { return "" }
        let partial = self == .partial
        let singleFan = self == .safeSingleFan
        let fanIDs = (partial || singleFan) ? [0] : [0, 1]
        let fanLines = fanIDs.map { id -> String in
            let forced = self == .forced && id == 0
            let disagrees = self == .modeDisagreement && id == 1
            let mode = forced ? "Forced" : (id == 1 && !disagrees ? "System" : "Auto")
            let raw = forced ? 1 : (id == 1 && !disagrees ? 3 : 0)
            let modeOnly = self == .safeModeOnly && id == 0
            let missingFanCount = self == .missingFanCountTrust
            let canRestore = !missingFanCount
            let reasons = missingFanCount ? "missingFanCount" : (modeOnly ? "missingTargetKey" : "none")
            return "fan[\(id)] name=\"Fan \(id)\" rpm=2200 min=1400 max=6800 controllable=\(!modeOnly) hardwareMode=\(mode) hardwareModeRawValue=\(raw) hardwareModeKey=F\(id)\(id == 1 ? "md" : "Md") targetRPM=\(modeOnly ? "nil" : "2200") canApplyFixedRPM=\(!modeOnly && !missingFanCount) canRestoreOSManagedMode=\(canRestore) controlIneligibilityReasons=\(reasons)"
        }
        return ([
            "model=MacBookPro18,3 appleSilicon=true macBookPro=true",
            "fans=\(fanIDs.count)"
        ] + fanLines + ["temperatures=0"]).joined(separator: "\n") + "\n"
    }
}

private enum InstallDittoBehavior {
    case fail
    case copy
    case copyAndCorrupt
    case copyRequiringFrozenAuthority
    case failThenCopyRequiringFrozenAuthority
}

private final class InstallReplacementFixture {
    let root: URL
    let existingMain: URL
    let existingCtl: URL
    let dittoLog: URL
    let probeLog: URL
    let candidateCtlLog: URL
    let existingCtlLog: URL
    let replacementLifecycleLog: URL
    let destinationApp: URL

    private let repositoryRoot: URL
    private let installDirectory: URL
    private let buildApp: URL
    private let helperTarget: URL
    private let fakeMake: URL
    private let fakeDitto: URL
    private let fakeReplacementLifecycle: URL
    private let replacementFrozenMarker: URL
    private let replacementTransactionFile: URL
    private let emulateSystemFallback: Bool
    private let allowPublishedV132Fixture: Bool
    private let allowProtocolV2Fixture: Bool
    private let failStageMktemp: Bool
    private let failSHA256: Bool
    private let failRollbackRestore: Bool
    private let failPostSwapVerification: Bool
    private let mutateReplacementLifecycleAfterPrepare: Bool

    init(
        report: InstallReplacementReport,
        candidateReport: InstallReplacementReport? = nil,
        fallbackReport: InstallReplacementReport? = nil,
        emulateSystemFallback: Bool = false,
        localProbe: InstallReplacementLocalProbe? = nil,
        installedVersion: String = "1.3.2",
        installedBuild: String = "7",
        installedBundleID: String = "tech.reidar.vifty",
        installedTeamID: String = "X88J3853S2",
        allowPublishedV132Fixture: Bool = false,
        allowProtocolV2Fixture: Bool? = nil,
        dittoBehavior: InstallDittoBehavior = .fail,
        existingCtlExitCode: Int = 0,
        failStageMktemp: Bool = false,
        failSHA256: Bool = false,
        failRollbackRestore: Bool = false,
        failPostSwapVerification: Bool = false,
        failNewReplacementFinish: Bool = false,
        failNewReplacementFinishWithActiveAuthority: Bool = false,
        failOldReplacementFinishWithActiveAuthority: Bool = false,
        failFallbackOldReplacementFinishWithActiveAuthority: Bool = false,
        interruptNewReplacementFinish: Bool = false,
        removeCandidateDaemonAfterDiagnose: Bool = false,
        mutateReplacementLifecycleAfterPrepare: Bool = false
    ) throws {
        repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = try canonicalInstallReplacementTemporaryDirectory()
            .appendingPathComponent("vifty-install-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let fixtureHome = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureHome, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixtureHome.path)
        installDirectory = root.appendingPathComponent("install", isDirectory: true)
        buildApp = root.appendingPathComponent("build/Vifty.app", isDirectory: true)
        let existingApp = installDirectory.appendingPathComponent("Vifty.app", isDirectory: true)
        destinationApp = existingApp
        existingMain = existingApp.appendingPathComponent("Contents/MacOS/Vifty")
        existingCtl = existingApp.appendingPathComponent("Contents/MacOS/viftyctl")
        dittoLog = root.appendingPathComponent("ditto.log")
        probeLog = root.appendingPathComponent("probe.log")
        candidateCtlLog = root.appendingPathComponent("candidate-ctl.log")
        existingCtlLog = root.appendingPathComponent("existing-ctl.log")
        replacementLifecycleLog = root.appendingPathComponent("replacement-lifecycle.log")
        replacementFrozenMarker = root.appendingPathComponent("replacement-authority-frozen")
        replacementTransactionFile = root.appendingPathComponent("replacement-transaction-id")
        helperTarget = root.appendingPathComponent("installed-helper/tech.reidar.vifty.daemon")
        try FileManager.default.createDirectory(
            at: existingCtl.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: buildApp.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: helperTarget.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: existingMain)
        let existingDaemon = existingApp.appendingPathComponent("Contents/MacOS/ViftyDaemon")
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: existingDaemon)
        try Self.writeExecutable(
            "#!/bin/bash\nexit 0\n",
            to: existingApp.appendingPathComponent("Contents/MacOS/ViftyHelper")
        )
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: helperTarget)
        let existingResources = existingApp.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: existingResources, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: existingResources.appendingPathComponent("preserve-me"))
        try Self.writeAppMetadata(
            app: existingApp,
            version: installedVersion,
            build: installedBuild,
            bundleID: installedBundleID,
            teamID: installedTeamID
        )
        let encoded = Data(report.json(
            expectedDaemonPath: "__VIFTY_EXPECTED_DAEMON_PATH__",
            installedDaemonPath: helperTarget.path
        ).utf8).base64EncodedString()
        try Self.writeExecutable(
            "#!/bin/bash\nprintf '%s\\n' \"$*\" >> '\(existingCtlLog.path)'\npayload=$(printf '%s' '\(encoded)' | /usr/bin/base64 --decode)\ndaemon_path=$(cd \"$(dirname \"$0\")\" && pwd)/ViftyDaemon\nprintf '%s' \"$payload\" | /usr/bin/sed \"s|__VIFTY_EXPECTED_DAEMON_PATH__|$daemon_path|g\"\n\(removeCandidateDaemonAfterDiagnose ? "/bin/rm -f '\(buildApp.appendingPathComponent("Contents/MacOS/ViftyDaemon").path)'" : ":")\nexit \(existingCtlExitCode)\n",
            to: existingCtl
        )
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: buildApp.appendingPathComponent("Contents/MacOS/Vifty"))
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: buildApp.appendingPathComponent("Contents/MacOS/ViftyDaemon"))
        let resolvedCandidateReport = candidateReport ?? (report.isPublishedV132Report ? .candidateObservesLegacyV132 : report)
        let encodedCandidate = Data(resolvedCandidateReport.json(
            expectedDaemonPath: existingDaemon.path,
            installedDaemonPath: helperTarget.path
        ).utf8).base64EncodedString()
        let encodedFallbackCandidate = Data((fallbackReport ?? resolvedCandidateReport).json(
            expectedDaemonPath: existingDaemon.path,
            installedDaemonPath: helperTarget.path
        ).utf8).base64EncodedString()
        try Self.writeExecutable(
            "#!/bin/bash\nprintf '%s\\n' \"$*\" >> '\(candidateCtlLog.path)'\ncalls=$(/usr/bin/wc -l < '\(candidateCtlLog.path)' | /usr/bin/tr -d ' ')\nif [[ \"$calls\" -gt 1 ]]; then encoded='\(encodedFallbackCandidate)'; else encoded='\(encodedCandidate)'; fi\nprintf '%s' \"$encoded\" | /usr/bin/base64 --decode\nexit 0\n",
            to: buildApp.appendingPathComponent("Contents/MacOS/viftyctl")
        )
        let probe = localProbe ?? .failed
        let encodedProbe = Data(probe.output.utf8).base64EncodedString()
        try Self.writeExecutable(
            "#!/bin/bash\nprintf '%s\\n' \"$*\" >> '\(probeLog.path)'\nprintf '%s' '\(encodedProbe)' | /usr/bin/base64 --decode\nexit \(probe.exitCode)\n",
            to: buildApp.appendingPathComponent("Contents/MacOS/ViftyHelper")
        )
        fakeMake = root.appendingPathComponent("make")
        try Self.writeExecutable("#!/bin/bash\nexit 0\n", to: fakeMake)
        fakeDitto = root.appendingPathComponent("ditto")
        self.emulateSystemFallback = emulateSystemFallback
        let dittoBody: String
        switch dittoBehavior {
        case .fail:
            dittoBody = "exit 99"
        case .copy:
            dittoBody = "args=(\"$@\")\ncount=${#args[@]}\nsource=${args[$((count-2))]}\ndestination=${args[$((count-1))]}\n/bin/cp -R \"$source\" \"$destination\""
        case .copyAndCorrupt:
            dittoBody = "args=(\"$@\")\ncount=${#args[@]}\nsource=${args[$((count-2))]}\ndestination=${args[$((count-1))]}\n/bin/cp -R \"$source\" \"$destination\"\nprintf 'corrupt\\n' >> \"$destination/Contents/MacOS/Vifty\""
        case .copyRequiringFrozenAuthority:
            dittoBody = "[[ -f '\(replacementFrozenMarker.path)' ]] || { printf 'copy-without-freeze\\n' >> '\(replacementLifecycleLog.path)'; exit 98; }\nprintf 'copy\\n' >> '\(replacementLifecycleLog.path)'\nargs=(\"$@\")\ncount=${#args[@]}\nsource=${args[$((count-2))]}\ndestination=${args[$((count-1))]}\n/bin/cp -R \"$source\" \"$destination\""
        case .failThenCopyRequiringFrozenAuthority:
            dittoBody = "[[ -f '\(replacementFrozenMarker.path)' ]] || { printf 'copy-without-freeze\\n' >> '\(replacementLifecycleLog.path)'; exit 98; }\ncalls=$(/usr/bin/wc -l < '\(dittoLog.path)' | /usr/bin/tr -d ' ')\nif [[ \"$calls\" == 1 ]]; then printf 'copy:primary-failed\\n' >> '\(replacementLifecycleLog.path)'; exit 99; fi\nprintf 'copy:fallback\\n' >> '\(replacementLifecycleLog.path)'\nargs=(\"$@\")\ncount=${#args[@]}\nsource=${args[$((count-2))]}\ndestination=${args[$((count-1))]}\n/bin/cp -R \"$source\" \"$destination\""
        }
        try Self.writeExecutable(
            "#!/bin/bash\nprintf 'called\\n' >> '\(dittoLog.path)'\n\(dittoBody)\n",
            to: fakeDitto
        )
        fakeReplacementLifecycle = root.appendingPathComponent("replacement-lifecycle")
        if failNewReplacementFinish {
            try Data().write(to: root.appendingPathComponent("fail-new-replacement-finish"))
        }
        if failNewReplacementFinishWithActiveAuthority {
            try Data().write(
                to: root.appendingPathComponent("fail-new-replacement-finish-active")
            )
        }
        if interruptNewReplacementFinish {
            try Data().write(
                to: root.appendingPathComponent("interrupt-new-replacement-finish")
            )
        }
        if failOldReplacementFinishWithActiveAuthority {
            try Data().write(
                to: root.appendingPathComponent("fail-old-replacement-finish-active")
            )
        }
        if failFallbackOldReplacementFinishWithActiveAuthority {
            try Data().write(
                to: root.appendingPathComponent("fail-fallback-old-replacement-finish-active")
            )
        }
        if mutateReplacementLifecycleAfterPrepare {
            try Data().write(
                to: root.appendingPathComponent("mutate-replacement-lifecycle-after-prepare")
            )
        }
        try Self.writeExecutable(
            "#!/bin/bash\nset -euo pipefail\nphase=''\ndestination=''\ntransaction=''\ncandidate=''\nprevious=''\nresult=''\nwhile [[ $# -gt 0 ]]; do\n  case \"$1\" in\n    --replacement-phase) phase=\"$2\"; shift 2 ;;\n    --replacement-destination) destination=\"$2\"; shift 2 ;;\n    --replacement-transaction-id) transaction=\"$2\"; shift 2 ;;\n    --replacement-candidate) candidate=\"$2\"; shift 2 ;;\n    --replacement-previous) previous=\"$2\"; shift 2 ;;\n    --replacement-result) result=\"$2\"; shift 2 ;;\n    *) shift ;;\n  esac\ndone\n[[ \"$transaction\" =~ ^[0-9a-f-]{36}$ ]] || exit 64\ncase \"$phase\" in\n  prepare)\n    [[ -n \"$candidate\" && \"$previous\" == \"$destination\" && -z \"$result\" ]] || exit 64\n    printf '%s\\n' \"$transaction\" > '\(replacementTransactionFile.path)'\n    printf 'prepare\\n' >> '\(replacementLifecycleLog.path)'\n    : > '\(replacementFrozenMarker.path)'\n    ;;\n  finish)\n    [[ \"$(< '\(replacementTransactionFile.path)')\" == \"$transaction\" ]] || exit 75\n    if [[ ! -f '\(replacementFrozenMarker.path)' ]]; then\n      printf 'finish:without-freeze\\n' >> '\(replacementLifecycleLog.path)'\n      exit 75\n    fi\n    if [[ -f \"$destination/Contents/Resources/preserve-me\" ]]; then state=old; else state=new; fi\n    [[ \"$state:$result\" == 'old:rolled-back' || \"$state:$result\" == 'new:installed' ]] || exit 75\n    if [[ \"$state\" == old && -f '\(root.appendingPathComponent("fail-old-replacement-finish-active").path)' ]]; then\n      printf 'finish:old-active-failed\\n' >> '\(replacementLifecycleLog.path)'\n      /bin/rm -f '\(replacementFrozenMarker.path)'\n      exit 76\n    fi\n    if [[ \"$state\" == old && \"$destination\" == *'/home/Applications/Vifty.app' && -f '\(root.appendingPathComponent("fail-fallback-old-replacement-finish-active").path)' ]]; then\n      printf 'finish:old-active-failed\\n' >> '\(replacementLifecycleLog.path)'\n      /bin/rm -f '\(replacementFrozenMarker.path)'\n      exit 76\n    fi\n    if [[ \"$state\" == new && -f '\(root.appendingPathComponent("interrupt-new-replacement-finish").path)' ]]; then\n      printf 'finish:new-interrupted\\n' >> '\(replacementLifecycleLog.path)'\n      /bin/rm -f '\(replacementFrozenMarker.path)'\n      exit 130\n    fi\n    if [[ \"$state\" == new && -f '\(root.appendingPathComponent("fail-new-replacement-finish-active").path)' ]]; then\n      printf 'finish:new-active-failed\\n' >> '\(replacementLifecycleLog.path)'\n      /bin/rm -f '\(replacementFrozenMarker.path)'\n      exit 76\n    fi\n    if [[ \"$state\" == new && -f '\(root.appendingPathComponent("fail-new-replacement-finish").path)' ]]; then\n      printf 'finish:new-failed\\n' >> '\(replacementLifecycleLog.path)'\n      exit 75\n    fi\n    printf 'finish:%s\\n' \"$state\" >> '\(replacementLifecycleLog.path)'\n    /bin/rm -f '\(replacementFrozenMarker.path)'\n    ;;\n  *) exit 64 ;;\nesac\n",
            to: fakeReplacementLifecycle
        )
        let fakeReplacementLifecycleBase = root.appendingPathComponent("replacement-lifecycle-base")
        try FileManager.default.moveItem(
            at: fakeReplacementLifecycle,
            to: fakeReplacementLifecycleBase
        )
        try Self.writeExecutable(
            """
            #!/bin/bash
            set -euo pipefail
            phase=''
            transaction=''
            destination=''
            args=("$@")
            index=0
            while [[ "$index" -lt "${#args[@]}" ]]; do
              case "${args[$index]}" in
                --replacement-phase) phase="${args[$((index+1))]}"; index=$((index+2)) ;;
                --replacement-transaction-id) transaction="${args[$((index+1))]}"; index=$((index+2)) ;;
                --replacement-destination) destination="${args[$((index+1))]}"; index=$((index+2)) ;;
                *) index=$((index+1)) ;;
              esac
            done
            if [[ "$phase" == "release-lock" ]]; then
              [[ -n "$destination" ]] || exit 75
              exit 0
            fi
            "\(fakeReplacementLifecycleBase.path)" "$@"
            if [[ "$phase" == "prepare" ]]; then
              lifecycle_dir="${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}/$transaction"
              /bin/mkdir -p "${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}" "$lifecycle_dir"
              /bin/chmod 755 "${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}" "$lifecycle_dir"
              /bin/cp "$0" "$lifecycle_dir/vifty-helper-lifecycle.sh"
              /bin/chmod 555 "$lifecycle_dir/vifty-helper-lifecycle.sh"
              /usr/bin/chflags uchg "$lifecycle_dir/vifty-helper-lifecycle.sh" "$lifecycle_dir"
              if [[ -f "\(root.appendingPathComponent("mutate-replacement-lifecycle-after-prepare").path)" ]]; then
                /bin/chmod 700 "$0"
                printf '# mutation\n' >> "$0"
              fi
            fi
            """,
            to: fakeReplacementLifecycle
        )
        if let fallbackReport {
            let fallbackApp = root.appendingPathComponent(
                "home/Applications/Vifty.app",
                isDirectory: true
            )
            let fallbackCtl = fallbackApp.appendingPathComponent("Contents/MacOS/viftyctl")
            try FileManager.default.createDirectory(
                at: fallbackCtl.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.writeExecutable(
                "#!/bin/bash\nexit 0\n",
                to: fallbackApp.appendingPathComponent("Contents/MacOS/Vifty")
            )
            try Self.writeExecutable(
                "#!/bin/bash\nexit 0\n",
                to: fallbackApp.appendingPathComponent("Contents/MacOS/ViftyDaemon")
            )
            try Self.writeExecutable(
                "#!/bin/bash\nexit 0\n",
                to: fallbackApp.appendingPathComponent("Contents/MacOS/ViftyHelper")
            )
            let fallbackResources = fallbackApp.appendingPathComponent("Contents/Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: fallbackResources, withIntermediateDirectories: true)
            try Data("existing".utf8).write(to: fallbackResources.appendingPathComponent("preserve-me"))
            try Self.writeAppMetadata(
                app: fallbackApp,
                version: installedVersion,
                build: installedBuild,
                bundleID: installedBundleID,
                teamID: installedTeamID
            )
            let fallbackEncoded = Data(fallbackReport.json(
                expectedDaemonPath: fallbackApp.appendingPathComponent("Contents/MacOS/ViftyDaemon").path,
                installedDaemonPath: helperTarget.path
            ).utf8).base64EncodedString()
            try Self.writeExecutable(
                "#!/bin/bash\nprintf '%s\\n' \"$*\" >> '\(existingCtlLog.path)'\nprintf '%s' '\(fallbackEncoded)' | /usr/bin/base64 --decode\nexit 0\n",
                to: fallbackCtl
            )
        }
        self.allowPublishedV132Fixture = allowPublishedV132Fixture
        self.allowProtocolV2Fixture = allowProtocolV2Fixture ?? !allowPublishedV132Fixture
        self.failStageMktemp = failStageMktemp
        self.failSHA256 = failSHA256
        self.failRollbackRestore = failRollbackRestore
        self.failPostSwapVerification = failPostSwapVerification
        self.mutateReplacementLifecycleAfterPrepare = mutateReplacementLifecycleAfterPrepare
    }

    func remove() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["-R", "nouchg", root.path]
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: root)
    }

    func dittoCallCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: dittoLog.path) else { return 0 }
        return try String(contentsOf: dittoLog, encoding: .utf8)
            .split(separator: "\n")
            .count
    }

    func probeInvocations() throws -> [String] {
        guard FileManager.default.fileExists(atPath: probeLog.path) else { return [] }
        return try String(contentsOf: probeLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func candidateCtlInvocations() throws -> [String] {
        try invocations(in: candidateCtlLog)
    }

    func existingCtlInvocations() throws -> [String] {
        try invocations(in: existingCtlLog)
    }

    func replacementLifecycleInvocations() throws -> [String] {
        try invocations(in: replacementLifecycleLog)
    }

    func replacementAuthorityIsFrozen() throws -> Bool {
        FileManager.default.fileExists(atPath: replacementFrozenMarker.path)
    }

    func existingSentinelContents() throws -> String? {
        let sentinel = destinationApp.appendingPathComponent("Contents/Resources/preserve-me")
        guard FileManager.default.fileExists(atPath: sentinel.path) else { return nil }
        return try String(contentsOf: sentinel, encoding: .utf8)
    }

    func recoveryPreviousApps() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: installDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".vifty-install-stage.") }
            .map { $0.appendingPathComponent("previous-Vifty.app") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func displacedPreviousApps() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: installDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".vifty-install-stage.") }
            .map { $0.appendingPathComponent("displaced-previous-Vifty.app") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func replaceExistingCtl(with contents: String) throws {
        try Self.writeExecutable(contents, to: existingCtl)
    }

    func replaceDestinationWithRelativeAppSymlink() throws {
        let realParent = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        let realApp = realParent.appendingPathComponent("Vifty.app", isDirectory: true)
        try FileManager.default.moveItem(at: destinationApp, to: realApp)
        try FileManager.default.createSymbolicLink(
            atPath: destinationApp.path,
            withDestinationPath: "../real/Vifty.app"
        )
    }

    func signExistingAppAdHoc() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", destinationApp.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    func writeExecutable(_ contents: String, to url: URL) throws {
        try Self.writeExecutable(contents, to: url)
    }

    private func invocations(in log: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: log.path) else { return [] }
        return try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func run(overrides: [String: String] = [:]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/install-vifty.sh")
        var environment = ProcessInfo.processInfo.environment.merging([
            "CONFIGURATION": "debug",
            "VIFTY_INSTALL_DIR": installDirectory.path,
            "VIFTY_BUILD_APP_PATH": buildApp.path,
            "VIFTY_MAKE": fakeMake.path,
            "VIFTY_DITTO": fakeDitto.path,
            "VIFTY_HELPER_LIFECYCLE": fakeReplacementLifecycle.path,
            "VIFTY_REPLACEMENT_LIFECYCLE_ROOT": root.appendingPathComponent("root-staged-lifecycle").path,
            "VIFTY_HELPER_TARGET": helperTarget.path,
            "VIFTY_INSTALL_FIXTURE_NO_RUNNING_APP": "1",
            "VIFTY_INSTALL_FIXTURE_SYSTEM_FALLBACK": emulateSystemFallback ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_PUBLISHED_V132": allowPublishedV132Fixture ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_PROTOCOL_V2": allowProtocolV2Fixture ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_STAGE_MKTEMP_FAILURE": failStageMktemp ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_SHA256_FAILURE": failSHA256 ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_ROLLBACK_RESTORE_FAILURE": failRollbackRestore ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_POST_SWAP_VERIFICATION_FAILURE": failPostSwapVerification ? "1" : "0",
            "VIFTY_INSTALL_FIXTURE_UNSIGNED_BUILD": "1",
            "VIFTY_INSTALL_FIXTURE_ROOT": root.path,
            "VIFTY_INSTALL_FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE": mutateReplacementLifecycleAfterPrepare ? "1" : "0",
            "TMPDIR": root.path,
            "HOME": root.appendingPathComponent("home", isDirectory: true).path,
            "QUIT_RUNNING_APP": "0",
            "CHECK_HELPER_DAEMON": "0"
        ]) { _, new in new }
        environment.merge(overrides) { _, new in new }
        process.environment = environment
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

    private static func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func writeAppMetadata(
        app: URL,
        version: String,
        build: String,
        bundleID: String,
        teamID: String
    ) throws {
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": "Vifty",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: app.appendingPathComponent("Contents/Info.plist"))

        let daemonPlist: [String: Any] = [
            "Label": "tech.reidar.vifty.daemon",
            "EnvironmentVariables": ["VIFTY_XPC_ALLOWED_TEAM_ID": teamID]
        ]
        let daemonData = try PropertyListSerialization.data(
            fromPropertyList: daemonPlist,
            format: .xml,
            options: 0
        )
        let daemonURL = app.appendingPathComponent(
            "Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )
        try FileManager.default.createDirectory(
            at: daemonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try daemonData.write(to: daemonURL)
    }
}

private func canonicalInstallReplacementTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    guard let resolved = realpath(temporaryDirectory.path, nil) else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
    }
    defer { free(resolved) }
    let bytes = UnsafeRawBufferPointer(start: resolved, count: strlen(resolved))
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
}
