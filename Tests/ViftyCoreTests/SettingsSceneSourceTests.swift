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
        XCTAssertTrue(settingsView.contains("Label(\"General\", systemImage: \"gearshape\")"))
        XCTAssertTrue(settingsView.contains("Label(\"Menu Bar\", systemImage: \"menubar.rectangle\")"))
        XCTAssertTrue(settingsView.contains("Label(\"Notifications\", systemImage: \"bell\")"))
        XCTAssertTrue(settingsView.contains("Label(\"Agent Workflows\", systemImage: \"terminal\")"))
        XCTAssertTrue(general.contains("Picker(\"Default mode\", selection: $model.startupMode)"))
        XCTAssertTrue(general.contains("Text(\"Auto\").tag(ModeSelection.auto)"))
        XCTAssertTrue(general.contains("Text(\"Fixed RPM\").tag(ModeSelection.fixed)"))
        XCTAssertTrue(general.contains("Text(\"Temperature Curve\").tag(ModeSelection.curve)"))
        XCTAssertTrue(general.contains("StartupModePresentation.resolve(model.startupMode).detail"))
        XCTAssertFalse(general.contains("Text(mode.rawValue)"))
        XCTAssertTrue(menuBar.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(notifications.contains("Toggle(\"Helper failure\", isOn: $model.notificationSettings.helperFailure)"))
        XCTAssertTrue(agentWorkflows.contains("AgentWorkflowSupport.safeWorkloadCommandTemplates"))
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
