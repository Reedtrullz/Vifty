import Foundation
import ViftyCore

@main
struct ViftyCtlMain {
    static func main() async {
        do {
            let command = try ViftyCtlArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let runner = ViftyCtlRunner(client: ViftyCtlDaemonClient(), processRunner: ViftyCtlProcessRunner())
            let result = try await runner.run(command)
            if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data(result.stdout.utf8)) }
            if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
            exit(result.exitCode)
        } catch {
            FileHandle.standardError.write(Data("viftyctl failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

struct ViftyCtlProcessRunner: ViftyCtlProcessRunning {
    func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
