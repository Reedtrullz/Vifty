import Foundation

public struct ViftyCtlResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public struct ViftyCtlRunLifecycleCapabilities: Codable, Equatable, Sendable {
    public var childCommandPreflightBeforeCooling: Bool
    public var signalsForwardedToChild: [String]
    public var autoRestoreAfterChildExit: Bool
    public var structuredPreChildFailures: Bool
    public var cleanupStateReportedOnLaunchFailure: Bool

    public init(
        childCommandPreflightBeforeCooling: Bool = true,
        signalsForwardedToChild: [String] = ["INT", "TERM", "HUP"],
        autoRestoreAfterChildExit: Bool = true,
        structuredPreChildFailures: Bool = true,
        cleanupStateReportedOnLaunchFailure: Bool = true
    ) {
        self.childCommandPreflightBeforeCooling = childCommandPreflightBeforeCooling
        self.signalsForwardedToChild = signalsForwardedToChild
        self.autoRestoreAfterChildExit = autoRestoreAfterChildExit
        self.structuredPreChildFailures = structuredPreChildFailures
        self.cleanupStateReportedOnLaunchFailure = cleanupStateReportedOnLaunchFailure
    }

    public static let unsupported = ViftyCtlRunLifecycleCapabilities(
        childCommandPreflightBeforeCooling: false,
        signalsForwardedToChild: [],
        autoRestoreAfterChildExit: false,
        structuredPreChildFailures: false,
        cleanupStateReportedOnLaunchFailure: false
    )
}

public struct ViftyCtlDirectControlLifecycleCapabilities: Codable, Equatable, Sendable {
    public var prepareUsesIdempotencyKey: Bool
    public var restoreAutoAcceptsIdempotencyKey: Bool
    public var restoreAutoScopedByIdempotencyKey: Bool
    public var preferRunForSingleChildWorkloads: Bool

    public init(
        prepareUsesIdempotencyKey: Bool = true,
        restoreAutoAcceptsIdempotencyKey: Bool = false,
        restoreAutoScopedByIdempotencyKey: Bool = false,
        preferRunForSingleChildWorkloads: Bool = true
    ) {
        self.prepareUsesIdempotencyKey = prepareUsesIdempotencyKey
        self.restoreAutoAcceptsIdempotencyKey = restoreAutoAcceptsIdempotencyKey
        self.restoreAutoScopedByIdempotencyKey = restoreAutoScopedByIdempotencyKey
        self.preferRunForSingleChildWorkloads = preferRunForSingleChildWorkloads
    }

    public static let unsupported = ViftyCtlDirectControlLifecycleCapabilities(
        prepareUsesIdempotencyKey: false,
        restoreAutoAcceptsIdempotencyKey: true,
        restoreAutoScopedByIdempotencyKey: true,
        preferRunForSingleChildWorkloads: false
    )
}

public struct ViftyCtlMetadataLimits: Codable, Equatable, Sendable {
    public var maximumReasonLength: Int
    public var maximumIdempotencyKeyLength: Int

    public init(
        maximumReasonLength: Int = AgentControlRequest.maximumReasonLength,
        maximumIdempotencyKeyLength: Int = AgentControlRequest.maximumIdempotencyKeyLength
    ) {
        self.maximumReasonLength = maximumReasonLength
        self.maximumIdempotencyKeyLength = maximumIdempotencyKeyLength
    }

    public static let unsupported = ViftyCtlMetadataLimits(
        maximumReasonLength: 0,
        maximumIdempotencyKeyLength: 0
    )
}

public struct ViftyCtlWrapperResources: Codable, Equatable, Sendable {
    public static let workloadScriptNames = [
        "cargo-build.sh",
        "cargo-test.sh",
        "custom-workload.sh",
        "local-model.sh",
        "make-build.sh",
        "make-test.sh",
        "make-verify.sh",
        "npm-build.sh",
        "npm-test.sh",
        "pytest.sh",
        "swift-release-build.sh",
        "swift-test.sh",
        "xcode-build.sh",
        "xcode-test.sh"
    ]

    public var sourceDirectory: String
    public var bundleDirectory: String
    public var guardedRunScript: String
    public var workloadScripts: [String]

    public init(
        sourceDirectory: String = "examples/viftyctl",
        bundleDirectory: String = "Contents/Resources/viftyctl-wrappers",
        guardedRunScript: String = "guarded-run.sh",
        workloadScripts: [String] = Self.workloadScriptNames
    ) {
        self.sourceDirectory = sourceDirectory
        self.bundleDirectory = bundleDirectory
        self.guardedRunScript = guardedRunScript
        self.workloadScripts = workloadScripts
    }

    public static let unsupported = ViftyCtlWrapperResources(
        sourceDirectory: "",
        bundleDirectory: "",
        guardedRunScript: "",
        workloadScripts: []
    )
}

