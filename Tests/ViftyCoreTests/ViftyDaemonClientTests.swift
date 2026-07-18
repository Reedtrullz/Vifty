import Darwin
import XCTest
@testable import ViftyCore

final class ViftyDaemonClientTests: XCTestCase {
    func testHelperMaintenancePrepareSendsExactCanonicalCandidateDigest() async throws {
        let expectedDigest = String(repeating: "c", count: 64)
        let proxy = FakeDaemonProxy()
        proxy.prepareHelperMaintenanceHandler = { operation, helperSHA256, reply in
            XCTAssertEqual(operation, HelperMaintenanceOperation.repair.rawValue)
            XCTAssertEqual(helperSHA256, expectedDigest)
            reply(XPCHelperMaintenanceCoding.encode(HelperMaintenanceReport(
                operation: .repair,
                safeToStop: false,
                quiesced: false,
                restoreAttempted: false,
                restoreSucceeded: false,
                completeExpectedSetConfirmed: false,
                fanResults: [],
                blockers: [],
                token: nil
            )), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(
            connectionFactory: { connection },
            maintenanceHelperIdentity: { expectedDigest }
        )

        _ = try await client.prepareHelperMaintenance(operation: .repair)

        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testHelperMaintenanceConsumeUsesTransactionDeadlineInsteadOfShortReadDeadline() async throws {
        let issuedAt = Date(timeIntervalSince1970: 1_000)
        let token = HelperMaintenanceToken(
            tokenID: "maintenance-slow-commit",
            operation: .repair,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60),
            bootSessionID: "boot",
            daemonSessionID: "daemon",
            journalGeneration: 1,
            expectedFanIDs: [0],
            helperSHA256: String(repeating: "c", count: 64),
            quiesceGeneration: 1
        )
        let request = HelperMaintenanceAuthorizationRequest(operation: .repair, token: token)
        let expected = HelperMaintenanceAuthorization(
            authorized: true,
            operation: .repair,
            tokenID: token.tokenID,
            consumedAt: issuedAt.addingTimeInterval(1),
            quiesced: true,
            tokenConsumed: true
        )
        let proxy = FakeDaemonProxy()
        proxy.consumeHelperMaintenanceTokenHandler = { _, reply in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                reply(XPCHelperMaintenanceCoding.encode(expected), nil)
            }
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(
            timeout: 0.01,
            fanControlTransactionTimeout: 0.5,
            connectionFactory: { connection }
        )

        let actual = try await client.consumeHelperMaintenanceToken(request)

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testCandidateHelperIdentityHashesExactStableExecutableBytes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-maintenance-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("ViftyHelper")
        try Data("abc".utf8).write(to: helper)
        XCTAssertEqual(chmod(helper.path, 0o755), 0)

        XCTAssertEqual(
            try HelperMaintenanceCandidateIdentity.sha256(at: helper, maximumBytes: 3),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )

        let link = root.appendingPathComponent("ViftyHelper-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        XCTAssertThrowsError(try HelperMaintenanceCandidateIdentity.sha256(at: link))
    }

    func testSnapshotReturnsDecodedProxyResponse() async throws {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2_000, minimumRPM: 1_200, maximumRPM: 6_000, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let proxy = FakeDaemonProxy()
        proxy.snapshotHandler = { reply in
            reply(XPCSnapshotCoding.encode(snapshot), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        let decoded = try await client.snapshot()

        XCTAssertEqual(decoded.modelIdentifier, snapshot.modelIdentifier)
        XCTAssertEqual(decoded.fans, snapshot.fans)
        XCTAssertEqual(decoded.temperatureSensors, snapshot.temperatureSensors)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testAgentControlAuditReturnsDecodedProxyResponse() async throws {
        let events = [
            AgentControlAuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_000),
                action: "prepare",
                leaseID: "lease-1",
                message: "Swift build"
            )
        ]
        let proxy = FakeDaemonProxy()
        proxy.agentControlAuditHandler = { limit, reply in
            XCTAssertEqual(limit, 10)
            reply(XPCAgentControlCoding.encodeAuditEvents(events), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        let decoded = try await client.agentControlAudit(limit: 10)

        XCTAssertEqual(decoded, events)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testAgentMutationsUseOnlyProtocolV2SelectorsOnOneConnection() async throws {
        let legacyPrepareCalled = SendableTestFlag()
        let legacyRestoreCalled = SendableTestFlag()
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 60,
            maxRPMPercent: 60,
            reason: "fixture",
            idempotencyKey: "fixture"
        )
        let expected = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: nil,
            lastErrorCode: nil
        )
        let proxy = FakeDaemonProxy()
        proxy.prepareAgentControlHandler = { _, _ in legacyPrepareCalled.mark() }
        proxy.restoreAgentControlHandler = { _, _ in legacyRestoreCalled.mark() }
        proxy.prepareAgentControlV2Handler = { dictionary, reply in
            XCTAssertEqual(XPCAgentControlCoding.decodeRequest(dictionary), request)
            reply(XPCAgentControlCoding.encode(expected), nil)
        }
        proxy.restoreAgentControlV2Handler = { reason, reply in
            XCTAssertEqual(reason, "test restore")
            reply(XPCAgentControlCoding.encode(expected), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        let prepared = try await client.prepareAgentControl(request)
        let restored = try await client.restoreAgentControl(reason: "test restore")
        XCTAssertEqual(prepared, expected)
        XCTAssertEqual(restored, expected)
        XCTAssertFalse(legacyPrepareCalled.value)
        XCTAssertFalse(legacyRestoreCalled.value)
        XCTAssertEqual(connection.resumeCount, 2)
    }

    func testManualBatchUsesOneProtocolV2SelectorWithoutStatusTOCTOU() async throws {
        let statusRequested = SendableTestFlag()
        let proxy = FakeDaemonProxy()
        proxy.fanControlOwnershipStatusHandler = { reply in
            statusRequested.mark()
            reply(XPCFanControlCoding.encode(.osManaged), nil)
        }
        let request = ManualFanControlRequest(
            transactionID: "manual-1",
            sessionID: "manual-1",
            expectedFanIDs: [0, 1],
            targetRPMByFanID: [0: 3_000, 1: 3_200],
            reason: "Fixed"
        )
        let expected = FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
        proxy.applyManualFanControlHandler = { dictionary, reply in
            XCTAssertEqual(XPCFanControlCoding.decodeManualRequest(dictionary), request)
            reply(XPCFanControlCoding.encode(expected), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        let actual = try await client.applyManualFanControl(request)
        XCTAssertEqual(actual, expected)
        XCTAssertFalse(statusRequested.value)
        XCTAssertEqual(connection.resumeCount, 1)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testFanMutationUsesTransactionDeadlineInsteadOfShortReadDeadline() async throws {
        let request = ManualFanControlRequest(
            transactionID: "manual-slow-protected-mode",
            sessionID: "manual-slow-protected-mode",
            expectedFanIDs: [0],
            targetRPMByFanID: [0: 3_000],
            reason: "Protected-mode retry fixture"
        )
        let expected = FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
        let proxy = FakeDaemonProxy()
        proxy.applyManualFanControlHandler = { _, reply in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                reply(XPCFanControlCoding.encode(expected), nil)
            }
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(
            timeout: 0.01,
            fanControlTransactionTimeout: 0.5,
            connectionFactory: { connection }
        )

        let actual = try await client.applyManualFanControl(request)

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testMissingProtocolV2ManualSelectorFailsWithoutLegacyFallback() async {
        let proxy = FakeDaemonProxy()
        proxy.applyManualFanControlHandler = { _, reply in
            reply(nil, "unrecognized protocol-v2 selector")
        }
        let client = ViftyDaemonClient(connectionFactory: { FakeDaemonConnection(proxy: proxy) })

        do {
            _ = try await client.applyManualFanControl(ManualFanControlRequest(
                transactionID: "manual-1",
                sessionID: "manual-1",
                expectedFanIDs: [0],
                targetRPMByFanID: [0: 3_000],
                reason: "Fixed"
            ))
            XCTFail("Expected missing protocol-v2 selector to fail closed")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("protocol-v2"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLegacyRestoreConvenienceMapsToFullSetProtocolV2Restore() async throws {
        let proxy = FakeDaemonProxy()
        proxy.restoreAllAutoHandler = { dictionary, reply in
            guard let request = XPCFanControlCoding.decodeAutoRestoreRequest(dictionary) else {
                XCTFail("Expected decodable restore request")
                return
            }
            XCTAssertTrue(request.expectedFanIDs.isEmpty)
            XCTAssertTrue(request.allowRestoreAllTrustedFans)
            reply(XPCFanControlCoding.encode(FanControlTransactionResult(
                transactionID: request.transactionID,
                owner: nil,
                phase: nil,
                expectedFanIDs: [0, 1],
                confirmedFanIDs: [0, 1]
            )), nil)
        }
        let client = ViftyDaemonClient(connectionFactory: { FakeDaemonConnection(proxy: proxy) })

        try await client.restoreAuto(fan: Self.fan(id: 0))
    }


    func testProxyErrorInvalidatesConnectionAndReturnsFailure() async {
        let connection = FakeDaemonConnection(proxy: nil)
        connection.proxyError = ViftyError.helperRejected("proxy failed")
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            _ = try await client.snapshot()
            XCTFail("Expected proxy error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("proxy failed"))
            XCTAssertEqual(connection.invalidateCount, 1)
        }
    }

    func testTimeoutInvalidatesConnectionAndLateReplyIsIgnored() async {
        let proxy = FakeDaemonProxy()
        let replyStore = ReplyStore<Bool>()
        proxy.pingHandler = { reply in
            replyStore.store(reply)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(timeout: 0.01, connectionFactory: { connection })

        let result = await client.ping()
        replyStore.reply(with: true)

        XCTAssertFalse(result)
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testProtocolMethodThatNeverRepliesStillTimesOut() async {
        let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
        let client = ViftyDaemonClient(timeout: 0.01, connectionFactory: { connection })

        do {
            _ = try await client.fanControlOwnershipStatus()
            XCTFail("Expected missing reply to time out")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertEqual(connection.invalidateCount, 1)
    }

    func testMissingProxyUsesOneShotCallbackStateWhenInvalidateFiresHandler() async {
        let connection = FakeDaemonConnection(proxy: nil)
        connection.fireInvalidationOnInvalidate = true
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            _ = try await client.snapshot()
            XCTFail("Expected missing proxy error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Could not create daemon proxy"))
            XCTAssertEqual(connection.invalidateCount, 1)
        }
    }

    func testApplyRejectsMismatchedFanIDBeforeXPC() async {
        let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.apply(
                FanCommand(fanID: 1, mode: .fixedRPM(3200)),
                fan: Self.fan(id: 0)
            )
            XCTFail("Expected mismatched fan ID rejection")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Fan command ID 1 does not match hardware fan ID 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(connection.resumeCount, 0)
        XCTAssertEqual(connection.invalidateCount, 0)
    }

    func testLegacyPerFanApplyFailsClosedBeforeXPC() async {
        let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3200)),
                fan: Self.fan(id: 0)
            )
            XCTFail("Expected legacy per-fan write rejection")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Legacy per-fan writes are disabled"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(connection.resumeCount, 0)
        XCTAssertEqual(connection.invalidateCount, 0)
    }

    func testRestoreAutoRejectsInvalidFanIDBeforeXPC() async {
        let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.restoreAuto(fan: Self.fan(id: 10))
            XCTFail("Expected invalid fan ID rejection")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Invalid fan ID 10"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(connection.resumeCount, 0)
        XCTAssertEqual(connection.invalidateCount, 0)
    }

    func testRestoreAutoDoesNotTreatLegacyFanRangeAsWriteAuthority() async {
        let proxy = FakeDaemonProxy()
        let statusRequested = SendableTestFlag()
        proxy.fanControlOwnershipStatusHandler = { _ in
            statusRequested.mark()
        }
        proxy.restoreAllAutoHandler = { dictionary, reply in
            guard let request = XPCFanControlCoding.decodeAutoRestoreRequest(dictionary) else {
                return reply(nil, "invalid request")
            }
            reply(XPCFanControlCoding.encode(FanControlTransactionResult(
                transactionID: request.transactionID,
                owner: nil,
                phase: nil,
                expectedFanIDs: [0],
                confirmedFanIDs: [0]
            )), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.restoreAuto(fan: Self.fan(id: 0, minimumRPM: 6000, maximumRPM: 1400))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(statusRequested.value)
        XCTAssertEqual(connection.resumeCount, 1)
    }

    func testRestoreAutoDoesNotTreatLegacyControllableFlagAsWriteAuthority() async {
        let proxy = FakeDaemonProxy()
        let statusRequested = SendableTestFlag()
        proxy.fanControlOwnershipStatusHandler = { _ in
            statusRequested.mark()
        }
        proxy.restoreAllAutoHandler = { dictionary, reply in
            guard let request = XPCFanControlCoding.decodeAutoRestoreRequest(dictionary) else {
                return reply(nil, "invalid request")
            }
            reply(XPCFanControlCoding.encode(FanControlTransactionResult(
                transactionID: request.transactionID,
                owner: nil,
                phase: nil,
                expectedFanIDs: [0],
                confirmedFanIDs: [0]
            )), nil)
        }
        let connection = FakeDaemonConnection(proxy: proxy)
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.restoreAuto(fan: Self.fan(id: 0, controllable: false))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(statusRequested.value)
        XCTAssertEqual(connection.resumeCount, 1)
    }

    private static func fan(
        id: Int,
        minimumRPM: Int = 1400,
        maximumRPM: Int = 6000,
        controllable: Bool = true
    ) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: controllable
        )
    }
}

private final class FakeDaemonConnection: ViftyDaemonConnection, @unchecked Sendable {
    private let lock = NSLock()
    private let proxy: ViftyDaemonProtocol?

    var proxyError: Error?
    var fireInvalidationOnInvalidate = false
    private var invalidationHandler: (@Sendable () -> Void)?
    private var interruptionHandler: (@Sendable () -> Void)?

    private var _invalidateCount = 0
    private var _resumeCount = 0

    init(proxy: ViftyDaemonProtocol?) {
        self.proxy = proxy
    }

    var resumeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _resumeCount
    }

    var invalidateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _invalidateCount
    }

    func resume() {
        lock.lock()
        _resumeCount += 1
        lock.unlock()
    }

    func setInvalidationHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        invalidationHandler = handler
        lock.unlock()
    }

    func setInterruptionHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        interruptionHandler = handler
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        _invalidateCount += 1
        let handler = fireInvalidationOnInvalidate ? invalidationHandler : nil
        lock.unlock()
        handler?()
    }

    func remoteObjectProxyWithErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) -> Any? {
        if let proxyError {
            handler(proxyError)
            return nil
        }
        return proxy
    }
}

private final class FakeDaemonProxy: ViftyDaemonProtocol, @unchecked Sendable {
    var pingHandler: (@Sendable (@escaping (Bool) -> Void) -> Void)?
    var snapshotHandler: ((@escaping (NSDictionary?, String?) -> Void) -> Void)?
    var agentControlStatusHandler: (@Sendable (@escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var agentControlAuditHandler: (@Sendable (Int, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var prepareAgentControlHandler: (@Sendable (NSDictionary, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var restoreAgentControlHandler: (@Sendable (String, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var prepareAgentControlV2Handler: (@Sendable (NSDictionary, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var restoreAgentControlV2Handler: (@Sendable (String, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var fanControlOwnershipStatusHandler: (@Sendable (@escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var applyManualFanControlHandler: (@Sendable (NSDictionary, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var restoreAllAutoHandler: (@Sendable (NSDictionary, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var prepareHelperMaintenanceHandler: (@Sendable (String, String, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var consumeHelperMaintenanceTokenHandler: (@Sendable (NSDictionary, @escaping @Sendable (NSDictionary?, String?) -> Void) -> Void)?
    var cancelHelperMaintenanceHandler: (@Sendable (@escaping @Sendable (Bool, String?) -> Void) -> Void)?
    var setFixedRPMHandler: (@Sendable (Int, Int, Int, Int, @escaping @Sendable (Bool, String?) -> Void) -> Void)?
    var restoreAutoHandler: (@Sendable (Int, Int, Int, @escaping @Sendable (Bool, String?) -> Void) -> Void)?

    func ping(reply: @escaping (Bool) -> Void) {
        pingHandler?(reply)
    }

    func snapshot(reply: @escaping (NSDictionary?, String?) -> Void) {
        snapshotHandler?(reply)
    }

    func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        agentControlStatusHandler?(reply)
    }

    func agentControlAudit(_ limit: Int, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        agentControlAuditHandler?(limit, reply)
    }

    func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        prepareAgentControlHandler?(request, reply)
    }

    func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        restoreAgentControlHandler?(reason, reply)
    }

    func prepareAgentControlV2(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        prepareAgentControlV2Handler?(request, reply)
    }

    func restoreAgentControlV2(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        restoreAgentControlV2Handler?(reason, reply)
    }

    func fanControlOwnershipStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        fanControlOwnershipStatusHandler?(reply)
    }

    func applyManualFanControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        applyManualFanControlHandler?(request, reply)
    }

    func restoreAllAuto(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        restoreAllAutoHandler?(request, reply)
    }

    func prepareHelperMaintenance(
        _ operation: String,
        helperSHA256: String,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        prepareHelperMaintenanceHandler?(operation, helperSHA256, reply)
    }

    func consumeHelperMaintenanceToken(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    ) {
        consumeHelperMaintenanceTokenHandler?(request, reply)
    }

    func cancelHelperMaintenance(reply: @escaping @Sendable (Bool, String?) -> Void) {
        cancelHelperMaintenanceHandler?(reply)
    }

    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        setFixedRPMHandler?(fanID, rpm, minimumRPM, maximumRPM, reply)
    }

    func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        restoreAutoHandler?(fanID, minimumRPM, maximumRPM, reply)
    }
}

private final class ReplyStore<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: ((T) -> Void)?

    func store(_ reply: @escaping (T) -> Void) {
        lock.lock()
        self.reply = reply
        lock.unlock()
    }

    func reply(with value: T) {
        lock.lock()
        let reply = reply
        lock.unlock()
        reply?(value)
    }
}

private final class SendableTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func mark() {
        lock.withLock { storage = true }
    }
}
