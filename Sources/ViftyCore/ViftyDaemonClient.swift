@preconcurrency import Foundation

public final class ViftyDaemonClient: @unchecked Sendable {
    private let timeout: TimeInterval
    private let connectionFactory: @Sendable () -> any ViftyDaemonConnection

    public init(
        serviceName: String = ViftyDaemonConstants.machServiceName,
        timeout: TimeInterval = 3
    ) {
        self.timeout = timeout
        self.connectionFactory = { XPCDaemonConnection(serviceName: serviceName) }
    }

    init(
        timeout: TimeInterval = 3,
        connectionFactory: @escaping @Sendable () -> any ViftyDaemonConnection
    ) {
        self.timeout = timeout
        self.connectionFactory = connectionFactory
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
        try await withProxy { proxy, finish in
            proxy.prepareAgentControl(XPCAgentControlCoding.encode(request)) { dictionary, error in
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
        try await withProxy { proxy, finish in
            proxy.restoreAgentControl(reason) { dictionary, error in
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

    public func apply(_ command: FanCommand, fan: Fan) async throws {
        try validateFanID(fan.id)
        guard command.fanID == fan.id else {
            throw ViftyError.helperRejected("Fan command ID \(command.fanID) does not match hardware fan ID \(fan.id)")
        }

        switch command.mode {
        case .fixedRPM(let rpm):
            guard fan.controllable, fan.maximumRPM > fan.minimumRPM else {
                throw ViftyError.noControllableFans
            }
            try await setFixedRPM(fanID: fan.id, rpm: rpm, minimumRPM: fan.minimumRPM, maximumRPM: fan.maximumRPM)
        case .auto:
            try await restoreAuto(fan: fan)
        case .temperatureCurve:
            throw ViftyError.helperRejected("Curve commands must be resolved before reaching the daemon.")
        }
    }

    public func restoreAuto(fan: Fan) async throws {
        try validateFanID(fan.id)
        try await withProxy { proxy, finish in
            proxy.restoreAuto(fan.id, minimumRPM: fan.minimumRPM, maximumRPM: fan.maximumRPM) { ok, error in
                if ok {
                    finish(.success(()))
                } else {
                    finish(.failure(ViftyError.helperRejected(error ?? "Daemon failed to restore Auto.")))
                }
            }
        }
    }

    private func validateFanID(_ fanID: Int) throws {
        guard SMCFanControlKeys.isValidFanID(fanID) else {
            throw ViftyError.helperRejected("Invalid fan ID \(fanID); SMC fan IDs must be 0 through 9.")
        }
    }

    private func setFixedRPM(fanID: Int, rpm: Int, minimumRPM: Int, maximumRPM: Int) async throws {
        try await withProxy { proxy, finish in
            proxy.setFixedRPM(fanID, rpm: rpm, minimumRPM: minimumRPM, maximumRPM: maximumRPM) { ok, error in
                if ok {
                    finish(.success(()))
                } else {
                    finish(.failure(ViftyError.helperRejected(error ?? "Daemon failed to set fixed RPM.")))
                }
            }
        }
    }

    private func withProxy<T: Sendable>(
        _ operation: @escaping (
            ViftyDaemonProtocol,
            @escaping @Sendable (Result<T, Error>) -> Void
        ) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let state = CallbackState<T>()
            let connection = connectionFactory()

            connection.setInvalidationHandler {
                state.finish(.failure(ViftyError.helperRejected("Daemon connection invalidated.")), continuation: continuation)
            }
            connection.setInterruptionHandler {
                state.finish(.failure(ViftyError.helperRejected("Daemon connection interrupted.")), continuation: continuation)
            }
            connection.resume()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if state.finish(.failure(ViftyError.helperRejected("Daemon request timed out.")), continuation: continuation) {
                    connection.invalidate()
                }
            }
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

    @discardableResult
    func finish(_ result: Result<T, Error>, continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        return true
    }
}
