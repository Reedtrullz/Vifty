import Foundation
import ViftyCore

/// Owns the state mutations behind `FanControlPanel` actions so the view remains
/// a presentation boundary and every editor action can be exercised without
/// constructing SwiftUI or invoking AppKit.
@MainActor
struct FanControlPanelActionHandler {
    let model: AppModel

    @discardableResult
    func handle(_ action: FanControlPanelAction) -> FanControlPanelActionResult {
        switch action {
        case .fixedRPMChanged(let value):
            model.fixedRPM = value
        case .fixedRPMEditingEnded:
            model.markFanControlDraftPending()
        case .perFanFixedRPMChanged(let isEnabled):
            model.usePerFanFixedRPM = isEnabled
            if isEnabled {
                model.ensureFixedFanTargets(for: controllableFans)
            }
            model.markFanControlDraftPending()
        case .initializeFixedFanTargets:
            model.ensureFixedFanTargets(for: controllableFans)
        case .fixedFanRPMChanged(let fanID, let rpm):
            guard let fan = fan(withID: fanID), fan.controllable else { return .none }
            model.setFixedFanRPM(rpm, for: fan, persist: false)
        case .fixedFanEditingEnded:
            model.commitFixedFanTargetsAndApply()
        case .curveTemperatureChanged(let point, let value):
            switch point {
            case .start: model.curveStartTemp = value
            case .ramp: model.curveMidTemp = value
            case .high: model.curveMaxTemp = value
            }
            model.markFanControlDraftPending()
        case .curveRPMChanged(let point, let value):
            switch point {
            case .start: model.curveStartRPM = value
            case .ramp: model.curveMidRPM = value
            case .high: model.curveMaxRPM = value
            }
            model.markFanControlDraftPending()
        case .sensorSelected(let sensorID):
            model.selectedSensorID = sensorID
            model.markFanControlDraftPending()
        case .perFanOverridesChanged(let isEnabled):
            model.usePerFanOverrides = isEnabled
            if isEnabled {
                model.ensureFanOverrides(for: controllableFans)
            }
            model.markFanControlDraftPending()
        case .initializeFanOverrides:
            model.ensureFanOverrides(for: controllableFans)
        case .fanOverrideRPMChanged(let fanID, let point, let rpm):
            guard let fan = fan(withID: fanID), fan.controllable else { return .none }
            switch point {
            case .start: model.setOverrideStartRPM(rpm, for: fan)
            case .ramp: model.setOverrideMidRPM(rpm, for: fan)
            case .high: model.setOverrideMaxRPM(rpm, for: fan)
            }
            model.markFanControlDraftPending()
        case .curveProfileSelected(let profileID):
            _ = model.selectCurveProfile(id: profileID)
        case .developerPresetSelected(let preset):
            model.loadDeveloperPreset(preset)
        case .updateCurveProfile:
            _ = model.updateSelectedCurveProfile()
        case .saveCurveProfile(let name, let confirmOverwrite):
            return .curveProfileSave(
                model.saveCurrentProfileAs(
                    name: name,
                    confirmOverwrite: confirmOverwrite
                )
            )
        case .deleteCurveProfile(let profileID):
            guard let profile = model.savedProfiles.first(where: { $0.id == profileID }) else {
                return .none
            }
            _ = model.deleteProfile(profile)
        }
        return .none
    }

    private var controllableFans: [Fan] {
        (model.snapshot?.fans ?? []).filter(\.controllable)
    }

    private func fan(withID fanID: Int) -> Fan? {
        model.snapshot?.fans.first { $0.id == fanID }
    }
}
