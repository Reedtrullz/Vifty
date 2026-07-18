import Darwin
import Dispatch
import Foundation
import ViftyCore

final class ChildProcessSupervisor: @unchecked Sendable {
    struct Policy: Sendable {
        var naturalExitGraceNanoseconds: UInt64
        var terminationGraceNanoseconds: UInt64
        var killGraceNanoseconds: UInt64
        var pollIntervalNanoseconds: UInt64

        static let production = Policy(
            naturalExitGraceNanoseconds: 250_000_000,
            terminationGraceNanoseconds: 1_000_000_000,
            killGraceNanoseconds: 1_000_000_000,
            pollIntervalNanoseconds: 10_000_000
        )

        static let test = Policy(
            naturalExitGraceNanoseconds: 20_000_000,
            terminationGraceNanoseconds: 20_000_000,
            killGraceNanoseconds: 500_000_000,
            pollIntervalNanoseconds: 5_000_000
        )
    }

    private let policy: Policy
    private let processGroupOperations: ProcessGroupOperations
    private let beforeSpawn: (() -> Void)?
    private let afterSpawn: ((pid_t) -> Void)?
    private let runLock = NSLock()

    init(
        policy: Policy = .production,
        processGroupOperations: ProcessGroupOperations = .production,
        beforeSpawn: (() -> Void)? = nil,
        afterSpawn: ((pid_t) -> Void)? = nil
    ) {
        self.policy = policy
        self.processGroupOperations = processGroupOperations
        self.beforeSpawn = beforeSpawn
        self.afterSpawn = afterSpawn
    }

    func run(_ arguments: [String]) throws -> Int32 {
        let completion = runMaintainingSignalShield(arguments)
        defer { completion.finishSignalHandling() }
        return try completion.get()
    }

    func runMaintainingSignalShield(_ arguments: [String]) -> ViftyCtlProcessRunCompletion {
        precondition(!arguments.isEmpty)
        let forwarder = ChildProcessSignalForwarder()
        forwarder.start()

        do {
            let exitCode = try run(arguments, forwarder: forwarder)
            return ViftyCtlProcessRunCompletion(
                exitCode: exitCode,
                finishSignalHandling: { forwarder.cancel() }
            )
        } catch {
            return ViftyCtlProcessRunCompletion(
                error: error,
                finishSignalHandling: { forwarder.cancel() }
            )
        }
    }

    private func run(
        _ arguments: [String],
        forwarder: ChildProcessSignalForwarder
    ) throws -> Int32 {
        runLock.lock()
        defer { runLock.unlock() }

        beforeSpawn?()
        let processID: pid_t
        do {
            processID = try spawn(arguments)
        } catch {
            throw ViftyCtlChildProcessLifecycleError(
                phase: .launch,
                message: error.localizedDescription,
                descendantCleanupCompleted: true,
                backgroundProcessesMayRemain: false
            )
        }
        forwarder.attach(processGroupID: processID)
        afterSpawn?(processID)

        let leaderResult = Result { try waitForLeader(processID) }
        let cleanupResult = Result { try terminateRemainingProcesses(inGroup: processID) }

        switch (leaderResult, cleanupResult) {
        case (.success(let exitCode), .success):
            return exitCode
        case (.success(let exitCode), .failure(let cleanupError)):
            throw ViftyCtlChildProcessLifecycleError(
                phase: .descendantCleanup,
                message: cleanupError.localizedDescription,
                childExitCode: exitCode,
                descendantCleanupCompleted: false,
                backgroundProcessesMayRemain: true
            )
        case (.failure(let waitError), .success):
            throw ViftyCtlChildProcessLifecycleError(
                phase: .wait,
                message: waitError.localizedDescription,
                descendantCleanupCompleted: true,
                backgroundProcessesMayRemain: false
            )
        case (.failure(let waitError), .failure(let cleanupError)):
            throw ViftyCtlChildProcessLifecycleError(
                phase: .descendantCleanup,
                message: "Leader wait failed: \(waitError.localizedDescription). Descendant cleanup also failed: \(cleanupError.localizedDescription)",
                descendantCleanupCompleted: false,
                backgroundProcessesMayRemain: true
            )
        }
    }

