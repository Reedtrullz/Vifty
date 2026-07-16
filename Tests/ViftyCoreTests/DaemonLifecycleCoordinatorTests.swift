import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyDaemonSupport
@testable import ViftyFanControlSafety

final class DaemonLifecycleCoordinatorTests: XCTestCase {
    func testLiveCoordinatorRejectsOfflineRecoveryBeforeQuiescingOrRestoring() async throws {
        let fixture = makeFixture()

        do {
            _ = try await fixture.coordinator.prepare(operation: .offlineRecovery)
            XCTFail("Live coordinator must reject the offline-only operation")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .unsupportedOperation)
        }
        let isQuiesced = await fixture.coordinator.isQuiesced
        XCTAssertFalse(isQuiesced)
        XCTAssertEqual(fixture.state.restoreCallCount, 0)
    }

    func testPrepareRestoresQuiescesAndIssuesBoundTokenThenConsumesOnce() async throws {
        let fixture = makeFixture()

        let report = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)

        XCTAssertTrue(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertTrue(report.restoreAttempted)
        XCTAssertTrue(report.restoreSucceeded)
        XCTAssertTrue(report.completeExpectedSetConfirmed)
        XCTAssertEqual(report.fanResults.map(\.fanID), [0, 1])
        XCTAssertTrue(report.fanResults.allSatisfy(\.confirmedOSManaged))
        XCTAssertTrue(report.blockers.isEmpty)
        let token = try XCTUnwrap(report.token)
        XCTAssertEqual(token.operation, .repair)
        XCTAssertEqual(token.expectedFanIDs, [0, 1])
        XCTAssertEqual(token.helperSHA256, Self.helperHashA)
        XCTAssertEqual(token.bootSessionID, "boot-A")
        XCTAssertEqual(token.daemonSessionID, "daemon-A")
        XCTAssertEqual(fixture.state.restoreCallCount, 1)
        XCTAssertThrowsError(try fixture.coordinator.requireControlAllowed()) { error in
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .maintenanceQuiesced)
        }

        let authorization = try await fixture.coordinator.consume(
            HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
        )
        XCTAssertTrue(authorization.authorized)
        XCTAssertTrue(authorization.quiesced)
        XCTAssertTrue(authorization.tokenConsumed)
        XCTAssertEqual(authorization.tokenID, token.tokenID)
        let receipt = try XCTUnwrap(fixture.state.authorityReceipt)
        XCTAssertEqual(receipt.operation, .repair)
        XCTAssertEqual(receipt.tokenID, token.tokenID)
        XCTAssertEqual(receipt.tokenIssuedAt, token.issuedAt)
        XCTAssertEqual(receipt.bootSessionID, token.bootSessionID)
        XCTAssertEqual(receipt.daemonSessionID, token.daemonSessionID)
        XCTAssertEqual(receipt.journalGeneration, token.journalGeneration)
        XCTAssertEqual(receipt.expectedFanIDs, token.expectedFanIDs)
        XCTAssertEqual(receipt.helperSHA256, token.helperSHA256)
        XCTAssertEqual(receipt.quiesceGeneration, token.quiesceGeneration)
        XCTAssertTrue(receipt.quiesced)
        XCTAssertTrue(receipt.tokenConsumed)
        XCTAssertEqual(receipt.expiresAt.timeIntervalSince(receipt.authorizedAt), 300)

        let termination = try await fixture.coordinator.prepareVoluntaryTermination()
        XCTAssertTrue(termination.safeToStop)
        XCTAssertTrue(termination.quiesced)
        XCTAssertTrue(termination.tokenConsumed)
        XCTAssertFalse(termination.restoreAttempted)
        XCTAssertEqual(fixture.state.restoreCallCount, 1)

        do {
            _ = try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
            )
            XCTFail("Expected single-use token rejection")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenAlreadyConsumed)
        }
        do {
            try await fixture.coordinator.cancel()
            XCTFail("Consumed maintenance must remain quiesced")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .consumedMaintenanceCannotResume)
        }
    }

    func testConcurrentConsumeReservesTokenBeforeAwaitAndAuthorizesExactlyOnce() async throws {
        let fixture = makeFixture()
        let report = try await fixture.coordinator.prepare(
            operation: .repair,
            helperSHA256: fixture.state.helperHash
        )
        let token = try XCTUnwrap(report.token)
        let request = HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
        let journalGate = LifecycleJournalGenerationGate()
        fixture.state.journalGenerationGate = journalGate

        let firstConsume = Task {
            try await fixture.coordinator.consume(request)
        }
        await journalGate.waitUntilEntered()

        do {
            _ = try await fixture.coordinator.consume(request)
            XCTFail("A concurrent consumer must not pass an in-flight token reservation")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenAlreadyConsumed)
        }

        let commitTime = fixture.state.date.addingTimeInterval(2)
        fixture.state.date = commitTime
        await journalGate.open()
        let authorization = try await firstConsume.value
        XCTAssertTrue(authorization.authorized)
        XCTAssertEqual(authorization.tokenID, token.tokenID)
        XCTAssertEqual(authorization.consumedAt, commitTime)
        XCTAssertEqual(fixture.state.authorityPersistenceCallCount, 1)
        XCTAssertEqual(fixture.state.authorityReceipt?.tokenID, token.tokenID)
        XCTAssertEqual(fixture.state.authorityReceipt?.authorizedAt, commitTime)
        XCTAssertEqual(
            fixture.state.authorityReceipt?.expiresAt,
            commitTime.addingTimeInterval(300)
        )
    }

    func testCancelCannotUnquiesceAnInFlightPreparation() async throws {
        let fixture = makeFixture()
        let journalGate = LifecycleJournalGenerationGate()
        fixture.state.journalGenerationGate = journalGate

        let preparation = Task {
            try await fixture.coordinator.prepare(
                operation: .repair,
                helperSHA256: fixture.state.helperHash
            )
        }
        await journalGate.waitUntilEntered()

        do {
            try await fixture.coordinator.cancel()
            XCTFail("Cancellation must not end a quiesce generation while preparation can still publish its token")
        } catch {
            XCTAssertEqual(
                error as? DaemonLifecycleCoordinatorError,
                .maintenancePreparationInProgress
            )
        }
        let remainsQuiesced = await fixture.coordinator.isQuiesced
        XCTAssertTrue(remainsQuiesced)

        await journalGate.open()
        let report = try await preparation.value
        XCTAssertTrue(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertNotNil(report.token)

        try await fixture.coordinator.cancel()
        let quiescedAfterCompletedPreparationCancel = await fixture.coordinator.isQuiesced
        XCTAssertFalse(quiescedAfterCompletedPreparationCancel)
    }

    func testTokenExpiryAtConsumeCommitCannotPersistAuthority() async throws {
        let fixture = makeFixture(tokenTTL: 5)
        let report = try await fixture.coordinator.prepare(
            operation: .repair,
            helperSHA256: fixture.state.helperHash
        )
        let token = try XCTUnwrap(report.token)
        let journalGate = LifecycleJournalGenerationGate()
        fixture.state.journalGenerationGate = journalGate

        let consumption = Task {
            try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
            )
        }
        await journalGate.waitUntilEntered()
        fixture.state.date = token.expiresAt.addingTimeInterval(1)
        await journalGate.open()

        do {
            _ = try await consumption.value
            XCTFail("A token that expires during live-state validation must not commit authority")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenExpired)
        }
        XCTAssertNil(fixture.state.authorityReceipt)
        XCTAssertEqual(fixture.state.authorityPersistenceCallCount, 0)
        let remainsQuiesced = await fixture.coordinator.isQuiesced
        XCTAssertTrue(remainsQuiesced)
    }

    func testRestoreFailureKeepsQuiescedAndIssuesNoToken() async throws {
        let fixture = makeFixture()
        fixture.state.restoreError = ViftyError.helperRejected("restore readback failed")

        let report = try await fixture.coordinator.prepare(operation: .uninstall, helperSHA256: fixture.state.helperHash)

        XCTAssertFalse(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertTrue(report.restoreAttempted)
        XCTAssertFalse(report.restoreSucceeded)
        XCTAssertNil(report.token)
        XCTAssertTrue(report.blockers.contains { $0.code == .restoreFailed })
        XCTAssertThrowsError(try fixture.coordinator.requireControlAllowed())
    }

    func testClientSuppliedHelperDigestMustMatchDaemonCanonicalHelperBeforeQuiesce() async throws {
        let fixture = makeFixture()

        do {
            _ = try await fixture.coordinator.prepare(
                operation: .repair,
                helperSHA256: Self.helperHashB
            )
            XCTFail("A client-supplied digest must not replace the daemon's canonical helper identity")
        } catch {
            XCTAssertEqual(
                error as? DaemonLifecycleCoordinatorError,
                .bindingChanged(
                    "the requesting client helper digest does not match the running daemon app's canonical ViftyHelper"
                )
            )
        }
        let isQuiesced = await fixture.coordinator.isQuiesced
        XCTAssertFalse(isQuiesced)
        XCTAssertEqual(fixture.state.restoreCallCount, 0)
        XCTAssertNil(fixture.state.authorityReceipt)
    }

    func testForcedOrIncompleteFreshTelemetryBlocksToken() async throws {
        let forced = makeFixture()
        forced.state.postRestoreSnapshot = Self.snapshot(fans: [
            Self.fan(id: 0, mode: .automatic),
            Self.fan(id: 1, mode: .forced)
        ])

        let forcedReport = try await forced.coordinator.prepare(operation: .repair, helperSHA256: forced.state.helperHash)
        XCTAssertFalse(forcedReport.safeToStop)
        XCTAssertNil(forcedReport.token)
        XCTAssertTrue(forcedReport.blockers.contains { $0.code == .fanStateUnconfirmed })

        let incomplete = makeFixture()
        incomplete.state.postRestoreSnapshot = Self.snapshot(fans: [])
        let incompleteReport = try await incomplete.coordinator.prepare(operation: .repair, helperSHA256: incomplete.state.helperHash)
        XCTAssertFalse(incompleteReport.safeToStop)
        XCTAssertNil(incompleteReport.token)
        XCTAssertTrue(incompleteReport.blockers.contains { $0.code == .fanInventoryInvalid })
    }

    func testTokenExpiresAndCannotBeRecoveredFromReportJSON() async throws {
        let fixture = makeFixture(tokenTTL: 5)
        let report = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)
        let token = try XCTUnwrap(report.token)
        fixture.state.date = fixture.state.date.addingTimeInterval(6)

        do {
            _ = try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
            )
            XCTFail("Expected expired token")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenExpired)
        }

        do {
            _ = try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
            )
            XCTFail("Report JSON must not recreate daemon-owned authorization")
        } catch {
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenUnavailable)
        }
    }

    func testOperationHelperGenerationOwnershipAndFanSetBindingsFailClosed() async throws {
        try await assertBindingFailure { fixture, token in
            var changed = token
            changed.operation = .uninstall
            return HelperMaintenanceAuthorizationRequest(operation: .uninstall, token: changed)
        } verify: { error in
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .operationMismatch)
        }

        try await assertBindingFailure { _, token in
            var changed = token
            changed.helperSHA256 = Self.helperHashB
            return HelperMaintenanceAuthorizationRequest(operation: .repair, token: changed)
        } verify: { error in
            XCTAssertEqual(error as? DaemonLifecycleCoordinatorError, .tokenMismatch)
        }
        try await assertStateBindingFailure { state in
            state.helperHash = Self.helperHashB
        }
        try await assertStateBindingFailure { state in
            state.generation &+= 1
        }
        try await assertStateBindingFailure { state in
            state.status = FanControlOwnershipStatus(
                owner: .manual(sessionID: "foreign"),
                phase: .active,
                transactionID: "foreign-transaction",
                expectedFanIDs: [0, 1],
                recoveryPending: false
            )
        }
        try await assertStateBindingFailure { state in
            state.snapshot = Self.snapshot(fans: [Self.fan(id: 0, mode: .automatic)])
        }
    }

    func testModeOnlyPhysicalFanRemainsInCompleteMaintenanceDomain() async throws {
        let fixture = makeFixture()
        fixture.state.postRestoreSnapshot = Self.snapshot(fans: [
            Self.fan(id: 0, mode: .automatic),
            Self.fan(
                id: 1,
                mode: .system,
                controllable: false,
                eligibility: FanControlEligibility(
                    canApplyFixedRPM: false,
                    canRestoreOSManagedMode: true,
                    reasons: [.missingTargetKey]
                )
            )
        ])

        let report = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)

        XCTAssertTrue(report.safeToStop)
        XCTAssertEqual(report.token?.expectedFanIDs, [0, 1])
        XCTAssertEqual(report.fanResults.map(\.fanID), [0, 1])
        XCTAssertTrue(report.fanResults.allSatisfy(\.confirmedOSManaged))
    }

    func testUnknownOrRestoreIneligibleSecondPhysicalFanBlocksMaintenance() async throws {
        let unknown = makeFixture()
        unknown.state.postRestoreSnapshot = Self.snapshot(fans: [
            Self.fan(id: 0, mode: .automatic),
            Self.fan(id: 1, mode: .unknown(7))
        ])
        let unknownReport = try await unknown.coordinator.prepare(operation: .repair, helperSHA256: unknown.state.helperHash)
        XCTAssertFalse(unknownReport.safeToStop)
        XCTAssertNil(unknownReport.token)
        XCTAssertTrue(unknownReport.blockers.contains { $0.code == .fanStateUnconfirmed })

        let ineligible = makeFixture()
        ineligible.state.postRestoreSnapshot = Self.snapshot(fans: [
            Self.fan(id: 0, mode: .automatic),
            Self.fan(
                id: 1,
                mode: .automatic,
                eligibility: .legacyUnspecified
            )
        ])
        let ineligibleReport = try await ineligible.coordinator.prepare(operation: .repair, helperSHA256: ineligible.state.helperHash)
        XCTAssertFalse(ineligibleReport.safeToStop)
        XCTAssertNil(ineligibleReport.token)
        XCTAssertTrue(ineligibleReport.blockers.contains { $0.code == .fanInventoryInvalid })
    }

    func testCancelUnquiescesOnlyUnconsumedPreparation() async throws {
        let fixture = makeFixture()
        fixture.state.authorityReceipt = HelperMaintenanceAuthorityReceipt(
            operation: .repair,
            tokenID: "stale",
            tokenIssuedAt: fixture.state.date,
            authorizedAt: fixture.state.date,
            expiresAt: fixture.state.date.addingTimeInterval(300),
            bootSessionID: "boot-A",
            daemonSessionID: "daemon-A",
            journalGeneration: 0,
            expectedFanIDs: [0],
            helperSHA256: Self.helperHashA,
            quiesceGeneration: 1
        )
        _ = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)
        XCTAssertNil(fixture.state.authorityReceipt)
        let quiescedBeforeCancel = await fixture.coordinator.isQuiesced
        XCTAssertTrue(quiescedBeforeCancel)

        try await fixture.coordinator.cancel()

        let quiescedAfterCancel = await fixture.coordinator.isQuiesced
        XCTAssertFalse(quiescedAfterCancel)
        XCTAssertNoThrow(try fixture.coordinator.requireControlAllowed())
        XCTAssertNil(fixture.state.authorityReceipt)
    }

    func testReceiptPersistenceFailureNeverConsumesTokenOrReleasesQuiescence() async throws {
        let fixture = makeFixture()
        let report = try await fixture.coordinator.prepare(operation: .uninstall, helperSHA256: fixture.state.helperHash)
        let token = try XCTUnwrap(report.token)
        fixture.state.authorityPersistenceFails = true

        do {
            _ = try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .uninstall, token: token)
            )
            XCTFail("Missing root-owned receipt must block token consumption")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("could not be persisted"))
        }
        XCTAssertNil(fixture.state.authorityReceipt)
        XCTAssertThrowsError(try fixture.coordinator.requireControlAllowed())
        fixture.state.authorityPersistenceFails = false
        try await fixture.coordinator.cancel()
        XCTAssertNoThrow(try fixture.coordinator.requireControlAllowed())
    }

    func testVoluntaryTerminationRequiresSameRestoreProofButNoTeardownToken() async throws {
        let fixture = makeFixture()

        let report = try await fixture.coordinator.prepareVoluntaryTermination()

        XCTAssertTrue(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertTrue(report.completeExpectedSetConfirmed)
        XCTAssertNil(report.token)
    }

    func testConsumedAuthorizationRefusesTerminationAfterGenerationChange() async throws {
        let fixture = makeFixture()
        let report = try await fixture.coordinator.prepare(operation: .uninstall, helperSHA256: fixture.state.helperHash)
        let token = try XCTUnwrap(report.token)
        _ = try await fixture.coordinator.consume(
            HelperMaintenanceAuthorizationRequest(operation: .uninstall, token: token)
        )
        fixture.state.generation &+= 1

        do {
            _ = try await fixture.coordinator.prepareVoluntaryTermination()
            XCTFail("Changed state must refuse voluntary termination")
        } catch {
            XCTAssertTrue(error is DaemonLifecycleCoordinatorError)
        }
    }

    func testMaintenanceXPCEnvelopeRoundTripsExactlyAndRejectsExtraKeys() throws {
        let fixture = makeFixture()
        let token = HelperMaintenanceToken(
            tokenID: "token",
            operation: .repair,
            issuedAt: fixture.state.date,
            expiresAt: fixture.state.date.addingTimeInterval(30),
            bootSessionID: "boot-A",
            daemonSessionID: "daemon-A",
            journalGeneration: 4,
            expectedFanIDs: [0, 1],
            helperSHA256: Self.helperHashA,
            quiesceGeneration: 2
        )
        let request = HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
        let encoded = XPCHelperMaintenanceCoding.encode(request)
        XCTAssertEqual(XPCHelperMaintenanceCoding.decodeAuthorizationRequest(encoded), request)

        let withExtraKey = encoded.mutableCopy() as! NSMutableDictionary
        withExtraKey["safeToStop"] = true
        XCTAssertNil(XPCHelperMaintenanceCoding.decodeAuthorizationRequest(withExtraKey))
        XCTAssertNil(XPCHelperMaintenanceCoding.decodeAuthorizationRequest(["json": Data()] as NSDictionary))
    }

    func testHelperBinaryIdentityStreamsRegularExecutableAndRejectsSymlinkOrOversize() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("helper-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executable = root.appendingPathComponent("helper")
        try Data("abc".utf8).write(to: executable)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)
        XCTAssertEqual(
            try HelperBinaryIdentity.sha256(
                at: executable,
                requiredOwnerID: geteuid(),
                maximumBytes: 3
            ),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )

        let symlink = root.appendingPathComponent("helper-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: executable)
        XCTAssertThrowsError(try HelperBinaryIdentity.sha256(
            at: symlink,
            requiredOwnerID: geteuid()
        ))

        let oversized = root.appendingPathComponent("oversized-helper")
        try Data("123456789".utf8).write(to: oversized)
        XCTAssertEqual(chmod(oversized.path, 0o755), 0)
        XCTAssertThrowsError(try HelperBinaryIdentity.sha256(
            at: oversized,
            requiredOwnerID: geteuid(),
            maximumBytes: 8
        ))

        let hardLink = root.appendingPathComponent("helper-hardlink")
        XCTAssertEqual(link(executable.path, hardLink.path), 0)
        XCTAssertThrowsError(try HelperBinaryIdentity.sha256(
            at: executable,
            requiredOwnerID: geteuid()
        ))
    }

    func testDaemonIdentitySupportsSMAppServiceBundleProgramAndLegacyRootShape() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("daemon-path-identity-\(UUID().uuidString)", isDirectory: true)
        let bundled = root.appendingPathComponent("Vifty.app/Contents/MacOS/ViftyDaemon")
        let legacy = root.appendingPathComponent("legacy/tech.reidar.vifty.daemon")
        try FileManager.default.createDirectory(at: bundled.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("bundle-daemon".utf8).write(to: bundled)
        try Data("legacy-daemon".utf8).write(to: legacy)
        XCTAssertEqual(chmod(bundled.path, 0o755), 0)
        XCTAssertEqual(chmod(legacy.path, 0o755), 0)

        let bundledHash = try HelperBinaryIdentity.daemonExecutableSHA256(
            at: bundled,
            legacyURL: legacy,
            legacyOwnerID: geteuid()
        )
        let legacyHash = try HelperBinaryIdentity.daemonExecutableSHA256(
            at: legacy,
            legacyURL: legacy,
            legacyOwnerID: geteuid()
        )
        XCTAssertEqual(bundledHash.count, 64)
        XCTAssertEqual(legacyHash.count, 64)
        XCTAssertNotEqual(bundledHash, legacyHash)

        let unrelated = root.appendingPathComponent("ViftyDaemon")
        try Data("untrusted".utf8).write(to: unrelated)
        XCTAssertEqual(chmod(unrelated.path, 0o755), 0)
        XCTAssertThrowsError(try HelperBinaryIdentity.daemonExecutableSHA256(
            at: unrelated,
            legacyURL: legacy,
            legacyOwnerID: geteuid()
        ))
    }

    private func assertBindingFailure(
        request: (LifecycleFixture, HelperMaintenanceToken) -> HelperMaintenanceAuthorizationRequest,
        verify: (Error) -> Void
    ) async throws {
        let fixture = makeFixture()
        let report = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)
        let token = try XCTUnwrap(report.token)
        do {
            _ = try await fixture.coordinator.consume(request(fixture, token))
            XCTFail("Expected binding rejection")
        } catch {
            verify(error)
        }
    }

    private func assertStateBindingFailure(
        mutate: (LifecycleState) -> Void
    ) async throws {
        let fixture = makeFixture()
        let report = try await fixture.coordinator.prepare(operation: .repair, helperSHA256: fixture.state.helperHash)
        let token = try XCTUnwrap(report.token)
        mutate(fixture.state)
        do {
            _ = try await fixture.coordinator.consume(
                HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
            )
            XCTFail("Expected state binding rejection")
        } catch {
            XCTAssertTrue(
                error is DaemonLifecycleCoordinatorError,
                "Expected a stable lifecycle error, got \(error)"
            )
        }
    }

    private func makeFixture(tokenTTL: TimeInterval = 30) -> LifecycleFixture {
        let signal = FanControlRestoreSignal()
        let state = LifecycleState(snapshot: Self.snapshot())
        let coordinator = DaemonLifecycleCoordinator(
            restoreSignal: signal,
            restoreAllAuto: { _ in
                try state.performRestore(signal: signal)
            },
            ownershipStatus: { state.status },
            freshSnapshot: { state.snapshot },
            journalGeneration: { await state.readJournalGeneration() },
            persistAuthority: { try state.persistAuthority($0) },
            clearAuthority: { state.authorityReceipt = nil },
            helperIdentity: { state.helperHash },
            bootSessionID: { state.bootSessionID },
            now: { state.date },
            tokenTTL: tokenTTL,
            daemonSessionID: "daemon-A"
        )
        return LifecycleFixture(coordinator: coordinator, state: state)
    }

    private static func snapshot(
        fans: [Fan] = [fan(id: 0, mode: .automatic), fan(id: 1, mode: .system)]
    ) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: fans,
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU", celsius: 55, source: .synthetic)
            ],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            fanControlProtocolVersion: FanControlProtocolVersion.current
        )
    }

    private static func fan(
        id: Int,
        mode: FanHardwareMode,
        controllable: Bool = true,
        eligibility: FanControlEligibility = .trusted
    ) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: 1_400,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: controllable,
            hardwareMode: mode,
            hardwareModeKey: "F\(id)Md",
            targetRPM: 1_400,
            controlEligibility: eligibility
        )
    }

    private static let helperHashA = String(repeating: "a", count: 64)
    private static let helperHashB = String(repeating: "b", count: 64)
}

