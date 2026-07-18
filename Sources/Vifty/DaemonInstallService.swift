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

struct DaemonInstallProcessRunner: Sendable {
    let run: @Sendable (URL, [String], Data) async throws -> DaemonInstallProcessOutput

    init(
        run: @escaping @Sendable (URL, [String], Data) async throws -> DaemonInstallProcessOutput
    ) {
        self.run = run
    }

    static let system = DaemonInstallProcessRunner { executable, arguments, standardInput in
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
            ]
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
                try inputPipe.fileHandleForWriting.close()
            } catch {
                process.terminate()
                throw error
            }
            process.waitUntilExit()
            return DaemonInstallProcessOutput(
                terminationStatus: process.terminationStatus,
                standardOutput: String(
                    decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ),
                standardError: String(
                    decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )
            )
        }.value
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
        let expectedSHA256 = "374fa2976610adb3bb426e78ab3c135210e1c139dd24ee28533a13c3f8eede20"
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
        processRunner = .system
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
        } catch {
            return DaemonInstallResult(
                outcome: .failed,
                operatorMessage: "Fan helper lifecycle could not start; fan writes stay blocked."
            )
        }
    }
}
