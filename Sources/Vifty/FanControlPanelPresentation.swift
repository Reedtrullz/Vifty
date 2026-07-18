import Foundation
import ViftyCore

enum FanCurveControlPoint: String, CaseIterable, Equatable {
    case start
    case ramp
    case high
}

enum FanControlPanelAction: Equatable {
    case fixedRPMChanged(Double)
    case fixedRPMEditingEnded
    case perFanFixedRPMChanged(Bool)
    case initializeFixedFanTargets
    case fixedFanRPMChanged(fanID: Int, rpm: Int)
    case fixedFanEditingEnded
    case curveTemperatureChanged(point: FanCurveControlPoint, value: Double)
    case curveRPMChanged(point: FanCurveControlPoint, value: Double)
    case sensorSelected(String?)
    case perFanOverridesChanged(Bool)
    case initializeFanOverrides
    case fanOverrideRPMChanged(fanID: Int, point: FanCurveControlPoint, rpm: Int)
    case curveProfileSelected(CurveProfile.ID?)
    case developerPresetSelected(DeveloperFanPreset)
    case updateCurveProfile
    case saveCurveProfile(name: String, confirmOverwrite: Bool)
    case deleteCurveProfile(CurveProfile.ID)

    static func == (lhs: FanControlPanelAction, rhs: FanControlPanelAction) -> Bool {
        switch (lhs, rhs) {
        case (.fixedRPMChanged(let lhs), .fixedRPMChanged(let rhs)):
            lhs == rhs
        case (.fixedRPMEditingEnded, .fixedRPMEditingEnded),
             (.initializeFixedFanTargets, .initializeFixedFanTargets),
             (.fixedFanEditingEnded, .fixedFanEditingEnded),
             (.initializeFanOverrides, .initializeFanOverrides),
             (.updateCurveProfile, .updateCurveProfile):
            true
        case (.perFanFixedRPMChanged(let lhs), .perFanFixedRPMChanged(let rhs)),
             (.perFanOverridesChanged(let lhs), .perFanOverridesChanged(let rhs)):
            lhs == rhs
        case (
            .fixedFanRPMChanged(let lhsFanID, let lhsRPM),
            .fixedFanRPMChanged(let rhsFanID, let rhsRPM)
        ):
            lhsFanID == rhsFanID && lhsRPM == rhsRPM
        case (
            .curveTemperatureChanged(let lhsPoint, let lhsValue),
            .curveTemperatureChanged(let rhsPoint, let rhsValue)
        ), (
            .curveRPMChanged(let lhsPoint, let lhsValue),
            .curveRPMChanged(let rhsPoint, let rhsValue)
        ):
            lhsPoint == rhsPoint && lhsValue == rhsValue
        case (.sensorSelected(let lhs), .sensorSelected(let rhs)):
            lhs == rhs
        case (
            .fanOverrideRPMChanged(let lhsFanID, let lhsPoint, let lhsRPM),
            .fanOverrideRPMChanged(let rhsFanID, let rhsPoint, let rhsRPM)
        ):
            lhsFanID == rhsFanID && lhsPoint == rhsPoint && lhsRPM == rhsRPM
        case (.curveProfileSelected(let lhs), .curveProfileSelected(let rhs)):
            lhs == rhs
        case (.developerPresetSelected(let lhs), .developerPresetSelected(let rhs)):
            lhs.rawValue == rhs.rawValue
        case (
            .saveCurveProfile(let lhsName, let lhsConfirmOverwrite),
            .saveCurveProfile(let rhsName, let rhsConfirmOverwrite)
        ):
            lhsName == rhsName && lhsConfirmOverwrite == rhsConfirmOverwrite
        case (.deleteCurveProfile(let lhs), .deleteCurveProfile(let rhs)):
            lhs == rhs
        default:
            false
        }
    }
}

enum FanControlPanelActionResult: Equatable {
    case none
    case curveProfileSave(CurveProfileSaveResult?)
}

struct FanControlPanelActionDispatcher {
    private let handler: (FanControlPanelAction) -> FanControlPanelActionResult