private struct LifecycleFixture {
    var coordinator: DaemonLifecycleCoordinator
    var state: LifecycleState
}

private final class LifecycleState: @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: HardwareSnapshot
    private var _postRestoreSnapshot: HardwareSnapshot?
    private var _status: FanControlOwnershipStatus = .osManaged
    private var _generation: UInt64 = 0
    private var _helperHash = String(repeating: "a", count: 64)
    private var _bootSessionID = "boot-A"
    private var _date = Date(timeIntervalSince1970: 1_000)
    private var _restoreError: Error?
    private var _restoreCallCount = 0
    private var _authorityReceipt: HelperMaintenanceAuthorityReceipt?
    private var _authorityPersistenceFails = false
    private var _authorityPersistenceCallCount = 0
    private var _journalGenerationGate: LifecycleJournalGenerationGate?

    init(snapshot: HardwareSnapshot) {
        _snapshot = snapshot
    }

    var snapshot: HardwareSnapshot {
        get { lock.withLock { _snapshot } }
        set { lock.withLock { _snapshot = newValue } }
    }

    var postRestoreSnapshot: HardwareSnapshot? {
        get { lock.withLock { _postRestoreSnapshot } }
        set { lock.withLock { _postRestoreSnapshot = newValue } }
    }

    var status: FanControlOwnershipStatus {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }

    var generation: UInt64 {
        get { lock.withLock { _generation } }
        set { lock.withLock { _generation = newValue } }
    }

    var journalGenerationGate: LifecycleJournalGenerationGate? {
        get { lock.withLock { _journalGenerationGate } }
        set { lock.withLock { _journalGenerationGate = newValue } }
    }

    var helperHash: String {
        get { lock.withLock { _helperHash } }
        set { lock.withLock { _helperHash = newValue } }
    }

    var bootSessionID: String {
        get { lock.withLock { _bootSessionID } }
        set { lock.withLock { _bootSessionID = newValue } }
    }

    var date: Date {
        get { lock.withLock { _date } }
        set { lock.withLock { _date = newValue } }
    }

    var restoreError: Error? {
        get { lock.withLock { _restoreError } }
        set { lock.withLock { _restoreError = newValue } }
    }

    var restoreCallCount: Int { lock.withLock { _restoreCallCount } }

    var authorityReceipt: HelperMaintenanceAuthorityReceipt? {
        get { lock.withLock { _authorityReceipt } }
        set { lock.withLock { _authorityReceipt = newValue } }
    }

    var authorityPersistenceFails: Bool {
        get { lock.withLock { _authorityPersistenceFails } }
        set { lock.withLock { _authorityPersistenceFails = newValue } }
    }

    var authorityPersistenceCallCount: Int {
        lock.withLock { _authorityPersistenceCallCount }
    }

    func readJournalGeneration() async -> UInt64 {
        let gate = journalGenerationGate
        if let gate {
            await gate.wait()
        }
        return generation
    }

    func persistAuthority(_ receipt: HelperMaintenanceAuthorityReceipt) throws {
        try lock.withLock {
            _authorityPersistenceCallCount += 1
            if _authorityPersistenceFails {
                throw ViftyError.helperRejected("fixture authority persistence failure")
            }
            _authorityReceipt = receipt
        }
    }

    func performRestore(signal: FanControlRestoreSignal) throws -> FanControlTransactionResult {
        let restoreGeneration = signal.beginRestore()
        defer { signal.completeRestore(through: restoreGeneration) }
        return try lock.withLock {
            _restoreCallCount += 1
            if let _restoreError { throw _restoreError }
            if let _postRestoreSnapshot { _snapshot = _postRestoreSnapshot }
            _status = .osManaged
            _generation &+= 1
            let expected = _snapshot.fans.map(\.id).sorted()
            return FanControlTransactionResult(
                transactionID: "maintenance-restore",
                owner: nil,
                phase: nil,
                expectedFanIDs: expected,
                confirmedFanIDs: expected
            )
        }
    }
}

private actor LifecycleJournalGenerationGate {
    private var isEntered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        isEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
