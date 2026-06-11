import XCTest
@testable import ViftyCore

final class ViftyDaemonClientTests: XCTestCase {
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

    func testApplyRejectsInvalidRPMRangeBeforeXPC() async {
        let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
        let client = ViftyDaemonClient(connectionFactory: { connection })

        do {
            try await client.apply(
                FanCommand(fanID: 0, mode: .fixedRPM(3200)),
                fan: Self.fan(id: 0, minimumRPM: 6000, maximumRPM: 1400)
            )
            XCTFail("Expected invalid fan range rejection")
        } catch ViftyError.noControllableFans {
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

    private static func fan(id: Int, minimumRPM: Int = 1400, maximumRPM: Int = 6000) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: true
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
    var setFixedRPMHandler: (@Sendable (Int, Int, Int, Int, @escaping (Bool, String?) -> Void) -> Void)?
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

    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
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