    init(_ handler: @escaping (FanControlPanelAction) -> FanControlPanelActionResult) {
        self.handler = handler
    }

    @discardableResult
    func dispatch(_ action: FanControlPanelAction) -> FanControlPanelActionResult {
        handler(action)
    }

    func fixedRPMChanged(_ value: Double) {
        dispatch(.fixedRPMChanged(value))
    }

    func fixedRPMEditingEnded() {
        dispatch(.fixedRPMEditingEnded)
    }

    func perFanFixedRPMChanged(_ isEnabled: Bool) {
        dispatch(.perFanFixedRPMChanged(isEnabled))
    }

    func initializeFixedFanTargets() {
        dispatch(.initializeFixedFanTargets)
    }

    func fixedFanRPMChanged(fanID: Int, rpm: Int) {
        dispatch(.fixedFanRPMChanged(fanID: fanID, rpm: rpm))
    }

    func fixedFanEditingEnded() {
        dispatch(.fixedFanEditingEnded)
    }

    func curveTemperatureChanged(point: FanCurveControlPoint, value: Double) {
        dispatch(.curveTemperatureChanged(point: point, value: value))
    }

    func curveRPMChanged(point: FanCurveControlPoint, value: Double) {
        dispatch(.curveRPMChanged(point: point, value: value))
    }

    func sensorSelected(_ sensorID: String?) {
        dispatch(.sensorSelected(sensorID))
    }

    func perFanOverridesChanged(_ isEnabled: Bool) {
        dispatch(.perFanOverridesChanged(isEnabled))
    }

    func initializeFanOverrides() {
        dispatch(.initializeFanOverrides)
    }

    func fanOverrideRPMChanged(
        fanID: Int,
        point: FanCurveControlPoint,
        rpm: Int
    ) {
        dispatch(.fanOverrideRPMChanged(fanID: fanID, point: point, rpm: rpm))
    }

    func curveProfileSelected(_ profileID: CurveProfile.ID?) {
        dispatch(.curveProfileSelected(profileID))
    }

    func developerPresetSelected(_ preset: DeveloperFanPreset) {
        dispatch(.developerPresetSelected(preset))
    }

    func updateCurveProfile() {
        dispatch(.updateCurveProfile)
    }

    func saveCurveProfile(
        name: String,
        confirmOverwrite: Bool
    ) -> CurveProfileSaveResult? {
        guard case .curveProfileSave(let result) = dispatch(
            .saveCurveProfile(name: name, confirmOverwrite: confirmOverwrite)
        ) else {
            return nil
        }
        return result
    }

    func deleteCurveProfile(_ profileID: CurveProfile.ID) {
        dispatch(.deleteCurveProfile(profileID))
    }
}

struct FanControlPanelFanMetrics: Equatable {
    let fanID: Int
    let appliedTargetRPM: Int?
    let draftTargetRPM: Int?
    let fixedSliderRPM: Int
    let fixedTargetRPM: Int
    let fixedTargetPercent: Int
}

struct FixedRPMFanPresentation: Equatable, Identifiable {
    let fanID: Int
    let name: String
    let minimumRPM: Int
    let maximumRPM: Int
    let sliderRPM: Int
    let targetRPM: Int
    let targetPercent: Int

    var id: Int { fanID }
}

struct FixedRPMEditorPresentation: Equatable {
    let fixedRPM: Double
    let usesPerFanTargets: Bool
    let fanRange: ClosedRange<Double>
    let fans: [FixedRPMFanPresentation]
    let isEnabled: Bool

    var showsPerFanToggle: Bool { fans.count > 1 }
    var showsPerFanEditors: Bool { usesPerFanTargets && showsPerFanToggle }
}

struct TemperatureCurvePointPresentation: Equatable {
    let temperature: Double
    let rpm: Double
}

struct PerFanCurveOverridePresentation: Equatable, Identifiable {
    let fanID: Int
    let name: String
    let minimumRPM: Int
    let maximumRPM: Int
    let startRPM: Int
    let rampRPM: Int
    let highRPM: Int

