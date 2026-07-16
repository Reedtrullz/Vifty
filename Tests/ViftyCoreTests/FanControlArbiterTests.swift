import Darwin
import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyFanControlSafety

final class FanControlArbiterTests: XCTestCase {
    func testManualApplyPersistsAndConfirmsResolvedTargetsForCompleteExpectedDomain() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: [
            Self.fan(id: 0, mode: .automatic, targetRPM: 1_400),
            Self.fan(id: 1, mode: .automatic, targetRPM: 1_500)
        ])
        try await withArbiter(hardware: hardware) { arbiter, store in
            let result = try await arbiter.applyManual(
                ManualFanControlRequest(
                    transactionID: "manual-1",
                    sessionID: "session-1",
                    expectedFanIDs: [0, 1],
                    targetRPMByFanID: [0: 3_200, 1: 3_300],
                    reason: "User applied Fixed"
                )
            )

            XCTAssertEqual(result.phase, .active)
            XCTAssertEqual(result.expectedFanIDs, [0, 1])
            XCTAssertEqual(result.confirmedFanIDs, [0, 1])
            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.expectedFanIDs, [0, 1])
            XCTAssertEqual(journal.appliedFanIDs, [0, 1])
            XCTAssertEqual(journal.phase, .active)
        }
    }

    func testInitialApplyRejectsExpectedFanWithoutResolvedTargetBeforeJournalOrWrites() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: [
            Self.fan(id: 0, mode: .automatic, targetRPM: 1_400),
            Self.fan(id: 1, mode: .automatic, targetRPM: 1_500)
        ])
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(ManualFanControlRequest(
                    transactionID: "manual-partial",
                    sessionID: "session-partial",
                    expectedFanIDs: [0, 1],
                    targetRPMByFanID: [0: 3_200],
                    reason: "Malformed partial request"
                ))
                XCTFail("Expected unresolved target refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("Every expected fan"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testGlobalAutoRejectsPartialModeTelemetryBeforeAnyWrite() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: [
            Self.fan(id: 0, mode: .automatic, targetRPM: 1_400),
            Fan(
                id: 1,
                name: "Fan 1",
                currentRPM: 1_500,
                minimumRPM: 1_200,
                maximumRPM: 5_000,
                controllable: true,
                hardwareMode: nil,
                controlEligibility: FanControlEligibility(
                    canApplyFixedRPM: false,
                    canRestoreOSManagedMode: false,
                    reasons: [.missingModeKey]
                )
            )
        ])
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.restoreAuto(AutoRestoreRequest(
                    transactionID: "global-auto",
                    expectedFanIDs: [],
                    reason: "Global Auto",
                    allowRestoreAllTrustedFans: true
                ))
                XCTFail("Expected partial telemetry refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("complete native fan inventory"))
            }
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testNoJournalGlobalApprovalRejectsCallerSelectedSubsetBeforeWrites() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.restoreAuto(AutoRestoreRequest(
                    transactionID: "mixed-global-subset",
                    expectedFanIDs: [0],
                    reason: "Unsafe mixed request",
                    allowRestoreAllTrustedFans: true
                ))
                XCTFail("Expected mixed global/subset refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("caller-selected subset"))
            }
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testUnreadableJournalBlocksAutomaticGlobalRestoreWithoutWrites() async throws {
        let unreadableFixtures = [
            Data("not-json".utf8),
            Data(#"{"schemaVersion":99,"transactionID":"future"}"#.utf8)
        ]
        for data in unreadableFixtures {
            let hardware = FakePrivilegedFanControlHardware(fans: [
                Self.fan(id: 0, mode: .forced),
                Self.fan(id: 1, mode: .forced)
            ])
            try await withUnreadableJournal(data, hardware: hardware) { arbiter, store in
                do {
                    _ = try await arbiter.restoreAuto(AutoRestoreRequest(
                        transactionID: "automatic-recovery",
                        reason: "Automatic lifecycle restore",
                        allowRestoreAllTrustedFans: true
                    ))
                    XCTFail("Expected unreadable-journal authority refusal")
                } catch {
                    XCTAssertTrue(error.localizedDescription.contains("explicit operator-approved"))
                }
                XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
                XCTAssertEqual(try Data(contentsOf: store.journalURL), data)
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: store.preservedUnreadableJournalURL.path
                ))
            }
        }
    }

    func testExplicitOperatorRecoveryPreservesUnreadableJournalAndRestoresCompleteSet() async throws {
        let unreadableFixtures = [
            Data("not-json".utf8),
            Data(#"{"schemaVersion":99,"transactionID":"future"}"#.utf8)
        ]
        for data in unreadableFixtures {
            let hardware = FakePrivilegedFanControlHardware(fans: [
                Self.fan(id: 0, mode: .forced),
                Self.fan(id: 1, mode: .forced)
            ])
            try await withUnreadableJournal(data, hardware: hardware) { arbiter, store in
                let result = try await arbiter.restoreAuto(AutoRestoreRequest(
                    transactionID: "operator-recovery",
                    reason: "User explicitly approved restore all",
                    allowRestoreAllTrustedFans: true,
                    unreadableJournalRecoveryAuthority: .explicitOperator
                ))

                XCTAssertEqual(result.expectedFanIDs, [0, 1])
                XCTAssertEqual(result.confirmedFanIDs, [0, 1])
                XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
                XCTAssertNil(try store.load())
                XCTAssertEqual(
                    try Data(contentsOf: store.preservedUnreadableJournalURL),
                    data
                )
            }
        }
    }

    func testDurableRecoveryAuthorityRequiresAndRestoresCompletePhysicalSet() async throws {
        let corrupt = Data("not-json".utf8)
        let hardware = FakePrivilegedFanControlHardware(fans: [
            Self.fan(id: 0, mode: .forced),
            Self.fan(id: 1, mode: .forced)
        ])
        try await withUnreadableJournal(corrupt, hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.restoreAuto(AutoRestoreRequest(
                    transactionID: "partial-durable-recovery",
                    expectedFanIDs: [0],
                    reason: "Reconstructed durable lease",
                    unreadableJournalRecoveryAuthority: .durableState
                ))
                XCTFail("Expected partial durable set refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("complete trusted physical fan set"))
            }
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: store.journalURL), corrupt)

            let result = try await arbiter.restoreAuto(AutoRestoreRequest(
                transactionID: "complete-durable-recovery",
                expectedFanIDs: [0, 1],
                reason: "Reconstructed durable lease",
                unreadableJournalRecoveryAuthority: .durableState
            ))
            XCTAssertEqual(result.confirmedFanIDs, [0, 1])
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            XCTAssertNil(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.preservedUnreadableJournalURL), corrupt)
        }
    }

    func testManualAndAgentOwnershipAreMutuallyExclusive() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, _ in
            _ = try await arbiter.applyManual(Self.manualRequest())

            do {
                _ = try await arbiter.applyAgent(
                    AgentFanControlRequest(
                        transactionID: "agent-1",
                        leaseID: "lease-1",
                        expectedFanIDs: [0, 1],
                        targetRPMByFanID: [0: 3_500, 1: 3_600]
                    )
                )
                XCTFail("Expected ownership conflict")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("owned by unresolved transaction"))
            }
            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
        }
    }

    func testOwnerConditionalRestoreAtomicallyRestoresExactAgentTransaction() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, store in
            let request = AgentFanControlRequest(
                transactionID: "agent-1",
                leaseID: "lease-1",
                expectedFanIDs: [0, 1],
                targetRPMByFanID: [0: 3_200, 1: 3_300]
            )
            _ = try await arbiter.applyAgent(request)

            let result = try await arbiter.restoreAutoIfOwned(
                transactionID: "agent-1",
                owner: .agent(leaseID: "lease-1"),
                reason: "Lease persistence failed"
            )

            XCTAssertEqual(result?.confirmedFanIDs, [0, 1])
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            XCTAssertNil(try store.load())
        }
    }

    func testOwnerConditionalRestoreLeavesForeignTransactionUntouchedAndDoesNotRaiseRestorePriority() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, store in
            let request = Self.manualRequest()
            _ = try await arbiter.applyManual(request)

            let result = try await arbiter.restoreAutoIfOwned(
                transactionID: "agent-1",
                owner: .agent(leaseID: "lease-1"),
                reason: "Stale agent rollback"
            )

            XCTAssertNil(result)
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertEqual(try store.load()?.owner, .manual(sessionID: "session-1"))
            _ = try await arbiter.applyManual(request)
            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
        }
    }

    func testConcurrentManualAndAgentRequestsProduceExactlyOneOwner() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, store in
            async let manualSucceeded: Bool = {
                do {
                    _ = try await arbiter.applyManual(Self.manualRequest())
                    return true
                } catch {
                    return false
                }
            }()
            async let agentSucceeded: Bool = {
                do {
                    _ = try await arbiter.applyAgent(AgentFanControlRequest(
                        transactionID: "agent-1",
                        leaseID: "lease-1",
                        expectedFanIDs: [0, 1],
                        targetRPMByFanID: [0: 3_500, 1: 3_600]
                    ))
                    return true
                } catch {
                    return false
                }
            }()

            let outcomes = await (manualSucceeded, agentSucceeded)
            XCTAssertNotEqual(outcomes.0, outcomes.1)
            XCTAssertEqual(hardware.appliedFanIDs.count, 2)
            XCTAssertNotNil(try store.load()?.owner)
        }
    }

    func testFailingFanIsIncludedInFullRollback() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.failApplyFanID = 1
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected apply failure")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("injected apply failure"))
            }

            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            XCTAssertNil(try store.load())
        }
    }

    func testRollbackFailureRetainsRecoveryOwnershipAndCompleteExpectedSet() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.failApplyFanID = 1
        hardware.failRestoreFanID = 1
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected apply and restore failure")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("recovery remains pending"))
            }

            let record = try XCTUnwrap(store.load())
            XCTAssertEqual(record.owner, .recovery)
            XCTAssertEqual(record.phase, .restorePending)
            XCTAssertEqual(record.expectedFanIDs, [0, 1])
            let status = await arbiter.status()
            XCTAssertTrue(status.recoveryPending)
        }
    }

    func testPartialSnapshotRefusesBeforeJournalOrHardwareWrites() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: [Self.fan(id: 0)])
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected incomplete domain refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("incomplete"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testApplyRejectsDuplicatePhysicalFanIDsBeforeJournalOrHardwareWrites() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.enqueueSnapshot(fans: [
            Self.fan(id: 0),
            Self.fan(id: 0),
            Self.fan(id: 1)
        ])

        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected duplicate fan telemetry refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("duplicate fan IDs"))
            }

            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testRestoreRejectsDuplicateInitialFanIDsAndRetainsRecoveryJournal() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)

        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())
            hardware.enqueueSnapshot(fans: [
                Self.fan(id: 0, mode: .forced, targetRPM: 3_200),
                Self.fan(id: 0, mode: .forced, targetRPM: 3_200),
                Self.fan(id: 1, mode: .forced, targetRPM: 3_300)
            ])

            do {
                _ = try await arbiter.restoreAuto(
                    AutoRestoreRequest(transactionID: "restore", reason: "User requested Auto")
                )
                XCTFail("Expected duplicate fan telemetry refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("duplicate fan IDs"))
            }

            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.owner, .recovery)
            XCTAssertEqual(journal.phase, .restorePending)
            XCTAssertEqual(journal.expectedFanIDs, [0, 1])
            XCTAssertEqual(journal.lastErrorCode, "RESTORE_UNCONFIRMED")
        }
    }

    func testDuplicateFixedReadbackTriggersFullRollbackAndRetainsRecoveryOnRestoreFailure() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.failRestoreFanID = 1
        hardware.afterApply = { fanID in
            guard fanID == 1 else { return }
            hardware.enqueueSnapshot(fans: [
                Self.fan(id: 0, mode: .forced, targetRPM: 3_200),
                Self.fan(id: 0, mode: .forced, targetRPM: 3_200),
                Self.fan(id: 1, mode: .forced, targetRPM: 3_300)
            ])
        }

        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected duplicate fixed-readback refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("duplicate fan IDs"))
                XCTAssertTrue(error.localizedDescription.contains("recovery remains pending"))
            }

            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.owner, .recovery)
            XCTAssertEqual(journal.phase, .restorePending)
            XCTAssertEqual(journal.expectedFanIDs, [0, 1])
            XCTAssertEqual(journal.lastErrorCode, "RESTORE_UNCONFIRMED")
        }
    }

    func testDuplicateRestoreReadbackRemainsRecoveryPending() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.afterRestore = { fanID in
            guard fanID == 1 else { return }
            hardware.enqueueSnapshot(fans: [
                Self.fan(id: 0, mode: .automatic),
                Self.fan(id: 0, mode: .automatic),
                Self.fan(id: 1, mode: .automatic)
            ])
        }

        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())

            do {
                _ = try await arbiter.restoreAuto(
                    AutoRestoreRequest(transactionID: "restore", reason: "User requested Auto")
                )
                XCTFail("Expected duplicate restore-readback refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("duplicate fan IDs"))
            }

            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.owner, .recovery)
            XCTAssertEqual(journal.phase, .restorePending)
            XCTAssertEqual(journal.expectedFanIDs, [0, 1])
            XCTAssertEqual(journal.lastErrorCode, "RESTORE_UNCONFIRMED")
        }
    }

    func testJournalDurabilityFailureProducesZeroHardwareWrites() async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("journal", isDirectory: true),
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { _, point in
                if point == .temporaryFile {
                    throw FanControlJournalStoreError.ioFailure("injected journal fsync failure")
                }
            }
        )
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        let exclusiveLock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("lock/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: store,
            exclusiveLock: exclusiveLock
        )

        do {
            _ = try await arbiter.applyManual(Self.manualRequest())
            XCTFail("Expected durability failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("fsync"))
        }
        XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
    }

    func testReleasedExclusiveLockProducesZeroHardwareWritesAndNoJournal() async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("journal", isDirectory: true),
            requiredOwnerID: geteuid()
        )
        let exclusiveLock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("lock/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: store,
            exclusiveLock: exclusiveLock
        )
        exclusiveLock.release()

        do {
            _ = try await arbiter.applyManual(Self.manualRequest())
            XCTFail("Expected missing lock refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("safety lock is not held"))
        }
        XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
        XCTAssertNil(try store.load())
    }

    func testSystemManagedReadbackCountsAsSafeOSOwnership() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.restoreModeByFanID = [0: .system, 1: .system]
        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())
            arbiter.requestRestorePriority()

            let result = try await arbiter.restoreAuto(
                AutoRestoreRequest(transactionID: "restore", reason: "User requested Auto")
            )

            XCTAssertEqual(result.confirmedFanIDs, [0, 1])
            XCTAssertNil(result.owner)
            XCTAssertNil(try store.load())
        }
    }

    func testForcedOrUnknownRestoreReadbackRemainsPending() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.restoreModeByFanID = [0: .forced, 1: .unknown(2)]
        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())
            arbiter.requestRestorePriority()

            do {
                _ = try await arbiter.restoreAuto(
                    AutoRestoreRequest(transactionID: "restore", reason: "User requested Auto")
                )
                XCTFail("Expected unconfirmed restore")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("unconfirmed"))
            }

            XCTAssertEqual(try store.load()?.phase, .restorePending)
        }
    }

    func testSameActiveTransactionIsIdempotent() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, _ in
            let request = Self.manualRequest()
            _ = try await arbiter.applyManual(request)
            _ = try await arbiter.applyManual(request)

            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
        }
    }

    func testSameManualSessionCanApplyLaterPartialBatchWithoutShrinkingExpectedDomain() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())
            _ = try await arbiter.applyManual(ManualFanControlRequest(
                transactionID: "manual-1",
                sessionID: "session-1",
                expectedFanIDs: [0, 1],
                targetRPMByFanID: [1: 3_800],
                reason: "Curve tick"
            ))

            XCTAssertEqual(hardware.appliedFanIDs, [0, 1, 1])
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.expectedFanIDs, [0, 1])
            XCTAssertEqual(journal.targetRPMByFanID, [0: 3_200, 1: 3_800])
            XCTAssertEqual(journal.phase, .active)
        }
    }

    func testApplyRejectsUntrustedPhysicalFanOutsideExpectedDomainBeforeWrites() async throws {
        let extra = Fan(
            id: 2,
            name: "Read-only fan",
            currentRPM: 1_400,
            minimumRPM: 0,
            maximumRPM: 0,
            controllable: false,
            hardwareMode: nil,
            controlEligibility: .legacyUnspecified
        )
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans + [extra])
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected incomplete physical inventory refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("physical fan inventory"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testApplyAllowsTrustedAutoModeOnlyPhysicalFanOutsideFixedTargets() async throws {
        let extra = Self.modeOnlyFan(id: 2, mode: .automatic)
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans + [extra])
        try await withArbiter(hardware: hardware) { arbiter, _ in
            let result = try await arbiter.applyManual(Self.manualRequest())
            XCTAssertEqual(result.expectedFanIDs, [0, 1])
            XCTAssertEqual(hardware.appliedFanIDs, [0, 1])
        }
    }

    func testApplyRejectsForcedModeOnlyPhysicalFanBeforeAnyWrite() async throws {
        let extra = Self.modeOnlyFan(id: 2, mode: .forced)
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans + [extra])
        try await withArbiter(hardware: hardware) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected unowned physical Forced fan refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("every physical fan"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testOwnershipClearFailureKeepsRecoveryJournalAfterHardwareConfirmation() async throws {
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        let callbackObservedJournal = ArbiterTestFlag()
        try await withArbiter(hardware: hardware) { arbiter, store in
            _ = try await arbiter.applyManual(Self.manualRequest())
            arbiter.requestRestorePriority()

            do {
                _ = try await arbiter.restoreAuto(
                    AutoRestoreRequest(transactionID: "restore", reason: "User requested Auto"),
                    beforeJournalClear: {
                        if (try? store.load()) != nil { callbackObservedJournal.mark() }
                        throw ArbiterInjectedFailure.ownershipClearFailed
                    }
                )
                XCTFail("Expected durable ownership clear failure")
            } catch ArbiterInjectedFailure.ownershipClearFailed {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            XCTAssertTrue(callbackObservedJournal.value)
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            let journal = try XCTUnwrap(store.load())
            XCTAssertEqual(journal.phase, .restorePending)
            XCTAssertEqual(journal.owner, .recovery)
            XCTAssertEqual(journal.lastErrorCode, "OWNERSHIP_CLEAR_FAILED")
        }
    }

    func testRestoreSignalPreemptsApplyAtFanBoundaryAndRollsBackWholeSet() async throws {
        let signal = FanControlRestoreSignal()
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.afterApply = { fanID in
            if fanID == 0 { signal.requestRestore() }
        }
        try await withArbiter(hardware: hardware, restoreSignal: signal) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected restore preemption")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("preempted"))
            }

            XCTAssertEqual(hardware.appliedFanIDs, [0])
            XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
            XCTAssertNil(try store.load())
        }
    }

    func testPendingRestoreBeforeApplyEntryRejectsWithZeroWritesAndNoJournal() async throws {
        let signal = FanControlRestoreSignal()
        signal.requestRestore()
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)

        try await withArbiter(hardware: hardware, restoreSignal: signal) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected pending restore refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("preempted"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testRestoreRaisedDuringPreflightRejectsBeforeJournalOrWrites() async throws {
        let signal = FanControlRestoreSignal()
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        hardware.afterSnapshot = { signal.requestRestore() }

        try await withArbiter(hardware: hardware, restoreSignal: signal) { arbiter, store in
            do {
                _ = try await arbiter.applyManual(Self.manualRequest())
                XCTFail("Expected preflight restore refusal")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("preempted"))
            }
            XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
            XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
            XCTAssertNil(try store.load())
        }
    }

    func testRestoreRaisedDuringJournalSaveBeforeMutationProducesZeroFixedWrites() async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let signal = FanControlRestoreSignal()
        let fireOnce = ArbiterTestFlag()
        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("journal", isDirectory: true),
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { descriptor, point in
                if point == .temporaryFile, !fireOnce.value {
                    fireOnce.mark()
                    signal.requestRestore()
                }
                guard fsync(descriptor) == 0 else {
                    throw FanControlJournalStoreError.ioFailure("fsync failed")
                }
            }
        )
        let lock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("lock/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let hardware = FakePrivilegedFanControlHardware(fans: Self.twoAutomaticFans)
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: store,
            exclusiveLock: lock,
            restoreSignal: signal
        )

        do {
            _ = try await arbiter.applyManual(Self.manualRequest())
            XCTFail("Expected restore preemption")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("preempted"))
        }
        XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
        XCTAssertEqual(hardware.restoredFanIDs, [0, 1])
        XCTAssertNil(try store.load())
    }

    func testInitialManualAndAgentApplyRejectUnownedForcedOrUnknownFans() async throws {
        for mode in [FanHardwareMode.forced, .unknown(2)] {
            for owner in ["manual", "agent"] {
                let hardware = FakePrivilegedFanControlHardware(fans: [
                    Self.fan(id: 0, mode: .automatic),
                    Self.fan(id: 1, mode: mode)
                ])
                try await withArbiter(hardware: hardware) { arbiter, store in
                    do {
                        if owner == "manual" {
                            _ = try await arbiter.applyManual(Self.manualRequest())
                        } else {
                            _ = try await arbiter.applyAgent(AgentFanControlRequest(
                                transactionID: "agent-1",
                                leaseID: "lease-1",
                                expectedFanIDs: [0, 1],
                                targetRPMByFanID: [0: 3_200, 1: 3_300]
                            ))
                        }
                        XCTFail("Expected unowned \(mode) refusal")
                    } catch {
                        XCTAssertTrue(error.localizedDescription.contains("Auto/System"))
                    }
                    XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
                    XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
                    XCTAssertNil(try store.load())
                }
            }
        }
    }

    private func withArbiter(
        hardware: FakePrivilegedFanControlHardware,
        restoreSignal: FanControlRestoreSignal = FanControlRestoreSignal(),
        body: (FanControlArbiter, FanControlJournalStore) async throws -> Void
    ) async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("journal", isDirectory: true),
            requiredOwnerID: geteuid()
        )
        let exclusiveLock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("lock/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: store,
            exclusiveLock: exclusiveLock,
            now: { Date(timeIntervalSince1970: 1_000) },
            restoreSignal: restoreSignal
        )
        try await body(arbiter, store)
    }

    private func withUnreadableJournal(
        _ data: Data,
        hardware: FakePrivilegedFanControlHardware,
        body: (FanControlArbiter, FanControlJournalStore) async throws -> Void
    ) async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("journal", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let store = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        try data.write(to: store.journalURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: store.journalURL.path
        )
        let lock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("lock/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: store,
            exclusiveLock: lock,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        try await body(arbiter, store)
    }

    private static func manualRequest() -> ManualFanControlRequest {
        ManualFanControlRequest(
            transactionID: "manual-1",
            sessionID: "session-1",
            expectedFanIDs: [0, 1],
            targetRPMByFanID: [0: 3_200, 1: 3_300],
            reason: "User applied Fixed"
        )
    }

    private static var twoAutomaticFans: [Fan] {
        [fan(id: 0), fan(id: 1)]
    }

    private static func fan(
        id: Int,
        mode: FanHardwareMode = .automatic,
        targetRPM: Int = 1_400
    ) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: targetRPM,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: mode,
            hardwareModeKey: "F\(id)Md",
            targetRPM: targetRPM,
            controlEligibility: .trusted
        )
    }

    private static func modeOnlyFan(id: Int, mode: FanHardwareMode) -> Fan {
        Fan(
            id: id,
            name: "Mode-only fan \(id)",
            currentRPM: 1_400,
            minimumRPM: 0,
            maximumRPM: 0,
            controllable: false,
            hardwareMode: mode,
            hardwareModeKey: "F\(id)Md",
            targetRPM: nil,
            controlEligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: true,
                reasons: [.missingTargetKey]
            )
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("arbiter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private enum ArbiterInjectedFailure: Error {
    case ownershipClearFailed
}

private final class ArbiterTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool { lock.withLock { storage } }
    func mark() { lock.withLock { storage = true } }
}

