import CryptoKit
import Darwin
import Foundation

enum DaemonInstallOperation: String, Sendable {
    case repair
    case uninstall
}

enum DaemonInstallOutcome: Equatable, Sendable {
    case completed
    case blocked
    case failed
}

struct DaemonInstallResult: Equatable, Sendable {
    var outcome: DaemonInstallOutcome
    var operatorMessage: String
}

struct DaemonInstallProcessOutput: Equatable, Sendable {
    var terminationStatus: Int32
    var standardOutput: String
    var standardError: String
}

enum DaemonInstallProcessError: Error, Equatable, Sendable {
    case timedOut
    case processGroupUnavailable
}

private actor BoundedProcessOutput {
    static let maximumBytesPerStream = 64 * 1_024
    private var data = Data()

    func append(_ chunk: Data) {
        guard data.count < Self.maximumBytesPerStream else { return }
        data.append(chunk.prefix(Self.maximumBytesPerStream - data.count))
    }

    func snapshot() -> Data {
        data
    }
}

struct DaemonInstallProcessRunner: Sendable {
    let run: @Sendable (URL, [String], Data) async throws -> DaemonInstallProcessOutput

    init(
        run: @escaping @Sendable (URL, [String], Data) async throws -> DaemonInstallProcessOutput
    ) {
        self.run = run
    }

    static let defaultLifecycleTimeout: TimeInterval = 180

    static func system(
        timeout: TimeInterval = defaultLifecycleTimeout
    ) -> DaemonInstallProcessRunner {
        DaemonInstallProcessRunner { executable, arguments, standardInput in
            try await Task.detached(priority: .userInitiated) {
                let commandArguments = [executable.path] + arguments
                var inputFileDescriptors = [Int32](repeating: 0, count: 2)
                var outputFileDescriptors = [Int32](repeating: 0, count: 2)
                var errorFileDescriptors = [Int32](repeating: 0, count: 2)
                guard pipe(&inputFileDescriptors) == 0,
                      pipe(&outputFileDescriptors) == 0,
                      pipe(&errorFileDescriptors) == 0 else {
                    (inputFileDescriptors + outputFileDescriptors + errorFileDescriptors)
                        .filter { $0 > 0 }
                        .forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }

                var fileActions: posix_spawn_file_actions_t?
                guard posix_spawn_file_actions_init(&fileActions) == 0 else {
                    (inputFileDescriptors + outputFileDescriptors + errorFileDescriptors)
                        .forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                defer { posix_spawn_file_actions_destroy(&fileActions) }

                let childFileDescriptors = inputFileDescriptors + outputFileDescriptors + errorFileDescriptors
                let actionResults = [
                    posix_spawn_file_actions_adddup2(&fileActions, inputFileDescriptors[0], STDIN_FILENO),
                    posix_spawn_file_actions_adddup2(&fileActions, outputFileDescriptors[1], STDOUT_FILENO),
                    posix_spawn_file_actions_adddup2(&fileActions, errorFileDescriptors[1], STDERR_FILENO)
                ] + childFileDescriptors.map {
                    posix_spawn_file_actions_addclose(&fileActions, $0)
                }
                guard actionResults.allSatisfy({ $0 == 0 }) else {
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
                }

                var attributes: posix_spawnattr_t?
                guard posix_spawnattr_init(&attributes) == 0 else {
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                defer { posix_spawnattr_destroy(&attributes) }
                guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
                      posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }

                var cArguments = commandArguments.map { strdup($0) }
                guard cArguments.allSatisfy({ $0 != nil }) else {
                    cArguments.compactMap { $0 }.forEach { free($0) }
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))
                }
                cArguments.append(nil)
                defer { cArguments.compactMap { $0 }.forEach { free($0) } }

                let environment = [
                    "HOME=\(FileManager.default.homeDirectoryForCurrentUser.path)",
                    "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
                ]
                var cEnvironment = environment.map { strdup($0) }
                guard cEnvironment.allSatisfy({ $0 != nil }) else {
                    cEnvironment.compactMap { $0 }.forEach { free($0) }
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))
                }
                cEnvironment.append(nil)
                defer { cEnvironment.compactMap { $0 }.forEach { free($0) } }