public struct ViftyCtlCapabilities: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var commands: [String]
    public var workloads: [String]
    public var schemas: ViftyCtlSchemaReferences
    public var schemaResources: ViftyCtlSchemaReferences
    public var schemaIDs: ViftyCtlSchemaReferences
    public var policy: AgentControlPolicySnapshot
    public var policySource: ViftyCtlPolicySource
    public var daemonStatusAvailable: Bool
    public var policyStatusAvailable: Bool
    public var agentControlStatusError: String?
    public var supportsForceRetry: Bool
    public var runLifecycle: ViftyCtlRunLifecycleCapabilities
    public var directControlLifecycle: ViftyCtlDirectControlLifecycleCapabilities
    public var metadataLimits: ViftyCtlMetadataLimits
    public var wrapperResources: ViftyCtlWrapperResources
    public var exitCodes: ViftyCtlExitCodes

    public init(
        schemaVersion: Int = 1,
        commands: [String] = ["status", "capabilities", "diagnose", "audit", "prepare", "restore-auto", "run"],
        workloads: [String] = AgentControlWorkload.allCases.map(\.rawValue),
        schemas: ViftyCtlSchemaReferences = ViftyCtlSchemaReferences(),
        schemaResources: ViftyCtlSchemaReferences = .bundleResources,
        schemaIDs: ViftyCtlSchemaReferences = .schemaIDs,
        policy: AgentControlPolicySnapshot,
        policySource: ViftyCtlPolicySource = .daemonStatus,
        daemonStatusAvailable: Bool = true,
        policyStatusAvailable: Bool = true,
        agentControlStatusError: String? = nil,
        supportsForceRetry: Bool = true,
        runLifecycle: ViftyCtlRunLifecycleCapabilities = ViftyCtlRunLifecycleCapabilities(),
        directControlLifecycle: ViftyCtlDirectControlLifecycleCapabilities = ViftyCtlDirectControlLifecycleCapabilities(),
        metadataLimits: ViftyCtlMetadataLimits = ViftyCtlMetadataLimits(),
        wrapperResources: ViftyCtlWrapperResources = ViftyCtlWrapperResources(),
        exitCodes: ViftyCtlExitCodes = ViftyCtlExitCodes()
    ) {
        self.schemaVersion = schemaVersion
        self.commands = commands
        self.workloads = workloads
        self.schemas = schemas
        self.schemaResources = schemaResources
        self.schemaIDs = schemaIDs
        self.policy = policy
        self.policySource = policySource
        self.daemonStatusAvailable = daemonStatusAvailable
        self.policyStatusAvailable = policyStatusAvailable
        self.agentControlStatusError = agentControlStatusError
        self.supportsForceRetry = supportsForceRetry
        self.runLifecycle = runLifecycle
        self.directControlLifecycle = directControlLifecycle
        self.metadataLimits = metadataLimits
        self.wrapperResources = wrapperResources
        self.exitCodes = exitCodes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case commands
        case workloads
        case schemas
        case schemaResources
        case schemaIDs
        case policy
        case policySource
        case daemonStatusAvailable
        case policyStatusAvailable
        case agentControlStatusError
        case supportsForceRetry
        case runLifecycle
        case directControlLifecycle
        case metadataLimits
        case wrapperResources
        case exitCodes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        commands = try container.decode([String].self, forKey: .commands)
        workloads = try container.decode([String].self, forKey: .workloads)
        schemas = try container.decode(ViftyCtlSchemaReferences.self, forKey: .schemas)
        schemaResources = try container.decode(ViftyCtlSchemaReferences.self, forKey: .schemaResources)
        schemaIDs = try container.decode(ViftyCtlSchemaReferences.self, forKey: .schemaIDs)
        policy = try container.decode(AgentControlPolicySnapshot.self, forKey: .policy)
        policySource = try container.decode(ViftyCtlPolicySource.self, forKey: .policySource)
        daemonStatusAvailable = try container.decode(Bool.self, forKey: .daemonStatusAvailable)
        policyStatusAvailable = try container.decodeIfPresent(Bool.self, forKey: .policyStatusAvailable) ?? false
        agentControlStatusError = try container.decodeIfPresent(String.self, forKey: .agentControlStatusError)
        supportsForceRetry = try container.decodeIfPresent(Bool.self, forKey: .supportsForceRetry) ?? false
        runLifecycle = try container.decodeIfPresent(
            ViftyCtlRunLifecycleCapabilities.self,
            forKey: .runLifecycle
        ) ?? .unsupported
        directControlLifecycle = try container.decodeIfPresent(
            ViftyCtlDirectControlLifecycleCapabilities.self,
            forKey: .directControlLifecycle
        ) ?? .unsupported
        metadataLimits = try container.decodeIfPresent(
            ViftyCtlMetadataLimits.self,
            forKey: .metadataLimits
        ) ?? .unsupported
        wrapperResources = try container.decodeIfPresent(
            ViftyCtlWrapperResources.self,
            forKey: .wrapperResources
        ) ?? .unsupported
        exitCodes = try container.decode(ViftyCtlExitCodes.self, forKey: .exitCodes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(commands, forKey: .commands)
        try container.encode(workloads, forKey: .workloads)
        try container.encode(schemas, forKey: .schemas)
        try container.encode(schemaResources, forKey: .schemaResources)
        try container.encode(schemaIDs, forKey: .schemaIDs)
        try container.encode(policy, forKey: .policy)
        try container.encode(policySource, forKey: .policySource)
        try container.encode(daemonStatusAvailable, forKey: .daemonStatusAvailable)
        try container.encode(policyStatusAvailable, forKey: .policyStatusAvailable)
        if let agentControlStatusError {
            try container.encode(agentControlStatusError, forKey: .agentControlStatusError)
        } else {
            try container.encodeNil(forKey: .agentControlStatusError)
        }
        try container.encode(supportsForceRetry, forKey: .supportsForceRetry)
        try container.encode(runLifecycle, forKey: .runLifecycle)
        try container.encode(directControlLifecycle, forKey: .directControlLifecycle)
        try container.encode(metadataLimits, forKey: .metadataLimits)
        try container.encode(wrapperResources, forKey: .wrapperResources)
        try container.encode(exitCodes, forKey: .exitCodes)
    }
}

