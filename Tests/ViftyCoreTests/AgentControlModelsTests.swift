import XCTest
@testable import ViftyCore

final class AgentControlModelsTests: XCTestCase {
    func testRequestDefaultsAndCodableRoundTrip() throws {
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 45 * 60,
            maxRPMPercent: 75,
            reason: "Swift release build",
            idempotencyKey: "agent-build-001"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AgentControlRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.workload.displayName, "Build")
    }

    func testLeaseComputesActiveStateFromExpiration() {
        let created = Date(timeIntervalSince1970: 1_000)
        let lease = AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Tests", idempotencyKey: "key-1"),
            createdAt: created,
            expiresAt: created.addingTimeInterval(600),
            targetRPMByFanID: [0: 3700, 1: 3900],
            restoredAt: nil
        )

        XCTAssertTrue(lease.isActive(at: created.addingTimeInterval(599)))
        XCTAssertFalse(lease.isActive(at: created.addingTimeInterval(600)))
    }

    func testAgentControlStatusIsCodable() throws {
        let status = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: AgentControlDecision.denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 20),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(AgentControlStatus.self, from: data)

        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.lastDecision?.allowed, false)
        XCTAssertEqual(decoded.lastDecision?.retryAfterSeconds, 20)
        XCTAssertEqual(decoded.policy?.prepareCooldownSeconds, 30)
    }
}