                var processID = pid_t()
                let spawnResult = cArguments.withUnsafeMutableBufferPointer { argumentBuffer in
                    cEnvironment.withUnsafeMutableBufferPointer { environmentBuffer in
                        executable.path.withCString { executablePath in
                            posix_spawn(
                                &processID,
                                executablePath,
                                &fileActions,
                                &attributes,
                                argumentBuffer.baseAddress,
                                environmentBuffer.baseAddress
                            )
                        }
                    }
                }
                guard spawnResult == 0 else {
                    childFileDescriptors.forEach { _ = close($0) }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(spawnResult))
                }

                let privateGroupID = processID
                let groupIsPrivate = getpgid(processID) == privateGroupID && privateGroupID != getpgrp()
                guard groupIsPrivate else {
                    _ = kill(processID, SIGTERM)
                    _ = kill(processID, SIGKILL)
                    var status = Int32()
                    let cleanupDeadline = DispatchTime.now().uptimeNanoseconds + 250_000_000
                    while DispatchTime.now().uptimeNanoseconds < cleanupDeadline {
                        let waitResult = waitpid(processID, &status, WNOHANG)
                        if waitResult == processID || (waitResult == -1 && errno != EINTR) { break }
                        usleep(10_000)
                    }
                    (inputFileDescriptors + outputFileDescriptors + errorFileDescriptors)
                        .forEach { _ = close($0) }
                    throw DaemonInstallProcessError.processGroupUnavailable
                }

                _ = close(inputFileDescriptors[0])
                _ = close(outputFileDescriptors[1])
                _ = close(errorFileDescriptors[1])
                let inputHandle = FileHandle(fileDescriptor: inputFileDescriptors[1], closeOnDealloc: true)
                let outputHandle = FileHandle(fileDescriptor: outputFileDescriptors[0], closeOnDealloc: true)
                let errorHandle = FileHandle(fileDescriptor: errorFileDescriptors[0], closeOnDealloc: true)
                var inputClosed = false
                var outputClosed = false
                var errorClosed = false
                func closeInput() {
                    guard !inputClosed else { return }
                    inputClosed = true
                    try? inputHandle.close()
                }
                func closeOutput() {
                    guard !outputClosed else { return }
                    outputClosed = true
                    try? outputHandle.close()
                }
                func closeError() {
                    guard !errorClosed else { return }
                    errorClosed = true
                    try? errorHandle.close()
                }
                defer {
                    closeInput()
                    closeOutput()
                    closeError()
                }

                let output = BoundedProcessOutput()
                let error = BoundedProcessOutput()
                let outputReader = Task.detached(priority: .userInitiated) {
                    do {
                        while let chunk = try outputHandle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                            await output.append(chunk)
                        }
                    } catch {}
                }
                let errorReader = Task.detached(priority: .userInitiated) {
                    do {
                        while let chunk = try errorHandle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                            await error.append(chunk)
                        }
                    } catch {}
                }

                var waitStatus = Int32()
                var leaderExited = false
                func reapLeaderIfNeeded() throws {
                    guard !leaderExited else { return }
                    while true {
                        let waitResult = waitpid(processID, &waitStatus, WNOHANG)
                        if waitResult == processID {
                            leaderExited = true
                            return
                        }
                        if waitResult == 0 { return }
                        if errno == EINTR { continue }
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                }
                func groupExists() -> Bool {
                    let result = kill(-privateGroupID, 0)
                    return result == 0 || errno == EPERM
                }
                func waitForCleanup(until deadline: UInt64) throws {
                    while DispatchTime.now().uptimeNanoseconds < deadline {
                        try reapLeaderIfNeeded()
                        if leaderExited && !groupExists() { return }
                        usleep(10_000)
                    }
                    try reapLeaderIfNeeded()
                }
                func terminatePrivateGroup() throws {
                    if groupExists() { _ = kill(-privateGroupID, SIGTERM) }
                    do {
                        try waitForCleanup(until: DispatchTime.now().uptimeNanoseconds + 250_000_000)
                    } catch {
                        if groupExists() { _ = kill(-privateGroupID, SIGKILL) }
                        try? waitForCleanup(until: DispatchTime.now().uptimeNanoseconds + 250_000_000)
                        throw error
                    }
                    if groupExists() { _ = kill(-privateGroupID, SIGKILL) }
                    try waitForCleanup(until: DispatchTime.now().uptimeNanoseconds + 250_000_000)
                }

                do {
                    try inputHandle.write(contentsOf: standardInput)
                    closeInput()
                } catch {
                    closeInput()
                    try? terminatePrivateGroup()
                    closeOutput()
                    closeError()
                    _ = await outputReader.value
                    _ = await errorReader.value
                    throw error
                }

                let deadline = DispatchTime.now().uptimeNanoseconds
                    + UInt64(max(0, timeout) * 1_000_000_000)
                while !leaderExited {
                    try reapLeaderIfNeeded()
                    if leaderExited { break }
                    if DispatchTime.now().uptimeNanoseconds >= deadline { break }
                    usleep(10_000)
                }

                if !leaderExited {
                    try? terminatePrivateGroup()
                    closeOutput()
                    closeError()
                    _ = await outputReader.value
                    _ = await errorReader.value
                    throw DaemonInstallProcessError.timedOut
                }

                try terminatePrivateGroup()
                closeOutput()
                closeError()
                _ = await outputReader.value
                _ = await errorReader.value
                return DaemonInstallProcessOutput(
                    terminationStatus: (waitStatus & 0x7f) == 0 ? (waitStatus >> 8) & 0xff : 128 + (waitStatus & 0x7f),
                    standardOutput: String(decoding: await output.snapshot(), as: UTF8.self),
                    standardError: String(decoding: await error.snapshot(), as: UTF8.self)
                )
            }.value
        }
    }
}

