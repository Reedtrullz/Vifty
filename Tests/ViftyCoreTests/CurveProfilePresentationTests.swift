import XCTest
import ViftyCore
@testable import Vifty

final class CurveProfilePresentationTests: XCTestCase {
    func testToolbarKeepsSelectedIdentityEditedStateAndActionsExplicit() {
        let profile = draft().profile(id: fixedID(1), name: "Quiet Build")

        let presentation = CurveProfileToolbarPresentation.resolve(
            profiles: [profile],
            selectedProfileID: profile.id,
            editState: .edited(profileID: profile.id)
        )

        XCTAssertEqual(presentation.selectedProfileName, "Quiet Build")
        XCTAssertTrue(presentation.showsEditedBadge)
        XCTAssertTrue(presentation.canUpdate)
        XCTAssertTrue(presentation.canDelete)
        XCTAssertEqual(
            presentation.visibleActionTitles,
            ["Presets", "Update", "Save As", "Delete"]
        )
    }

    func testToolbarUnsavedStateKeepsSaveActionsWithoutFalseIdentity() {
        let presentation = CurveProfileToolbarPresentation.resolve(
            profiles: [],
            selectedProfileID: nil,
            editState: .unsaved
        )

        XCTAssertEqual(presentation.selectedProfileName, "Unsaved")
        XCTAssertFalse(presentation.showsEditedBadge)
        XCTAssertFalse(presentation.canUpdate)
        XCTAssertFalse(presentation.canDelete)
        XCTAssertEqual(presentation.visibleActionTitles, ["Presets", "Save As"])
    }

    func testPointSensorAndOverrideEditsBecomeEditedAndRevertingBecomesSaved() {
        let profile = makeProfile()

        XCTAssertEqual(
            CurveProfileEditState.resolve(
                selectedProfile: profile,
                draft: CurveProfileDraftSnapshot(profile: profile)
            ),
            .saved(profileID: profile.id)
        )

        var edited = CurveProfileDraftSnapshot(profile: profile)
        edited = draft(
            sensorID: "Tp02",
            rampRPM: edited.rampRPM + 50,
            overrides: [FanCurveOverride(fanID: 1, startRPM: 1_600, midRPM: 3_100, maxRPM: 4_600)]
        )
        XCTAssertEqual(
            CurveProfileEditState.resolve(selectedProfile: profile, draft: edited),
            .edited(profileID: profile.id)
        )

        XCTAssertEqual(
            CurveProfileEditState.resolve(
                selectedProfile: profile,
                draft: CurveProfileDraftSnapshot(profile: profile)
            ),
            .saved(profileID: profile.id)
        )
    }

    func testOverrideOrderingDoesNotCreateFalseEdits() {
        let profile = CurveProfile(
            id: fixedID(1),
            name: "Dual",
            sensorID: "Tp01",
            startTemp: 50,
            startRPM: 1_500,
            midTemp: 65,
            midRPM: 3_000,
            maxTemp: 80,
            maxRPM: 4_500,
            fanOverrides: [
                FanCurveOverride(fanID: 0, startRPM: 1_500, midRPM: 3_000, maxRPM: 4_500),
                FanCurveOverride(fanID: 1, startRPM: 1_600, midRPM: 3_100, maxRPM: 4_600)
            ]
        )
        let reordered = draft(
            overrides: Array(profile.fanOverrides.reversed())
        )

        XCTAssertEqual(
            CurveProfileEditState.resolve(selectedProfile: profile, draft: reordered),
            .saved(profileID: profile.id)
        )
    }

    func testUpdatePreservesSelectedProfileIdentity() {
        let profile = makeProfile()
        let edited = draft(rampRPM: 3_250)

        guard case .updated(let updated) = CurveProfileSavePolicy.update(
            selectedProfile: profile,
            draft: edited
        ) else {
            return XCTFail("Expected an update result")
        }

        XCTAssertEqual(updated.id, profile.id)
        XCTAssertEqual(updated.name, profile.name)
        XCTAssertEqual(updated.midRPM, 3_250)
    }

    func testSaveAsCollisionRequiresExplicitConfirmation() {
        let existing = makeProfile()
        let edited = draft(rampRPM: 3_250)

        guard case .overwriteConfirmationRequired(let collided, let proposed) = CurveProfileSavePolicy.saveAs(
            name: " quiet ",
            draft: edited,
            existingProfiles: [existing],
            confirmOverwrite: false
        ) else {
            return XCTFail("Expected overwrite confirmation")
        }

        XCTAssertEqual(collided.id, existing.id)
        XCTAssertEqual(proposed.id, existing.id)
        XCTAssertEqual(proposed.midRPM, 3_250)

        guard case .updated(let confirmed) = CurveProfileSavePolicy.saveAs(
            name: "QUIET",
            draft: edited,
            existingProfiles: [existing],
            confirmOverwrite: true
        ) else {
            return XCTFail("Expected confirmed update")
        }
        XCTAssertEqual(confirmed.id, existing.id)
    }

    func testUniqueSaveAsUsesInjectedIdentity() {
        let newID = fixedID(9)

        guard case .created(let created) = CurveProfileSavePolicy.saveAs(
            name: "Performance",
            draft: draft(),
            existingProfiles: [makeProfile()],
            confirmOverwrite: false,
            makeID: { newID }
        ) else {
            return XCTFail("Expected new profile")
        }

        XCTAssertEqual(created.id, newID)
        XCTAssertEqual(created.name, "Performance")
    }

    private func makeProfile() -> CurveProfile {
        draft().profile(id: fixedID(1), name: "Quiet")
    }

    private func draft(
        sensorID: String? = "Tp01",
        rampRPM: Int = 3_000,
        overrides: [FanCurveOverride] = [
            FanCurveOverride(fanID: 1, startRPM: 1_600, midRPM: 3_100, maxRPM: 4_600)
        ]
    ) -> CurveProfileDraftSnapshot {
        CurveProfileDraftSnapshot(
            sensorID: sensorID,
            startTemperature: 50,
            startRPM: 1_500,
            rampTemperature: 65,
            rampRPM: rampRPM,
            highTemperature: 80,
            highRPM: 4_500,
            fanOverrides: overrides
        )
    }

    private func fixedID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }
}
