import Darwin
import Foundation
import ViftyAXEvidenceCore
import ViftyBuildProvenance

public struct AXCollectCommandOptions: Equatable, Sendable {
    public var processIdentifier: Int32
    public var captureID: String
    public var checkID: String
    public var windowIdentifier: String
    public var rootIdentifier: String
    public var requestJSONPath: String
    public var outputPath: String
    public var timeoutSeconds: Double
    public var maximumNodeCount: Int
    public var maximumDepth: Int

    public init(
        processIdentifier: Int32,
        captureID: String,
        checkID: String,
        windowIdentifier: String,
        rootIdentifier: String,
        requestJSONPath: String,
        outputPath: String,
        timeoutSeconds: Double,
        maximumNodeCount: Int,
        maximumDepth: Int
    ) {
        self.processIdentifier = processIdentifier
        self.captureID = captureID
        self.checkID = checkID
        self.windowIdentifier = windowIdentifier
        self.rootIdentifier = rootIdentifier
        self.requestJSONPath = requestJSONPath
        self.outputPath = outputPath
        self.timeoutSeconds = timeoutSeconds
        self.maximumNodeCount = maximumNodeCount
        self.maximumDepth = maximumDepth
    }
}

public struct AXSealCommandOptions: Equatable, Sendable {
    public var rawCapturePath: String
    public var rawCaptureSHA256: String
    public var fixtureReportPath: String
    public var fixtureReportSHA256: String
    public var debugExecutablePath: String
    public var debugExecutableSHA256: String
    public var outputPath: String

    public init(
        rawCapturePath: String,
        rawCaptureSHA256: String,
        fixtureReportPath: String,
        fixtureReportSHA256: String,
        debugExecutablePath: String,
        debugExecutableSHA256: String,
        outputPath: String
    ) {
        self.rawCapturePath = rawCapturePath
        self.rawCaptureSHA256 = rawCaptureSHA256
        self.fixtureReportPath = fixtureReportPath
        self.fixtureReportSHA256 = fixtureReportSHA256
        self.debugExecutablePath = debugExecutablePath
        self.debugExecutableSHA256 = debugExecutableSHA256
        self.outputPath = outputPath
    }
}

public enum AXCollectorCommand: Equatable, Sendable {
    case collect(AXCollectCommandOptions)
    case seal(AXSealCommandOptions)
    case help

    public static func parse(arguments: [String]) throws -> AXCollectorCommand {
        guard let mode = arguments.first else { throw AXCollectorCommandError.usage("missing mode") }
        if mode == "--help" || mode == "-h" || mode == "help" { return .help }
        let values = try parseOptions(Array(arguments.dropFirst()))
        switch mode {
        case "collect":
            let allowed = Set([
                "--pid", "--capture-id", "--check-id", "--window-identifier",
                "--root-identifier", "--request-json", "--output",
                "--timeout-seconds", "--maximum-nodes", "--maximum-depth"
            ])
            try rejectUnknown(values, allowed: allowed)
            guard let pidText = values["--pid"], let pid = Int32(pidText), pid > 0 else {
                throw AXCollectorCommandError.usage("--pid requires a positive Int32")
            }
            let timeout = try double(values["--timeout-seconds"] ?? "2", flag: "--timeout-seconds")
            let maximumNodes = try integer(values["--maximum-nodes"] ?? "2048", flag: "--maximum-nodes")
            let maximumDepth = try integer(values["--maximum-depth"] ?? "32", flag: "--maximum-depth")
            let options = AXCollectCommandOptions(
                processIdentifier: pid,
                captureID: try required("--capture-id", in: values),
                checkID: try required("--check-id", in: values),
                windowIdentifier: try required("--window-identifier", in: values),
                rootIdentifier: try required("--root-identifier", in: values),
                requestJSONPath: try required("--request-json", in: values),
                outputPath: try required("--output", in: values),
                timeoutSeconds: timeout,
                maximumNodeCount: maximumNodes,
                maximumDepth: maximumDepth
            )
            try rejectOutputAliasing(options.outputPath, inputs: [options.requestJSONPath])
            return .collect(options)
        case "seal":
            let allowed = Set([
                "--raw-capture", "--raw-capture-sha256",
                "--fixture-report", "--fixture-report-sha256",
                "--debug-executable", "--debug-executable-sha256", "--output"
            ])
            try rejectUnknown(values, allowed: allowed)
            let options = AXSealCommandOptions(
                rawCapturePath: try required("--raw-capture", in: values),
                rawCaptureSHA256: try required("--raw-capture-sha256", in: values),
                fixtureReportPath: try required("--fixture-report", in: values),
                fixtureReportSHA256: try required("--fixture-report-sha256", in: values),
                debugExecutablePath: try required("--debug-executable", in: values),
                debugExecutableSHA256: try required("--debug-executable-sha256", in: values),
                outputPath: try required("--output", in: values)
            )
            try rejectOutputAliasing(options.outputPath, inputs: [
                options.rawCapturePath,
                options.fixtureReportPath,
                options.debugExecutablePath
            ])
            return .seal(options)
        default:
            throw AXCollectorCommandError.usage("unknown mode: \(mode)")
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else {
            throw AXCollectorCommandError.usage("every option requires exactly one value")
        }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            let value = arguments[index + 1]
            guard flag.hasPrefix("--"), !value.isEmpty else {
                throw AXCollectorCommandError.usage("invalid option pair: \(flag)")
            }
            guard values.updateValue(value, forKey: flag) == nil else {
                throw AXCollectorCommandError.usage("duplicate option: \(flag)")
            }
            index += 2
        }
        return values
    }

