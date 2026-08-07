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
    public var canApplyFixedRPM: Bool?
    public var canRestoreOSManagedMode: Bool?
    public var controlIneligibilityReasons: [String]?

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
        self.canApplyFixedRPM = fan.controlEligibility.canApplyFixedRPM
        self.canRestoreOSManagedMode = fan.controlEligibility.canRestoreOSManagedMode
        self.controlIneligibilityReasons = fan.controlEligibility.reasons.map(\.rawValue)
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
    public var fanControlOwnership: FanControlOwnershipStatus?
    public var daemonSnapshotError: String?
    public var agentControlStatusError: String?
    public var fanControlOwnershipStatusError: String?
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
        case fanControlOwnership
        case daemonSnapshotError
        case agentControlStatusError
        case fanControlOwnershipStatusError
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
        fanControlOwnership: FanControlOwnershipStatus? = nil,
        daemonSnapshotError: String? = nil,
        agentControlStatusError: String? = nil,
        fanControlOwnershipStatusError: String? = nil,
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
        self.fanControlOwnership = fanControlOwnership
        self.daemonSnapshotError = daemonSnapshotError
        self.agentControlStatusError = agentControlStatusError
        self.fanControlOwnershipStatusError = fanControlOwnershipStatusError
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
            fanControlOwnership: try container.decodeIfPresent(
                FanControlOwnershipStatus.self,
                forKey: .fanControlOwnership
            ),
            daemonSnapshotError: try container.decodeIfPresent(String.self, forKey: .daemonSnapshotError),
            agentControlStatusError: try container.decodeIfPresent(String.self, forKey: .agentControlStatusError),
            fanControlOwnershipStatusError: try container.decodeIfPresent(
                String.self,
                forKey: .fanControlOwnershipStatusError
            ),
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
        try container.encodeIfPresent(fanControlOwnership, forKey: .fanControlOwnership)
        try container.encodeIfPresent(daemonSnapshotError, forKey: .daemonSnapshotError)
        try container.encodeIfPresent(agentControlStatusError, forKey: .agentControlStatusError)
        try container.encodeIfPresent(
            fanControlOwnershipStatusError,
            forKey: .fanControlOwnershipStatusError
        )
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
        agentControlStatusError: String? = nil,
        fanControlOwnership: FanControlOwnershipStatus? = nil,
        fanControlOwnershipStatusError: String? = nil
    ) -> ViftyCtlReadinessReport {
        let fans = snapshot.fans.map(ViftyCtlFanReport.init(fan:))
        let sensors = snapshot.temperatureSensors.map(ViftyCtlTemperatureSensorReport.init(sensor:))
        let controllableFans = snapshot.fans.filter {
            $0.controllable && $0.controlEligibility.canApplyFixedRPM
        }
        let checks = makeChecks(
            snapshot: snapshot,
            agentControl: agentControl,
            thermalPressure: thermalPressure,
            controllableFans: controllableFans,
            manualControlActive: manualControlActive,
            appPreferences: appPreferences,
            daemonRuntime: daemonRuntime,
            daemonSnapshotError: daemonSnapshotError,
            agentControlStatusError: agentControlStatusError,
            fanControlOwnership: fanControlOwnership,
            fanControlOwnershipStatusError: fanControlOwnershipStatusError
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
            fanControlOwnership: fanControlOwnership,
            daemonSnapshotError: daemonSnapshotError,
            agentControlStatusError: agentControlStatusError,
            fanControlOwnershipStatusError: fanControlOwnershipStatusError,
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
        agentControlStatusError: String?,
        fanControlOwnership: FanControlOwnershipStatus?,
        fanControlOwnershipStatusError: String?
    ) -> [ViftyCtlReadinessCheck] {
        var checks = [
            daemonSnapshotAvailableCheck(daemonSnapshotError),
            agentControlStatusAvailableCheck(agentControlStatusError),
            daemonControlPathReadyCheck(
                daemonSnapshotError: daemonSnapshotError,
                agentControlStatusError: agentControlStatusError,
                ownershipStatusError: fanControlOwnershipStatusError
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
        if fanControlOwnership != nil || fanControlOwnershipStatusError != nil {
            checks.insert(
                fanControlOwnershipStatusAvailableCheck(fanControlOwnershipStatusError),
                at: 2
            )
            checks.append(contentsOf: fanControlOwnershipChecks(
                fanControlOwnership,
                snapshot: snapshot,
                agentControl: agentControl
            ))
            let replacementAttestation = replacementMaintenanceAttestationCheck(
                snapshot: snapshot,
                agentControl: agentControl,
                manualControlActive: manualControlActive,
                daemonSnapshotError: daemonSnapshotError,
                agentControlStatusError: agentControlStatusError,
                ownershipStatus: fanControlOwnership,
                ownershipStatusError: fanControlOwnershipStatusError
            )
            // This is affirmative replacement authority, not another general
            // cooling-readiness failure. Missing authority is fail-closed for
            // the installer while preserving the existing readiness taxonomy.
            if replacementAttestation.passed {
                checks.append(replacementAttestation)
            }
        }
        return checks
    }

    /// A narrow, read-only attestation for replacing the installed app bundle.
    ///
    /// This deliberately reuses the daemon maintenance inventory analyzer: its
    /// restore eligibility is derived from a trusted FNum-backed physical fan
    /// domain, not from `fans.count`. The installer still cross-checks the raw
    /// fields so a legacy report cannot opt into this assertion by shape alone.
    private static func replacementMaintenanceAttestationCheck(
        snapshot: HardwareSnapshot,
        agentControl: AgentControlStatus,
        manualControlActive: Bool,
        daemonSnapshotError: String?,
        agentControlStatusError: String?,
        ownershipStatus: FanControlOwnershipStatus?,
        ownershipStatusError: String?
    ) -> ViftyCtlReadinessCheck {
        let inventory = HelperMaintenanceSnapshotAnalyzer.analyze(snapshot)
        let supportedHardware = snapshot.isAppleSilicon && snapshot.isMacBookPro
        let ownershipClear = ownershipStatus.map { status in
            status.protocolVersion == FanControlProtocolVersion.current
                && status.owner == nil
                && status.phase == nil
                && status.transactionID == nil
                && status.expectedFanIDs.isEmpty
                && status.confirmedOSManagedFanIDs.isEmpty
                && !status.recoveryPending
                && status.errorCode == nil
                && status.errorMessage == nil
        } == true
        let passed = daemonSnapshotError == nil
            && agentControlStatusError == nil
            && ownershipStatusError == nil
            && snapshot.fanControlProtocolVersion == FanControlProtocolVersion.current
            && supportedHardware
            && inventory.blockers.isEmpty
            && ownershipClear
            && agentControl.activeLease == nil
            && !manualControlActive

        return ViftyCtlReadinessCheck(
            id: "replacementMaintenanceAttestation",
            severity: .error,
            passed: passed,
            message: passed
                ? "Fresh protocol-v2 telemetry attests one complete physical fan inventory in Auto/System with no owner or lease."
                : "App replacement is not attested: require supported hardware, protocol v2, one complete trusted fan inventory in Auto/System, and explicit clear ownership and lease state."
        )
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

    private static func fanControlOwnershipStatusAvailableCheck(
        _ error: String?
    ) -> ViftyCtlReadinessCheck {
        if let error {
            return ViftyCtlReadinessCheck(
                id: "fanControlOwnershipStatusAvailable",
                severity: .error,
                passed: false,
                message: "Daemon fan-control ownership status is unavailable: \(error)"
            )
        }
        return ViftyCtlReadinessCheck(
            id: "fanControlOwnershipStatusAvailable",
            severity: .info,
            passed: true,
            message: "Daemon fan-control ownership status is available."
        )
    }

    private static func fanControlOwnershipChecks(
        _ status: FanControlOwnershipStatus?,
        snapshot: HardwareSnapshot,
        agentControl: AgentControlStatus
    ) -> [ViftyCtlReadinessCheck] {
        guard let status else {
            return [
                ViftyCtlReadinessCheck(
                    id: "fanControlProtocolCurrent",
                    severity: .error,
                    passed: false,
                    message: "Fan-control protocol version could not be verified."
                ),
                ViftyCtlReadinessCheck(
                    id: "fanControlOwnershipStateValid",
                    severity: .error,
                    passed: false,
                    message: "Fan-control ownership state could not be verified."
                ),
                ViftyCtlReadinessCheck(
                    id: "fanControlRecoveryClear",
                    severity: .error,
                    passed: false,
                    message: "Fan-control recovery state could not be verified."
                ),
                ViftyCtlReadinessCheck(
                    id: "fanControlOwnershipClear",
                    severity: .error,
                    passed: false,
                    message: "Fan-control ownership could not be verified as clear."
                ),
                ViftyCtlReadinessCheck(
                    id: "fanControlHardwareConsistent",
                    severity: .error,
                    passed: false,
                    message: "Physical fan ownership could not be reconciled with daemon state."
                )
            ]
        }

        let protocolCurrent = status.protocolVersion >= FanControlProtocolVersion.current
            && snapshot.fanControlProtocolVersion >= FanControlProtocolVersion.current
        let protocolCheck = ViftyCtlReadinessCheck(
            id: "fanControlProtocolCurrent",
            severity: .error,
            passed: protocolCurrent,
            message: protocolCurrent
                ? "Daemon and snapshot advertise fan-control protocol v2."
                : "Fan-control protocol v2 is required; update or safely repair the helper before cooling."
        )

        let confirmedIsSubset = Set(status.confirmedOSManagedFanIDs).isSubset(of: status.expectedFanIDs)
        let transactionIDPresent = status.transactionID?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let ownerShapeValid: Bool = switch status.owner {
        case nil:
            status.phase == nil
                && status.transactionID == nil
                && status.expectedFanIDs.isEmpty
                && status.confirmedOSManagedFanIDs.isEmpty
                && !status.recoveryPending
        case .manual(let sessionID):
            status.phase == .active
                && transactionIDPresent
                && !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !status.expectedFanIDs.isEmpty
                && status.confirmedOSManagedFanIDs.isEmpty
                && !status.recoveryPending
        case .agent(let leaseID):
            status.phase == .active
                && transactionIDPresent
                && !leaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !status.expectedFanIDs.isEmpty
                && status.confirmedOSManagedFanIDs.isEmpty
                && !status.recoveryPending
        case .recovery:
            (status.phase == .restoring || status.phase == .restorePending)
                && transactionIDPresent
                && !status.expectedFanIDs.isEmpty
                && status.recoveryPending
        }
        let stateValid = ownerShapeValid && confirmedIsSubset && status.errorCode == nil
        let stateCheck = ViftyCtlReadinessCheck(
            id: "fanControlOwnershipStateValid",
            severity: .error,
            passed: stateValid,
            message: stateValid
                ? "Daemon fan-control ownership state is structurally valid."
                : "Daemon fan-control ownership state is corrupt or internally inconsistent\(status.errorCode.map { ": \($0)" } ?? ".")"
        )

        let recoveryClear = !status.recoveryPending
            && status.owner != .recovery
            && status.phase != .restoring
            && status.phase != .restorePending
        let recoveryCheck = ViftyCtlReadinessCheck(
            id: "fanControlRecoveryClear",
            severity: .error,
            passed: recoveryClear,
            message: recoveryClear
                ? "No fan-control recovery transaction is pending."
                : "Fan-control recovery is pending; request one full Auto restore and verify it before cooling."
        )

        let ownershipClear = status.owner == nil && !status.recoveryPending
        let ownershipClearCheck = ViftyCtlReadinessCheck(
            id: "fanControlOwnershipClear",
            severity: .error,
            passed: ownershipClear,
            message: ownershipClear
                ? "No manual, agent, or recovery fan-control owner is active."
                : "A fan-control owner is already active; request one full Auto restore and re-run diagnose before new cooling."
        )

        let fanIDs = snapshot.fans.map(\.id)
        let fansByID = Dictionary(snapshot.fans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let expectedSet = Set(status.expectedFanIDs)
        let inventoryValid = fanIDs.count == Set(fanIDs).count
            && fanIDs.allSatisfy(SMCFanControlKeys.isValidFanID)
            && expectedSet.isSubset(of: fansByID.keys)
        let forcedFanIDs = Set(snapshot.fans.compactMap {
            $0.hardwareMode == .forced ? $0.id : nil
        })
        let outsideExpectedIsOSManaged = snapshot.fans
            .filter { !expectedSet.contains($0.id) }
            .allSatisfy { $0.hardwareMode == .automatic || $0.hardwareMode == .system }
        let expectedMatchesForcedDomain = expectedSet == forcedFanIDs
        let physicalStateConsistent: Bool
        switch status.owner {
        case nil:
            physicalStateConsistent = snapshot.fans.allSatisfy {
                $0.controlEligibility.canRestoreOSManagedMode
                    && ($0.hardwareMode == .automatic || $0.hardwareMode == .system)
            }
        case .manual:
            physicalStateConsistent = !expectedSet.isEmpty
                && expectedMatchesForcedDomain
                && outsideExpectedIsOSManaged
                && status.expectedFanIDs.allSatisfy {
                    fansByID[$0]?.hardwareMode == .forced && fansByID[$0]?.targetRPM != nil
                }
        case .agent(let leaseID):
            let leaseTargetFanIDs = Set(
                agentControl.activeLease?.targetRPMByFanID.keys.map { $0 } ?? []
            )
            physicalStateConsistent = agentControl.activeLease?.id == leaseID
                && !expectedSet.isEmpty
                && expectedSet == leaseTargetFanIDs
                && expectedMatchesForcedDomain
                && outsideExpectedIsOSManaged
                && status.expectedFanIDs.allSatisfy {
                    fansByID[$0]?.hardwareMode == .forced && fansByID[$0]?.targetRPM != nil
                }
        case .recovery:
            physicalStateConsistent = false
        }
        let hardwareConsistent = inventoryValid && physicalStateConsistent
        let hardwareCheck = ViftyCtlReadinessCheck(
            id: "fanControlHardwareConsistent",
            severity: .error,
            passed: hardwareConsistent,
            message: hardwareConsistent
                ? "Fresh fan telemetry agrees with daemon ownership."
                : "Fresh fan telemetry disagrees with daemon ownership, includes partial inventory, or shows Forced/Unknown mode without an owner."
        )

        return [protocolCheck, stateCheck, recoveryCheck, ownershipClearCheck, hardwareCheck]
    }

    private static func daemonControlPathReadyCheck(
        daemonSnapshotError: String?,
        agentControlStatusError: String?,
        ownershipStatusError: String?
    ) -> ViftyCtlReadinessCheck {
        let passed = daemonSnapshotError == nil
            && agentControlStatusError == nil
            && ownershipStatusError == nil
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
            || failedCheck("fanControlOwnershipStatusAvailable", in: checks)
            || failedCheck("fanControlProtocolCurrent", in: checks)
            || failedCheck("daemonControlPathReady", in: checks)
            || failedCheck("daemonRuntimeMatchesExpected", in: checks) {
            return .repairHelper
        }

        if agentAction == .restoreAutoBeforeRequestingCooling
            || failedCheck("activeLeaseClear", in: checks)
            || failedCheck("manualControlClear", in: checks)
            || failedCheck("fanControlRecoveryClear", in: checks)
            || failedCheck("fanControlOwnershipClear", in: checks)
            || failedCheck("fanControlOwnershipStateValid", in: checks)
            || failedCheck("fanControlHardwareConsistent", in: checks) {
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
        if failedCheck("fanControlRecoveryClear", in: checks)
            || failedCheck("fanControlOwnershipClear", in: checks)
            || failedCheck("fanControlOwnershipStateValid", in: checks)
            || failedCheck("fanControlHardwareConsistent", in: checks) {
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

        if failedCheck("activeLeaseClear", in: checks)
            || failedCheck("manualControlClear", in: checks)
            || failedCheck("fanControlRecoveryClear", in: checks)
            || failedCheck("fanControlOwnershipClear", in: checks)
            || failedCheck("fanControlOwnershipStateValid", in: checks)
            || failedCheck("fanControlHardwareConsistent", in: checks) {
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
                && !failedCheck("fanControlOwnershipStatusAvailable", in: checks)
                && !failedCheck("fanControlProtocolCurrent", in: checks)
                && !failedCheck("fanControlOwnershipStateValid", in: checks)
                && !failedCheck("fanControlRecoveryClear", in: checks)
                && !failedCheck("fanControlHardwareConsistent", in: checks)
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
import Foundation

public enum ViftyCtlRecoverySteps {
    public static let repairHelper = ViftyAgentRule.repairHelperRecoveryActions

    public static let restoreAutoBeforeRetry = [
        "Restore Auto once with Vifty or viftyctl restore-auto --json, then rerun diagnose --json.",
        "If manualControlActive remains true, switch Vifty/default startup mode to Auto before requesting cooling."
    ]

    public static let backOffWorkload = [
        "Pause or reduce the workload and let macOS thermal pressure recover.",
        "Rerun diagnose --json before requesting cooling."
    ]

    public static let inspectPolicy = [
        "Run viftyctl status --json and capabilities --json to inspect local policy/status.",
        "Do not request cooling until policy.enabled and policyStatusAvailable are true."
    ]

    public static let collectHardwareEvidence = [
        "Collect read-only validation evidence before requesting cooling on this hardware.",
        "Do not run fan-write smoke until reviewed readiness is safe."
    ]

    public static let runDiagnose = [
        "Run viftyctl diagnose --json and follow its readiness fields before requesting cooling."
    ]

    public static let fixArguments = [
        "Fix the viftyctl or wrapper arguments, then rerun the command."
    ]

    public static let fixChildCommand = [
        "Fix the workload command/path or show the launch error; do not treat this as a helper failure."
    ]

    public static let waitBeforeRetry = [
        "Wait for retryAfterSeconds before retrying, or show the JSON to the user if no retryAfterSeconds is present."
    ]

    public static func steps(for action: ViftyCtlReadinessRecoveryAction) -> [String] {
        switch action {
        case .none:
            return []
        case .repairHelper:
            return repairHelper
        case .restoreAutoBeforeRetry:
            return restoreAutoBeforeRetry
        case .backOffWorkload:
            return backOffWorkload
        case .inspectPolicy:
            return inspectPolicy
        case .collectHardwareEvidence:
            return collectHardwareEvidence
        }
    }

    public static func steps(for action: ViftyCtlCommandErrorRecoveryAction) -> [String] {
        switch action {
        case .runDiagnose:
            return runDiagnose
        case .repairHelper:
            return repairHelper
        case .fixArguments:
            return fixArguments
        case .fixChildCommand:
            return fixChildCommand
        case .restoreAutoBeforeRetry:
            return restoreAutoBeforeRetry
        case .waitBeforeRetry:
            return waitBeforeRetry
        }
    }
}
import Foundation

public enum ViftyAgentRuleWorkloadCommandMode: String, CaseIterable, Identifiable, Sendable {
    case run
    case preflight

    public var id: String { rawValue }
}

public struct ViftyAgentRuleCommands: Codable, Equatable, Sendable {
    public var viftyctlCommand: String
    public var capabilitiesCommand: String
    public var diagnoseCommand: String
    public var strictDiagnoseCommand: String
    public var agentCoolingEvidenceCommand: String
    public var agentCoolingPreflightEvidenceCommand: String
    public var guardedRunCommand: String
    public var guardedRunPreflightCommand: String

    public init(
        viftyctlCommand: String,
        capabilitiesCommand: String,
        diagnoseCommand: String,
        strictDiagnoseCommand: String,
        agentCoolingEvidenceCommand: String = "",
        agentCoolingPreflightEvidenceCommand: String = "",
        guardedRunCommand: String,
        guardedRunPreflightCommand: String
    ) {
        self.viftyctlCommand = viftyctlCommand
        self.capabilitiesCommand = capabilitiesCommand
        self.diagnoseCommand = diagnoseCommand
        self.strictDiagnoseCommand = strictDiagnoseCommand
        self.agentCoolingEvidenceCommand = agentCoolingEvidenceCommand
        self.agentCoolingPreflightEvidenceCommand = agentCoolingPreflightEvidenceCommand
        self.guardedRunCommand = guardedRunCommand
        self.guardedRunPreflightCommand = guardedRunPreflightCommand
    }
}

public struct ViftyAgentRuleJSONMarkerPair: Codable, Equatable, Sendable {
    public var begin: String
    public var end: String

    public init(begin: String, end: String) {
        self.begin = begin
        self.end = end
    }
}

public struct ViftyAgentRuleJSONMarkers: Codable, Equatable, Sendable {
    public var capabilities: ViftyAgentRuleJSONMarkerPair
    public var diagnose: ViftyAgentRuleJSONMarkerPair
    public var decision: ViftyAgentRuleJSONMarkerPair

    public init(
        capabilities: ViftyAgentRuleJSONMarkerPair,
        diagnose: ViftyAgentRuleJSONMarkerPair,
        decision: ViftyAgentRuleJSONMarkerPair
    ) {
        self.capabilities = capabilities
        self.diagnose = diagnose
        self.decision = decision
    }
}

public struct ViftyCtlAgentRuleReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var schemaID: String
    public var command: String
    public var generatedAt: Date
    public var rule: String
    public var viftyctlCommand: String
    public var capabilitiesCommand: String
    public var diagnoseCommand: String
    public var strictDiagnoseCommand: String?
    public var repairHelperRecoveryActions: [String]?
    public var agentCoolingEvidenceCommand: String
    public var agentCoolingPreflightEvidenceCommand: String
    public var guardedRunDecisionSchemaID: String
    public var guardedRunJSONMarkers: ViftyAgentRuleJSONMarkers
    public var guardedRunCommand: String
    public var guardedRunPreflightCommand: String
    public var schemaRequirements: [String]
    public var safetyRequirements: [String]
    public var forbiddenActions: [String]
    public var workloadTemplateIDs: [String]

    public init(
        schemaVersion: Int = 1,
        schemaID: String = ViftyCtlSchemaReferences.schemaIDs.agentRule,
        command: String = "agent-rule",
        generatedAt: Date,
        rule: String,
        commands: ViftyAgentRuleCommands,
        repairHelperRecoveryActions: [String]? = ViftyAgentRule.repairHelperRecoveryActions,
        guardedRunDecisionSchemaID: String = ViftyAgentRule.guardedRunDecisionSchemaID,
        guardedRunJSONMarkers: ViftyAgentRuleJSONMarkers = ViftyAgentRule.guardedRunJSONMarkers,
        schemaRequirements: [String] = ViftyAgentRule.schemaRequirements,
        safetyRequirements: [String] = ViftyAgentRule.safetyRequirements,
        forbiddenActions: [String] = ViftyAgentRule.forbiddenActions,
        workloadTemplateIDs: [String] = ViftyCtlWorkloadTemplate.auditedTemplates.map(\.id)
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.command = command
        self.generatedAt = generatedAt
        self.rule = rule
        self.viftyctlCommand = commands.viftyctlCommand
        self.capabilitiesCommand = commands.capabilitiesCommand
        self.diagnoseCommand = commands.diagnoseCommand
        self.strictDiagnoseCommand = commands.strictDiagnoseCommand
        self.repairHelperRecoveryActions = repairHelperRecoveryActions
        self.agentCoolingEvidenceCommand = commands.agentCoolingEvidenceCommand
        self.agentCoolingPreflightEvidenceCommand = commands.agentCoolingPreflightEvidenceCommand
        self.guardedRunDecisionSchemaID = guardedRunDecisionSchemaID
        self.guardedRunJSONMarkers = guardedRunJSONMarkers
        self.guardedRunCommand = commands.guardedRunCommand
        self.guardedRunPreflightCommand = commands.guardedRunPreflightCommand
        self.schemaRequirements = schemaRequirements
        self.safetyRequirements = safetyRequirements
        self.forbiddenActions = forbiddenActions
        self.workloadTemplateIDs = workloadTemplateIDs
    }
}

public enum ViftyAgentRule {
    public static let canonicalAppPath = "/Applications/Vifty.app"
    public static let canonicalViftyCtlPath = "/Applications/Vifty.app/Contents/MacOS/viftyctl"
    public static let guardedRunResourcePath = "Contents/Resources/viftyctl-wrappers/guarded-run.sh"
    public static let agentCoolingEvidenceResourcePath = "Contents/Resources/collect-agent-cooling-evidence.sh"
    public static let guardedRunDecisionSchemaID = "https://vifty.local/schemas/guarded-run-decision.schema.json"
    public static let guardedRunJSONMarkers = ViftyAgentRuleJSONMarkers(
        capabilities: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON",
            end: "guarded-run: END_VIFTY_CAPABILITIES_JSON"
        ),
        diagnose: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON",
            end: "guarded-run: END_VIFTY_DIAGNOSE_JSON"
        ),
        decision: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON",
            end: "guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON"
        )
    )

    public static let schemaRequirements = [
        "schemaVersion == 1",
        "schemaIDs.capabilities",
        "schemaIDs.diagnose",
        "schemaIDs.commandError",
        "schemaIDs.run",
        "schemaIDs.agentRule",
        "guardedRunDecisionSchemaID",
        "guardedRunJSONMarkers",
        "agentCoolingEvidenceCommand",
        "agentCoolingPreflightEvidenceCommand",
        "wrapperResources",
        "workloadTemplates",
        "runLifecycle.resolvedChildExecutableReported == true"
    ]

    public static let safetyRequirements = [
        "policyStatusAvailable == true",
        "policy.enabled == true",
        "safeToRequestCooling == true",
        "daemonControlPathReady == true",
        "manualControlActive == false",
        "daemonRuntime.matchRequired != true || daemonRuntime.matchesExpectedDaemon == true",
        "coolingBlockerIDs is empty"
    ]

    public static let repairHelperRecoveryActions = [
        "Open Vifty and use Repair/Reinstall Helper, then approve Login Items if macOS asks.",
        "In a source checkout, run make repair-helper for the same explicit administrator-approved LaunchDaemon repair.",
        "After repair, rerun diagnose --json and require safe readiness before requesting cooling."
    ]

    public static let forbiddenActions = [
        "ViftyHelper setFixed",
        "ViftyHelper auto",
        "sudo",
        "raw SMC tools",
        "direct fan RPM writes",
        "unguarded viftyctl prepare"
    ]

    public static func rule(
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let commands = agentRuleCommands(bundleURL: bundleURL, fileManager: fileManager)

        return """
        For long local build/test/model workloads on this Mac, use Vifty only through the guarded local CLI.

        Before requesting cooling, run:

        ```sh
        \(commands.capabilitiesCommand)
        \(commands.diagnoseCommand)
        ```

        From capabilities, require `schemaVersion: 1`, `schemaIDs.capabilities`, `schemaIDs.diagnose`, `schemaIDs.commandError`, `schemaIDs.run`, `schemaIDs.agentRule`, `wrapperResources`, `workloadTemplates`, `runLifecycle.resolvedChildExecutableReported: true`, `policyStatusAvailable: true`, `policy.enabled: true`, and support for the requested workload before trusting policy limits, copied command templates, or wrapper output.

        Use `wrapperResources.bundleDirectory`, `wrapperResources.sourceDirectory`, `wrapperResources.guardedRunScript`, `wrapperResources.workloadScripts`, and `workloadTemplates` to choose the installed or source wrapper and audited workload defaults instead of inventing unaudited fan-control commands.

        If `state` is `blocked`, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, `daemonRuntime.matchRequired` is true while `daemonRuntime.matchesExpectedDaemon` is not true, or `coolingBlockerIDs` is non-empty, do not request cooling. Show the JSON to the user and stop.

        For shell-only gates that need an exit code instead of JSON parsing alone, run:

        ```sh
        \(commands.strictDiagnoseCommand)
        ```

        It prints the same diagnose JSON, but exits with blocked-readiness code `75` unless `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, and `coolingBlockerIDs` all permit a new cooling request.

        If `recommendedRecoveryAction` is `repairHelper`, show `repairHelperRecoveryActions` from this report when present: open Vifty and use Repair/Reinstall Helper, or in a source checkout run `make repair-helper` as an explicit administrator-approved repair, then rerun `diagnose --json`. Do not request cooling, use uncooled fallback, or call direct SMC/helper commands while repair is pending.

        For read-only support evidence after a helper, readiness, or guarded-run failure, show or run `agentCoolingEvidenceCommand`. For exact-workload triage without requesting cooling or launching the child command, use `agentCoolingPreflightEvidenceCommand`. These commands collect capabilities, diagnose, status, audit, launchd/helper evidence, privacy review, and optional guarded-run preflight evidence only; they are not cooling authorization.

        Prefer the guarded wrapper for one child workload:

        ```sh
        \(commands.guardedRunCommand)
        ```

        For read-only planning, use preflight mode:

        ```sh
        \(commands.guardedRunPreflightCommand)
        ```

        When guarded-run refuses before cooling or completes preflight-only, extract only the JSON payload between the marker pairs in `guardedRunJSONMarkers`: use `guardedRunJSONMarkers.capabilities.begin` / `.end`, `guardedRunJSONMarkers.diagnose.begin` / `.end`, and `guardedRunJSONMarkers.decision.begin` / `.end` instead of hardcoding marker strings. Decision payloads must use the `guardedRunDecisionSchemaID` from this report, include `decisionReason` and `recoverySteps`, and preflight-only success must report `coolingRequested: false`. Do not parse surrounding recovery prose.

        Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` and `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset unless the user explicitly approves that supervised behavior after seeing Vifty's structured readiness output. Do not catch a guarded-run failure and rerun the same workload without Vifty.

        Never call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, direct fan RPM writes, or unguarded `viftyctl prepare` from an agent.
        """
    }

    public static func report(
        generatedAt: Date,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> ViftyCtlAgentRuleReport {
        let commands = agentRuleCommands(bundleURL: bundleURL, fileManager: fileManager)
        return ViftyCtlAgentRuleReport(
            generatedAt: generatedAt,
            rule: rule(bundleURL: bundleURL, fileManager: fileManager),
            commands: commands
        )
    }

    public static func agentRuleCommands(
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> ViftyAgentRuleCommands {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)
        let viftyctl = shellQuote(paths.viftyCtlPath)
        let swiftTestTemplate = ViftyCtlWorkloadTemplate.auditedTemplates[0]
        return ViftyAgentRuleCommands(
            viftyctlCommand: viftyctl,
            capabilitiesCommand: "\(viftyctl) capabilities --json",
            diagnoseCommand: "\(viftyctl) diagnose --json",
            strictDiagnoseCommand: "\(viftyctl) diagnose --json --require-safe",
            agentCoolingEvidenceCommand: agentCoolingEvidenceCommand(
                template: swiftTestTemplate,
                includeGuardedPreflight: false,
                bundleURL: bundleURL,
                fileManager: fileManager
            ),
            agentCoolingPreflightEvidenceCommand: agentCoolingEvidenceCommand(
                template: swiftTestTemplate,
                includeGuardedPreflight: true,
                bundleURL: bundleURL,
                fileManager: fileManager
            ),
            guardedRunCommand: workloadCommand(
                swiftTestTemplate,
                mode: .run,
                bundleURL: bundleURL,
                fileManager: fileManager
            ),
            guardedRunPreflightCommand: workloadCommand(
                swiftTestTemplate,
                mode: .preflight,
                bundleURL: bundleURL,
                fileManager: fileManager
            )
        )
    }

    public static func workloadCommand(
        _ template: ViftyCtlWorkloadTemplate,
        mode: ViftyAgentRuleWorkloadCommandMode,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)

        switch mode {
        case .run:
            let shortcutPath = wrapperScriptPath(named: template.shortcutScript, guardedRunPath: paths.guardedRunPath)
            let command = ([shortcutPath] + template.shortcutArguments)
                .map(shellQuote)
                .joined(separator: " ")
            return commandWithViftyCtlEnvironmentIfNeeded(command, paths: paths)
        case .preflight:
            let arguments = [
                paths.guardedRunPath,
                "--preflight-only",
                template.workload,
                template.duration,
                "\(template.maxRPMPercent)",
                template.reason,
                "--"
            ] + template.childArguments
            let command = arguments.map(shellQuote).joined(separator: " ")
            return commandWithViftyCtlEnvironmentIfNeeded(command, paths: paths)
        }
    }

    public static func agentCoolingEvidenceCommand(
        template: ViftyCtlWorkloadTemplate,
        includeGuardedPreflight: Bool,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)
        let base = [
            "umask 077;",
            "out=\"$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)\";",
            shellQuote(paths.agentCoolingEvidencePath),
            "--viftyctl",
            shellQuote(paths.viftyCtlPath),
            "--output",
            "\"$out\""
        ].joined(separator: " ")

        guard includeGuardedPreflight else {
            return base
        }

        let preflightArguments = [
            "--guarded-run-script",
            shellQuote(paths.guardedRunPath),
            "--guarded-run-preflight",
            shellQuote(template.workload),
            shellQuote(template.duration),
            shellQuote("\(template.maxRPMPercent)"),
            shellQuote(template.reason),
            shellQuote("--")
        ] + template.childArguments.map(shellQuote)

        return ([base] + preflightArguments).joined(separator: " ")
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func agentWorkflowPaths(
        bundleURL: URL?,
        fileManager: FileManager
    ) -> (viftyCtlPath: String, guardedRunPath: String, agentCoolingEvidencePath: String, requiresExplicitViftyCtlEnvironment: Bool) {
        if let bundleURL {
            let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
            let bundledGuardedRun = bundleURL.appendingPathComponent(guardedRunResourcePath, isDirectory: false)
            let bundledEvidenceCollector = bundleURL.appendingPathComponent(agentCoolingEvidenceResourcePath, isDirectory: false)
            if bundleURL.pathExtension == "app",
               fileManager.isExecutableFile(atPath: bundledTool.path),
               fileManager.isExecutableFile(atPath: bundledGuardedRun.path),
               fileManager.isExecutableFile(atPath: bundledEvidenceCollector.path) {
                return (
                    bundledTool.path,
                    bundledGuardedRun.path,
                    bundledEvidenceCollector.path,
                    bundledTool.path != canonicalViftyCtlPath
                )
            }

            if bundleURL.pathExtension != "app",
               let sourcePaths = sourceCheckoutPaths(near: bundleURL, fileManager: fileManager) {
                return sourcePaths
            }
        }

        return (
            canonicalViftyCtlPath,
            "\(canonicalAppPath)/\(guardedRunResourcePath)",
            "\(canonicalAppPath)/\(agentCoolingEvidenceResourcePath)",
            false
        )
    }

    private static func sourceCheckoutPaths(
        near bundleURL: URL,
        fileManager: FileManager
    ) -> (viftyCtlPath: String, guardedRunPath: String, agentCoolingEvidencePath: String, requiresExplicitViftyCtlEnvironment: Bool)? {
        for candidate in ancestorDirectories(startingAt: bundleURL) {
            let packageManifest = candidate.appendingPathComponent("Package.swift", isDirectory: false)
            let guardedRun = candidate.appendingPathComponent("examples/viftyctl/guarded-run.sh", isDirectory: false)
            let evidenceCollector = candidate.appendingPathComponent("scripts/collect-agent-cooling-evidence.sh", isDirectory: false)
            guard fileManager.fileExists(atPath: packageManifest.path),
                  fileManager.isExecutableFile(atPath: guardedRun.path),
                  fileManager.isExecutableFile(atPath: evidenceCollector.path)
            else {
                continue
            }

            let candidateViftyCtlPaths = [
                bundleURL.appendingPathComponent("ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/debug/ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/release/ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/Vifty.app/Contents/MacOS/viftyctl", isDirectory: false)
            ]
            guard let viftyCtl = candidateViftyCtlPaths.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                continue
            }
            return (viftyCtl.path, guardedRun.path, evidenceCollector.path, true)
        }
        return nil
    }

    private static func ancestorDirectories(startingAt url: URL) -> [URL] {
        var result: [URL] = []
        var visited: Set<String> = []
        var currentPath = (url.path as NSString).standardizingPath

        for _ in 0..<128 {
            guard !currentPath.isEmpty, visited.insert(currentPath).inserted else {
                break
            }
            result.append(URL(fileURLWithPath: currentPath, isDirectory: true))

            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }
        return result
    }

    private static func wrapperScriptPath(named scriptName: String, guardedRunPath: String) -> String {
        let guardedRunURL = URL(fileURLWithPath: guardedRunPath)
        return guardedRunURL
            .deletingLastPathComponent()
            .appendingPathComponent(scriptName, isDirectory: false)
            .path
    }

    private static func commandWithViftyCtlEnvironmentIfNeeded(
        _ command: String,
        paths: (viftyCtlPath: String, guardedRunPath: String, agentCoolingEvidencePath: String, requiresExplicitViftyCtlEnvironment: Bool)
    ) -> String {
        guard paths.requiresExplicitViftyCtlEnvironment else {
            return command
        }
        return "VIFTYCTL=\(shellQuote(paths.viftyCtlPath)) \(command)"
    }
}