public struct ViftyCtlSchemaReferences: Codable, Equatable, Sendable {
    public static let bundleResources = ViftyCtlSchemaReferences(
        capabilities: "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
        audit: "Contents/Resources/schemas/viftyctl-audit.schema.json",
        diagnose: "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
        status: "Contents/Resources/schemas/viftyctl-status.schema.json",
        commandError: "Contents/Resources/schemas/viftyctl-command-error.schema.json",
        run: "Contents/Resources/schemas/viftyctl-run.schema.json"
    )

    public static let schemaIDs = ViftyCtlSchemaReferences(
        capabilities: "https://vifty.local/schemas/viftyctl-capabilities.schema.json",
        audit: "https://vifty.local/schemas/viftyctl-audit.schema.json",
        diagnose: "https://vifty.local/schemas/viftyctl-diagnose.schema.json",
        status: "https://vifty.local/schemas/viftyctl-status.schema.json",
        commandError: "https://vifty.local/schemas/viftyctl-command-error.schema.json",
        run: "https://vifty.local/schemas/viftyctl-run.schema.json"
    )

    public var capabilities: String
    public var audit: String
    public var diagnose: String
    public var status: String
    public var commandError: String
    public var run: String

    public init(
        capabilities: String = "docs/schemas/viftyctl-capabilities.schema.json",
        audit: String = "docs/schemas/viftyctl-audit.schema.json",
        diagnose: String = "docs/schemas/viftyctl-diagnose.schema.json",
        status: String = "docs/schemas/viftyctl-status.schema.json",
        commandError: String = "docs/schemas/viftyctl-command-error.schema.json",
        run: String = "docs/schemas/viftyctl-run.schema.json"
    ) {
        self.capabilities = capabilities
        self.audit = audit
        self.diagnose = diagnose
        self.status = status
        self.commandError = commandError
        self.run = run
    }

    private enum CodingKeys: String, CodingKey {
        case capabilities
        case audit
        case diagnose
        case status
        case commandError
        case run
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capabilities = try container.decode(String.self, forKey: .capabilities)
        audit = try container.decode(String.self, forKey: .audit)
        diagnose = try container.decode(String.self, forKey: .diagnose)
        status = try container.decode(String.self, forKey: .status)
        commandError = try container.decode(String.self, forKey: .commandError)
        run = try container.decodeIfPresent(String.self, forKey: .run)
            ?? "docs/schemas/viftyctl-run.schema.json"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(audit, forKey: .audit)
        try container.encode(diagnose, forKey: .diagnose)
        try container.encode(status, forKey: .status)
        try container.encode(commandError, forKey: .commandError)
        try container.encode(run, forKey: .run)
    }
}

public enum ViftyCtlPolicySource: String, Codable, Equatable, Sendable {
    case daemonStatus
    case fallbackUnavailable
}

public struct ViftyCtlExitCodes: Codable, Equatable, Sendable {
    public var success: Int32
    public var commandFailure: Int32
    public var usage: Int32
    public var unavailable: Int32
    public var blockedReadiness: Int32

    public init(
        success: Int32 = 0,
        commandFailure: Int32 = 1,
        usage: Int32 = 64,
        unavailable: Int32 = 69,
        blockedReadiness: Int32 = 75
    ) {
        self.success = success
        self.commandFailure = commandFailure
        self.usage = usage
        self.unavailable = unavailable
        self.blockedReadiness = blockedReadiness
    }
}

public enum ViftyCtlCommandErrorRecoveryAction: String, Codable, Equatable, Sendable {
    case runDiagnose = "runDiagnose"
    case repairHelper = "repairHelper"
    case fixArguments = "fixArguments"
    case fixChildCommand = "fixChildCommand"
    case restoreAutoBeforeRetry = "restoreAutoBeforeRetry"
    case waitBeforeRetry = "waitBeforeRetry"

    public static func recommended(for errorCode: AgentControlErrorCode?) -> ViftyCtlCommandErrorRecoveryAction {
        switch errorCode {
        case .helperUnreachable:
            return .repairHelper
        case .invalidArguments:
            return .fixArguments
        case .childCommandFailed:
            return .fixChildCommand
        case .restoreRequested:
            return .restoreAutoBeforeRetry
        case .prepareRateLimited:
            return .waitBeforeRetry
        case nil,
             .disabled,
             .unsupportedHardware,
             .temperatureSensorUnavailable,
             .noControllableFans,
             .policyDenied,
             .durationTooLong,
             .rpmOutOfRange,
             .thermalCritical,
             .leaseNotFound,
             .restoreFailed:
            return .runDiagnose
        }
    }
}

public struct ViftyCtlCommandErrorReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var schemaID: String
    public var command: String
    public var errorCode: AgentControlErrorCode?
    public var message: String
    public var safeToProceed: Bool
    public var recommendedRecoveryAction: ViftyCtlCommandErrorRecoveryAction
    public var coolingLeasePrepared: Bool
    public var autoRestoreAttempted: Bool
    public var autoRestoreSucceeded: Bool?
    public var retryAfterSeconds: Int?
    public var generatedAt: Date

    public init(
        schemaVersion: Int = 1,
        schemaID: String = ViftyCtlSchemaReferences.schemaIDs.commandError,
        command: String,
        errorCode: AgentControlErrorCode?,
        message: String,
        safeToProceed: Bool = false,
        recommendedRecoveryAction: ViftyCtlCommandErrorRecoveryAction? = nil,
        coolingLeasePrepared: Bool = false,
        autoRestoreAttempted: Bool = false,
        autoRestoreSucceeded: Bool? = nil,
        retryAfterSeconds: Int? = nil,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.command = command
        self.errorCode = errorCode
        self.message = message
        self.safeToProceed = safeToProceed
        self.recommendedRecoveryAction = recommendedRecoveryAction ?? .recommended(for: errorCode)
        self.coolingLeasePrepared = coolingLeasePrepared
        self.autoRestoreAttempted = autoRestoreAttempted
        self.autoRestoreSucceeded = autoRestoreSucceeded
        self.retryAfterSeconds = retryAfterSeconds
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schemaID
        case command
        case errorCode
        case message
        case safeToProceed
        case recommendedRecoveryAction
        case coolingLeasePrepared
        case autoRestoreAttempted
        case autoRestoreSucceeded
        case retryAfterSeconds
        case generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        schemaID = try container.decodeIfPresent(String.self, forKey: .schemaID)
            ?? ViftyCtlSchemaReferences.schemaIDs.commandError
        command = try container.decode(String.self, forKey: .command)
        errorCode = try container.decodeIfPresent(AgentControlErrorCode.self, forKey: .errorCode)
        message = try container.decode(String.self, forKey: .message)
        safeToProceed = try container.decode(Bool.self, forKey: .safeToProceed)
        recommendedRecoveryAction = try container.decodeIfPresent(
            ViftyCtlCommandErrorRecoveryAction.self,
            forKey: .recommendedRecoveryAction
        ) ?? .recommended(for: errorCode)
        coolingLeasePrepared = try container.decodeIfPresent(Bool.self, forKey: .coolingLeasePrepared) ?? false
        autoRestoreAttempted = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreAttempted) ?? false
        autoRestoreSucceeded = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreSucceeded)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(schemaID, forKey: .schemaID)
        try container.encode(command, forKey: .command)
        try container.encode(errorCode, forKey: .errorCode)
        try container.encode(message, forKey: .message)
        try container.encode(safeToProceed, forKey: .safeToProceed)
        try container.encode(recommendedRecoveryAction, forKey: .recommendedRecoveryAction)
        try container.encode(coolingLeasePrepared, forKey: .coolingLeasePrepared)
        try container.encode(autoRestoreAttempted, forKey: .autoRestoreAttempted)
        if let autoRestoreSucceeded {
            try container.encode(autoRestoreSucceeded, forKey: .autoRestoreSucceeded)
        } else {
            try container.encodeNil(forKey: .autoRestoreSucceeded)
        }
        try container.encodeIfPresent(retryAfterSeconds, forKey: .retryAfterSeconds)
        try container.encode(generatedAt, forKey: .generatedAt)
    }
}

public struct ViftyCtlRunReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var schemaID: String
    public var command: String
    public var coolingLeasePrepared: Bool
    public var autoRestoreAttempted: Bool
    public var autoRestoreSucceeded: Bool
    public var childExitCode: Int32
    public var autoRestoreError: String?
    public var generatedAt: Date

    public init(
        schemaVersion: Int = 1,
        schemaID: String = ViftyCtlSchemaReferences.schemaIDs.run,
        command: String = "run",
        coolingLeasePrepared: Bool = true,
        autoRestoreAttempted: Bool = true,
        autoRestoreSucceeded: Bool,
        childExitCode: Int32,
        autoRestoreError: String? = nil,
        generatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.command = command
        self.coolingLeasePrepared = coolingLeasePrepared
        self.autoRestoreAttempted = autoRestoreAttempted
        self.autoRestoreSucceeded = autoRestoreSucceeded
        self.childExitCode = childExitCode
        self.autoRestoreError = autoRestoreError
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schemaID
        case command
        case coolingLeasePrepared
        case autoRestoreAttempted
        case autoRestoreSucceeded
        case childExitCode
        case autoRestoreError
        case generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        schemaID = try container.decodeIfPresent(String.self, forKey: .schemaID)
            ?? ViftyCtlSchemaReferences.schemaIDs.run
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? "run"
        coolingLeasePrepared = try container.decodeIfPresent(Bool.self, forKey: .coolingLeasePrepared) ?? true
        autoRestoreAttempted = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreAttempted) ?? true
        autoRestoreSucceeded = try container.decode(Bool.self, forKey: .autoRestoreSucceeded)
        childExitCode = try container.decode(Int32.self, forKey: .childExitCode)
        autoRestoreError = try container.decodeIfPresent(String.self, forKey: .autoRestoreError)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(schemaID, forKey: .schemaID)
        try container.encode(command, forKey: .command)
        try container.encode(coolingLeasePrepared, forKey: .coolingLeasePrepared)
        try container.encode(autoRestoreAttempted, forKey: .autoRestoreAttempted)
        try container.encode(autoRestoreSucceeded, forKey: .autoRestoreSucceeded)
        try container.encode(childExitCode, forKey: .childExitCode)
        if let autoRestoreError {
            try container.encode(autoRestoreError, forKey: .autoRestoreError)
        } else {
            try container.encodeNil(forKey: .autoRestoreError)
        }
        try container.encode(generatedAt, forKey: .generatedAt)
    }
}

