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
        let health = AgentControlPersistenceHealth(
            policyStatusAvailable: false,
            policyError: "policy unreadable",
            auditStatusAvailable: true,
            auditError: nil
        )
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
            policy: AgentControlPolicy(enabled: true, minimumAgentRPMPercent: 40, maximumAllowedRPMPercent: 75, maxDurationSeconds: 1_800, prepareCooldownSeconds: 12).snapshot,
            persistenceHealth: health
        )

        let encoded = XPCAgentControlCoding.encode(status)
        let decoded = XPCAgentControlCoding.decodeStatus(encoded)

        XCTAssertEqual(decoded, status)
        XCTAssertEqual(decoded?.lastDecision?.retryAfterSeconds, 12)
        XCTAssertEqual(decoded?.policy?.maximumAllowedRPMPercent, 75)
    }

    func testPersistenceFailureRoundTripsThroughJSONAndXPC() throws {
        let status = AgentControlStatus(
            enabled: false,
            activeLease: nil,
            lastDecision: .denied(.persistenceFailure, message: "policy unreadable"),
            lastErrorCode: .persistenceFailure,
            policy: AgentControlPolicy(enabled: false).snapshot,
            persistenceHealth: AgentControlPersistenceHealth(
                policyStatusAvailable: false,
                policyError: "policy unreadable",
                auditStatusAvailable: true,
                auditError: nil
            )
        )

        let json = try JSONDecoder().decode(
            AgentControlStatus.self,
            from: JSONEncoder().encode(status)
        )

        XCTAssertEqual(json, status)
        XCTAssertEqual(XPCAgentControlCoding.decodeStatus(XPCAgentControlCoding.encode(status)), status)
    }

    func testOlderStatusWithoutLeaseStillDecodes() {
        let dictionary: NSDictionary = ["enabled": true]

        let decoded = XPCAgentControlCoding.decodeStatus(dictionary)

        XCTAssertEqual(decoded?.enabled, true)
        XCTAssertNil(decoded?.activeLease)
        XCTAssertNil(decoded?.lastDecision)
        XCTAssertNil(decoded?.policy)
        XCTAssertEqual(decoded?.persistenceHealth.policyStatusAvailable, false)
        XCTAssertEqual(decoded?.persistenceHealth.auditStatusAvailable, false)
        XCTAssertEqual(decoded?.persistenceHealth.policyError, "Persistence health unavailable from older daemon response.")
        XCTAssertEqual(decoded?.persistenceHealth.auditError, "Persistence health unavailable from older daemon response.")
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
