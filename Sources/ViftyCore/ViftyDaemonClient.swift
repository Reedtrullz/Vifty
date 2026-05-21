@preconcurrency import Foundation

public final class ViftyDaemonClient: @unchecked Sendable {
    private let serviceName: String
    private let timeout: TimeInterval

    public init(
        serviceName: String = ViftyDaemonConstants.machServiceName,
        timeout: TimeInterval = 3
    ) {
        self.serviceName = serviceName
        self.timeout = timeout
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

    public func apply(_ command: FanCommand, fan: Fan) async throws {
        switch command.mode {
        case .fixedRPM(let rpm):
            try await setFixedRPM(fanID: fan.id, rpm: rpm, minimumRPM: fan.minimumRPM, maximumRPM: fan.maximumRPM)
        case .auto:
            try await restoreAuto(fan: fan)
        case .temperatureCurve:
            throw ViftyError.helperRejected("Curve commands must be resolved before reaching the daemon.")
        }
    }

    public func restoreAuto(fan: Fan) async throws {
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
        _ operation: @escaping (ViftyDaemonProtocol, @escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let state = CallbackState<T>()
            let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: ViftyDaemonProtocol.self)

            connection.invalidationHandler = {
                state.finish(.failure(ViftyError.helperRejected("Daemon connection invalidated.")), continuation: continuation)
            }
            connection.interruptionHandler = {
                state.finish(.failure(ViftyError.helperRejected("Daemon connection interrupted.")), continuation: continuation)
            }
            connection.resume()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                state.finish(.failure(ViftyError.helperRejected("Daemon request timed out.")), continuation: continuation)
                connection.invalidate()
            }
            timer.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                state.finish(.failure(ViftyError.helperRejected(error.localizedDescription)), continuation: continuation)
                timer.cancel()
                connection.invalidate()
            }) as? ViftyDaemonProtocol else {
                timer.cancel()
                connection.invalidate()
                continuation.resume(throwing: ViftyError.helperRejected("Could not create daemon proxy."))
                return
            }

            operation(proxy) { result in
                timer.cancel()
                state.finish(result, continuation: continuation)
                connection.invalidate()
            }
        }
    }
}

private final class CallbackState<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func finish(_ result: Result<T, Error>, continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
