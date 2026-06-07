import XCTest
@testable import ViftyCore

final class AgentControlStoreTests: XCTestCase {
    func testSaveAndLoadActiveLease() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let lease = AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 1_600),
            targetRPMByFanID: [0: 3600]
        )

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

    func testDirectoryIsCreatedWithRestrictedPermissions() throws {
        let tempDir = temporaryDirectory()
        let store = AgentControlStore(directory: tempDir)
        try store.saveActiveLease(nil) // triggers createDirectoryIfNeeded

        let attributes = try FileManager.default.attributesOfItem(atPath: tempDir.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-store-\(UUID().uuidString)", isDirectory: true)
    }
}
