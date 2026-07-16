import XCTest
@testable import Vifty
@testable import ViftyCore

@MainActor
final class HelperServiceManagementBridgeTests: XCTestCase {
    func testParserAcceptsOnlyExactMainExecutableBridgeArguments() throws {
        XCTAssertEqual(
            try HelperServiceManagementRequest.parse(arguments: [
                "/Applications/Vifty.app/Contents/MacOS/Vifty",
                "--helper-service-management",
                "register",
                "--json"
            ]),
            .register
        )
        XCTAssertNil(try HelperServiceManagementRequest.parse(arguments: ["Vifty"]))
        XCTAssertThrowsError(try HelperServiceManagementRequest.parse(arguments: [
            "Vifty", "--helper-service-management", "register", "--json", "extra"
        ]))
        XCTAssertThrowsError(try HelperServiceManagementRequest.parse(arguments: [
            "Vifty", "--helper-service-management", "unregister", "--json"
        ]))
        let fixedEvidencePath = HelperPrivilegedExecutionEvidence.defaultURL.path
        XCTAssertEqual(
            try HelperServiceManagementRequest.parse(arguments: [
                "Vifty", "--helper-service-management", "unregister-legacy",
                "--operation", "uninstall", "--root-record", fixedEvidencePath, "--json"
            ]),
            .unregisterLegacy(operation: .uninstall, rootRecordPath: fixedEvidencePath)
        )
        XCTAssertTrue(fixedEvidencePath.contains("/ViftyMaintenanceEvidence/"))
        XCTAssertFalse(fixedEvidencePath.contains("/Vifty/Maintenance/"))
    }

    func testRegisterRequiresEnabledReadbackAndSurfacesApproval() async throws {
        let enabled = HelperServiceBackendFixture(state: .notRegistered, stateAfterRegister: .enabled)
        let enabledReport = try await performRegister(backend: enabled)
        XCTAssertEqual(enabledReport.state, .enabled)
        XCTAssertTrue(enabledReport.complete)
        XCTAssertEqual(enabled.registerCount, 1)

        let approval = HelperServiceBackendFixture(state: .requiresApproval)
        let approvalReport = try await performRegister(backend: approval)
        XCTAssertEqual(approvalReport.state, .requiresApproval)
        XCTAssertFalse(approvalReport.complete)
        XCTAssertTrue(approvalReport.operatorActionRequired)
        XCTAssertEqual(approval.registerCount, 0)
    }

    func testUnregisterRequiresNotRegisteredReadbackAndUnknownFailsClosed() async throws {
        let report = Self.maintenanceReport()
        let token = try XCTUnwrap(report.token)
        let request = HelperServiceManagementRequest.unregister(
            operation: .uninstall,
            reportPath: "/fixture/report.json"
        )
        let authorization = HelperMaintenanceAuthorization(
            authorized: true,
            operation: .uninstall,
            tokenID: token.tokenID,
            consumedAt: Date(timeIntervalSince1970: 1_001),
            quiesced: true,
            tokenConsumed: true
        )
        let removed = HelperServiceBackendFixture(state: .enabled, stateAfterUnregister: .notRegistered)
        let removedReport = try await HelperServiceManagementBridge.perform(
            request,
            backend: removed,
            maintenanceReportReader: { _ in report },
            maintenanceAuthorizer: { _ in authorization }
        )
        XCTAssertEqual(removedReport.state, .notRegistered)
        XCTAssertTrue(removedReport.complete)
        XCTAssertEqual(removed.unregisterCount, 1)

        let stuck = HelperServiceBackendFixture(state: .enabled, stateAfterUnregister: .enabled)
        do {
            _ = try await HelperServiceManagementBridge.perform(
                request,
                backend: stuck,
                maintenanceReportReader: { _ in report },
                maintenanceAuthorizer: { _ in authorization }
            )
            XCTFail("Expected verified unregister failure")
        } catch {
            XCTAssertTrue(error is HelperServiceManagementBridgeError)
        }

        let unknown = HelperServiceBackendFixture(state: .unknown)
        do {
            _ = try await HelperServiceManagementBridge.perform(
                request,
                backend: unknown,
                maintenanceReportReader: { _ in report },
                maintenanceAuthorizer: { _ in authorization }
            )
            XCTFail("Expected unknown service state to fail closed")
        } catch {}
    }

    func testUncredentialedUnregisterCannotMutateServiceManagement() async throws {
        let backend = HelperServiceBackendFixture(state: .enabled)
        XCTAssertThrowsError(try HelperServiceManagementRequest.parse(arguments: [
            "Vifty", "--helper-service-management", "unregister", "--json"
        ]))
        XCTAssertEqual(backend.unregisterCount, 0)
    }

    func testProtocolV1BridgeOnlyUnregistersForRootOfflineRecovery() async throws {
        let backend = HelperServiceBackendFixture(state: .enabled)
        let now = Date(timeIntervalSince1970: 2_000)
        let report = try await HelperServiceManagementBridge.perform(
            .unregisterLegacy(operation: .uninstall, rootRecordPath: "/fixture/root-record.json"),
            backend: backend,
            maintenanceReportReader: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
            maintenanceAuthorizer: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
            privilegedExecutionReader: { _ in Self.privilegedEvidence(now: now) },
            now: { now },
            requestingUserID: 501,
            requestingProcessID: 42
        )
        XCTAssertTrue(report.complete)
        XCTAssertTrue(report.legacyProtocolGateUsed)
        XCTAssertFalse(report.maintenanceAuthorized)
        XCTAssertFalse(report.legacyMarkerPresent)
        XCTAssertEqual(backend.unregisterCount, 1)
    }