public struct ViftyCtlAuditReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var readOnly: Bool
    public var coolingCommandsRun: Bool
    public var limit: Int
    public var eventCount: Int
    public var events: [AgentControlAuditEvent]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date,
        readOnly: Bool = true,
        coolingCommandsRun: Bool = false,
        limit: Int,
        events: [AgentControlAuditEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.readOnly = readOnly
        self.coolingCommandsRun = coolingCommandsRun
        self.limit = limit
        self.eventCount = events.count
        self.events = events
    }
}

public struct ViftyCtlStatusReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var schemaID: String
    public var generatedAt: Date
    public var enabled: Bool
    public var activeLease: AgentCoolingLease?
    public var lastDecision: AgentControlDecision?
    public var lastErrorCode: AgentControlErrorCode?
    public var policy: AgentControlPolicySnapshot?

    public init(
        schemaVersion: Int = 1,
        schemaID: String = ViftyCtlSchemaReferences.schemaIDs.status,
        generatedAt: Date,
        status: AgentControlStatus
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.generatedAt = generatedAt
        self.enabled = status.enabled
        self.activeLease = status.activeLease
        self.lastDecision = status.lastDecision
        self.lastErrorCode = status.lastErrorCode
        self.policy = status.policy
    }
}

public protocol ViftyCtlAgentControlClient: Sendable {
    func snapshot() async throws -> HardwareSnapshot
    func status() async throws -> AgentControlStatus
    func auditEvents(limit: Int) async throws -> [AgentControlAuditEvent]
    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus
    func restore(reason: String) async throws -> AgentControlStatus
}

public protocol ViftyCtlProcessRunning: Sendable {
    func resolve(_ arguments: [String]) throws -> [String]
    func run(_ arguments: [String]) throws -> Int32
}

private struct ViftyCtlForceRetryWaitError: Error, LocalizedError, Sendable {
    var underlyingMessage: String
    var retryAfterSeconds: Int?

    var errorDescription: String? {
        "Force retry wait was interrupted before retrying rate-limited prepare request: \(underlyingMessage)"
    }
}

private struct ViftyCtlChildCommandError: Error, LocalizedError, Sendable {
    var message: String

    var errorDescription: String? {
        message
    }
}

public extension ViftyCtlProcessRunning {
    func resolve(_ arguments: [String]) throws -> [String] {
        arguments
    }
}

public struct ViftyCtlDaemonClient: ViftyCtlAgentControlClient {
    private let client: ViftyDaemonClient

    public init(client: ViftyDaemonClient = ViftyDaemonClient()) {
        self.client = client
    }

    public func status() async throws -> AgentControlStatus {
        try await client.agentControlStatus()
    }

    public func snapshot() async throws -> HardwareSnapshot {
        try await client.snapshot()
    }

    public func auditEvents(limit: Int) async throws -> [AgentControlAuditEvent] {
        try await client.agentControlAudit(limit: limit)
    }

    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        try await client.prepareAgentControl(request)
    }

    public func restore(reason: String) async throws -> AgentControlStatus {
        try await client.restoreAgentControl(reason: reason)
    }
}

public struct ViftyCtlRunner: Sendable {
    private let client: any ViftyCtlAgentControlClient
    private let processRunner: any ViftyCtlProcessRunning
    private let thermalReader: @Sendable () -> ThermalPressure
    private let manualControlActiveReader: @Sendable () -> Bool
    private let appPreferencesReader: @Sendable () -> ViftyAppPreferencesDiagnostic
    private let manualControlClearer: @Sendable () -> Void
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (UInt64) async throws -> Void

    public init(
        client: any ViftyCtlAgentControlClient,
        processRunner: any ViftyCtlProcessRunning,
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        manualControlActiveReader: @escaping @Sendable () -> Bool = { ManualControlMarker().wasManualControlActive },
        appPreferencesReader: @escaping @Sendable () -> ViftyAppPreferencesDiagnostic = {
            ViftyAppPreferencesDiagnosticReader().read()
        },
        manualControlClearer: @escaping @Sendable () -> Void = { ManualControlMarker().clear() },
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.client = client
        self.processRunner = processRunner
        self.thermalReader = thermalReader
        self.manualControlActiveReader = manualControlActiveReader
        self.appPreferencesReader = appPreferencesReader
        self.manualControlClearer = manualControlClearer
        self.now = now
        self.sleep = sleep
    }

