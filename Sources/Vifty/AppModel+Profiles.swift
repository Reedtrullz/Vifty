import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    func saveCurrentProfile(name: String) {
        guard let result = saveCurrentProfileAs(name: name, confirmOverwrite: false) else { return }
        if case .overwriteConfirmationRequired(let existing, _) = result {
            lastError = "Confirm before replacing the saved profile \(existing.name)."
        }
    }

    @discardableResult
    func saveCurrentProfileAs(
        name: String,
        confirmOverwrite: Bool
    ) -> CurveProfileSaveResult? {
        guard let result = CurveProfileSavePolicy.saveAs(
            name: name,
            draft: currentCurveProfileDraft,
            existingProfiles: savedProfiles,
            confirmOverwrite: confirmOverwrite
        ) else { return nil }

        switch result {
        case .created(let profile):
            let proposedProfiles = savedProfiles + [profile]
            guard persistProfiles(proposedProfiles) else {
                return .persistenceFailed(message: profilePersistenceErrorMessage)
            }
            savedProfiles = proposedProfiles
            selectedCurveProfileID = profile.id
        case .updated(let profile):
            guard let index = savedProfiles.firstIndex(where: { $0.id == profile.id }) else {
                return nil
            }
            var proposedProfiles = savedProfiles
            proposedProfiles[index] = profile
            guard persistProfiles(proposedProfiles) else {
                return .persistenceFailed(message: profilePersistenceErrorMessage)
            }
            savedProfiles = proposedProfiles
            selectedCurveProfileID = profile.id
        case .overwriteConfirmationRequired:
            break
        case .persistenceFailed:
            preconditionFailure("CurveProfileSavePolicy never emits persistence results.")
        }
        return result
    }

    @discardableResult
    func updateSelectedCurveProfile() -> Bool {
        let selected = selectedCurveProfileID.flatMap { selectedID in
            savedProfiles.first { $0.id == selectedID }
        }
        guard case .updated(let profile)? = CurveProfileSavePolicy.update(
            selectedProfile: selected,
            draft: currentCurveProfileDraft
        ), let index = savedProfiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }

        var proposedProfiles = savedProfiles
        proposedProfiles[index] = profile
        guard persistProfiles(proposedProfiles) else { return false }
        savedProfiles = proposedProfiles
        selectedCurveProfileID = profile.id
        return true
    }

    func loadProfile(_ profile: CurveProfile) {
        curveStartTemp = profile.startTemp
        curveStartRPM = Double(profile.startRPM)
        curveMidTemp = profile.midTemp
        curveMidRPM = Double(profile.midRPM)
        curveMaxTemp = profile.maxTemp
        curveMaxRPM = Double(profile.maxRPM)
        selectedSensorID = profile.sensorID
        fanOverrides = profile.fanOverrides
        usePerFanOverrides = !profile.fanOverrides.isEmpty
        if let fans = snapshot?.fans, usePerFanOverrides {
            ensureFanOverrides(for: fans)
        }
        markFanControlDraftPending()
    }

    @discardableResult
    func selectCurveProfile(id profileID: CurveProfile.ID?) -> Bool {
        guard let profileID else {
            selectedCurveProfileID = nil
            return true
        }
        guard let profile = savedProfiles.first(where: { $0.id == profileID }) else {
            return false
        }
        selectedCurveProfileID = profileID
        selectedMode = .curve
        loadProfile(profile)
        return true
    }

    func loadDeveloperPreset(_ preset: DeveloperFanPreset) {
        selectedCurveProfileID = nil
        selectedMode = .curve
        curveStartTemp = preset.startTemperatureCelsius
        curveMidTemp = preset.midTemperatureCelsius
        curveMaxTemp = preset.maxTemperatureCelsius
        curveStartRPM = Double(rpm(forPercent: preset.startRPMPercent))
        curveMidRPM = Double(rpm(forPercent: preset.midRPMPercent))
        curveMaxRPM = Double(rpm(forPercent: preset.maxRPMPercent))
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
        usePerFanOverrides = false
        fanOverrides = []
        curveDefaultsSynced = true
        markFanControlDraftPending()
    }

    @discardableResult
    func deleteProfile(_ profile: CurveProfile) -> Bool {
        let proposedProfiles = savedProfiles.filter { $0.id != profile.id }
        guard persistProfiles(proposedProfiles) else { return false }
        savedProfiles = proposedProfiles
        if selectedCurveProfileID == profile.id {
            selectedCurveProfileID = nil
        }
        return true
    }

    var profilePersistenceErrorMessage: String {
        curveProfilePersistenceError ?? "Failed to save profiles."
    }

    @discardableResult
    func persistProfiles(_ profiles: [CurveProfile]) -> Bool {
        do {
            try profileStore.saveThrowing(profiles)
            curveProfileRecoveryMessage = nil
            if lastError == curveProfilePersistenceError {
                lastError = nil
            }
            curveProfilePersistenceError = nil
            return true
        } catch {
            let message = "Failed to save profiles: \(error.localizedDescription)"
            curveProfilePersistenceError = message
            lastError = message
            return false
        }
    }

}
