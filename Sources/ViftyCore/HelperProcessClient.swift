import Foundation

public struct HelperProcessClient: Sendable {
    private let executableURL: URL?

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    public func apply(_ command: FanCommand, fan: Fan) throws {
        guard fan.controllable else { throw ViftyError.noControllableFans }

        switch command.mode {
        case .fixedRPM(let rpm):
            let clamped = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
            try run(arguments: [
                "setFixed",
                String(fan.id),
                String(clamped),
                String(fan.minimumRPM),
                String(fan.maximumRPM)
            ])
        case .auto:
            try restoreAuto(fan: fan)
        case .temperatureCurve:
            throw ViftyError.helperRejected("Curve commands must be resolved to fixed RPM before reaching the helper.")
        }
    }

    public func restoreAuto(fan: Fan) throws {
        try run(arguments: [
            "auto",
            String(fan.id),
            String(fan.minimumRPM),
            String(fan.maximumRPM)
        ])
    }

    private func run(arguments: [String]) throws {
        let helperURL = try resolvedHelperURL()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ViftyError.helperRejected(message.isEmpty ? "Helper exited with \(process.terminationStatus)" : message)
        }
    }

    private func resolvedHelperURL() throws -> URL {
        if let executableURL {
            return executableURL
        }

        var candidates: [URL] = []

        if let bundleExecutable = Bundle.main.executableURL {
            let directory = bundleExecutable.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("ViftyHelper"))
        }

        let currentExecutable = URL(fileURLWithPath: CommandLine.arguments[0])
        candidates.append(currentExecutable.deletingLastPathComponent().appendingPathComponent("ViftyHelper"))

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match
        }

        throw ViftyError.helperRejected("ViftyHelper was not found next to the app executable.")
    }
}