    public func run(_ command: ViftyCtlCommand) async throws -> ViftyCtlResult {
        do {
            switch command {
            case .status(let json):
                let status = try await client.status()
                let stdout = try formatStatus(status, json: json)
                return ViftyCtlResult(stdout: stdout)
            case .capabilities(let json):
                let capabilities = await capabilitiesReport()
                if json {
                    return ViftyCtlResult(
                        stdout: try encodeJSON(capabilities) + "\n",
                        exitCode: capabilities.daemonStatusAvailable ? 0 : capabilities.exitCodes.unavailable
                    )
                }
                let stderr = capabilities.agentControlStatusError.map {
                    "viftyctl capabilities: daemon status unavailable; policy is a disabled fallback: \($0)\n"
                } ?? ""
                return ViftyCtlResult(
                    stdout: capabilities.commands.joined(separator: "\n") + "\n",
                    stderr: stderr,
                    exitCode: capabilities.daemonStatusAvailable ? 0 : capabilities.exitCodes.unavailable
                )
            case .diagnose(let json):
                let report = await diagnoseReport()
                if json {
                    return ViftyCtlResult(
                        stdout: try encodeJSON(report) + "\n",
                        exitCode: diagnoseExitCode(for: report)
                    )
                }
                return ViftyCtlResult(
                    stdout: formatHumanReadable(report) + "\n",
                    exitCode: diagnoseExitCode(for: report)
                )
            case .audit(let limit, let json):
                let events = try await client.auditEvents(limit: limit)
                let report = ViftyCtlAuditReport(
                    generatedAt: now(),
                    limit: limit,
                    events: events
                )
                if json {
                    return ViftyCtlResult(stdout: try encodeJSON(report) + "\n")
                }
                return ViftyCtlResult(stdout: formatHumanReadable(report) + "\n")
            case .prepare(let request, let json, let force):
                let status = try await prepareWithOptionalForceRetry(request, force: force)
                let stdout = try formatStatus(status, json: json)
                return ViftyCtlResult(
                    stdout: stdout,
                    exitCode: prepareSucceeded(status, request: request) ? 0 : 1
                )
            case .restoreAuto(let reason, let json):
                let status = try await client.restore(reason: reason)
                manualControlClearer()
                let stdout = try formatStatus(status, json: json)
                return ViftyCtlResult(stdout: stdout)
            case .run(let request, let childArguments, let json, let force):
                let resolvedChildArguments: [String]
                do {
                    resolvedChildArguments = try processRunner.resolve(childArguments)
                } catch {
                    throw ViftyCtlChildCommandError(message: error.localizedDescription)
                }
                let prepareStatus = try await prepareWithOptionalForceRetry(request, force: force)
                guard prepareSucceeded(prepareStatus, request: request) else {
                    let message = prepareFailureMessage(prepareStatus, request: request)
                    if json {
                        return try commandErrorResult(
                            command: command,
                            errorCode: prepareFailureCode(prepareStatus),
                            message: message,
                            retryAfterSeconds: prepareRetryAfterSeconds(prepareStatus)
                        )
                    }
                    let stderr = "viftyctl run: prepare denied — \(message)\n"
                    return ViftyCtlResult(stderr: stderr, exitCode: 1)
                }
                do {
                    let exitCode = try processRunner.run(resolvedChildArguments)
                    return try await restoreAfterRun(
                        reason: "viftyctl run child exited with \(exitCode)",
                        childExitCode: exitCode,
                        json: json
                    )
                } catch {
                    let reason = "viftyctl run failed to launch child: \(error.localizedDescription)"
                    do {
                        _ = try await client.restore(reason: reason)
                    } catch {
                        let message = "\(reason). Auto restore also failed: \(error.localizedDescription)"
                        if json {
                            return try commandErrorResult(
                                command: command,
                                errorCode: .restoreFailed,
                                message: message,
                                coolingLeasePrepared: true,
                                autoRestoreAttempted: true,
                                autoRestoreSucceeded: false
                            )
                        }
                        throw ViftyError.helperRejected(message)
                    }
                    if json {
                        return try commandErrorResult(
                            command: command,
                            errorCode: .childCommandFailed,
                            message: error.localizedDescription,
                            coolingLeasePrepared: true,
                            autoRestoreAttempted: true,
                            autoRestoreSucceeded: true
                        )
                    }
                    throw error
                }
            }
        } catch {
            guard jsonRequested(for: command) else { throw error }
            return try commandErrorResult(command: command, error: error)
        }
    }

    private func commandErrorResult(
        command: ViftyCtlCommand,
        error: any Error,
        coolingLeasePrepared: Bool = false,
        autoRestoreAttempted: Bool = false,
        autoRestoreSucceeded: Bool? = nil
    ) throws -> ViftyCtlResult {
        try commandErrorResult(
            command: command,
            errorCode: commandErrorCode(for: error),
            message: error.localizedDescription,
            coolingLeasePrepared: coolingLeasePrepared,
            autoRestoreAttempted: autoRestoreAttempted,
            autoRestoreSucceeded: autoRestoreSucceeded,
            retryAfterSeconds: commandRetryAfterSeconds(for: error)
        )
    }