    var id: Int { fanID }
}

struct TemperatureCurveEditorPresentation: Equatable {
    struct SensorOption: Equatable, Identifiable {
        let id: String
        let name: String
    }

    let start: TemperatureCurvePointPresentation
    let ramp: TemperatureCurvePointPresentation
    let high: TemperatureCurvePointPresentation
    let sensors: [SensorOption]
    let selectedSensorID: String?
    let liveTemperature: Double?
    let editingRPMRange: ClosedRange<Double>
    let chartFans: [Fan]
    let fanOverrides: [FanCurveOverride]
    let usesPerFanOverrides: Bool
    let overrideEditors: [PerFanCurveOverridePresentation]
    let profiles: [CurveProfile]
    let selectedProfileID: CurveProfile.ID?
    let profileEditState: CurveProfileEditState
    let profileRecoveryMessage: String?
    let isEnabled: Bool

    var showsPerFanOverrideToggle: Bool { chartFans.count > 1 }
    var showsPerFanOverrideEditors: Bool {
        usesPerFanOverrides && showsPerFanOverrideToggle
    }

    func point(_ point: FanCurveControlPoint) -> TemperatureCurvePointPresentation {
        switch point {
        case .start: start
        case .ramp: ramp
        case .high: high
        }
    }
}

struct FanStatusListItemPresentation: Equatable, Identifiable {
    let fanID: Int
    let fanName: String
    let status: FanStatusPresentation

    var id: Int { fanID }
}

struct FanStatusListPresentation: Equatable {
    let fans: [FanStatusListItemPresentation]
    let unavailableDescription: String
    let helperActionTitle: String?
    let helperActionHelp: String?
    let helperActionDisabled: Bool
    let helperStatusText: String
    let helperDiagnosticsCopied: Bool
}

struct FanControlPanelPresentation: Equatable {
    struct Input {
        let selectedMode: ModeSelection
        let fixedRPM: Double
        let usesPerFanFixedRPM: Bool
        let curveStartTemperature: Double
        let curveRampTemperature: Double
        let curveHighTemperature: Double
        let curveStartRPM: Double
        let curveRampRPM: Double
        let curveHighRPM: Double
        let sensors: [TemperatureSensor]
        let effectiveSensorID: String?
        let effectiveTemperature: Double?
        let usesPerFanOverrides: Bool
        let savedProfiles: [CurveProfile]
        let selectedCurveProfileID: CurveProfile.ID?
        let curveProfileEditState: CurveProfileEditState
        let curveProfileRecoveryMessage: String?
        let fanRange: ClosedRange<Double>
        let fans: [Fan]
        let fanOverrides: [FanCurveOverride]
        let fanMetrics: [FanControlPanelFanMetrics]
        let manualFanControlAvailable: Bool
        let helperRecoverySuggestion: String?
        let fanAccessMessage: String?
        let helperActionTitle: String?
        let helperActionHelp: String?
        let helperActionDisabled: Bool
        let helperStatusText: String
        let helperDiagnosticsCopied: Bool
    }

    let selectedMode: ModeSelection
    let fixedRPMEditor: FixedRPMEditorPresentation
    let temperatureCurveEditor: TemperatureCurveEditorPresentation
    let fanStatusList: FanStatusListPresentation

    static func == (lhs: FanControlPanelPresentation, rhs: FanControlPanelPresentation) -> Bool {
        lhs.selectedMode.rawValue == rhs.selectedMode.rawValue
            && lhs.fixedRPMEditor == rhs.fixedRPMEditor
            && lhs.temperatureCurveEditor == rhs.temperatureCurveEditor
            && lhs.fanStatusList == rhs.fanStatusList
    }

