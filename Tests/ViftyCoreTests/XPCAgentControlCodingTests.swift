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
            lastDecision: .allowed(targetRPMByFanID: [0: 3600]),
            lastErrorCode: nil
        )

        let encoded = XPCAgentControlCoding.encode(status)
        let decoded = XPCAgentControlCoding.decodeStatus(encoded)

        XCTAssertEqual(decoded, status)
    }

    func testOlderStatusWithoutLeaseStillDecodes() {
        let dictionary: NSDictionary = ["enabled": true]

        let decoded = XPCAgentControlCoding.decodeStatus(dictionary)

        XCTAssertEqual(decoded?.enabled, true)
        XCTAssertNil(decoded?.activeLease)
        XCTAssertNil(decoded?.lastDecision)
    }
}
