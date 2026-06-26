import Foundation

public enum ViftyCtlReadinessState: String, Codable, Equatable, Sendable {
    case ready
    case degraded
    case blocked
}

public enum ViftyCtlRecommendedAgentAction: String, Codable, Equatable, Sendable {
    case requestCooling
    case requestCoolingWithCaution
    case restoreAutoBeforeRequestingCooling
    case doNotRequestCooling
}

public enum ViftyCtlReadinessRecoveryAction: String, Codable, Equatable, Sendable {
    case none
    case repairHelper
    case restoreAutoBeforeRetry
    case backOffWorkload
    case inspectPolicy
    case collectHardwareEvidence
}

public enum ViftyCtlReadinessSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct ViftyCtlReadinessCheck: Codable, Equatable, Sendable {
    public var id: String
    public var severity: ViftyCtlReadinessSeverity
    public var passed: Bool
    public var message: String

    public init(id: String, severity: ViftyCtlReadinessSeverity, passed: Bool, message: String) {
        self.id = id
        self.severity = severity
        self.passed = passed
        self.message = message
    }
}

public struct ViftyCtlOperatorRecoveryCommand: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var command: String
    public var workingDirectoryHint: String
    public var requiresUserApproval: Bool
    public var safeForAgentsToRunAutomatically: Bool
    public var notes: [String]

    public init(
        id: String,
        title: String,
        command: String,
        workingDirectoryHint: String,
        requiresUserApproval: Bool,
        safeForAgentsToRunAutomatically: Bool,
        notes: [String]
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.workingDirectoryHint = workingDirectoryHint
        self.requiresUserApproval = requiresUserApproval
        self.safeForAgentsToRunAutomatically = safeForAgentsToRunAutomatically
        self.notes = notes
    }
}

public struct ViftyCtlFanReport: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var currentRPM: Int
    public var minimumRPM: Int
    public var maximumRPM: Int
    public var controllable: Bool
    public var hardwareMode: String?
    public var hardwareModeRawValue: Int?
    public var hardwareModeKey: String?
    public var targetRPM: Int?

    public init(fan: Fan) {
        self.id = fan.id
        self.name = fan.name
        self.currentRPM = fan.currentRPM
        self.minimumRPM = fan.minimumRPM
        self.maximumRPM = fan.maximumRPM
        self.controllable = fan.controllable
        self.hardwareMode = fan.hardwareMode?.displayName
        self.hardwareModeRawValue = fan.hardwareMode?.rawValue
        self.hardwareModeKey = fan.hardwareModeKey
        self.targetRPM = fan.targetRPM
    }
}

public struct ViftyCtlTemperatureSensorReport: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var celsius: Double
    public var source: String

    public init(sensor: TemperatureSensor) {
        self.id = sensor.id
        self.name = sensor.name
        self.celsius = sensor.celsius
        self.source = sensor.source.rawValue
    }
}

public struct ViftyCtlDaemonRuntimeDiagnostic: Codable, Equatable, Sendable {
    public static let standardInstalledDaemonPath = "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon"

    public static var unavailable: ViftyCtlDaemonRuntimeDiagnostic {
        ViftyCtlDaemonRuntimeDiagnostic(
            installedDaemonPath: standardInstalledDaemonPath,
            installedDaemonPresent: false,
            installedDaemonSHA256: nil,
            expectedDaemonPath: nil,
            expectedDaemonPresent: false,
            expectedDaemonSHA256: nil,
            matchesExpectedDaemon: nil,
            matchRequired: false
        )
    }

    public var installedDaemonPath: String
    public var installedDaemonPresent: Bool
    public var installedDaemonSHA256: String?
    public var expectedDaemonPath: String?
    public var expectedDaemonPresent: Bool
    public var expectedDaemonSHA256: String?
    public var matchesExpectedDaemon: Bool?
    public var matchRequired: Bool

    public init(
        installedDaemonPath: String,
        installedDaemonPresent: Bool,
        installedDaemonSHA256: String?,
        expectedDaemonPath: String?,
        expectedDaemonPresent: Bool,
        expectedDaemonSHA256: String?,
        matchesExpectedDaemon: Bool?,
        matchRequired: Bool
    ) {
        self.installedDaemonPath = installedDaemonPath
        self.installedDaemonPresent = installedDaemonPresent
        self.installedDaemonSHA256 = installedDaemonSHA256
        self.expectedDaemonPath = expectedDaemonPath
        self.expectedDaemonPresent = expectedDaemonPresent
        self.expectedDaemonSHA256 = expectedDaemonSHA256
        self.matchesExpectedDaemon = matchesExpectedDaemon
        self.matchRequired = matchRequired
    }
}