    func testProtocolV1DirectBridgeMisuseWithoutRootEvidenceCannotUnregister() async throws {
        XCTAssertThrowsError(try HelperServiceManagementRequest.parse(arguments: [
            "Vifty", "--helper-service-management", "unregister-legacy",
            "--operation", "uninstall", "--json"
        ]))
        XCTAssertThrowsError(try HelperServiceManagementRequest.parse(arguments: [
            "Vifty", "--helper-service-management", "unregister-legacy",
            "--operation", "repair", "--root-record", "/tmp/record", "--json"
        ]))

        let backend = HelperServiceBackendFixture(state: .enabled)
        do {
            _ = try await HelperServiceManagementBridge.perform(
                .unregisterLegacy(operation: .uninstall, rootRecordPath: "/fixture/root-record.json"),
                backend: backend,
                maintenanceReportReader: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
                maintenanceAuthorizer: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
                privilegedExecutionReader: { _ in
                    var evidence = Self.privilegedEvidence(now: Date(timeIntervalSince1970: 2_000))
                    evidence.status = "in-progress"
                    return evidence
                },
                now: { Date(timeIntervalSince1970: 2_000) },
                requestingUserID: 501,
                requestingProcessID: 42
            )
            XCTFail("Unfinished root evidence must not authorize unregister")
        } catch {}
        XCTAssertEqual(backend.unregisterCount, 0)

        let replayBackend = HelperServiceBackendFixture(state: .enabled)
        do {
            _ = try await HelperServiceManagementBridge.perform(
                .unregisterLegacy(operation: .uninstall, rootRecordPath: "/fixture/root-record.json"),
                backend: replayBackend,
                maintenanceReportReader: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
                maintenanceAuthorizer: { _ in throw HelperServiceManagementBridgeError.invalidArguments },
                privilegedExecutionReader: { _ in
                    Self.privilegedEvidence(now: Date(timeIntervalSince1970: 2_000))
                },
                now: { Date(timeIntervalSince1970: 2_000) },
                requestingUserID: 501,
                requestingProcessID: 43
            )
            XCTFail("A valid record from another lifecycle parent process must not replay")
        } catch {}
        XCTAssertEqual(replayBackend.unregisterCount, 0)
    }

    private func performRegister(
        backend: any HelperServiceManagementBackend
    ) async throws -> HelperServiceManagementReport {
        try await HelperServiceManagementBridge.perform(
            .register,
            backend: backend,
            maintenanceReportReader: { _ in
                throw HelperServiceManagementBridgeError.invalidArguments
            },
            maintenanceAuthorizer: { _ in
                throw HelperServiceManagementBridgeError.invalidArguments
            }
        )
    }

    private static func maintenanceReport() -> HelperMaintenanceReport {
        let issuedAt = Date(timeIntervalSince1970: 1_000)
        let token = HelperMaintenanceToken(
            tokenID: "fixture-token",
            operation: .uninstall,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(30),
            bootSessionID: "boot",
            daemonSessionID: "daemon",
            journalGeneration: 2,
            expectedFanIDs: [0, 1],
            helperSHA256: String(repeating: "a", count: 64),
            quiesceGeneration: 1
        )
        return HelperMaintenanceReport(
            operation: .uninstall,
            safeToStop: true,
            quiesced: true,
            restoreAttempted: true,
            restoreSucceeded: true,
            completeExpectedSetConfirmed: true,
            fanResults: [],
            blockers: [],
            token: token
        )
    }

    nonisolated private static func privilegedEvidence(
        now: Date
    ) -> HelperPrivilegedExecutionEvidence {
        HelperPrivilegedExecutionEvidence(
            schemaVersion: 1,
            schemaID: HelperPrivilegedExecutionEvidence.schemaID,
            operation: .uninstall,
            status: "completed",
            blocker: "",
            authorityMode: "offline-auto",
            requestingUserID: 501,
            requestingProcessID: 42,
            updatedAt: now,
            phases: [
                .init(phase: "verify-privileged-authority", attempted: true, succeeded: true),
                .init(phase: "disable-service-and-confirm-offline", attempted: true, succeeded: true),
                .init(phase: "post-freeze-offline-auto-confirm", attempted: true, succeeded: true),
                .init(phase: "remove-legacy-helper-plist-and-logs", attempted: true, succeeded: true)
            ]
        )
    }

}

@MainActor
private final class HelperServiceBackendFixture: HelperServiceManagementBackend {
    var state: HelperServiceRegistrationState
    let stateAfterRegister: HelperServiceRegistrationState
    let stateAfterUnregister: HelperServiceRegistrationState
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(
        state: HelperServiceRegistrationState,
        stateAfterRegister: HelperServiceRegistrationState = .enabled,
        stateAfterUnregister: HelperServiceRegistrationState = .notRegistered
    ) {
        self.state = state
        self.stateAfterRegister = stateAfterRegister
        self.stateAfterUnregister = stateAfterUnregister
    }

    func register() throws {
        registerCount += 1
        state = stateAfterRegister
    }

    func unregister() async throws {
        unregisterCount += 1
        state = stateAfterUnregister
    }
}
