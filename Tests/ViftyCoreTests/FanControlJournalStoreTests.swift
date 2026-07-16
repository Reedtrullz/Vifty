import Darwin
import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyFanControlSafety

final class FanControlJournalStoreTests: XCTestCase {
    func testAtomicRoundTripUsesStableTaggedOwnerAndPrivatePermissions() throws {
        try withStore { store in
            let record = Self.record(
                owner: .manual(sessionID: "manual-session"),
                expectedFanIDs: [1, 0],
                appliedFanIDs: [1]
            )

            try store.save(record)

            XCTAssertEqual(try store.load(), record)
            let data = try Data(contentsOf: store.journalURL)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let owner = try XCTUnwrap(object["owner"] as? [String: Any])
            XCTAssertEqual(owner["type"] as? String, "manual")
            XCTAssertEqual(owner["sessionID"] as? String, "manual-session")
            XCTAssertNil(owner["leaseID"])
            XCTAssertEqual(try Self.mode(of: store.directoryURL), 0o700)
            XCTAssertEqual(try Self.mode(of: store.journalURL), 0o600)
        }
    }

    func testExpectedFanSetCannotShrinkWithinTransaction() throws {
        try withStore { store in
            try store.save(Self.record(expectedFanIDs: [0, 1]))

            XCTAssertThrowsError(try store.save(Self.record(expectedFanIDs: [0]))) { error in
                XCTAssertEqual(error as? FanControlJournalStoreError, .expectedFanSetShrank)
            }
            XCTAssertEqual(try store.load()?.expectedFanIDs, [0, 1])
        }
    }

    func testUnresolvedTransactionCannotBeOverwritten() throws {
        try withStore { store in
            try store.save(Self.record(transactionID: "first"))

            XCTAssertThrowsError(try store.save(Self.record(transactionID: "second"))) { error in
                XCTAssertEqual(
                    error as? FanControlJournalStoreError,
                    .unresolvedTransactionExists("first")
                )
            }
            XCTAssertEqual(try store.load()?.transactionID, "first")
        }
    }

