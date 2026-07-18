import Darwin
import Dispatch
import Foundation
import ViftyCore

struct ViftyCtlMain {
    static func run() async {
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        do {
            let command = try ViftyCtlArguments.parse(rawArguments)
            let runner = ViftyCtlRunner(
                client: ViftyCtlDaemonClient(),
                processRunner: ViftyCtlProcessRunner(),
                agentRuleBundleURL: Bundle.main.bundleURL
            )
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

await ViftyCtlMain.run()

struct ViftyCtlProcessRunner: ViftyCtlProcessRunning {
    private let environment: [String: String]
    private let supervisor: ChildProcessSupervisor

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        supervisor: ChildProcessSupervisor = ChildProcessSupervisor()
    ) {
        self.environment = environment
        self.supervisor = supervisor
    }

    func resolve(_ arguments: [String]) throws -> [String] {
        if arguments[0].contains("/") {
            guard isExecutableCommand(atPath: arguments[0]) else {
                throw ViftyError.helperRejected("Child command is not executable: \(arguments[0])")
            }
            let executablePath = URL(fileURLWithPath: arguments[0]).standardizedFileURL.path
            return [executablePath] + Array(arguments.dropFirst())
        }

        let path = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(arguments[0])
                .standardizedFileURL
                .path
            if isExecutableCommand(atPath: candidate) {
                return [candidate] + Array(arguments.dropFirst())
            }
        }

        throw ViftyError.helperRejected("Child command was not found on PATH: \(arguments[0])")
    }

    func run(_ arguments: [String]) throws -> Int32 {
        try supervisor.run(arguments)
    }

    func runMaintainingSignalShield(_ arguments: [String]) -> ViftyCtlProcessRunCompletion {
        supervisor.runMaintainingSignalShield(arguments)
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

    private func isExecutableCommand(atPath path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
