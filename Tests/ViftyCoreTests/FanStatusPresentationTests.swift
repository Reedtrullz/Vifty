import XCTest
import ViftyCore
@testable import Vifty

final class FanStatusPresentationTests: XCTestCase {
    func testAppliedTargetDrivesDriftWhileDraftTargetStaysPreviewOnly() throws {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3_000,
            minimumRPM: 2_000,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .forced,
            targetRPM: 3_000
        )

        let presentation = FanStatusPresentation.make(
            fan: fan,
            appliedTargetRPM: 3_000,
            draftTargetRPM: 4_000
        )

        XCTAssertEqual(presentation.targetText, "Target 3000 RPM")
        XCTAssertEqual(presentation.deltaText, "On target")
        XCTAssertEqual(try XCTUnwrap(presentation.targetFraction), 0.25, accuracy: 0.0001)
        XCTAssertEqual(presentation.draftTargetText, "Draft 4000 RPM")
        XCTAssertEqual(try XCTUnwrap(presentation.draftTargetFraction), 0.5, accuracy: 0.0001)
        XCTAssertFalse(presentation.needsAttention)
    }

    func testForcedFanBelowTargetShowsMarkerAndAttention() throws {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3_600,
            minimumRPM: 2_000,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .forced,
            targetRPM: 3_900
        )

        let presentation = FanStatusPresentation.make(fan: fan, targetRPM: 4_000)

        XCTAssertEqual(presentation.currentText, "3600 RPM")
        XCTAssertEqual(presentation.targetText, "Target 4000 RPM")
        XCTAssertEqual(presentation.deltaText, "400 RPM below target")
        XCTAssertEqual(presentation.ownershipText, "Manual hardware control")
        XCTAssertEqual(presentation.currentFraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(presentation.targetFraction), 0.5, accuracy: 0.0001)
        XCTAssertTrue(presentation.needsAttention)
    }

    func testAutoFanWithoutTargetDoesNotInventTarget() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 2_500,
            minimumRPM: 2_000,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .automatic
        )

        let presentation = FanStatusPresentation.make(fan: fan, targetRPM: nil)

        XCTAssertEqual(presentation.ownershipText, "macOS Auto")
        XCTAssertNil(presentation.targetText)
        XCTAssertNil(presentation.deltaText)
        XCTAssertNil(presentation.targetFraction)
        XCTAssertFalse(presentation.needsAttention)
    }

    func testSystemManagedFanUsesSystemOwnershipCopy() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3_200,
            minimumRPM: 2_000,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .system
        )

        let presentation = FanStatusPresentation.make(fan: fan, targetRPM: nil)

        XCTAssertEqual(presentation.ownershipText, "macOS System control")
        XCTAssertFalse(presentation.needsAttention)
    }

    func testUnknownHardwareModeUsesExplicitUnknownCopy() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3_200,
            minimumRPM: 2_000,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .unknown(7)
        )

        let presentation = FanStatusPresentation.make(fan: fan, targetRPM: nil)

        XCTAssertEqual(presentation.ownershipText, "Hardware mode unknown")
        XCTAssertFalse(presentation.needsAttention)
    }
}