    private static func rejectUnknown(_ values: [String: String], allowed: Set<String>) throws {
        if let unknown = Set(values.keys).subtracting(allowed).sorted().first {
            throw AXCollectorCommandError.usage("unknown option: \(unknown)")
        }
    }

    private static func required(_ flag: String, in values: [String: String]) throws -> String {
        guard let value = values[flag], !value.isEmpty else {
            throw AXCollectorCommandError.usage("missing required option: \(flag)")
        }
        return value
    }

    private static func integer(_ value: String, flag: String) throws -> Int {
        guard let value = Int(value) else { throw AXCollectorCommandError.usage("\(flag) requires an integer") }
        return value
    }

    private static func double(_ value: String, flag: String) throws -> Double {
        guard let value = Double(value), value.isFinite else {
            throw AXCollectorCommandError.usage("\(flag) requires a finite number")
        }
        return value
    }

    private static func rejectOutputAliasing(_ output: String, inputs: [String]) throws {
        if inputs.contains(where: { pathsAlias(output, $0) }) {
            throw AXCollectorCommandError.usage("--output must not alias an input path")
        }
    }

    private static func pathsAlias(_ lhs: String, _ rhs: String) -> Bool {
        let lhsPath = URL(fileURLWithPath: lhs)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let rhsPath = URL(fileURLWithPath: rhs)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        if lhsPath == rhsPath { return true }

        let manager = FileManager.default
        guard let lhsAttributes = try? manager.attributesOfItem(atPath: lhsPath),
              let rhsAttributes = try? manager.attributesOfItem(atPath: rhsPath),
              let lhsDevice = lhsAttributes[.systemNumber] as? NSNumber,
              let rhsDevice = rhsAttributes[.systemNumber] as? NSNumber,
              let lhsFile = lhsAttributes[.systemFileNumber] as? NSNumber,
              let rhsFile = rhsAttributes[.systemFileNumber] as? NSNumber else {
            return false
        }
        return lhsDevice == rhsDevice && lhsFile == rhsFile
    }
}

public enum AXCollectorCommandError: Error, Equatable, Sendable {
    case usage(String)
}

public struct AXCollectorFailureReport: Codable, Equatable, Sendable {
    public static let schemaID = "https://vifty.app/schemas/ui-review-ax-collector-error-v1.schema.json"

    public var schemaVersion: Int
    public var schemaID: String
    public var code: String
    public var message: String
    public var promptRequested: Bool
    public var readOnly: Bool
    public var actionsPerformed: [String]

    public init(error: Error) {
        schemaVersion = 1
        schemaID = Self.schemaID
        code = Self.code(for: error)
        message = String(describing: error)
        promptRequested = false
        readOnly = true
        actionsPerformed = []
    }

