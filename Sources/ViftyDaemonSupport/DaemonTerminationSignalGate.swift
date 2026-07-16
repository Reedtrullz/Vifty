import Foundation

/// Buffers a voluntary termination request received while the daemon is still
/// bootstrapping. SIGTERM is ignored at the process level before bootstrap;
/// this gate replays one coalesced request as soon as the fully initialized
/// service can perform its quiesce-and-restore protocol.
public final class DaemonTerminationSignalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var hasPendingRequest = false

    public init() {}

    public func installHandler(_ handler: @escaping @Sendable () -> Void) {
        let shouldDeliverPending = lock.withLock {
            self.handler = handler
            guard hasPendingRequest else { return false }
            hasPendingRequest = false
            return true
        }
        if shouldDeliverPending {
            handler()
        }
    }

    public func requestTermination() {
        let installedHandler: (@Sendable () -> Void)? = lock.withLock {
            guard let handler else {
                hasPendingRequest = true
                return nil
            }
            return handler
        }
        installedHandler?()
    }
}