    func testFileSynchronizationFailureLeavesPreviousRecordIntact() throws {
        try withStore { liveStore in
            let original = Self.record(expectedFanIDs: [0])
            try liveStore.save(original)
            let failingStore = FanControlJournalStore(
                directoryURL: liveStore.directoryURL,
                requiredOwnerID: geteuid(),
                hooks: FanControlJournalDurabilityHooks { descriptor, point in
                    if point == .temporaryFile {
                        throw FanControlJournalStoreError.ioFailure("injected fsync failure")
                    }
                    guard fsync(descriptor) == 0 else {
                        throw FanControlJournalStoreError.ioFailure("unexpected fsync failure")
                    }
                }
            )

            XCTAssertThrowsError(
                try failingStore.save(Self.record(expectedFanIDs: [0, 1]))
            )
            XCTAssertEqual(try liveStore.load(), original)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: liveStore.directoryURL.path)
                .allSatisfy { !$0.hasSuffix(".tmp") })
        }
    }

    func testCorruptAndUnknownSchemaDataFailClosedWithoutReplacement() throws {
        try withStore { store in
            try Self.writeUnsafeFixture(Data("not-json".utf8), to: store)
            XCTAssertThrowsError(try store.load()) { error in
                guard case FanControlJournalStoreError.invalidRecord = error else {
                    return XCTFail("Expected invalidRecord, got \(error)")
                }
            }

            let future = Data(#"{"schemaVersion":99,"transactionID":"future"}"#.utf8)
            try future.write(to: store.journalURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.journalURL.path)
            XCTAssertThrowsError(try store.load()) { error in
                XCTAssertEqual(error as? FanControlJournalStoreError, .unsupportedSchemaVersion(99))
            }
            XCTAssertEqual(try Data(contentsOf: store.journalURL), future)
        }
    }

    func testAuthorizedRecoveryPreservesCorruptBytesBeforeReplacingPrimary() throws {
        try withStore { store in
            let corrupt = Data("not-json".utf8)
            try Self.writeUnsafeFixture(corrupt, to: store)
            let recovery = Self.record(
                transactionID: "recovery",
                owner: .recovery,
                expectedFanIDs: [0, 1],
                phase: .restoring
            )

            try store.replaceUnreadableForAuthorizedRecovery(with: recovery)

            XCTAssertEqual(try store.load(), recovery)
            XCTAssertEqual(try Data(contentsOf: store.preservedUnreadableJournalURL), corrupt)
            XCTAssertEqual(try Self.mode(of: store.preservedUnreadableJournalURL), 0o600)
        }
    }

    func testAuthorizedRecoveryPreservesFutureSchemaAndAllowsIdempotentRetry() throws {
        try withStore { store in
            let future = Data(#"{"schemaVersion":99,"transactionID":"future"}"#.utf8)
            try Self.writeUnsafeFixture(future, to: store)
            let recovery = Self.record(
                transactionID: "recovery",
                owner: .recovery,
                expectedFanIDs: [0, 1],
                phase: .restoring
            )

            try store.replaceUnreadableForAuthorizedRecovery(with: recovery)
            XCTAssertEqual(try Data(contentsOf: store.preservedUnreadableJournalURL), future)

            try Self.writeUnsafeFixture(future, to: store)
            try store.replaceUnreadableForAuthorizedRecovery(with: recovery)
            XCTAssertEqual(try store.load(), recovery)
            XCTAssertEqual(try Data(contentsOf: store.preservedUnreadableJournalURL), future)
        }
    }

    func testAuthorizedRecoveryStreamsAndPreservesOversizedJournal() throws {
        try withStore { store in
            let oversized = Data(
                repeating: 0x41,
                count: FanControlJournalStore.maximumJournalBytes + 1
            )
            try Self.writeUnsafeFixture(oversized, to: store)
            XCTAssertThrowsError(try store.load()) { error in
                guard case .invalidRecord = error as? FanControlJournalStoreError else {
                    return XCTFail("Expected oversized invalid record, got \(error)")
                }
            }
            let recovery = Self.record(
                transactionID: "oversized-recovery",
                owner: .recovery,
                expectedFanIDs: [0, 1],
                phase: .restoring
            )

            try store.replaceUnreadableForAuthorizedRecovery(with: recovery)

            XCTAssertEqual(try store.load(), recovery)
            XCTAssertEqual(
                try Data(contentsOf: store.preservedUnreadableJournalURL),
                oversized
            )
        }
    }

    func testAuthorizedRecoveryRefusesReadableJournalAndRotatesOlderPreservedIncident() throws {
        try withStore { store in
            let recovery = Self.record(
                transactionID: "recovery",
                owner: .recovery,
                expectedFanIDs: [0],
                phase: .restoring
            )
            try store.save(Self.record())
            XCTAssertThrowsError(
                try store.replaceUnreadableForAuthorizedRecovery(with: recovery)
            ) { error in
                guard case .unreadableRecoveryNotAllowed = error as? FanControlJournalStoreError else {
                    return XCTFail("Expected readable-journal refusal, got \(error)")
                }
            }

            let corrupt = Data("corrupt-primary".utf8)
            try Self.writeUnsafeFixture(corrupt, to: store)
            try Data("different-preserved-record".utf8).write(
                to: store.preservedUnreadableJournalURL
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: store.preservedUnreadableJournalURL.path
            )
            try store.replaceUnreadableForAuthorizedRecovery(with: recovery)

            XCTAssertEqual(try store.load(), recovery)
            XCTAssertEqual(try Data(contentsOf: store.preservedUnreadableJournalURL), corrupt)
        }
    }

    func testAuthorizedRecoveryPrimarySyncFailureLeavesCorruptPrimaryAndPreservedCopy() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let liveStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        let corrupt = Data("not-json".utf8)
        try Self.writeUnsafeFixture(corrupt, to: liveStore)
        let temporarySyncs = LockedSyncPoints()
        let failingStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { descriptor, point in
                temporarySyncs.append(point)
                let temporaryCount = temporarySyncs.values.filter { $0 == .temporaryFile }.count
                if point == .temporaryFile, temporaryCount == 2 {
                    throw FanControlJournalStoreError.ioFailure("injected replacement sync failure")
                }
                guard fsync(descriptor) == 0 else {
                    throw FanControlJournalStoreError.ioFailure("unexpected fsync failure")
                }
            }
        )
        let recovery = Self.record(
            transactionID: "recovery",
            owner: .recovery,
            expectedFanIDs: [0, 1],
            phase: .restoring
        )

        XCTAssertThrowsError(
            try failingStore.replaceUnreadableForAuthorizedRecovery(with: recovery)
        )
        XCTAssertEqual(try Data(contentsOf: liveStore.journalURL), corrupt)
        XCTAssertEqual(try Data(contentsOf: liveStore.preservedUnreadableJournalURL), corrupt)
    }

    func testAuthorizedRecoveryConvergesAfterPreservationDirectorySyncFailure() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let liveStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        let corrupt = Data("directory-sync-preservation".utf8)
        try Self.writeUnsafeFixture(corrupt, to: liveStore)
        let syncPoints = LockedSyncPoints()
        let failingStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { descriptor, point in
                syncPoints.append(point)
                if point == .directoryAfterReplace,
                   syncPoints.values.filter({ $0 == .directoryAfterReplace }).count == 1 {
                    throw FanControlJournalStoreError.ioFailure(
                        "injected preservation directory sync failure"
                    )
                }
                guard fsync(descriptor) == 0 else {
                    throw FanControlJournalStoreError.ioFailure("unexpected fsync failure")
                }
            }
        )
        let recovery = Self.record(
            transactionID: "recovery-after-preservation-sync",
            owner: .recovery,
            expectedFanIDs: [0, 1],
            phase: .restoring
        )

        XCTAssertThrowsError(
            try failingStore.replaceUnreadableForAuthorizedRecovery(with: recovery)
        )
        XCTAssertEqual(try Data(contentsOf: liveStore.journalURL), corrupt)
        XCTAssertEqual(try Data(contentsOf: liveStore.preservedUnreadableJournalURL), corrupt)

        let reopened = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        try reopened.replaceUnreadableForAuthorizedRecovery(with: recovery)
        XCTAssertEqual(try reopened.load(), recovery)
    }

    func testAuthorizedRecoveryExposesCommittedRecordAfterPrimaryDirectorySyncFailure() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let liveStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        let corrupt = Data("directory-sync-primary".utf8)
        try Self.writeUnsafeFixture(corrupt, to: liveStore)
        let syncPoints = LockedSyncPoints()
        let failingStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { descriptor, point in
                syncPoints.append(point)
                if point == .directoryAfterReplace,
                   syncPoints.values.filter({ $0 == .directoryAfterReplace }).count == 2 {
                    throw FanControlJournalStoreError.ioFailure(
                        "injected primary directory sync failure"
                    )
                }
                guard fsync(descriptor) == 0 else {
                    throw FanControlJournalStoreError.ioFailure("unexpected fsync failure")
                }
            }
        )
        let recovery = Self.record(
            transactionID: "recovery-after-primary-sync",
            owner: .recovery,
            expectedFanIDs: [0, 1],
            phase: .restoring
        )

        XCTAssertThrowsError(
            try failingStore.replaceUnreadableForAuthorizedRecovery(with: recovery)
        )

        let reopened = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        XCTAssertEqual(try reopened.load(), recovery)
        XCTAssertEqual(try Data(contentsOf: reopened.preservedUnreadableJournalURL), corrupt)
        try reopened.clear()
        XCTAssertNil(try reopened.load())
    }

    func testSymlinkDirectoryAndHardLinkedJournalAreRejected() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realDirectory = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: realDirectory.path)
        let linkedDirectory = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        let linkedStore = FanControlJournalStore(directoryURL: linkedDirectory, requiredOwnerID: geteuid())

        XCTAssertThrowsError(try linkedStore.save(Self.record())) { error in
            guard case FanControlJournalStoreError.unsafePath = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }

        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("store", isDirectory: true),
            requiredOwnerID: geteuid()
        )
        try store.save(Self.record())
        let secondLink = store.directoryURL.appendingPathComponent("second-link.json")
        XCTAssertEqual(link(store.journalURL.path, secondLink.path), 0)
        XCTAssertThrowsError(try store.load()) { error in
            guard case FanControlJournalStoreError.unsafePath = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testIntermediateDirectorySymlinkIsRejectedWithoutCreatingJournal() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realParent = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realParent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: realParent.path)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realParent)
        let store = FanControlJournalStore(
            directoryURL: alias.appendingPathComponent("journal", isDirectory: true),
            requiredOwnerID: geteuid()
        )

        XCTAssertThrowsError(try store.save(Self.record())) { error in
            guard case .unsafePath = error as? FanControlJournalStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: realParent.appendingPathComponent("journal/transaction-v2.json").path
        ))
    }

    func testRetainedDirectoryAnchorRejectsRuntimeDirectoryReplacement() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let movedDirectory = root.appendingPathComponent("moved", isDirectory: true)
        let store = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        try store.save(Self.record())

        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try store.load()) { error in
            guard case .unsafePath = error as? FanControlJournalStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.save(Self.record())) { error in
            guard case .unsafePath = error as? FanControlJournalStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testWrongOwnerAndModeAreRejected() throws {
        try withStore { store in
            try store.save(Self.record())
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.journalURL.path)
            XCTAssertThrowsError(try store.load())
        }

        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("owner", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let wrongOwnerStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid() &+ 1
        )
        XCTAssertThrowsError(try wrongOwnerStore.save(Self.record())) { error in
            guard case FanControlJournalStoreError.unsafePath = error else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testClearRemovesJournalAndSynchronizesDirectory() throws {
        let points = LockedSyncPoints()
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FanControlJournalStore(
            directoryURL: root.appendingPathComponent("store", isDirectory: true),
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { descriptor, point in
                points.append(point)
                guard fsync(descriptor) == 0 else {
                    throw FanControlJournalStoreError.ioFailure("fsync failed")
                }
            }
        )
        try store.save(Self.record())

        try store.clear()

        XCTAssertNil(try store.load())
        XCTAssertTrue(points.values.contains(.directoryAfterClear))
    }

    func testClearSynchronizationFailureIsReported() throws {
        let points = LockedSyncPoints()
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let liveStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )
        try liveStore.save(Self.record())
        let failingStore = FanControlJournalStore(
            directoryURL: directory,
            requiredOwnerID: geteuid(),
            hooks: FanControlJournalDurabilityHooks { _, point in
                points.append(point)
                if point == .directoryAfterClear {
                    throw FanControlJournalStoreError.ioFailure("injected directory sync failure")
                }
            }
        )

        XCTAssertThrowsError(try failingStore.clear()) { error in
            guard case .ioFailure(let reason) = error as? FanControlJournalStoreError else {
                return XCTFail("Expected ioFailure, got \(error)")
            }
            XCTAssertTrue(reason.contains("injected directory sync failure"))
        }
        XCTAssertEqual(points.values, [.directoryAfterClear])
    }

    func testDanglingJournalSymlinkIsRejectedByLoadSaveAndClearWithoutReplacement() throws {
        try withStore { store in
            try FileManager.default.createDirectory(
                at: store.directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: store.directoryURL.path
            )
            try FileManager.default.createSymbolicLink(
                at: store.journalURL,
                withDestinationURL: store.directoryURL.appendingPathComponent("missing-target")
            )

            let operations: [() throws -> Void] = [
                { _ = try store.load() },
                { try store.save(Self.record()) },
                { try store.clear() }
            ]
            for operation in operations {
                XCTAssertThrowsError(try operation()) { error in
                    guard case FanControlJournalStoreError.unsafePath = error else {
                        return XCTFail("Expected unsafePath, got \(error)")
                    }
                }
                var metadata = stat()
                XCTAssertEqual(lstat(store.journalURL.path, &metadata), 0)
                XCTAssertEqual(metadata.st_mode & S_IFMT, S_IFLNK)
            }
        }
    }

    func testOversizedJournalIsRejectedBeforeDecoding() throws {
        try withStore { store in
            try Self.writeUnsafeFixture(
                Data(repeating: UInt8(ascii: "x"), count: FanControlJournalStore.maximumJournalBytes + 1),
                to: store
            )

            XCTAssertThrowsError(try store.load()) { error in
                guard case .invalidRecord(let reason) = error as? FanControlJournalStoreError else {
                    return XCTFail("Expected invalidRecord, got \(error)")
                }
                XCTAssertTrue(reason.contains("encoded size exceeds"))
            }
        }
    }

    func testBlankOwnerIDsAndInvalidOwnerPhaseShapesAreRejectedOnLoad() throws {
        let corruptRecords = [
            Self.record(owner: .manual(sessionID: " \t")),
            Self.record(owner: .agent(leaseID: "\n")),
            Self.record(owner: .manual(sessionID: "manual"), phase: .restorePending),
            Self.record(owner: .agent(leaseID: "lease"), phase: .restoring),
            Self.record(owner: .recovery, phase: .active)
        ]

        for corruptRecord in corruptRecords {
            try withStore { store in
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .secondsSince1970
                try Self.writeUnsafeFixture(try encoder.encode(corruptRecord), to: store)

                XCTAssertThrowsError(try store.load()) { error in
                    guard case FanControlJournalStoreError.invalidRecord = error else {
                        return XCTFail("Expected invalidRecord, got \(error)")
                    }
                }
            }
        }
    }

    private func withStore(_ body: (FanControlJournalStore) throws -> Void) throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try body(FanControlJournalStore(
            directoryURL: root.appendingPathComponent("store", isDirectory: true),
            requiredOwnerID: geteuid()
        ))
    }

    private static func record(
        transactionID: String = "transaction",
        owner: FanControlOwner = .manual(sessionID: "session"),
        expectedFanIDs: [Int] = [0],
        appliedFanIDs: [Int] = [],
        phase: FanControlPhase = .prepared
    ) -> FanControlJournalRecord {
        FanControlJournalRecord(
            transactionID: transactionID,
            owner: owner,
            phase: phase,
            expectedFanIDs: expectedFanIDs,
            targetRPMByFanID: Dictionary(uniqueKeysWithValues: expectedFanIDs.map { ($0, 3_200 + $0 * 100) }),
            appliedFanIDs: appliedFanIDs,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 101)
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeUnsafeFixture(_ data: Data, to store: FanControlJournalStore) throws {
        try FileManager.default.createDirectory(at: store.directoryURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.directoryURL.path)
        try data.write(to: store.journalURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.journalURL.path)
    }

    private static func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private final class LockedSyncPoints: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FanControlJournalSyncPoint] = []

    var values: [FanControlJournalSyncPoint] {
        lock.withLock { storage }
    }

    func append(_ value: FanControlJournalSyncPoint) {
        lock.withLock { storage.append(value) }
    }
}
