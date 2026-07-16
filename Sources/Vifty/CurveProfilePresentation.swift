import Foundation
import ViftyCore

struct CurveProfileDraftSnapshot: Equatable, Sendable {
    let sensorID: String?
    let startTemperature: Double
    let startRPM: Int
    let rampTemperature: Double
    let rampRPM: Int
    let highTemperature: Double
    let highRPM: Int
    let fanOverrides: [FanCurveOverride]

    init(
        sensorID: String?,
        startTemperature: Double,
        startRPM: Int,
        rampTemperature: Double,
        rampRPM: Int,
        highTemperature: Double,
        highRPM: Int,
        fanOverrides: [FanCurveOverride]
    ) {
        let normalized = CurveProfile(
            name: "Draft",
            sensorID: sensorID,
            startTemp: startTemperature,
            startRPM: startRPM,
            midTemp: rampTemperature,
            midRPM: rampRPM,
            maxTemp: highTemperature,
            maxRPM: highRPM,
            fanOverrides: fanOverrides
        )
        self.sensorID = normalized.sensorID
        self.startTemperature = normalized.startTemp
        self.startRPM = normalized.startRPM
        self.rampTemperature = normalized.midTemp
        self.rampRPM = normalized.midRPM
        self.highTemperature = normalized.maxTemp
        self.highRPM = normalized.maxRPM
        self.fanOverrides = normalized.fanOverrides
    }

    init(profile: CurveProfile) {
        self.init(
            sensorID: profile.sensorID,
            startTemperature: profile.startTemp,
            startRPM: profile.startRPM,
            rampTemperature: profile.midTemp,
            rampRPM: profile.midRPM,
            highTemperature: profile.maxTemp,
            highRPM: profile.maxRPM,
            fanOverrides: profile.fanOverrides
        )
    }

    func profile(id: UUID, name: String) -> CurveProfile {
        CurveProfile(
            id: id,
            name: name,
            sensorID: sensorID,
            startTemp: startTemperature,
            startRPM: startRPM,
            midTemp: rampTemperature,
            midRPM: rampRPM,
            maxTemp: highTemperature,
            maxRPM: highRPM,
            fanOverrides: fanOverrides
        )
    }
}

enum CurveProfileEditState: Equatable, Sendable {
    case unsaved
    case saved(profileID: UUID)
    case edited(profileID: UUID)

    static func resolve(
        selectedProfile: CurveProfile?,
        draft: CurveProfileDraftSnapshot
    ) -> CurveProfileEditState {
        guard let selectedProfile else { return .unsaved }
        return CurveProfileDraftSnapshot(profile: selectedProfile) == draft
            ? .saved(profileID: selectedProfile.id)
            : .edited(profileID: selectedProfile.id)
    }

    var suffix: String? {
        switch self {
        case .edited: "Edited"
        case .saved, .unsaved: nil
        }
    }
}

struct CurveProfileToolbarPresentation: Equatable {
    let selectedProfileName: String
    let showsEditedBadge: Bool
    let canUpdate: Bool
    let canDelete: Bool
    let visibleActionTitles: [String]

    static func resolve(
        profiles: [CurveProfile],
        selectedProfileID: CurveProfile.ID?,
        editState: CurveProfileEditState
    ) -> CurveProfileToolbarPresentation {
        let selectedProfile = selectedProfileID.flatMap { id in
            profiles.first { $0.id == id }
        }
        let isEdited: Bool
        if case .edited = editState {
            isEdited = true
        } else {
            isEdited = false
        }
        var actions = ["Presets"]
        if selectedProfile != nil { actions.append("Update") }
        actions.append("Save As")
        if selectedProfile != nil { actions.append("Delete") }

        return CurveProfileToolbarPresentation(
            selectedProfileName: selectedProfile?.name ?? "Unsaved",
            showsEditedBadge: selectedProfile != nil && isEdited,
            canUpdate: selectedProfile != nil && isEdited,
            canDelete: selectedProfile != nil,
            visibleActionTitles: actions
        )
    }
}

enum CurveProfileSaveResult: Equatable, Sendable {
    case created(CurveProfile)
    case updated(CurveProfile)
    case overwriteConfirmationRequired(existing: CurveProfile, proposed: CurveProfile)
    case persistenceFailed(message: String)
}

enum CurveProfileSavePolicy {
    static func update(
        selectedProfile: CurveProfile?,
        draft: CurveProfileDraftSnapshot
    ) -> CurveProfileSaveResult? {
        guard let selectedProfile else { return nil }
        return .updated(draft.profile(id: selectedProfile.id, name: selectedProfile.name))
    }

    static func saveAs(
        name rawName: String,
        draft: CurveProfileDraftSnapshot,
        existingProfiles: [CurveProfile],
        confirmOverwrite: Bool,
        makeID: () -> UUID = UUID.init
    ) -> CurveProfileSaveResult? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let collision = existingProfiles.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            let proposed = draft.profile(id: collision.id, name: name)
            return confirmOverwrite
                ? .updated(proposed)
                : .overwriteConfirmationRequired(existing: collision, proposed: proposed)
        }

        return .created(draft.profile(id: makeID(), name: name))
    }
}
