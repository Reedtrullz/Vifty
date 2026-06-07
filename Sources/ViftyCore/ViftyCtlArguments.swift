import Foundation

public enum ViftyCtlCommand: Equatable, Sendable {
    case status(json: Bool)
    case capabilities(json: Bool)
    case prepare(AgentControlRequest, json: Bool)
    case restoreAuto(reason: String, idempotencyKey: String?, json: Bool)
    case run(AgentControlRequest, childArguments: [String])
}

public enum ViftyCtlArguments {
    public static func parse(_ arguments: [String]) throws -> ViftyCtlCommand {
        guard let command = arguments.first else {
            throw ViftyCtlParseError.missingCommand
        }

        let rest = Array(arguments.dropFirst())

        switch command {
        case "status":
            return .status(json: rest.contains("--json"))
        case "capabilities":
            return .capabilities(json: rest.contains("--json"))
        case "prepare":
            return .prepare(try parseRequest(rest), json: rest.contains("--json"))
        case "restore-auto":
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

            guard !childArguments.isEmpty else {
                throw ViftyCtlParseError.missingChildCommand
            }

            return .run(try parseRequest(requestArguments), childArguments: childArguments)
        default:
            throw ViftyCtlParseError.unknownCommand(command)
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
            let maxRPMPercent = Int(percentValue)
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

    private static func parseDurationSeconds(_ value: String) -> Int? {
        if value.hasSuffix("m") {
            return parsePositiveInteger(String(value.dropLast())).map { $0 * 60 }
        }

        if value.hasSuffix("h") {
            return parsePositiveInteger(String(value.dropLast())).map { $0 * 3_600 }
        }

        return parsePositiveInteger(value)
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

        return arguments[valueIndex]
    }
}

public enum ViftyCtlParseError: Error, Equatable, Sendable {
    case missingCommand
    case unknownCommand(String)
    case invalidWorkload
    case invalidDuration
    case invalidRPMPercent
    case missingChildCommand
}
