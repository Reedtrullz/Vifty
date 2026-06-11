import XCTest
@testable import ViftyCore

final class XPCAgentControlCodingTests: XCTestCase {
    func testRequestRoundTripsThroughNSDictionary() {
        let request = AgentControlRequest(workload: .build, durationSeconds: 1200, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key-1")

        let encoded = XPCAgentControlCoding.encode(request)
        let decoded = XPCAgentControlCoding.decodeRequest(encoded)

        XCTAssertEqual(decoded, request)
    }

    func testStatusRoundTripsThroughNSDictionary() {
        let created = Date(timeIntervalSince1970: 1_000)
        let status = AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-1",
                request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Tests", idempotencyKey: "key-2"),
                createdAt: created,
                expiresAt: created.addingTimeInterval(600),
                targetRPMByFanID: [0: 3600]
            ),
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 12),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, minimumAgentRPMPercent: 40, maximumAllowedRPMPercent: 75, maxDurationSeconds: 1_800, prepareCooldownSeconds: 12).snapshot
        )

        let encoded = XPCAgentControlCoding.encode(status)
        let decoded = XPCAgentControlCoding.decodeStatus(encoded)

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded?.lastDecision?.retryAfterSeconds, 12)
        XCTAssertEqual(decoded?.policy?.maximumAllowedRPMPercent, 75)
    }

    func testOlderStatusWithoutLeaseStillDecodes() {
        let dictionary: NSDictionary = ["enabled": true]

        let decoded = XPCAgentControlCoding.decodeStatus(dictionary)

        XCTAssertEqual(decoded?.enabled, true)
        XCTAssertNil(decoded?.activeLease)
        XCTAssertNil(decoded?.lastDecision)
        XCTAssertNil(decoded?.policy)
    }

    func testAuditEventsRoundTripThroughNSDictionary() {
        let events = [
            AgentControlAuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_000),
                action: "prepare",
                leaseID: "lease-1",
                message: "Swift build"
            ),
            AgentControlAuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_001),
                action: "restore-auto",
                leaseID: nil,
                message: "done"
            )
        ]

        let encoded = XPCAgentControlCoding.encodeAuditEvents(events)
        let decoded = XPCAgentControlCoding.decodeAuditEvents(encoded)

        XCTAssertEqual(decoded, events)
    }
}