    static func resolve(_ input: Input) -> FanControlPanelPresentation {
        let controllableFans = input.fans.filter(\.controllable)
        let selectedProfile = input.selectedCurveProfileID.flatMap { selectedID in
            input.savedProfiles.first { $0.id == selectedID }
        }
        let editingRPMRange = CurveRPMEditingEnvelope.resolve(
            fans: controllableFans,
            selectedProfile: selectedProfile
        )
        let controllableFanIDs = Set(controllableFans.map(\.id))
        let controllableOverrides = input.fanOverrides.filter {
            controllableFanIDs.contains($0.fanID)
        }
        let metricsByFanID = Dictionary(
            input.fanMetrics.map { ($0.fanID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let overridesByFanID = Dictionary(
            input.fanOverrides.map { ($0.fanID, $0) },
            uniquingKeysWith: { _, last in last }
        )

        let fixedFans = input.fans.compactMap { fan -> FixedRPMFanPresentation? in
            guard fan.controllable, let metrics = metricsByFanID[fan.id] else { return nil }
            return FixedRPMFanPresentation(
                fanID: fan.id,
                name: fan.name,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM,
                sliderRPM: metrics.fixedSliderRPM,
                targetRPM: metrics.fixedTargetRPM,
                targetPercent: metrics.fixedTargetPercent
            )
        }

        let overrideEditors = controllableFans.compactMap { fan -> PerFanCurveOverridePresentation? in
            guard let override = overridesByFanID[fan.id] else { return nil }
            return PerFanCurveOverridePresentation(
                fanID: fan.id,
                name: fan.name,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM,
                startRPM: override.startRPM,
                rampRPM: override.midRPM,
                highRPM: override.maxRPM
            )
        }

        let fanStatuses = input.fans.map { fan in
            let metrics = metricsByFanID[fan.id]
            return FanStatusListItemPresentation(
                fanID: fan.id,
                fanName: fan.name,
                status: FanStatusPresentation.make(
                    fan: fan,
                    appliedTargetRPM: metrics?.appliedTargetRPM,
                    draftTargetRPM: metrics?.draftTargetRPM
                )
            )
        }

        return FanControlPanelPresentation(
            selectedMode: input.selectedMode,
            fixedRPMEditor: FixedRPMEditorPresentation(
                fixedRPM: input.fixedRPM,
                usesPerFanTargets: input.usesPerFanFixedRPM,
                fanRange: input.fanRange,
                fans: fixedFans,
                isEnabled: input.manualFanControlAvailable
            ),
            temperatureCurveEditor: TemperatureCurveEditorPresentation(
                start: TemperatureCurvePointPresentation(
                    temperature: input.curveStartTemperature,
                    rpm: input.curveStartRPM
                ),
                ramp: TemperatureCurvePointPresentation(
                    temperature: input.curveRampTemperature,
                    rpm: input.curveRampRPM
                ),
                high: TemperatureCurvePointPresentation(
                    temperature: input.curveHighTemperature,
                    rpm: input.curveHighRPM
                ),
                sensors: input.sensors.map {
                    TemperatureCurveEditorPresentation.SensorOption(id: $0.id, name: $0.name)
                },
                selectedSensorID: input.effectiveSensorID,
                liveTemperature: input.effectiveTemperature,
                editingRPMRange: editingRPMRange,
                chartFans: controllableFans,
                fanOverrides: controllableOverrides,
                usesPerFanOverrides: input.usesPerFanOverrides,
                overrideEditors: overrideEditors,
                profiles: input.savedProfiles,
                selectedProfileID: input.selectedCurveProfileID,
                profileEditState: input.curveProfileEditState,
                profileRecoveryMessage: input.curveProfileRecoveryMessage,
                isEnabled: input.manualFanControlAvailable
            ),
            fanStatusList: FanStatusListPresentation(
                fans: fanStatuses,
                unavailableDescription: input.helperRecoverySuggestion
                    ?? input.fanAccessMessage
                    ?? input.helperStatusText,
                helperActionTitle: input.helperActionTitle,
                helperActionHelp: input.helperActionHelp,
                helperActionDisabled: input.helperActionDisabled,
                helperStatusText: input.helperStatusText,
                helperDiagnosticsCopied: input.helperDiagnosticsCopied
            )
        )
    }
}
