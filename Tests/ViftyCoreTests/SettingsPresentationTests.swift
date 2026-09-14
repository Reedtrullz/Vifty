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

    func testSettingsTabMetadataRemainsStable() {
        XCTAssertEqual(ViftySettingsTab.allCases.map(\.title), [
            "General", "Menu Bar", "Notifications", "Agent Workflows"
        ])
        XCTAssertEqual(ViftySettingsTab.allCases.map(\.systemImage), [
            "gearshape", "menubar.rectangle", "bell", "terminal"
        ])
        XCTAssertEqual(
            ViftySettingsTab.allCases.map(\.accessibilityIdentifier),
            [
                ViftyAccessibilityIdentifier.settingsTabGeneral,
                ViftyAccessibilityIdentifier.settingsTabMenuBar,
                ViftyAccessibilityIdentifier.settingsTabNotifications,
                ViftyAccessibilityIdentifier.settingsTabAgentWorkflows
            ]
        )
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