    private static func code(for error: Error) -> String {
        if (error as? AXCollectorError) == .permissionMissing { return "AX_PERMISSION_MISSING" }
        if error is AXCollectorCommandError { return "AX_USAGE" }
        if error is AXSealError { return "AX_SEAL_FAILED" }
        if error is AXCollectorError { return "AX_COLLECTION_BLOCKED" }
        if error is CocoaError || error is POSIXError || error is DecodingError { return "AX_IO_ERROR" }
        return "AX_INTERNAL_ERROR"
    }
}

public enum AXCollectorCLI {
    public static let usage = """
    Usage:
      ViftyAXCollector collect --pid PID --capture-id ID --check-id ID \\
        --window-identifier ID --root-identifier ID --request-json PATH --output PATH \\
        [--timeout-seconds 2] [--maximum-nodes 2048] [--maximum-depth 32]
      ViftyAXCollector seal --raw-capture PATH --raw-capture-sha256 SHA256 \\
        --fixture-report PATH --fixture-report-sha256 SHA256 \\
        --debug-executable PATH --debug-executable-sha256 SHA256 --output PATH
    """

    public static func run(arguments: [String]) -> Int32 {
        run(arguments: arguments, reader: AXSystemReader())
    }

    static func run<Reader: AXReadAdapter>(
        arguments: [String],
        reader: Reader,
        collectorBuildProvenance suppliedCollectorBuildProvenance: ViftyBuildProvenance? = nil
    ) -> Int32 {
        var failureOutputPath: String?
        do {
            switch try AXCollectorCommand.parse(arguments: arguments) {
            case .help:
                FileHandle.standardOutput.write(Data((usage + "\n").utf8))
                return AXCollectorExitCode.success
            case let .collect(options):
                failureOutputPath = options.outputPath
                let collectorBuildProvenance = try suppliedCollectorBuildProvenance ??
                    ViftyBuildProvenanceReader.readCurrentExecutable(
                        expectedRole: "ax-collector",
                        expectedConfiguration: "debug"
                    )
                let requestData = try Data(contentsOf: URL(fileURLWithPath: options.requestJSONPath))
                let semanticRequest = try JSONDecoder().decode(AXSemanticRequest.self, from: requestData)
                let request = AXEvidenceRequest(
                    checkID: options.checkID,
                    captureID: options.captureID,
                    processIdentifier: options.processIdentifier,
                    windowIdentifier: options.windowIdentifier,
                    rootIdentifier: options.rootIdentifier,
                    semanticRequest: semanticRequest
                )
                let capture = try AXEvidenceCollector(reader: reader).collect(
                    AXCollectionConfiguration(
                        request: request,
                        timeoutSeconds: options.timeoutSeconds,
                        maximumNodeCount: options.maximumNodeCount,
                        maximumDepth: options.maximumDepth,
                        collectorBuildProvenance: collectorBuildProvenance
                    )
                )
                try write(AXCanonicalJSON.data(capture), to: options.outputPath)
                return AXCollectorExitCode.success
            case let .seal(options):
                failureOutputPath = options.outputPath
                let collectorBuildProvenance = try suppliedCollectorBuildProvenance ??
                    ViftyBuildProvenanceReader.readCurrentExecutable(
                        expectedRole: "ax-collector",
                        expectedConfiguration: "debug"
                    )
                let sealed = try AXEvidenceSealer.seal(AXSealConfiguration(
                    rawCapturePath: options.rawCapturePath,
                    expectedRawCaptureSHA256: options.rawCaptureSHA256,
                    fixtureReportPath: options.fixtureReportPath,
                    expectedFixtureReportSHA256: options.fixtureReportSHA256,
                    debugExecutablePath: options.debugExecutablePath,
                    expectedDebugExecutableSHA256: options.debugExecutableSHA256,
                    collectorBuildProvenance: collectorBuildProvenance,
                    outputPath: options.outputPath
                ))
                try write(AXCanonicalJSON.data(sealed), to: options.outputPath)
                return AXCollectorExitCode.success
            }
        } catch {
            let report = AXCollectorFailureReport(error: error)
            if let data = try? AXCanonicalJSON.data(report) {
                if let failureOutputPath {
                    try? write(data, to: failureOutputPath)
                }
                FileHandle.standardError.write(data)
                FileHandle.standardError.write(Data("\n".utf8))
            }
            return AXCollectorExitCode.code(for: error)
        }
    }

    private static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

exit(AXCollectorCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