public struct ViftyCtlReadinessReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var state: ViftyCtlReadinessState
    public var recommendedAgentAction: ViftyCtlRecommendedAgentAction?
    public var recommendedRecoveryAction: ViftyCtlReadinessRecoveryAction
    public var recoverySteps: [String]
    public var operatorRecoveryCommands: [ViftyCtlOperatorRecoveryCommand]?
    public var safeToRequestCooling: Bool?
    public var daemonControlPathReady: Bool
    public var manualControlActive: Bool
    public var failedCheckIDs: [String]
    public var coolingBlockerIDs: [String]
    public var appPreferences: ViftyAppPreferencesDiagnostic
    public var daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic
    public var modelIdentifier: String
    public var isAppleSilicon: Bool
    public var isMacBookPro: Bool
    public var thermalPressure: ThermalPressure
    public var fanCount: Int
    public var controllableFanCount: Int
    public var temperatureSensorCount: Int
    public var highestTemperatureCelsius: Double?
    public var fans: [ViftyCtlFanReport]
    public var temperatureSensors: [ViftyCtlTemperatureSensorReport]
    public var agentControl: AgentControlStatus
    public var daemonSnapshotError: String?
    public var agentControlStatusError: String?
    public var checks: [ViftyCtlReadinessCheck]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case state
        case recommendedAgentAction
        case recommendedRecoveryAction
        case recoverySteps
        case operatorRecoveryCommands
        case safeToRequestCooling
        case daemonControlPathReady
        case manualControlActive
        case failedCheckIDs
        case coolingBlockerIDs
        case appPreferences
        case daemonRuntime
        case modelIdentifier
        case isAppleSilicon
        case isMacBookPro
        case thermalPressure
        case fanCount
        case controllableFanCount
        case temperatureSensorCount
        case highestTemperatureCelsius
        case fans
        case temperatureSensors
        case agentControl
        case daemonSnapshotError
        case agentControlStatusError
        case checks
    }

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date,
        state: ViftyCtlReadinessState,
        recommendedAgentAction: ViftyCtlRecommendedAgentAction? = nil,
        recommendedRecoveryAction: ViftyCtlReadinessRecoveryAction? = nil,
        recoverySteps: [String]? = nil,
        operatorRecoveryCommands: [ViftyCtlOperatorRecoveryCommand]? = nil,
        safeToRequestCooling: Bool? = nil,
        daemonControlPathReady: Bool? = nil,
        manualControlActive: Bool = false,
        appPreferences: ViftyAppPreferencesDiagnostic = .unavailable,
        daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic = .unavailable,
        modelIdentifier: String,
        isAppleSilicon: Bool,
        isMacBookPro: Bool,
        thermalPressure: ThermalPressure,
        fanCount: Int,
        controllableFanCount: Int,
        temperatureSensorCount: Int,
        highestTemperatureCelsius: Double?,
        fans: [ViftyCtlFanReport],
        temperatureSensors: [ViftyCtlTemperatureSensorReport],
        agentControl: AgentControlStatus,
        daemonSnapshotError: String? = nil,
        agentControlStatusError: String? = nil,
        checks: [ViftyCtlReadinessCheck]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.state = state
        let resolvedAction = recommendedAgentAction ?? Self.recommendedAgentAction(for: state, checks: checks)
        self.recommendedAgentAction = resolvedAction
        let resolvedRecoveryAction = recommendedRecoveryAction
            ?? Self.recommendedRecoveryAction(for: state, agentAction: resolvedAction, checks: checks)
        self.recommendedRecoveryAction = resolvedRecoveryAction
        self.recoverySteps = recoverySteps ?? Self.recoverySteps(for: resolvedRecoveryAction, checks: checks)
        self.operatorRecoveryCommands = operatorRecoveryCommands
            ?? Self.operatorRecoveryCommands(
                for: resolvedRecoveryAction,
                checks: checks,
                daemonRuntime: daemonRuntime
            )
        self.safeToRequestCooling = safeToRequestCooling ?? Self.safeToRequestCooling(for: resolvedAction)
        self.daemonControlPathReady = daemonControlPathReady ?? Self.daemonControlPathReady(from: checks)
        self.manualControlActive = manualControlActive
        self.failedCheckIDs = Self.failedCheckIDs(from: checks)
        self.coolingBlockerIDs = Self.coolingBlockerIDs(from: checks)
        self.appPreferences = appPreferences
        self.daemonRuntime = daemonRuntime
        self.modelIdentifier = modelIdentifier
        self.isAppleSilicon = isAppleSilicon
        self.isMacBookPro = isMacBookPro
        self.thermalPressure = thermalPressure
        self.fanCount = fanCount
        self.controllableFanCount = controllableFanCount
        self.temperatureSensorCount = temperatureSensorCount
        self.highestTemperatureCelsius = highestTemperatureCelsius
        self.fans = fans
        self.temperatureSensors = temperatureSensors
        self.agentControl = agentControl
        self.daemonSnapshotError = daemonSnapshotError
        self.agentControlStatusError = agentControlStatusError
        self.checks = checks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(ViftyCtlReadinessState.self, forKey: .state)
        let checks = try container.decode([ViftyCtlReadinessCheck].self, forKey: .checks)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            state: state,
            recommendedAgentAction: try container.decodeIfPresent(
                ViftyCtlRecommendedAgentAction.self,
                forKey: .recommendedAgentAction
            ),
            recommendedRecoveryAction: try container.decodeIfPresent(
                ViftyCtlReadinessRecoveryAction.self,
                forKey: .recommendedRecoveryAction
            ),
            recoverySteps: try container.decodeIfPresent([String].self, forKey: .recoverySteps),
            operatorRecoveryCommands: try container.decodeIfPresent(
                [ViftyCtlOperatorRecoveryCommand].self,
                forKey: .operatorRecoveryCommands
            ),
            safeToRequestCooling: try container.decodeIfPresent(Bool.self, forKey: .safeToRequestCooling),
            daemonControlPathReady: try container.decodeIfPresent(Bool.self, forKey: .daemonControlPathReady),
            manualControlActive: try container.decodeIfPresent(Bool.self, forKey: .manualControlActive) ?? false,
            appPreferences: try container.decodeIfPresent(
                ViftyAppPreferencesDiagnostic.self,
                forKey: .appPreferences
            ) ?? .unavailable,
            daemonRuntime: try container.decodeIfPresent(
                ViftyCtlDaemonRuntimeDiagnostic.self,
                forKey: .daemonRuntime
            ) ?? .unavailable,
            modelIdentifier: try container.decode(String.self, forKey: .modelIdentifier),
            isAppleSilicon: try container.decode(Bool.self, forKey: .isAppleSilicon),
            isMacBookPro: try container.decode(Bool.self, forKey: .isMacBookPro),
            thermalPressure: try container.decode(ThermalPressure.self, forKey: .thermalPressure),
            fanCount: try container.decode(Int.self, forKey: .fanCount),
            controllableFanCount: try container.decode(Int.self, forKey: .controllableFanCount),
            temperatureSensorCount: try container.decode(Int.self, forKey: .temperatureSensorCount),
            highestTemperatureCelsius: try container.decodeIfPresent(
                Double.self,
                forKey: .highestTemperatureCelsius
            ),
            fans: try container.decode([ViftyCtlFanReport].self, forKey: .fans),
            temperatureSensors: try container.decode(
                [ViftyCtlTemperatureSensorReport].self,
                forKey: .temperatureSensors
            ),
            agentControl: try container.decode(AgentControlStatus.self, forKey: .agentControl),
            daemonSnapshotError: try container.decodeIfPresent(String.self, forKey: .daemonSnapshotError),
            agentControlStatusError: try container.decodeIfPresent(String.self, forKey: .agentControlStatusError),
            checks: checks
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(recommendedAgentAction, forKey: .recommendedAgentAction)
        try container.encode(recommendedRecoveryAction, forKey: .recommendedRecoveryAction)
        try container.encode(recoverySteps, forKey: .recoverySteps)
        try container.encodeIfPresent(operatorRecoveryCommands, forKey: .operatorRecoveryCommands)
        try container.encodeIfPresent(safeToRequestCooling, forKey: .safeToRequestCooling)
        try container.encode(daemonControlPathReady, forKey: .daemonControlPathReady)
        try container.encode(manualControlActive, forKey: .manualControlActive)
        try container.encode(failedCheckIDs, forKey: .failedCheckIDs)
        try container.encode(coolingBlockerIDs, forKey: .coolingBlockerIDs)
        try container.encode(appPreferences, forKey: .appPreferences)
        try container.encode(daemonRuntime, forKey: .daemonRuntime)
        try container.encode(modelIdentifier, forKey: .modelIdentifier)
        try container.encode(isAppleSilicon, forKey: .isAppleSilicon)
        try container.encode(isMacBookPro, forKey: .isMacBookPro)
        try container.encode(thermalPressure, forKey: .thermalPressure)
        try container.encode(fanCount, forKey: .fanCount)
        try container.encode(controllableFanCount, forKey: .controllableFanCount)
        try container.encode(temperatureSensorCount, forKey: .temperatureSensorCount)
        try container.encodeIfPresent(highestTemperatureCelsius, forKey: .highestTemperatureCelsius)
        try container.encode(fans, forKey: .fans)
        try container.encode(temperatureSensors, forKey: .temperatureSensors)
        try container.encode(agentControl, forKey: .agentControl)
        try container.encodeIfPresent(daemonSnapshotError, forKey: .daemonSnapshotError)
        try container.encodeIfPresent(agentControlStatusError, forKey: .agentControlStatusError)
        try container.encode(checks, forKey: .checks)
    }

    public static func make(
        snapshot: HardwareSnapshot,
        agentControl: AgentControlStatus,
        thermalPressure: ThermalPressure,
        generatedAt: Date = Date(),
        manualControlActive: Bool = false,
        appPreferences: ViftyAppPreferencesDiagnostic = .unavailable,
        daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic = .unavailable,
        daemonSnapshotError: String? = nil,
        agentControlStatusError: String? = nil
    ) -> ViftyCtlReadinessReport {
        let fans = snapshot.fans.map(ViftyCtlFanReport.init(fan:))
        let sensors = snapshot.temperatureSensors.map(ViftyCtlTemperatureSensorReport.init(sensor:))
        let controllableFans = snapshot.fans.filter(\.controllable)
        let checks = makeChecks(
            snapshot: snapshot,
            agentControl: agentControl,
            thermalPressure: thermalPressure,
            controllableFans: controllableFans,
            manualControlActive: manualControlActive,
            appPreferences: appPreferences,
            daemonRuntime: daemonRuntime,
            daemonSnapshotError: daemonSnapshotError,
            agentControlStatusError: agentControlStatusError
        )
        let state = resolveState(from: checks)
        let recommendedAgentAction = recommendedAgentAction(for: state, checks: checks)

        return ViftyCtlReadinessReport(
            generatedAt: generatedAt,
            state: state,
            recommendedAgentAction: recommendedAgentAction,
            safeToRequestCooling: safeToRequestCooling(for: recommendedAgentAction),
            daemonControlPathReady: daemonControlPathReady(from: checks),
            manualControlActive: manualControlActive,
            appPreferences: appPreferences,
            daemonRuntime: daemonRuntime,
            modelIdentifier: snapshot.modelIdentifier,
            isAppleSilicon: snapshot.isAppleSilicon,
            isMacBookPro: snapshot.isMacBookPro,
            thermalPressure: thermalPressure,
            fanCount: snapshot.fans.count,
            controllableFanCount: controllableFans.count,
            temperatureSensorCount: snapshot.temperatureSensors.count,
            highestTemperatureCelsius: snapshot.highestTemperature?.celsius,
            fans: fans,
            temperatureSensors: sensors,
            agentControl: agentControl,
            daemonSnapshotError: daemonSnapshotError,
            agentControlStatusError: agentControlStatusError,
            checks: checks
        )
    }

    private static func makeChecks(
        snapshot: HardwareSnapshot,
        agentControl: AgentControlStatus,
        thermalPressure: ThermalPressure,
        controllableFans: [Fan],
        manualControlActive: Bool,
        appPreferences: ViftyAppPreferencesDiagnostic,
        daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic,
        daemonSnapshotError: String?,
        agentControlStatusError: String?
    ) -> [ViftyCtlReadinessCheck] {
        [
            daemonSnapshotAvailableCheck(daemonSnapshotError),
            agentControlStatusAvailableCheck(agentControlStatusError),
            daemonControlPathReadyCheck(
                daemonSnapshotError: daemonSnapshotError,
                agentControlStatusError: agentControlStatusError
            ),
            daemonRuntimeMatchesExpectedCheck(daemonRuntime),
            supportedHardwareCheck(snapshot),
            agentControlEnabledCheck(agentControl),
            temperatureSensorsPresentCheck(snapshot),
            controllableFansPresentCheck(controllableFans),
            fanIDsValidCheck(controllableFans),
            fanIDsUniqueCheck(controllableFans),
            fanRangesValidCheck(controllableFans),
            thermalPressureSafeCheck(thermalPressure),
            activeLeaseClearCheck(agentControl),
            manualControlClearCheck(manualControlActive, appPreferences: appPreferences),
            fanModeTelemetryCheck(snapshot)
        ]
    }

    private static func daemonSnapshotAvailableCheck(_ error: String?) -> ViftyCtlReadinessCheck {
        if let error {
            return ViftyCtlReadinessCheck(
                id: "daemonSnapshotAvailable",
                severity: .error,
                passed: false,
                message: "Daemon hardware snapshot is unavailable: \(error)"
            )
        }

        return ViftyCtlReadinessCheck(
            id: "daemonSnapshotAvailable",
            severity: .info,
            passed: true,
            message: "Daemon hardware snapshot is available."
        )
    }

    private static func agentControlStatusAvailableCheck(_ error: String?) -> ViftyCtlReadinessCheck {
        if let error {
            return ViftyCtlReadinessCheck(
                id: "agentControlStatusAvailable",
                severity: .error,
                passed: false,
                message: "Daemon agent-control status is unavailable: \(error)"
            )
        }

        return ViftyCtlReadinessCheck(
            id: "agentControlStatusAvailable",
            severity: .info,
            passed: true,
            message: "Daemon agent-control status is available."
        )
    }

    private static func daemonControlPathReadyCheck(
        daemonSnapshotError: String?,
        agentControlStatusError: String?
    ) -> ViftyCtlReadinessCheck {
        let passed = daemonSnapshotError == nil && agentControlStatusError == nil
        return ViftyCtlReadinessCheck(
            id: "daemonControlPathReady",
            severity: .error,
            passed: passed,
            message: passed
                ? "Daemon-backed control path is ready for bounded agent cooling requests."
                : "Daemon-backed control path is unavailable; repair the helper before requesting cooling."
        )
    }

    private static func daemonRuntimeMatchesExpectedCheck(
        _ daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic
    ) -> ViftyCtlReadinessCheck {
        guard daemonRuntime.matchRequired else {
            return ViftyCtlReadinessCheck(
                id: "daemonRuntimeMatchesExpected",
                severity: .info,
                passed: true,
                message: "Current-build daemon runtime parity is not required for this diagnose context."
            )
        }

        guard daemonRuntime.expectedDaemonPresent, daemonRuntime.expectedDaemonSHA256 != nil else {
            return ViftyCtlReadinessCheck(
                id: "daemonRuntimeMatchesExpected",
                severity: .error,
                passed: false,
                message: "Expected ViftyDaemon for this viftyctl build is missing; rebuild or reinstall Vifty before requesting cooling."
            )
        }

        guard daemonRuntime.installedDaemonPresent, daemonRuntime.installedDaemonSHA256 != nil else {
            return ViftyCtlReadinessCheck(
                id: "daemonRuntimeMatchesExpected",
                severity: .error,
                passed: false,
                message: "Installed privileged fan helper is missing; use Repair/Reinstall Helper before requesting cooling."
            )
        }

        guard daemonRuntime.matchesExpectedDaemon == true else {
            return ViftyCtlReadinessCheck(
                id: "daemonRuntimeMatchesExpected",
                severity: .error,
                passed: false,
                message: "Installed privileged fan helper does not match this Vifty build; use Repair/Reinstall Helper before requesting cooling."
            )
        }

        return ViftyCtlReadinessCheck(
            id: "daemonRuntimeMatchesExpected",
            severity: .info,
            passed: true,
            message: "Installed privileged fan helper matches this Vifty build."
        )
    }

    private static func supportedHardwareCheck(_ snapshot: HardwareSnapshot) -> ViftyCtlReadinessCheck {
        let passed = snapshot.isAppleSilicon && snapshot.isMacBookPro
        return ViftyCtlReadinessCheck(
            id: "supportedHardware",
            severity: .error,
            passed: passed,
            message: passed
                ? "Apple Silicon MacBook Pro hardware detected."
                : "Agent cooling is supported only on Apple Silicon MacBook Pro hardware."
        )
    }

    private static func agentControlEnabledCheck(_ agentControl: AgentControlStatus) -> ViftyCtlReadinessCheck {
        ViftyCtlReadinessCheck(
            id: "agentControlEnabled",
            severity: .error,
            passed: agentControl.enabled,
            message: agentControl.enabled
                ? "Agent cooling policy is enabled in the daemon."
                : "Agent cooling policy is disabled in the daemon."
        )
    }

    private static func temperatureSensorsPresentCheck(_ snapshot: HardwareSnapshot) -> ViftyCtlReadinessCheck {
        let count = snapshot.temperatureSensors.count
        return ViftyCtlReadinessCheck(
            id: "temperatureSensorsPresent",
            severity: .error,
            passed: count > 0,
            message: count > 0
                ? "\(count) temperature sensor(s) available."
                : "No temperature sensors are available for safety monitoring."
        )
    }

    private static func controllableFansPresentCheck(_ controllableFans: [Fan]) -> ViftyCtlReadinessCheck {
        ViftyCtlReadinessCheck(
            id: "controllableFansPresent",
            severity: .error,
            passed: !controllableFans.isEmpty,
            message: controllableFans.isEmpty
                ? "No controllable fans were reported."
                : "\(controllableFans.count) controllable fan(s) available."
        )
    }

    private static func fanIDsValidCheck(_ controllableFans: [Fan]) -> ViftyCtlReadinessCheck {
        let invalidFanIDs = controllableFans
            .filter { !SMCFanControlKeys.isValidFanID($0.id) }
            .map(\.id)
            .uniqueSorted()
        return ViftyCtlReadinessCheck(
            id: "fanIDsValid",
            severity: .error,
            passed: invalidFanIDs.isEmpty,
            message: invalidFanIDs.isEmpty
                ? "Controllable fan IDs are valid."
                : "Invalid controllable fan ID(s): \(invalidFanIDs.joinedIDList()); SMC fan IDs must be 0 through 9."
        )
    }

    private static func fanIDsUniqueCheck(_ controllableFans: [Fan]) -> ViftyCtlReadinessCheck {
        var seen = Set<Int>()
        var duplicateFanIDs = Set<Int>()
        for fan in controllableFans where !seen.insert(fan.id).inserted {
            duplicateFanIDs.insert(fan.id)
        }
        let duplicates = duplicateFanIDs.sorted()
        return ViftyCtlReadinessCheck(
            id: "fanIDsUnique",
            severity: .error,
            passed: duplicates.isEmpty,
            message: duplicates.isEmpty
                ? "Controllable fan IDs are unique."
                : "Duplicate controllable fan ID(s): \(duplicates.joinedIDList())."
        )
    }

    private static func fanRangesValidCheck(_ controllableFans: [Fan]) -> ViftyCtlReadinessCheck {
        let invalidFans = controllableFans.filter { fan in
            fan.maximumRPM <= 0 || fan.minimumRPM < 0 || fan.minimumRPM > fan.maximumRPM
        }
        return ViftyCtlReadinessCheck(
            id: "fanRangesValid",
            severity: .error,
            passed: invalidFans.isEmpty,
            message: invalidFans.isEmpty
                ? "Controllable fan RPM ranges are valid."
                : "Invalid RPM range reported for fan ID(s): \(invalidFans.map(\.id).map(String.init).joined(separator: ", "))."
        )
    }

    private static func thermalPressureSafeCheck(_ thermalPressure: ThermalPressure) -> ViftyCtlReadinessCheck {
        switch thermalPressure {
        case .critical:
            return ViftyCtlReadinessCheck(
                id: "thermalPressureSafe",
                severity: .error,
                passed: false,
                message: "Thermal pressure is critical; workloads should pause instead of requesting fan control."
            )
        case .serious:
            return ViftyCtlReadinessCheck(
                id: "thermalPressureSafe",
                severity: .warning,
                passed: false,
                message: "Thermal pressure is serious; cooling may help, but the workload should be ready to back off."
            )
        case .unknown:
            return ViftyCtlReadinessCheck(
                id: "thermalPressureSafe",
                severity: .warning,
                passed: false,
                message: "Thermal pressure is unknown."
            )
        case .fair, .nominal:
            return ViftyCtlReadinessCheck(
                id: "thermalPressureSafe",
                severity: .info,
                passed: true,
                message: "Thermal pressure is \(thermalPressure.displayName.lowercased())."
            )
        }
    }

    private static func activeLeaseClearCheck(_ agentControl: AgentControlStatus) -> ViftyCtlReadinessCheck {
        ViftyCtlReadinessCheck(
            id: "activeLeaseClear",
            severity: .warning,
            passed: agentControl.activeLease == nil,
            message: agentControl.activeLease == nil
                ? "No active agent cooling lease."
                : "An agent cooling lease is already active; restore Auto before starting another workload."
        )
    }

    private static func manualControlClearCheck(
        _ manualControlActive: Bool,
        appPreferences: ViftyAppPreferencesDiagnostic
    ) -> ViftyCtlReadinessCheck {
        ViftyCtlReadinessCheck(
            id: "manualControlClear",
            severity: .warning,
            passed: !manualControlActive,
            message: manualControlActive
                ? manualControlActiveMessage(appPreferences: appPreferences)
                : "No Vifty/manual fan-control marker is active."
        )
    }

    private static func manualControlActiveMessage(
        appPreferences: ViftyAppPreferencesDiagnostic
    ) -> String {
        var message = "Vifty/manual fan control appears active; restore Auto once, then re-run diagnose."
        switch appPreferences.startupMode {
        case .curve, .fixed:
            if let startupMode = appPreferences.startupMode {
                message += " Vifty default startup mode is \(startupMode.rawValue); switch Vifty/default mode to Auto before requesting agent cooling."
            }
        case .auto:
            message += " Vifty default startup mode is Auto; if manualControlActive stays true, restore the current manual run to Auto before requesting agent cooling."
        case nil:
            message += " If manualControlActive stays true, switch Vifty/default mode to Auto before requesting agent cooling."
        }
        return message
    }

    private static func fanModeTelemetryCheck(_ snapshot: HardwareSnapshot) -> ViftyCtlReadinessCheck {
        let systemFans = snapshot.fans.filter { $0.hardwareMode == .system }
        if !systemFans.isEmpty {
            return ViftyCtlReadinessCheck(
                id: "fanModeTelemetry",
                severity: .warning,
                passed: false,
                message: "System/protected fan mode observed for fan ID(s): \(systemFans.map(\.id).map(String.init).joined(separator: ", "))."
            )
        }

        let missingModeFans = snapshot.fans.filter { $0.hardwareMode == nil }
        if !missingModeFans.isEmpty {
            return ViftyCtlReadinessCheck(
                id: "fanModeTelemetry",
                severity: .warning,
                passed: false,
                message: "Fan hardware mode telemetry is unavailable for fan ID(s): \(missingModeFans.map(\.id).map(String.init).joined(separator: ", "))."
            )
        }

        return ViftyCtlReadinessCheck(
            id: "fanModeTelemetry",
            severity: .info,
            passed: true,
            message: "Fan hardware mode telemetry is available."
        )
    }

    private static func resolveState(from checks: [ViftyCtlReadinessCheck]) -> ViftyCtlReadinessState {
        if checks.contains(where: { !$0.passed && $0.severity == .error }) {
            return .blocked
        }
        if checks.contains(where: { !$0.passed && $0.severity == .warning }) {
            return .degraded
        }
        return .ready
    }

    private static func recommendedAgentAction(
        for state: ViftyCtlReadinessState,
        checks: [ViftyCtlReadinessCheck]
    ) -> ViftyCtlRecommendedAgentAction {
        if state == .blocked {
            return .doNotRequestCooling
        }

        if checks.contains(where: { ($0.id == "activeLeaseClear" || $0.id == "manualControlClear") && !$0.passed }) {
            return .restoreAutoBeforeRequestingCooling
        }

        if state == .degraded {
            return .requestCoolingWithCaution
        }

        return .requestCooling
    }

    private static func recommendedRecoveryAction(
        for state: ViftyCtlReadinessState,
        agentAction: ViftyCtlRecommendedAgentAction,
        checks: [ViftyCtlReadinessCheck]
    ) -> ViftyCtlReadinessRecoveryAction {
        if failedCheck("daemonSnapshotAvailable", in: checks)
            || failedCheck("agentControlStatusAvailable", in: checks)
            || failedCheck("daemonControlPathReady", in: checks)
            || failedCheck("daemonRuntimeMatchesExpected", in: checks) {
            return .repairHelper
        }

        if agentAction == .restoreAutoBeforeRequestingCooling
            || failedCheck("activeLeaseClear", in: checks)
            || failedCheck("manualControlClear", in: checks) {
            return .restoreAutoBeforeRetry
        }

        if failedErrorCheck("thermalPressureSafe", in: checks) {
            return .backOffWorkload
        }

        if failedCheck("agentControlEnabled", in: checks) {
            return .inspectPolicy
        }

        if state == .blocked {
            return .collectHardwareEvidence
        }

        return .none
    }

    private static func recoverySteps(
        for action: ViftyCtlReadinessRecoveryAction,
        checks: [ViftyCtlReadinessCheck]
    ) -> [String] {
        var actions: [ViftyCtlReadinessRecoveryAction] = []

        func appendAction(_ action: ViftyCtlReadinessRecoveryAction) {
            guard action != .none, !actions.contains(action) else { return }
            actions.append(action)
        }

        appendAction(action)

        if failedCheck("activeLeaseClear", in: checks) || failedCheck("manualControlClear", in: checks) {
            appendAction(.restoreAutoBeforeRetry)
        }

        if failedErrorCheck("thermalPressureSafe", in: checks) {
            appendAction(.backOffWorkload)
        }

        if failedCheck("agentControlEnabled", in: checks)
            && !failedCheck("agentControlStatusAvailable", in: checks) {
            appendAction(.inspectPolicy)
        }

        return actions.flatMap(ViftyCtlRecoverySteps.steps(for:))
    }

    private static func operatorRecoveryCommands(
        for action: ViftyCtlReadinessRecoveryAction,
        checks: [ViftyCtlReadinessCheck],
        daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic
    ) -> [ViftyCtlOperatorRecoveryCommand]? {
        guard daemonRuntime.matchRequired,
              daemonRuntime.expectedDaemonPresent,
              let appPath = appBundlePath(forExpectedDaemonPath: daemonRuntime.expectedDaemonPath) else {
            return nil
        }

        var commands: [ViftyCtlOperatorRecoveryCommand] = []

        if action == .repairHelper {
            commands.append(ViftyCtlOperatorRecoveryCommand(
                id: "repair-helper-current-app",
                title: "Repair helper from this Vifty app bundle",
                command: "REPAIR_HELPER_APP=\(ViftyAgentRule.shellQuote(appPath)) make repair-helper",
                workingDirectoryHint: "Run from the Vifty source checkout.",
                requiresUserApproval: true,
                safeForAgentsToRunAutomatically: false,
                notes: [
                    "Shows the same explicit administrator-approved LaunchDaemon repair path as the app UI.",
                    "Does not request cooling or write fan state directly.",
                    "After repair, rerun viftyctl diagnose --json and require safe readiness before requesting cooling."
                ]
            ))
        }

        if failedCheck("activeLeaseClear", in: checks) || failedCheck("manualControlClear", in: checks) {
            let toolPath = "\(appPath)/Contents/MacOS/viftyctl"
            commands.append(ViftyCtlOperatorRecoveryCommand(
                id: "restore-auto-current-app",
                title: "Restore Auto from this Vifty app bundle",
                command: "\(ViftyAgentRule.shellQuote(toolPath)) restore-auto --json --reason \(ViftyAgentRule.shellQuote("operator recovery before agent cooling"))",
                workingDirectoryHint: "Run from any directory.",
                requiresUserApproval: true,
                safeForAgentsToRunAutomatically: false,
                notes: [
                    "Requires an explicit human decision because restore-auto writes fan control state through the helper.",
                    "If helper repair is also listed, repair the helper and rerun diagnose before considering restore-auto.",
                    "Run at most once, then rerun viftyctl diagnose --json and require manualControlActive=false before requesting cooling."
                ]
            ))
        }

        return commands.isEmpty ? nil : commands
    }

    private static func appBundlePath(forExpectedDaemonPath expectedDaemonPath: String?) -> String? {
        guard let expectedDaemonPath else {
            return nil
        }

        let suffix = "/Contents/MacOS/ViftyDaemon"
        guard expectedDaemonPath.hasSuffix(suffix) else {
            return nil
        }

        let appPath = String(expectedDaemonPath.dropLast(suffix.count))
        guard appPath.hasSuffix(".app") else {
            return nil
        }
        return appPath
    }

    private static func safeToRequestCooling(for action: ViftyCtlRecommendedAgentAction) -> Bool {
        switch action {
        case .requestCooling, .requestCoolingWithCaution:
            return true
        case .restoreAutoBeforeRequestingCooling, .doNotRequestCooling:
            return false
        }
    }

    private static func daemonControlPathReady(from checks: [ViftyCtlReadinessCheck]) -> Bool {
        if checks.contains(where: { $0.id == "daemonControlPathReady" }) {
            return !failedCheck("daemonControlPathReady", in: checks)
        }
        return !failedCheck("daemonSnapshotAvailable", in: checks)
            && !failedCheck("agentControlStatusAvailable", in: checks)
    }

    private static func failedCheckIDs(from checks: [ViftyCtlReadinessCheck]) -> [String] {
        checks
            .filter { !$0.passed }
            .map(\.id)
    }

    private static func coolingBlockerIDs(from checks: [ViftyCtlReadinessCheck]) -> [String] {
        checks
            .filter { check in
                !check.passed
                    && (check.severity == .error
                        || check.id == "activeLeaseClear"
                        || check.id == "manualControlClear")
            }
            .map(\.id)
    }

    private static func failedCheck(_ id: String, in checks: [ViftyCtlReadinessCheck]) -> Bool {
        checks.contains { $0.id == id && !$0.passed }
    }

    private static func failedErrorCheck(_ id: String, in checks: [ViftyCtlReadinessCheck]) -> Bool {
        checks.contains { $0.id == id && !$0.passed && $0.severity == .error }
    }
}

private extension Array where Element == Int {
    func uniqueSorted() -> [Int] {
        Array(Set(self)).sorted()
    }

    func joinedIDList() -> String {
        map(String.init).joined(separator: ", ")
    }
}