    private func commandErrorResult(
        command: ViftyCtlCommand,
        errorCode: AgentControlErrorCode?,
        message: String,
        coolingLeasePrepared: Bool = false,
        autoRestoreAttempted: Bool = false,
        autoRestoreSucceeded: Bool? = nil,
        retryAfterSeconds: Int? = nil
    ) throws -> ViftyCtlResult {
        let report = ViftyCtlCommandErrorReport(
            command: commandName(for: command),
            errorCode: errorCode,
            message: message,
            coolingLeasePrepared: coolingLeasePrepared,
            autoRestoreAttempted: autoRestoreAttempted,
            autoRestoreSucceeded: autoRestoreSucceeded,
            retryAfterSeconds: retryAfterSeconds,
            generatedAt: now()
        )
        return ViftyCtlResult(stdout: try encodeJSON(report) + "\n", exitCode: 1)
    }

    private func jsonRequested(for command: ViftyCtlCommand) -> Bool {
        switch command {
        case .status(let json),
             .capabilities(let json),
             .diagnose(let json),
             .audit(_, let json):
            return json
        case .prepare(_, let json, _),
             .restoreAuto(_, let json):
            return json
        case .run(_, _, let json, _):
            return json
        }
    }

    private func commandName(for command: ViftyCtlCommand) -> String {
        switch command {
        case .status:
            return "status"
        case .capabilities:
            return "capabilities"
        case .diagnose:
            return "diagnose"
        case .audit:
            return "audit"
        case .prepare:
            return "prepare"
        case .restoreAuto:
            return "restore-auto"
        case .run:
            return "run"
        }
    }

    private func commandErrorCode(for error: any Error) -> AgentControlErrorCode? {
        if error is ViftyCtlForceRetryWaitError {
            return .prepareRateLimited
        }
        if error is ViftyCtlChildCommandError {
            return .childCommandFailed
        }
        if error is ViftyCtlParseError {
            return .invalidArguments
        }
        if error is DecodingError || error is EncodingError {
            return .invalidArguments
        }
        if case ViftyError.helperRejected = error {
            return .helperUnreachable
        }
        return nil
    }

    private func commandRetryAfterSeconds(for error: any Error) -> Int? {
        guard let waitError = error as? ViftyCtlForceRetryWaitError else {
            return nil
        }
        return waitError.retryAfterSeconds
    }

    private func capabilitiesReport() async -> ViftyCtlCapabilities {
        do {
            let status = try await client.status()
            let policy = status.policy ?? AgentControlPolicy(enabled: status.enabled).snapshot
            return ViftyCtlCapabilities(
                policy: policy,
                policyStatusAvailable: status.policy != nil
            )
        } catch {
            return ViftyCtlCapabilities(
                policy: AgentControlPolicy(enabled: false).snapshot,
                policySource: .fallbackUnavailable,
                daemonStatusAvailable: false,
                policyStatusAvailable: false,
                agentControlStatusError: error.localizedDescription
            )
        }
    }

    private func diagnoseReport() async -> ViftyCtlReadinessReport {
        let generatedAt = now()
        async let snapshotProbe = capture { try await client.snapshot() }
        async let statusProbe = capture { try await client.status() }
        let (snapshotResult, statusResult) = await (snapshotProbe, statusProbe)

        let snapshot: HardwareSnapshot
        let daemonSnapshotError: String?
        switch snapshotResult {
        case .success(let value):
            snapshot = value
            daemonSnapshotError = nil
        case .failure(let error):
            snapshot = unavailableHardwareSnapshot(capturedAt: generatedAt)
            daemonSnapshotError = error.localizedDescription
        }

        let status: AgentControlStatus
        let agentControlStatusError: String?
        switch statusResult {
        case .success(let value):
            status = value
            agentControlStatusError = nil
        case .failure(let error):
            status = unavailableAgentControlStatus(error: error)
            agentControlStatusError = error.localizedDescription
        }

        return ViftyCtlReadinessReport.make(
            snapshot: snapshot,
            agentControl: status,
            thermalPressure: thermalReader(),
            generatedAt: generatedAt,
            manualControlActive: manualControlActiveReader(),
            appPreferences: appPreferencesReader(),
            daemonSnapshotError: daemonSnapshotError,
            agentControlStatusError: agentControlStatusError
        )
    }

