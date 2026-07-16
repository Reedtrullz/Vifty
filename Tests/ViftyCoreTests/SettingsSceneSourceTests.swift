import Foundation
import XCTest

final class SettingsSceneSourceTests: XCTestCase {
    func testSettingsLiveInNativeSceneAndRailUsesLauncher() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let header = try read("Sources/Vifty/MainWindowHeader.swift")
        let settingsView = try read("Sources/Vifty/ViftySettingsView.swift")
        let general = try read("Sources/Vifty/SettingsGeneralView.swift")
        let menuBar = try read("Sources/Vifty/SettingsMenuBarView.swift")
        let notifications = try read("Sources/Vifty/SettingsNotificationsView.swift")
        let agentWorkflows = try read("Sources/Vifty/SettingsAgentWorkflowView.swift")
        let pane = try read("Sources/Vifty/SettingsPane.swift")

        XCTAssertTrue(app.contains("Settings {"))
        XCTAssertTrue(app.contains("ViftySettingsView(model: model)"))
        XCTAssertTrue(app.contains("Window(\"Vifty\", id: \"main\")"))
        XCTAssertFalse(app.contains("windowStyle(.hiddenTitleBar)"))
        XCTAssertTrue(contentView.contains("SettingsLink"))
        XCTAssertTrue(contentView.contains("MainWindowHeader("))
        XCTAssertFalse(contentView.contains("SettingsToolsPanel("))
        XCTAssertFalse(contentView.contains("workbenchControlRailSectionsView("))
        XCTAssertFalse(contentView.contains("Spacer(minLength: 24)"))
        XCTAssertTrue(settingsView.contains("SettingsGeneralView(model: model)"))
        XCTAssertTrue(settingsView.contains("SettingsMenuBarView(model: model)"))
        XCTAssertTrue(settingsView.contains("SettingsNotificationsView(model: model)"))
        XCTAssertTrue(settingsView.contains("SettingsAgentWorkflowView(model: model)"))
        XCTAssertTrue(settingsView.contains("ForEach(ViftySettingsTab.allCases)"))
        XCTAssertTrue(settingsView.contains("Label(tab.title, systemImage: tab.systemImage)"))
        XCTAssertTrue(settingsView.contains(".accessibilityValue(isSelected ? \"Selected\" : \"Not selected\")"))
        XCTAssertTrue(settingsView.contains(".accessibilityIdentifier(tab.accessibilityIdentifier)"))
        XCTAssertFalse(settingsView.contains("TabView(selection:"))
        XCTAssertTrue(settingsView.contains(".frame(width: 600, height: 420)"))
        XCTAssertTrue(pane.contains("ScrollView"))
        XCTAssertTrue(pane.contains("Form {"))
        XCTAssertTrue(pane.contains("alignment: .topLeading"))
        XCTAssertTrue(general.contains("SettingsPane(accessibilityPane: .general) {"))
        XCTAssertTrue(general.contains("Section(\"Startup\")"))
        XCTAssertTrue(general.contains("Section(\"Login\")"))
        XCTAssertTrue(general.contains("Picker(\"Default mode\", selection: $model.startupMode)"))
        XCTAssertTrue(general.contains("Text(\"Auto\").tag(ModeSelection.auto)"))
        XCTAssertTrue(general.contains("Text(\"Fixed RPM\").tag(ModeSelection.fixed)"))
        XCTAssertTrue(general.contains("Text(\"Temperature Curve\").tag(ModeSelection.curve)"))
        XCTAssertTrue(general.contains("StartupModePresentation.resolve(model.startupMode).detail"))
        XCTAssertFalse(general.contains("Text(mode.rawValue)"))
        XCTAssertTrue(menuBar.contains("SettingsPane(accessibilityPane: .menuBar) {"))
        XCTAssertTrue(menuBar.contains("Section(\"Display\")"))
        XCTAssertTrue(menuBar.contains("Text(\"Custom Fields\")"))
        XCTAssertTrue(menuBar.contains("Section(\"Codex Usage\")"))
        XCTAssertTrue(menuBar.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(notifications.contains("Section(\"Authorization\")"))
        XCTAssertTrue(notifications.contains("Section(\"Events\")"))
        XCTAssertTrue(notifications.contains("SettingsPane(accessibilityPane: .notifications) {"))
        XCTAssertTrue(notifications.contains("Toggle(\"Helper failure\", isOn: notificationBinding(.helperFailure))"))
        XCTAssertTrue(notifications.contains("SettingsNotificationAuthorizationPresentation.resolve"))
        XCTAssertTrue(notifications.contains("Text(authorizationPresentation.statusText)"))
        XCTAssertTrue(notifications.contains(".foregroundStyle(.primary)"))
        XCTAssertFalse(notifications.contains("Text(model.notificationAuthorization.displayName)\n                        .foregroundStyle(.green)"))
        XCTAssertTrue(notifications.contains("Label(\"Open Notification Settings\", systemImage:"))
        XCTAssertTrue(notifications.contains("Label(\"Send Test Notification\", systemImage:"))
        XCTAssertTrue(agentWorkflows.contains("Section(\"Commands\")"))
        XCTAssertTrue(agentWorkflows.contains("Section(\"Agent Rule\")"))
        XCTAssertTrue(agentWorkflows.contains("SettingsPane(accessibilityPane: .agentWorkflows) {"))
        XCTAssertTrue(agentWorkflows.contains("AgentWorkflowSupport.safeWorkloadCommandTemplates"))
        for settingsSource in [general, menuBar, notifications, agentWorkflows] {
            XCTAssertFalse(settingsSource.contains("FanCommand("))
            XCTAssertFalse(settingsSource.contains("setFixedFanRPM("))
            XCTAssertFalse(settingsSource.contains("restoreAuto()"))
        }
        XCTAssertFalse(header.contains("SettingsLink"))
    }

    private func read(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
