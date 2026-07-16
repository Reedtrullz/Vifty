import Foundation

public enum ViftyCtlChildProcessFailurePhase: String, Codable, Equatable, Sendable {
    case launch
    case wait
    case descendantCleanup
}

/// Structured child-lifecycle failure shared by the executable supervisor and
/// the machine-readable viftyctl runner. In particular, cleanup failures must
/// never be mislabeled as launch failures or hidden behind a successful child
/// exit code.
public struct ViftyCtlChildProcessLifecycleError: Error, LocalizedError, Equatable, Sendable {
    public var phase: ViftyCtlChildProcessFailurePhase
    public var message: String
    public var childExitCode: Int32?
    public var descendantCleanupCompleted: Bool
    public var backgroundProcessesMayRemain: Bool

    public init(
        phase: ViftyCtlChildProcessFailurePhase,
        message: String,
        childExitCode: Int32? = nil,
        descendantCleanupCompleted: Bool,
        backgroundProcessesMayRemain: Bool
    ) {
        self.phase = phase
        self.message = message
        self.childExitCode = childExitCode
        self.descendantCleanupCompleted = descendantCleanupCompleted
        self.backgroundProcessesMayRemain = backgroundProcessesMayRemain
    }

    public var errorDescription: String? { message }
}

/// Retains viftyctl's process-signal shield after the child process group has
/// exited so an interrupt cannot terminate the wrapper while it is awaiting
/// the daemon-owned Auto restoration. The runner explicitly finishes the
/// shield after that restore attempt; deinit is a defensive leak guard.
public final class ViftyCtlProcessRunCompletion: @unchecked Sendable {
    private let result: Result<Int32, any Error>
    private let finishHandler: @Sendable () -> Void
    private let lock = NSLock()
    private var isFinished = false

    public init(
        exitCode: Int32,
        finishSignalHandling: @escaping @Sendable () -> Void = {}
    ) {
        self.result = .success(exitCode)
        self.finishHandler = finishSignalHandling
    }

    public init(
        error: any Error,
        finishSignalHandling: @escaping @Sendable () -> Void = {}
    ) {
        self.result = .failure(error)
        self.finishHandler = finishSignalHandling
    }

    deinit {
        finishSignalHandling()
    }

    public func get() throws -> Int32 {
        try result.get()
    }

    public func finishSignalHandling() {
        let shouldFinish = lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        if shouldFinish {
            finishHandler()
        }
    }
}