    private func spawn(_ arguments: [String]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        var result = posix_spawnattr_init(&attributes)
        guard result == 0 else {
            throw ChildProcessSupervisorError(operation: "initialize spawn attributes", code: result)
        }
        defer { posix_spawnattr_destroy(&attributes) }

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signalNumber in ChildProcessSignalForwarder.handledSignals {
            sigaddset(&defaultSignals, signalNumber)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF)
        result = posix_spawnattr_setflags(&attributes, flags)
        guard result == 0 else {
            throw ChildProcessSupervisorError(operation: "set spawn flags", code: result)
        }
        result = posix_spawnattr_setpgroup(&attributes, 0)
        guard result == 0 else {
            throw ChildProcessSupervisorError(operation: "create child process group", code: result)
        }
        result = posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        guard result == 0 else {
            throw ChildProcessSupervisorError(operation: "reset child signal handlers", code: result)
        }

        var cArguments = arguments.map { strdup($0) }
        guard cArguments.allSatisfy({ $0 != nil }) else {
            cArguments.compactMap { $0 }.forEach { free($0) }
            throw ChildProcessSupervisorError(operation: "allocate child arguments", code: ENOMEM)
        }
        cArguments.append(nil)
        defer { cArguments.compactMap { $0 }.forEach { free($0) } }

        var cEnvironment = ProcessInfo.processInfo.environment
            .map { key, value in strdup("\(key)=\(value)") }
        guard cEnvironment.allSatisfy({ $0 != nil }) else {
            cEnvironment.compactMap { $0 }.forEach { free($0) }
            throw ChildProcessSupervisorError(operation: "allocate child environment", code: ENOMEM)
        }
        cEnvironment.append(nil)
        defer { cEnvironment.compactMap { $0 }.forEach { free($0) } }

        var processID = pid_t()
        result = cArguments.withUnsafeMutableBufferPointer { argumentBuffer in
            cEnvironment.withUnsafeMutableBufferPointer { environmentBuffer in
                arguments[0].withCString { executablePath in
                    posix_spawn(
                        &processID,
                        executablePath,
                        nil,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard result == 0 else {
            throw ChildProcessSupervisorError(operation: "launch child command \(arguments[0])", code: result)
        }
        return processID
    }

    private func waitForLeader(_ processID: pid_t) throws -> Int32 {
        var status = Int32()
        while true {
            let result = Darwin.waitpid(processID, &status, 0)
            if result == processID {
                return Self.shellExitCode(forWaitStatus: status)
            }
            if result == -1, errno == EINTR {
                continue
            }
            throw ChildProcessSupervisorError(operation: "wait for child process \(processID)", code: errno)
        }
    }

    private func terminateRemainingProcesses(inGroup processGroupID: pid_t) throws {
        guard waitForGroupExit(processGroupID, timeoutNanoseconds: policy.naturalExitGraceNanoseconds) == false else {
            return
        }
        let terminationError = processGroupOperations.signal(processGroupID, SIGTERM)
        guard waitForGroupExit(processGroupID, timeoutNanoseconds: policy.terminationGraceNanoseconds) == false else {
            return
        }
        let killError = processGroupOperations.signal(processGroupID, SIGKILL)
        guard waitForGroupExit(processGroupID, timeoutNanoseconds: policy.killGraceNanoseconds) else {
            let signalErrors = [
                terminationError.map { "SIGTERM failed with errno \($0)" },
                killError.map { "SIGKILL failed with errno \($0)" }
            ].compactMap { $0 }
            let detail = signalErrors.isEmpty
                ? "The process group still exists after TERM and KILL grace periods."
                : signalErrors.joined(separator: "; ")
            throw ChildProcessSupervisorError(
                operation: "clean descendant process group \(processGroupID) before Auto restoration",
                code: ETIMEDOUT,
                detail: detail
            )
        }
    }

    private func waitForGroupExit(_ processGroupID: pid_t, timeoutNanoseconds: UInt64) -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        let deadline = start.addingReportingOverflow(timeoutNanoseconds).partialValue
        repeat {
            if !processGroupOperations.exists(processGroupID) {
                return true
            }
            let microseconds = max(1, min(policy.pollIntervalNanoseconds / 1_000, UInt64(UInt32.max)))
            usleep(useconds_t(microseconds))
        } while DispatchTime.now().uptimeNanoseconds < deadline
        return !processGroupOperations.exists(processGroupID)
    }

    private static func shellExitCode(forWaitStatus status: Int32) -> Int32 {
        let terminatingSignal = status & 0x7f
        if terminatingSignal == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + terminatingSignal
    }
}

private struct ChildProcessSupervisorError: LocalizedError {
    var operation: String
    var code: Int32
    var detail: String? = nil

    var errorDescription: String? {
        let message = String(cString: strerror(code))
        let base = "Could not \(operation): \(message) (\(code))"
        return detail.map { "\(base). \($0)" } ?? base
    }
}

struct ProcessGroupOperations: @unchecked Sendable {
    /// Returns nil on success or when the group has already exited; otherwise
    /// returns the errno reported by kill(2).
    var signal: @Sendable (_ processGroupID: pid_t, _ signalNumber: Int32) -> Int32?
    var exists: @Sendable (_ processGroupID: pid_t) -> Bool

    static let production = ProcessGroupOperations(
        signal: { processGroupID, signalNumber in
            if Darwin.kill(-processGroupID, signalNumber) == 0 {
                return nil
            }
            return errno == ESRCH ? nil : errno
        },
        exists: { processGroupID in
            if Darwin.kill(-processGroupID, 0) == 0 {
                return true
            }
            return errno == EPERM
        }
    )
}

private final class ChildProcessSignalForwarder: @unchecked Sendable {
    typealias SignalHandler = @convention(c) (Int32) -> Void

    static let handledSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    private let queue = DispatchQueue(label: "tech.reidar.vifty.viftyctl.signal-forwarder")
    private var sources: [DispatchSourceSignal] = []
    private var previousHandlers: [(signal: Int32, handler: SignalHandler?)] = []
    private var processGroupID: pid_t?
    private var pendingSignals: Set<Int32> = []

    func start() {
        guard sources.isEmpty else { return }
        for signalNumber in Self.handledSignals {
            let previousHandler = Darwin.signal(signalNumber, SIG_IGN)
            previousHandlers.append((signalNumber, previousHandler))
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler { [weak self] in
                self?.receive(signalNumber)
            }
            source.resume()
            sources.append(source)
        }
    }

    func attach(processGroupID: pid_t) {
        queue.sync {
            self.processGroupID = processGroupID
            for signalNumber in pendingSignals {
                forward(signalNumber, toProcessGroup: processGroupID)
            }
            pendingSignals.removeAll()
        }
    }

    func cancel() {
        queue.sync {
            processGroupID = nil
            pendingSignals.removeAll()
            sources.forEach { $0.cancel() }
            sources.removeAll()
        }
        for previousHandler in previousHandlers {
            _ = Darwin.signal(previousHandler.signal, previousHandler.handler)
        }
        previousHandlers.removeAll()
    }

    private func receive(_ signalNumber: Int32) {
        guard let processGroupID else {
            pendingSignals.insert(signalNumber)
            return
        }
        forward(signalNumber, toProcessGroup: processGroupID)
    }

    private func forward(_ signalNumber: Int32, toProcessGroup processGroupID: pid_t) {
        guard processGroupID > 0 else { return }
        _ = Darwin.kill(-processGroupID, signalNumber)
    }
}