private final class FakePrivilegedFanControlHardware: PrivilegedFanControlHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var fansByID: [Int: Fan]
    private var queuedSnapshots: [[Fan]] = []
    private var applyLog: [Int] = []
    private var restoreLog: [Int] = []

    var failApplyFanID: Int?
    var failRestoreFanID: Int?
    var restoreModeByFanID: [Int: FanHardwareMode] = [:]
    var afterApply: (@Sendable (Int) -> Void)?
    var afterRestore: (@Sendable (Int) -> Void)?
    var afterSnapshot: (@Sendable () -> Void)?

    init(fans: [Fan]) {
        self.fansByID = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, $0) })
    }

    var appliedFanIDs: [Int] { lock.withLock { applyLog } }
    var restoredFanIDs: [Int] { lock.withLock { restoreLog } }

    func enqueueSnapshot(fans: [Fan]) {
        lock.withLock { queuedSnapshots.append(fans) }
    }

    func freshSnapshot() throws -> HardwareSnapshot {
        let fans = lock.withLock { () -> [Fan] in
            if !queuedSnapshots.isEmpty {
                return queuedSnapshots.removeFirst()
            }
            return fansByID.values.sorted { $0.id < $1.id }
        }
        afterSnapshot?()
        return HardwareSnapshot(
            fans: fans,
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU", celsius: 60, source: .synthetic)
            ],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }

    func applyFixedRPM(_ rpm: Int, to fan: Fan) throws -> FanMutationReceipt {
        let shouldFail = lock.withLock { () -> Bool in
            applyLog.append(fan.id)
            var updated = fansByID[fan.id] ?? fan
            updated.hardwareMode = .forced
            updated.targetRPM = rpm
            updated.currentRPM = rpm
            fansByID[fan.id] = updated
            return failApplyFanID == fan.id
        }
        afterApply?(fan.id)
        let receipt = FanMutationReceipt(
            fanID: fan.id,
            requestedMode: .forced,
            observedMode: .forced,
            observedTargetRPM: rpm,
            forceTestDisabled: true,
            recoveryConfirmed: false,
            warnings: []
        )
        if shouldFail {
            throw FanMutationError(
                code: .recoveryUnconfirmed,
                primaryError: "injected apply failure",
                cleanupErrors: [],
                receipt: receipt
            )
        }
        return receipt
    }

    func restoreOSManagedMode(for fan: Fan) throws -> FanMutationReceipt {
        let result = lock.withLock { () -> (Bool, FanHardwareMode) in
            restoreLog.append(fan.id)
            let mode = restoreModeByFanID[fan.id] ?? .automatic
            if failRestoreFanID != fan.id {
                var updated = fansByID[fan.id] ?? fan
                updated.hardwareMode = mode
                updated.targetRPM = updated.minimumRPM
                fansByID[fan.id] = updated
            }
            return (failRestoreFanID == fan.id, mode)
        }
        afterRestore?(fan.id)
        if result.0 {
            throw ViftyError.helperRejected("injected restore failure")
        }
        let isSafe = result.1 == .automatic || result.1 == .system
        return FanMutationReceipt(
            fanID: fan.id,
            requestedMode: .automatic,
            observedMode: result.1,
            observedTargetRPM: fan.minimumRPM,
            forceTestDisabled: true,
            recoveryConfirmed: isSafe,
            warnings: []
        )
    }
}
