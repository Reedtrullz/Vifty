import Darwin
import Dispatch
import Foundation
import ViftyCore

@main
struct ViftyCtlMain {
    static func main() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        do {
            let command = try ViftyCtlArguments.parse(rawArguments)
            let runner = ViftyCtlRunner(client: ViftyCtlDaemonClient(), processRunner: ViftyCtlProcessRunner())
            let result = try await runner.run(command)
            if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data(result.stdout.utf8)) }
            if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
            exit(result.exitCode)
        } catch let error as ViftyCtlParseError {
            if ViftyCtlArguments.requestsJSON(rawArguments) {
                writeJSONParseError(error, rawArguments: rawArguments)
            } else {
                FileHandle.standardError.write(Data("viftyctl failed: \(ViftyCtlArguments.humanReadableParseError(error))\n".utf8))
            }
            exit(64)
        } catch {
            FileHandle.standardError.write(Data("viftyctl failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func writeJSONParseError(_ error: ViftyCtlParseError, rawArguments: [String]) {
        let report = ViftyCtlCommandErrorReport(
            command: ViftyCtlArguments.commandNameHint(rawArguments),
            errorCode: .invalidArguments,
            message: ViftyCtlArguments.humanReadableParseError(error),
            generatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardError.write(Data("viftyctl failed: \(ViftyCtlArguments.humanReadableParseError(error))\n".utf8))
        }
    }
}

struct ViftyCtlProcessRunner: ViftyCtlProcessRunning {
    func resolve(_ arguments: [String]) throws -> [String] {
        if arguments[0].contains("/") {
            guard FileManager.default.isExecutableFile(atPath: arguments[0]) else {
                throw ViftyError.helperRejected("Child command is not executable: \(arguments[0])")
            }
            return arguments
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(arguments[0]).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return [candidate] + Array(arguments.dropFirst())
            }
        }

        throw ViftyError.helperRejected("Child command was not found on PATH: \(arguments[0])")
    }

    func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        try process.run()
        let signalForwarder = ChildProcessSignalForwarder(process: process)
        signalForwarder.start()
        process.waitUntilExit()
        signalForwarder.cancel()
        return Self.exitCode(for: process.terminationReason, status: process.terminationStatus)
    }

    static func exitCode(for reason: Process.TerminationReason, status: Int32) -> Int32 {
        switch reason {
        case .exit:
            return status
        case .uncaughtSignal:
            return 128 + max(0, status)
        @unknown default:
            return status
        }
    }
}

private final class ChildProcessSignalForwarder: @unchecked Sendable {
    private typealias SignalHandler = @convention(c) (Int32) -> Void

    private let process: Process
    private let queue = DispatchQueue(label: "tech.reidar.vifty.viftyctl.signal-forwarder")
    private let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]
    private var sources: [DispatchSourceSignal] = []
    private var previousHandlers: [(signal: Int32, handler: SignalHandler?)] = []

    init(process: Process) {
        self.process = process
    }

    func start() {
        guard sources.isEmpty else { return }
        previousHandlers.removeAll()
        for signalNumber in signals {
            let previousHandler = Darwin.signal(signalNumber, SIG_IGN)
            previousHandlers.append((signalNumber, previousHandler))
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
            source.setEventHandler { [weak self] in
                self?.forward(signalNumber)
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        previousHandlers.forEach { _ = Darwin.signal($0.signal, $0.handler) }
        previousHandlers.removeAll()
    }

    private func forward(_ signalNumber: Int32) {
        guard process.isRunning else { return }
        Darwin.kill(process.processIdentifier, signalNumber)
    }
}
