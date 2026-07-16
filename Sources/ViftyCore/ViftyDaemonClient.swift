@preconcurrency import Foundation

public final class ViftyDaemonClient: @unchecked Sendable {
    /// Protected-mode recovery may wait up to ten seconds per physical fan.
    /// Fan-control requests therefore need a deadline that covers the full
    /// allowlisted ten-fan transaction plus bounded daemon/readback overhead.
    public static let defaultFanControlTransactionTimeout: TimeInterval = 125

    private let timeout: TimeInterval
    private let fanControlTransactionTimeout: TimeInterval
    private let connectionFactory: @Sendable () -> any ViftyDaemonConnection
    private let maintenanceHelperIdentity: @Sendable () throws -> String

    public convenience init(
        serviceName: String = ViftyDaemonConstants.machServiceName,
        timeout: TimeInterval = 3
    ) {
        self.init(
            serviceName: serviceName,
            timeout: timeout,
            fanControlTransactionTimeout: Self.defaultFanControlTransactionTimeout
        )
    }

    public init(
        serviceName: String,
        timeout: TimeInterval,
        fanControlTransactionTimeout: TimeInterval
    ) {
        self.timeout = timeout
        self.fanControlTransactionTimeout = max(timeout, fanControlTransactionTimeout)
        self.connectionFactory = { XPCDaemonConnection(serviceName: serviceName) }
        self.maintenanceHelperIdentity = {
            try HelperMaintenanceCandidateIdentity.bundledHelperSHA256()
        }
    }

    init(
        timeout: TimeInterval = 3,
        fanControlTransactionTimeout: TimeInterval? = nil,
        connectionFactory: @escaping @Sendable () -> any ViftyDaemonConnection,
        maintenanceHelperIdentity: @escaping @Sendable () throws -> String = {
            try HelperMaintenanceCandidateIdentity.bundledHelperSHA256()
        }
    ) {
        self.timeout = timeout
        self.fanControlTransactionTimeout = max(timeout, fanControlTransactionTimeout ?? timeout)
        self.connectionFactory = connectionFactory
        self.maintenanceHelperIdentity = maintenanceHelperIdentity
    }

    public func ping() async -> Bool {
        do {
            return try await withProxy { proxy, finish in
                proxy.ping { ok in finish(.success(ok)) }
            }
        } catch {
            return false
        }
    }

    public func snapshot() async throws -> HardwareSnapshot {
        try await withProxy { proxy, finish in
            proxy.snapshot { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let snapshot = XPCSnapshotCoding.decode(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid snapshot.")))
                    return
                }
                finish(.success(snapshot))
            }
        }
    }

