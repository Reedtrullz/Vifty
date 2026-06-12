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

public struct ViftyCtlReadinessReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var state: ViftyCtlReadinessState
    public var recommendedAgentAction: ViftyCtlRecommendedAgentAction?
    public var recommendedRecoveryAction: ViftyCtlReadinessRecoveryAction
    public var safeToRequestCooling: Bool?
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
        case safeToRequestCooling
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
        safeToRequestCooling: Bool? = nil,
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
        self.recommendedRecoveryAction = recommendedRecoveryAction
            ?? Self.recommendedRecoveryAction(for: state, agentAction: resolvedAction, checks: checks)
        self.safeToRequestCooling = safeToRequestCooling ?? Self.safeToRequestCooling(for: resolvedAction)
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
            safeToRequestCooling: try container.decodeIfPresent(Bool.self, forKey: .safeToRequestCooling),
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
        try container.encodeIfPresent(safeToRequestCooling, forKey: .safeToRequestCooling)
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
        daemonSnapshotError: String?,
        agentControlStatusError: String?
    ) -> [ViftyCtlReadinessCheck] {
        [
            daemonSnapshotAvailableCheck(daemonSnapshotError),
            agentControlStatusAvailableCheck(agentControlStatusError),
            supportedHardwareCheck(snapshot),
            agentControlEnabledCheck(agentControl),
            temperatureSensorsPresentCheck(snapshot),
            controllableFansPresentCheck(controllableFans),
            fanIDsValidCheck(controllableFans),
            fanIDsUniqueCheck(controllableFans),
            fanRangesValidCheck(controllableFans),
            thermalPressureSafeCheck(thermalPressure),
            activeLeaseClearCheck(agentControl),
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

        if checks.contains(where: { $0.id == "activeLeaseClear" && !$0.passed }) {
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
            || failedCheck("agentControlStatusAvailable", in: checks) {
            return .repairHelper
        }

        if agentAction == .restoreAutoBeforeRequestingCooling
            || failedCheck("activeLeaseClear", in: checks) {
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

    private static func safeToRequestCooling(for action: ViftyCtlRecommendedAgentAction) -> Bool {
        switch action {
        case .requestCooling, .requestCoolingWithCaution:
            return true
        case .restoreAutoBeforeRequestingCooling, .doNotRequestCooling:
            return false
        }
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