    private func capture<T: Sendable>(_ operation: () async throws -> T) async -> Result<T, any Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private func unavailableHardwareSnapshot(capturedAt: Date) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "unknown",
            isAppleSilicon: false,
            isMacBookPro: false,
            capturedAt: capturedAt
        )
    }

    private func unavailableAgentControlStatus(error: any Error) -> AgentControlStatus {
        let message = "Daemon agent-control status is unavailable: \(error.localizedDescription)"
        return AgentControlStatus(
            enabled: false,
            activeLease: nil,
            lastDecision: .denied(.helperUnreachable, message: message),
            lastErrorCode: .helperUnreachable
        )
    }

    private func format<T: Encodable>(_ value: T, json: Bool) throws -> String {
        if json {
            return try encodeJSON(value) + "\n"
        }

        if let strings = value as? [String] {
            return strings.joined(separator: "\n") + "\n"
        }

        return String(describing: value) + "\n"
    }

    private func formatStatus(_ status: AgentControlStatus, json: Bool) throws -> String {
        if json {
            return try encodeJSON(ViftyCtlStatusReport(generatedAt: now(), status: status)) + "\n"
        }
        return try format(status, json: false)
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func formatHumanReadable(_ report: ViftyCtlReadinessReport) -> String {
        var lines = [
            "state=\(report.state.rawValue)",
            "agentAction=\(report.recommendedAgentAction?.rawValue ?? "unknown") safeToRequestCooling=\(report.safeToRequestCooling.map(String.init) ?? "unknown")",
            "recoveryAction=\(report.recommendedRecoveryAction.rawValue)",
            "model=\(report.modelIdentifier) appleSilicon=\(report.isAppleSilicon) macBookPro=\(report.isMacBookPro)",
            "fans=\(report.fanCount) controllable=\(report.controllableFanCount) temperatures=\(report.temperatureSensorCount) thermal=\(report.thermalPressure.displayName)",
            "agentControl=\(report.agentControl.enabled ? "enabled" : "disabled")"
        ]

        for check in report.checks {
            let mark = check.passed ? "pass" : reportMark(for: check.severity)
            lines.append("[\(mark)] \(check.id): \(check.message)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatHumanReadable(_ report: ViftyCtlAuditReport) -> String {
        guard !report.events.isEmpty else {
            return "No agent-control audit events."
        }

        let formatter = ISO8601DateFormatter()
        return report.events.map { event in
            let lease = event.leaseID.map { " lease=\($0)" } ?? ""
            return "\(formatter.string(from: event.timestamp)) \(event.action)\(lease) - \(event.message)"
        }.joined(separator: "\n")
    }

    private func reportMark(for severity: ViftyCtlReadinessSeverity) -> String {
        switch severity {
        case .info: "info"
        case .warning: "warn"
        case .error: "fail"
        }
    }

    private func diagnoseExitCode(for report: ViftyCtlReadinessReport) -> Int32 {
        report.state == .blocked ? 75 : 0
    }

    private func prepareWithOptionalForceRetry(_ request: AgentControlRequest, force: Bool) async throws -> AgentControlStatus {
        let status = try await client.prepare(request)
        guard force, status.lastErrorCode == .prepareRateLimited else {
            return status
        }

        do {
            try await sleep(retryDelayNanoseconds(for: status))
        } catch {
            throw ViftyCtlForceRetryWaitError(
                underlyingMessage: error.localizedDescription,
                retryAfterSeconds: rateLimitRetryAfterSeconds(for: status)
            )
        }
        return try await client.prepare(request)
    }

    private func retryDelayNanoseconds(for status: AgentControlStatus) -> UInt64 {
        UInt64(rateLimitRetryAfterSeconds(for: status)) * 1_000_000_000
    }

    private func prepareRetryAfterSeconds(_ status: AgentControlStatus) -> Int? {
        prepareFailureCode(status) == .prepareRateLimited ? rateLimitRetryAfterSeconds(for: status) : nil
    }

    private func rateLimitRetryAfterSeconds(for status: AgentControlStatus) -> Int {
        let seconds = status.lastDecision?.retryAfterSeconds ?? status.policy?.prepareCooldownSeconds ?? 30
        return max(0, seconds)
    }

    private func restoreAfterRun(
        reason: String,
        childExitCode: Int32,
        json: Bool
    ) async throws -> ViftyCtlResult {
        do {
            _ = try await client.restore(reason: reason)
            if json {
                let report = ViftyCtlRunReport(
                    autoRestoreSucceeded: true,
                    childExitCode: childExitCode,
                    generatedAt: now()
                )
                return ViftyCtlResult(stdout: try encodeJSON(report) + "\n", exitCode: childExitCode)
            }
            return ViftyCtlResult(exitCode: childExitCode)
        } catch {
            if json {
                let report = ViftyCtlRunReport(
                    autoRestoreSucceeded: false,
                    childExitCode: childExitCode,
                    autoRestoreError: error.localizedDescription,
                    generatedAt: now()
                )
                return ViftyCtlResult(
                    stdout: try encodeJSON(report) + "\n",
                    exitCode: childExitCode == 0 ? 1 : childExitCode
                )
            }
            let stderr = "viftyctl run: Auto restore failed after child exited with \(childExitCode): \(error.localizedDescription). The daemon lease monitor remains the safety fallback until expiry.\n"
            return ViftyCtlResult(stderr: stderr, exitCode: childExitCode == 0 ? 1 : childExitCode)
        }
    }

    private func prepareSucceeded(_ status: AgentControlStatus, request: AgentControlRequest) -> Bool {
        guard status.lastErrorCode == nil,
              let lease = status.activeLease,
              lease.request == request else {
            return false
        }
        return true
    }

    private func prepareFailureMessage(_ status: AgentControlStatus, request: AgentControlRequest) -> String {
        if let lease = status.activeLease, lease.request != request {
            return "daemon returned a lease that does not match this run request"
        }
        if status.activeLease == nil, status.lastDecision?.allowed == true {
            return "daemon did not return an active cooling lease"
        }
        if let decision = status.lastDecision {
            return decision.message
        }
        if let errorCode = status.lastErrorCode {
            return errorCode.rawValue
        }
        if status.activeLease == nil {
            return "daemon did not return an active cooling lease"
        }
        return "daemon returned a lease that does not match this run request"
    }

    private func prepareFailureCode(_ status: AgentControlStatus) -> AgentControlErrorCode? {
        status.lastErrorCode ?? status.lastDecision?.errorCode
    }
}