    public func agentControlStatus() async throws -> AgentControlStatus {
        try await withProxy { proxy, finish in
            proxy.agentControlStatus { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control status.")))
                    return
                }
                finish(.success(status))
            }
        }
    }

    public func agentControlAudit(limit: Int) async throws -> [AgentControlAuditEvent] {
        try await withProxy { proxy, finish in
            proxy.agentControlAudit(limit) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let events = XPCAgentControlCoding.decodeAuditEvents(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control audit response.")))
                    return
                }
                finish(.success(events))
            }
        }
    }

    public func prepareAgentControl(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.prepareAgentControlV2(XPCAgentControlCoding.encode(request)) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control prepare response.")))
                    return
                }
                finish(.success(status))
            }
        }
    }

    public func restoreAgentControl(reason: String) async throws -> AgentControlStatus {
        try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.restoreAgentControlV2(reason) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control restore response.")))
                    return
                }
                finish(.success(status))
            }
        }
    }

    public func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        try await withProxy { proxy, finish in
            proxy.fanControlOwnershipStatus { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let status = XPCFanControlCoding.decodeOwnershipStatus(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned invalid fan-control ownership status.")))
                    return
                }
                finish(.success(status))
            }
        }
    }

    public func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        return try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.applyManualFanControl(XPCFanControlCoding.encode(request)) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let result = XPCFanControlCoding.decodeTransactionResult(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid manual fan-control result.")))
                    return
                }
                finish(.success(result))
            }
        }
    }

    public func restoreAllAuto(
        _ request: AutoRestoreRequest
    ) async throws -> FanControlTransactionResult {
        return try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.restoreAllAuto(XPCFanControlCoding.encode(request)) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let result = XPCFanControlCoding.decodeTransactionResult(dictionary) else {
                    finish(.failure(ViftyError.helperRejected("Daemon returned an invalid full-set Auto result.")))
                    return
                }
                finish(.success(result))
            }
        }
    }

    public func prepareHelperMaintenance(
        operation: HelperMaintenanceOperation
    ) async throws -> HelperMaintenanceReport {
        let helperSHA256 = try maintenanceHelperIdentity()
        return try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.prepareHelperMaintenance(
                operation.rawValue,
                helperSHA256: helperSHA256
            ) { dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let report = XPCHelperMaintenanceCoding.decodeReport(dictionary) else {
                    finish(.failure(ViftyError.helperRejected(
                        "Daemon returned an invalid helper-maintenance report."
                    )))
                    return
                }
                finish(.success(report))
            }
        }
    }

    public func consumeHelperMaintenanceToken(
        _ request: HelperMaintenanceAuthorizationRequest
    ) async throws -> HelperMaintenanceAuthorization {
        return try await withProxy(timeout: fanControlTransactionTimeout) { proxy, finish in
            proxy.consumeHelperMaintenanceToken(XPCHelperMaintenanceCoding.encode(request)) {
                dictionary, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                    return
                }
                guard let dictionary,
                      let authorization = XPCHelperMaintenanceCoding.decodeAuthorization(dictionary) else {
                    finish(.failure(ViftyError.helperRejected(
                        "Daemon returned an invalid helper-maintenance authorization."
                    )))
                    return
                }
                finish(.success(authorization))
            }
        }
    }

    public func cancelHelperMaintenance() async throws {
        let _: Void = try await withProxy { proxy, finish in
            proxy.cancelHelperMaintenance { cancelled, error in
                if let error {
                    finish(.failure(ViftyError.helperRejected(error)))
                } else if cancelled {
                    finish(.success(()))
                } else {
                    finish(.failure(ViftyError.helperRejected(
                        "Daemon did not cancel helper maintenance."
                    )))
                }
            }
        }
    }

    public func apply(_ command: FanCommand, fan: Fan) async throws {
        try validateFanID(fan.id)
        guard command.fanID == fan.id else {
            throw ViftyError.helperRejected("Fan command ID \(command.fanID) does not match hardware fan ID \(fan.id)")
        }

        switch command.mode {
        case .fixedRPM:
            throw ViftyError.helperRejected(
                "Legacy per-fan writes are disabled. Use a protocol-v2 manual fan-control transaction."
            )
        case .auto:
            try await restoreAuto(fan: fan)
        case .temperatureCurve:
            throw ViftyError.helperRejected("Curve commands must be resolved before reaching the daemon.")
        }
    }

    public func restoreAuto(fan: Fan) async throws {
        try validateFanID(fan.id)
        guard fan.controlEligibility.canRestoreOSManagedMode else {
            throw ViftyError.helperRejected("Fan \(fan.id) lacks trusted mode telemetry for Auto recovery.")
        }
        _ = try await restoreAllAuto(
            AutoRestoreRequest(
                transactionID: "legacy-auto-\(UUID().uuidString)",
                expectedFanIDs: [],
                reason: "Legacy client requested Auto; mapped to authoritative full-set restore",
                allowRestoreAllTrustedFans: true
            )
        )
    }

    private func validateFanID(_ fanID: Int) throws {
        guard SMCFanControlKeys.isValidFanID(fanID) else {
            throw ViftyError.helperRejected("Invalid fan ID \(fanID); SMC fan IDs must be 0 through 9.")
        }
    }

    private func withProxy<T: Sendable>(
        timeout requestTimeout: TimeInterval? = nil,
        _ operation: @escaping (
            ViftyDaemonProtocol,
            @escaping @Sendable (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ViftyCoreLog.xpc.debug("Daemon request started")
            let state = CallbackState<T>()
            let connection = connectionFactory()

            connection.setInvalidationHandler {
                if state.finish(
                    .failure(ViftyError.helperRejected("Daemon connection invalidated.")),
                    continuation: continuation
                ) {
                    ViftyCoreLog.xpc.warning("Daemon request connection invalidated unexpectedly")
                }
            }
            connection.setInterruptionHandler {
                if state.finish(
                    .failure(ViftyError.helperRejected("Daemon connection interrupted.")),
                    continuation: continuation
                ) {
                    ViftyCoreLog.xpc.warning("Daemon request connection interrupted")
                }
            }
            connection.resume()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + (requestTimeout ?? timeout))
            timer.setEventHandler {
                if state.finish(.failure(ViftyError.helperRejected("Daemon request timed out.")), continuation: continuation) {
                    connection.invalidate()
                    ViftyCoreLog.xpc.warning("Daemon request timed out")
                }
            }
            state.retain(timer: timer)
            timer.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                timer.cancel()
                if state.finish(.failure(ViftyError.helperRejected(error.localizedDescription)), continuation: continuation) {
                    connection.invalidate()
                }
            }) as? ViftyDaemonProtocol else {
                timer.cancel()
                if state.finish(.failure(ViftyError.helperRejected("Could not create daemon proxy.")), continuation: continuation) {
                    connection.invalidate()
                }
                return
            }

            operation(proxy) { result in
                timer.cancel()
                if state.finish(result, continuation: continuation) {
                    connection.invalidate()
                    ViftyCoreLog.xpc.debug("Daemon request completed")
                }
            }
        }
    }
}

protocol ViftyDaemonConnection: Sendable {
    func setInvalidationHandler(_ handler: @escaping @Sendable () -> Void)
    func setInterruptionHandler(_ handler: @escaping @Sendable () -> Void)
    func resume()
    func invalidate()
    func remoteObjectProxyWithErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) -> Any?
}

private final class XPCDaemonConnection: ViftyDaemonConnection, @unchecked Sendable {
    private let connection: NSXPCConnection

    init(serviceName: String) {
        connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ViftyDaemonProtocol.self)
    }

    func setInvalidationHandler(_ handler: @escaping @Sendable () -> Void) {
        connection.invalidationHandler = handler
    }

    func setInterruptionHandler(_ handler: @escaping @Sendable () -> Void) {
        connection.interruptionHandler = handler
    }

    func resume() {
        connection.resume()
    }

    func invalidate() {
        connection.invalidate()
    }

    func remoteObjectProxyWithErrorHandler(_ handler: @escaping @Sendable (Error) -> Void) -> Any? {
        connection.remoteObjectProxyWithErrorHandler(handler)
    }
}

private final class CallbackState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var retainedTimer: DispatchSourceTimer?

    func retain(timer: DispatchSourceTimer) {
        lock.withLock {
            guard !finished else { return }
            retainedTimer = timer
        }
    }

    @discardableResult
    func finish(_ result: Result<T, Error>, continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        retainedTimer = nil
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        return true
    }
}
