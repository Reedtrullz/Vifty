import Foundation

public enum ViftyCtlCommand: Equatable, Sendable {
    case status(json: Bool)
    case capabilities(json: Bool)
    case diagnose(json: Bool)
    case audit(limit: Int, json: Bool)
    case prepare(AgentControlRequest, json: Bool, force: Bool)
    case restoreAuto(reason: String, idempotencyKey: String?, json: Bool)
    case run(AgentControlRequest, childArguments: [String], json: Bool, force: Bool)
}

public enum ViftyCtlArguments {
    public static let defaultAuditLimit = 20

    public static func parse(_ arguments: [String]) throws -> ViftyCtlCommand {
        guard let command = arguments.first else {
            throw ViftyCtlParseError.missingCommand
        }

        let rest = Array(arguments.dropFirst())

        switch command {
        case "status":
            try validateOptions(rest, flagOnly: ["--json"], valueFlags: [])
            return .status(json: rest.contains("--json"))
        case "capabilities":
            try validateOptions(rest, flagOnly: ["--json"], valueFlags: [])
            return .capabilities(json: rest.contains("--json"))
        case "diagnose":
            try validateOptions(rest, flagOnly: ["--json"], valueFlags: [])
            return .diagnose(json: rest.contains("--json"))
        case "audit":
            try validateOptions(rest, flagOnly: ["--json"], valueFlags: ["--limit"])
            return .audit(limit: try parseAuditLimit(rest), json: rest.contains("--json"))
        case "prepare":
            try validateRequestOptions(rest)
            return .prepare(try parseRequest(rest), json: rest.contains("--json"), force: rest.contains("--force"))
        case "restore-auto":
            try validateOptions(rest, flagOnly: ["--json"], valueFlags: ["--reason", "--idempotency-key"])
            return .restoreAuto(
                reason: value(for: "--reason", in: rest) ?? "manual restore",
                idempotencyKey: value(for: "--idempotency-key", in: rest),
                json: rest.contains("--json")
            )
        case "run":
            guard let separatorIndex = rest.firstIndex(of: "--") else {
                throw ViftyCtlParseError.missingChildCommand
            }

            let requestArguments = Array(rest[..<separatorIndex])
            let childArguments = Array(rest[rest.index(after: separatorIndex)...])
            try validateRequestOptions(requestArguments)

            guard !childArguments.isEmpty else {
                throw ViftyCtlParseError.missingChildCommand
            }

            return .run(
                try parseRequest(requestArguments),
                childArguments: childArguments,
                json: requestArguments.contains("--json"),
                force: requestArguments.contains("--force")
            )
        default:
            throw ViftyCtlParseError.unknownCommand(command)
        }
    }

    public static func requestsJSON(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else {
            return false
        }

        let rest = Array(arguments.dropFirst())
        if command == "run" {
            let requestArguments: ArraySlice<String>
            if let separatorIndex = rest.firstIndex(of: "--") {
                requestArguments = rest[..<separatorIndex]
            } else {
                requestArguments = rest[...]
            }
            return requestArguments.contains("--json")
        }

        return rest.contains("--json")
    }

    public static func commandNameHint(_ arguments: [String]) -> String {
        arguments.first ?? "unknown"
    }

    public static func humanReadableParseError(_ error: ViftyCtlParseError) -> String {
        switch error {
        case .missingCommand:
            return "missing command"
        case .unknownCommand(let command):
            return "unknown command '\(command)'"
        case .invalidWorkload:
            return "invalid or missing --workload"
        case .invalidDuration:
            return "invalid or missing --duration"
        case .invalidRPMPercent:
            return "invalid or missing --max-rpm-percent"
        case .invalidLimit:
            return "invalid or missing --limit"
        case .missingChildCommand:
            return "run requires -- followed by a child command"
        case .unknownOption(let option):
            return "unknown option '\(option)'"
        case .unexpectedArgument(let argument):
            return "unexpected argument '\(argument)'"
        }
    }

    private static func validateRequestOptions(_ arguments: [String]) throws {
        try validateOptions(
            arguments,
            flagOnly: ["--json", "--force"],
            valueFlags: ["--workload", "--duration", "--max-rpm-percent", "--reason", "--idempotency-key"]
        )
    }

    private static func validateOptions(
        _ arguments: [String],
        flagOnly: Set<String>,
        valueFlags: Set<String>
    ) throws {
        let allowedFlags = flagOnly.union(valueFlags)
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw ViftyCtlParseError.unexpectedArgument(argument)
            }
            guard allowedFlags.contains(argument) else {
                throw ViftyCtlParseError.unknownOption(argument)
            }

            let valueIndex = arguments.index(after: index)
            if valueFlags.contains(argument),
               valueIndex < arguments.endIndex,
               !arguments[valueIndex].hasPrefix("--") {
                index = arguments.index(after: valueIndex)
            } else {
                index = valueIndex
            }
        }
    }

    private static func parseRequest(_ arguments: [String]) throws -> AgentControlRequest {
        guard
            let workloadValue = value(for: "--workload", in: arguments),
            let workload = AgentControlWorkload(rawValue: workloadValue)
        else {
            throw ViftyCtlParseError.invalidWorkload
        }

        guard
            let durationValue = value(for: "--duration", in: arguments),
            let durationSeconds = parseDurationSeconds(durationValue)
        else {
            throw ViftyCtlParseError.invalidDuration
        }

        guard
            let percentValue = value(for: "--max-rpm-percent", in: arguments),
            let maxRPMPercent = Int(percentValue),
            (1...100).contains(maxRPMPercent)
        else {
            throw ViftyCtlParseError.invalidRPMPercent
        }

        return AgentControlRequest(
            workload: workload,
            durationSeconds: durationSeconds,
            maxRPMPercent: maxRPMPercent,
            reason: value(for: "--reason", in: arguments) ?? "Agent workload",
            idempotencyKey: value(for: "--idempotency-key", in: arguments) ?? UUID().uuidString
        )
    }

    private static func parseAuditLimit(_ arguments: [String]) throws -> Int {
        guard let limitValue = value(for: "--limit", in: arguments) else {
            return defaultAuditLimit
        }
        guard let limit = parsePositiveInteger(limitValue) else {
            throw ViftyCtlParseError.invalidLimit
        }
        return limit
    }

    private static func parseDurationSeconds(_ value: String) -> Int? {
        if value.hasSuffix("m") {
            return parsePositiveInteger(String(value.dropLast()))
                .flatMap { seconds in safeMultiply(seconds, by: 60) }
        }

        if value.hasSuffix("h") {
            return parsePositiveInteger(String(value.dropLast()))
                .flatMap { seconds in safeMultiply(seconds, by: 3_600) }
        }

        return parsePositiveInteger(value)
    }

    private static func safeMultiply(_ value: Int, by multiplier: Int) -> Int? {
        let result = value.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow else {
            return nil
        }

        return result.partialValue
    }

    private static func parsePositiveInteger(_ value: String) -> Int? {
        guard let integer = Int(value), integer > 0 else {
            return nil
        }

        return integer
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        let value = arguments[valueIndex]
        guard !value.hasPrefix("--") else {
            return nil
        }

        return value
    }
}

public enum ViftyCtlParseError: Error, Equatable, Sendable {
    case missingCommand
    case unknownCommand(String)
    case invalidWorkload
    case invalidDuration
    case invalidRPMPercent
    case invalidLimit
    case missingChildCommand
    case unknownOption(String)
    case unexpectedArgument(String)
}