struct DaemonLifecycleScriptLoader: Sendable {
    let load: @Sendable (URL) throws -> Data

    init(load: @escaping @Sendable (URL) throws -> Data) {
        self.load = load
    }

    static let bundled = DaemonLifecycleScriptLoader { url in
        // This digest is compiled into the signed app executable. The resource is
        // read once into an immutable Data snapshot and only that snapshot runs.
        // Update it intentionally whenever vifty-helper-lifecycle.sh changes.
        let expectedSHA256 = "8cc4772c1e6f30e6827059ab998d67db5eea8e2eb41f2c3fd11d9f1ede3e4157"
        let maximumSize = 256 * 1_024
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw DaemonLifecycleScriptError.unreadableResource
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var fileStatus = stat()
        guard fstat(descriptor, &fileStatus) == 0,
              (fileStatus.st_mode & S_IFMT) == S_IFREG,
              fileStatus.st_size >= 0,
              fileStatus.st_size <= maximumSize else {
            throw DaemonLifecycleScriptError.invalidSize
        }
        var data = Data()
        while data.count <= maximumSize {
            let remainingCapacity = maximumSize + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remainingCapacity)),
                  !chunk.isEmpty else {
                break
            }
            data.append(chunk)
        }
        guard !data.isEmpty, data.count <= maximumSize else {
            throw DaemonLifecycleScriptError.invalidSize
        }
        let actualSHA256 = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualSHA256 == expectedSHA256 else {
            throw DaemonLifecycleScriptError.integrityMismatch
        }
        guard data.starts(with: Data(
            "#!/usr/bin/env -S -i HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc\n".utf8
        )) else {
            throw DaemonLifecycleScriptError.invalidInterpreter
        }
        return data
    }
}

private enum DaemonLifecycleScriptError: Error {
    case unreadableResource
    case invalidSize
    case integrityMismatch
    case invalidInterpreter
    case unexpectedResourceLocation
}

protocol DaemonInstallServicing: Sendable {
    func perform(
        operation: DaemonInstallOperation,
        appBundleURL: URL,
        lifecycleScriptURL: URL
    ) async -> DaemonInstallResult
}

actor DaemonInstallService: DaemonInstallServicing {
    private let processRunner: DaemonInstallProcessRunner
    private let lifecycleScriptLoader: DaemonLifecycleScriptLoader

    init() {
        processRunner = .system()
        lifecycleScriptLoader = .bundled
    }

    #if DEBUG
    init(
        processRunner: DaemonInstallProcessRunner,
        lifecycleScriptLoader: DaemonLifecycleScriptLoader
    ) {
        self.processRunner = processRunner
        self.lifecycleScriptLoader = lifecycleScriptLoader
    }
    #endif

    func perform(
        operation: DaemonInstallOperation,
        appBundleURL: URL,
        lifecycleScriptURL: URL
    ) async -> DaemonInstallResult {
        do {
            let expectedScriptURL = appBundleURL
                .appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")
                .standardizedFileURL
            guard lifecycleScriptURL.standardizedFileURL == expectedScriptURL else {
                throw DaemonLifecycleScriptError.unexpectedResourceLocation
            }
            let scriptSnapshot = try lifecycleScriptLoader.load(lifecycleScriptURL)
            let output = try await processRunner.run(
                URL(fileURLWithPath: "/bin/bash"),
                ["--noprofile", "--norc", "-s", "--", "--operation", operation.rawValue, "--app", appBundleURL.path],
                scriptSnapshot
            )
            switch output.terminationStatus {
            case 0:
                return DaemonInstallResult(
                    outcome: .completed,
                    operatorMessage: "Fan helper lifecycle completed."
                )
            case 75:
                return DaemonInstallResult(
                    outcome: .blocked,
                    operatorMessage: "Helper maintenance is blocked until Vifty confirms Auto/System ownership with a valid maintenance token."
                )
            default:
                return DaemonInstallResult(
                    outcome: .failed,
                    operatorMessage: "Fan helper lifecycle failed; fan writes stay blocked. Copy support evidence if it keeps failing."
                )
            }
        } catch let error as DaemonInstallProcessError where error == .timedOut {
            return DaemonInstallResult(
                outcome: .blocked,
                operatorMessage: "Helper lifecycle timed out; fan writes stay blocked until helper state is verified."
            )
        } catch {
            return DaemonInstallResult(
                outcome: .failed,
                operatorMessage: "Fan helper lifecycle could not start; fan writes stay blocked."
            )
        }
    }
}
