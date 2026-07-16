import XCTest
@testable import Vifty

final class SettingsPresentationTests: XCTestCase {
    func testNotificationAuthorizationUsesPrimaryTextAndSemanticIconTone() {
        let allowed = SettingsNotificationAuthorizationPresentation.resolve(.authorized)
        let denied = SettingsNotificationAuthorizationPresentation.resolve(.denied)

        XCTAssertEqual(allowed.statusText, "Allowed")
        XCTAssertEqual(allowed.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(allowed.iconTone, .positive)
        XCTAssertTrue(allowed.usesPrimaryStatusText)

        XCTAssertEqual(denied.statusText, "Denied")
        XCTAssertEqual(denied.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(denied.iconTone, .warning)
        XCTAssertTrue(denied.usesPrimaryStatusText)
    }

    func testSettingsTabsUseStableSingleRowUntilAccessibilityScale() {
        XCTAssertEqual(ViftySettingsTabLayout.resolve(textScale: .standard), .singleRow)
        XCTAssertEqual(ViftySettingsTabLayout.resolve(textScale: .large), .singleRow)
        XCTAssertEqual(ViftySettingsTabLayout.resolve(textScale: .accessibility), .twoRows)
        XCTAssertEqual(ViftySettingsTabLayout.singleRow.columnCount, 4)
        XCTAssertEqual(ViftySettingsTabLayout.twoRows.columnCount, 2)
    }

    func testSingleRowTabWidthsPreserveIdealWidthsWhenTheyFitExactly() {
        let idealWidths: [CGFloat] = [72, 96, 118, 154]
        let spacing: CGFloat = 4
        let availableWidth = idealWidths.reduce(0, +)
            + spacing * CGFloat(idealWidths.count - 1)

        let widths = ViftySettingsTabWidthAllocation.resolve(
            idealWidths: idealWidths,
            availableWidth: availableWidth,
            spacing: spacing,
            arrangement: .singleRow
        )

        XCTAssertEqual(widths, idealWidths)
    }

    func testSingleRowTabWidthsDistributeRemainingSpaceAndConsumeAvailableWidth() {
        let idealWidths: [CGFloat] = [72, 96, 118, 154]
        let spacing: CGFloat = 4
        let availableWidth: CGFloat = 520

        let widths = ViftySettingsTabWidthAllocation.resolve(
            idealWidths: idealWidths,
            availableWidth: availableWidth,
            spacing: spacing,
            arrangement: .singleRow
        )

        XCTAssertEqual(widths.count, idealWidths.count)
        for (width, idealWidth) in zip(widths, idealWidths) {
            XCTAssertGreaterThanOrEqual(width, idealWidth)
        }
        XCTAssertEqual(
            widths.reduce(0, +) + spacing * CGFloat(widths.count - 1),
            availableWidth,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(widths.last ?? 0, widths.first ?? 0)
    }

    func testSingleRowTabWidthsRemainNonnegativeAndPreserveCountWhenConstrained() {
        let widths = ViftySettingsTabWidthAllocation.resolve(
            idealWidths: [0, -8, 90, 150],
            availableWidth: 30,
            spacing: 4,
            arrangement: .singleRow
        )

        XCTAssertEqual(widths.count, 4)
        XCTAssertTrue(widths.allSatisfy { $0 >= 0 })
        XCTAssertEqual(widths.reduce(0, +) + 12, 30, accuracy: 0.001)
    }

    func testTwoRowTabWidthsUseEqualColumns() {
        let widths = ViftySettingsTabWidthAllocation.resolve(
            idealWidths: [72, 96, 118, 154],
            availableWidth: 300,
            spacing: 4,
            arrangement: .twoRows
        )

        XCTAssertEqual(widths, [148, 148])
    }

    func testLastEnabledCustomMenuFieldCannotBeDisabled() {
        let presentation = SettingsMenuBarFieldTogglePresentation.resolve(
            field: .temperature,
            selectedFields: [.temperature]
        )

        XCTAssertTrue(presentation.isSelected)
        XCTAssertFalse(presentation.isToggleEnabled)
        XCTAssertEqual(
            presentation.helpText,
            SettingsMenuBarFieldTogglePresentation.minimumSelectionHelp
        )
    }

    func testSelectedFieldCanBeDisabledWhenAnotherFieldRemains() {
        let presentation = SettingsMenuBarFieldTogglePresentation.resolve(
            field: .temperature,
            selectedFields: [.temperature, .fanRPM]
        )

        XCTAssertTrue(presentation.isSelected)
        XCTAssertTrue(presentation.isToggleEnabled)
    }

    func testUnselectedFieldCanAlwaysBeEnabled() {
        let presentation = SettingsMenuBarFieldTogglePresentation.resolve(
            field: .fanRPM,
            selectedFields: [.temperature]
        )

        XCTAssertFalse(presentation.isSelected)
        XCTAssertTrue(presentation.isToggleEnabled)
    }
}
