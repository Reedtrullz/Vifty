import Foundation
import XCTest

final class SettingsSceneSourceTests: XCTestCase {
    func testSettingsLiveInNativeSceneAndRailUsesLauncher() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let settingsView = try read("Sources/Vifty/ViftySettingsView.swift")
        let settingsTools = try read("Sources/Vifty/SettingsToolsPanel.swift")

        XCTAssertTrue(app.contains("Settings {"))
        XCTAssertTrue(app.contains("ViftySettingsView(model: model)"))
        XCTAssertTrue(contentView.contains("SettingsLink"))
        XCTAssertFalse(contentView.contains("SettingsToolsPanel("))
        XCTAssertFalse(contentView.contains("workbenchControlRailSectionsView("))
        XCTAssertFalse(contentView.contains("Spacer(minLength: 24)"))
        XCTAssertTrue(settingsView.contains("SettingsToolsPanel("))
        XCTAssertFalse(settingsTools.contains("Label(\"Settings & Tools\", systemImage: \"gearshape\")"))
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
