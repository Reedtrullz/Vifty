import Darwin
import XCTest
@testable import ViftyCore

final class AgentControlStoreTests: XCTestCase {
    func testSaveAndLoadActiveLease() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let lease = makeLease()

        try store.saveActiveLease(lease)

        XCTAssertEqual(try store.loadActiveLease(), lease)

        let data = try Data(contentsOf: directory.appendingPathComponent("active-lease.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AgentControlStore.activeLeaseSchemaVersion)
        XCTAssertEqual(object["kind"] as? String, "tech.reidar.vifty.agent-control.active-lease")
        XCTAssertNotNil(object["lease"] as? [String: Any])
    }

    func testAppendAuditEventWritesJSONLine() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)

        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_000), action: "prepare", leaseID: "lease-1", message: "applied"))

        let contents = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(contents.contains("\"action\":\"prepare\""))
        XCTAssertTrue(contents.hasSuffix("\n"))
    }

    func testAuditLogTrimsOldestEventsToRetentionLimit() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory, maximumAuditEvents: 2)

        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_000), action: "old", leaseID: "lease-1", message: "old"))
        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_001), action: "middle", leaseID: "lease-2", message: "middle"))
        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_002), action: "new", leaseID: "lease-3", message: "new"))

        let contents = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        let lines = contents.split(separator: "\n")

        XCTAssertEqual(lines.count, 2)
        XCTAssertFalse(contents.contains("\"action\":\"old\""))
        XCTAssertTrue(contents.contains("\"action\":\"middle\""))
        XCTAssertTrue(contents.contains("\"action\":\"new\""))
        XCTAssertTrue(contents.hasSuffix("\n"))
    }

    func testLoadRecentAuditEventsReturnsNewestEventsWithinLimit() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory, maximumAuditEvents: 5)

        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_000), action: "old", leaseID: "lease-1", message: "old"))
        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_001), action: "middle", leaseID: nil, message: "middle"))
        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_002), action: "new", leaseID: "lease-3", message: "new"))

        let events = try store.loadRecentAuditEvents(limit: 2)

        XCTAssertEqual(events.map(\.action), ["middle", "new"])
        XCTAssertNil(events.first?.leaseID)
        XCTAssertEqual(events.last?.leaseID, "lease-3")
    }

    func testLoadRecentAuditEventsReturnsEmptyWhenAuditFileIsMissing() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)

        XCTAssertEqual(try store.loadRecentAuditEvents(limit: 20), [])
    }

    func testDirectoryIsCreatedWithRestrictedPermissions() throws {
        let tempDir = temporaryDirectory()
        let store = AgentControlStore(directory: tempDir)
        try store.saveActiveLease(nil) // triggers createDirectoryIfNeeded

        let attributes = try FileManager.default.attributesOfItem(atPath: tempDir.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
    }

    func testActiveLeaseFileIsCreatedWithRestrictedPermissions() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)

        try store.saveActiveLease(makeLease())

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("active-lease.json").path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testAuditFileIsCreatedWithRestrictedPermissions() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)

        try store.appendAuditEvent(makeAuditEvent())

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("audit.jsonl").path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testExistingAuditFileWithUnsafePermissionsIsRejectedWithoutRepair() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directory.path)
        let auditURL = directory.appendingPathComponent("audit.jsonl")
        try Data("legacy\n".utf8).write(to: auditURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: auditURL.path)

        let store = AgentControlStore(directory: directory)
        XCTAssertThrowsError(try store.appendAuditEvent(makeAuditEvent())) { error in
            guard case .unsafePath = error as? AgentControlStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: auditURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o644)
    }

    func testLegacyRawLeaseJSONIsNeverAcceptedAsActiveAuthority() throws {
        let directory = temporaryDirectory()
        try Self.preparePrivateDirectory(directory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let leaseURL = directory.appendingPathComponent("active-lease.json")
        try encoder.encode(makeLease()).write(to: leaseURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)

        let store = AgentControlStore(directory: directory)

        XCTAssertThrowsError(try store.loadActiveLease()) { error in
            guard case .invalidActiveLease(let reason) = error as? AgentControlStoreError else {
                return XCTFail("Expected invalidActiveLease, got \(error)")
            }
            XCTAssertTrue(reason.contains("legacy JSON is untrusted"))
        }
    }

    func testUnknownLeaseEnvelopeAndOversizedLeaseFailClosed() throws {
        let directory = temporaryDirectory()
        try Self.preparePrivateDirectory(directory)
        let leaseURL = directory.appendingPathComponent("active-lease.json")
        try Data(#"{"schemaVersion":99,"kind":"tech.reidar.vifty.agent-control.active-lease","lease":{}}"#.utf8)
            .write(to: leaseURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
        let store = AgentControlStore(directory: directory)

        XCTAssertThrowsError(try store.loadActiveLease()) { error in
            XCTAssertEqual(error as? AgentControlStoreError, .unsupportedLeaseSchemaVersion(99))
        }

        try Data(repeating: UInt8(ascii: "x"), count: AgentControlStore.maximumActiveLeaseBytes + 1)
            .write(to: leaseURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
        XCTAssertThrowsError(try store.loadActiveLease()) { error in
            guard case .invalidActiveLease(let reason) = error as? AgentControlStoreError else {
                return XCTFail("Expected invalidActiveLease, got \(error)")
            }
            XCTAssertTrue(reason.contains("encoded size exceeds"))
        }
    }

    func testIntermediateSymlinkAndUnsafeLeaseEntriesAreRejected() throws {
        let root = temporaryDirectory()
        try Self.preparePrivateDirectory(root)
        let realParent = root.appendingPathComponent("real", isDirectory: true)
        try Self.preparePrivateDirectory(realParent)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realParent)
        let linkedStore = AgentControlStore(directory: alias.appendingPathComponent("store", isDirectory: true))
        XCTAssertThrowsError(try linkedStore.saveActiveLease(makeLease())) { error in
            guard case .unsafePath = error as? AgentControlStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }

        let storeDirectory = root.appendingPathComponent("store", isDirectory: true)
        try Self.preparePrivateDirectory(storeDirectory)
        let target = storeDirectory.appendingPathComponent("target")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: target.path,
            contents: Data("target".utf8),
            attributes: [.posixPermissions: 0o600]
        ))
        let leaseURL = storeDirectory.appendingPathComponent("active-lease.json")
        XCTAssertEqual(link(target.path, leaseURL.path), 0)
        let hardLinkedStore = AgentControlStore(directory: storeDirectory)
        XCTAssertThrowsError(try hardLinkedStore.loadActiveLease()) { error in
            guard case .unsafePath = error as? AgentControlStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }

        XCTAssertEqual(unlink(leaseURL.path), 0)
        try FileManager.default.createSymbolicLink(at: leaseURL, withDestinationURL: target)
        let symlinkStore = AgentControlStore(directory: storeDirectory)
        XCTAssertThrowsError(try symlinkStore.loadActiveLease()) { error in
            guard case .unsafePath = error as? AgentControlStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testRetainedDirectoryAnchorRejectsRuntimeReplacement() throws {
        let root = temporaryDirectory()
        try Self.preparePrivateDirectory(root)
        let directory = root.appendingPathComponent("store", isDirectory: true)
        let movedDirectory = root.appendingPathComponent("moved", isDirectory: true)
        let store = AgentControlStore(directory: directory)
        try store.saveActiveLease(makeLease())

        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try Self.preparePrivateDirectory(directory)

        XCTAssertThrowsError(try store.loadActiveLease()) { error in
            guard case .unsafePath = error as? AgentControlStoreError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testLeaseReplacementSynchronizationFailurePreservesPreviousEnvelope() throws {
        let directory = temporaryDirectory()
        let original = makeLease()
        let liveStore = AgentControlStore(directory: directory)
        try liveStore.saveActiveLease(original)
        let points = LockedSecureStoragePoints()
        let failingStore = AgentControlStore(
            directory: directory,
            hooks: SecureStorageDurabilityHooks { descriptor, point in
                points.append(point)
                if point == .temporaryFile {
                    throw AgentControlStoreError.ioFailure("injected file sync failure")
                }
                guard fsync(descriptor) == 0 else {
                    throw AgentControlStoreError.ioFailure("unexpected fsync failure")
                }
            }
        )
        var replacement = original
        replacement.targetRPMByFanID = [0: 4_000]

        XCTAssertThrowsError(try failingStore.saveActiveLease(replacement))
        XCTAssertEqual(try liveStore.loadActiveLease(), original)
        XCTAssertEqual(points.values, [.temporaryFile])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .allSatisfy { !$0.hasSuffix(".tmp") })
    }

    func testLeaseDeleteSynchronizesDirectoryAndReportsFailure() throws {
        let directory = temporaryDirectory()
        let liveStore = AgentControlStore(directory: directory)
        try liveStore.saveActiveLease(makeLease())
        let points = LockedSecureStoragePoints()
        let failingStore = AgentControlStore(
            directory: directory,
            hooks: SecureStorageDurabilityHooks { _, point in
                points.append(point)
                if point == .directoryAfterDelete {
                    throw AgentControlStoreError.ioFailure("injected directory sync failure")
                }
            }
        )

        XCTAssertThrowsError(try failingStore.saveActiveLease(nil))
        XCTAssertEqual(points.values, [.directoryAfterDelete])
    }

    private func temporaryDirectory() -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("agent-store-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func makeLease() -> AgentCoolingLease {
        AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 1_600),
            targetRPMByFanID: [0: 3600]
        )
    }

    private func makeAuditEvent() -> AgentControlAuditEvent {
        AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_000), action: "prepare", leaseID: "lease-1", message: "applied")
    }

    private static func preparePrivateDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }
}

private final class LockedSecureStoragePoints: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecureStorageSyncPoint] = []

    var values: [SecureStorageSyncPoint] {
        lock.withLock { storage }
    }

    func append(_ value: SecureStorageSyncPoint) {
        lock.withLock { storage.append(value) }
    }
}
