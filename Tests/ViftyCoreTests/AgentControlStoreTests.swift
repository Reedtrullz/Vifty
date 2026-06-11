import XCTest
@testable import ViftyCore

final class AgentControlStoreTests: XCTestCase {
    func testSaveAndLoadActiveLease() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let lease = makeLease()

        try store.saveActiveLease(lease)

        XCTAssertEqual(try store.loadActiveLease(), lease)
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

    func testExistingAuditFilePermissionsAreRestrictedAfterAppend() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let auditURL = directory.appendingPathComponent("audit.jsonl")
        try Data("legacy\n".utf8).write(to: auditURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: auditURL.path)

        let store = AgentControlStore(directory: directory)
        try store.appendAuditEvent(makeAuditEvent())

        let attributes = try FileManager.default.attributesOfItem(atPath: auditURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-store-\(UUID().uuidString)", isDirectory: true)
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
}
