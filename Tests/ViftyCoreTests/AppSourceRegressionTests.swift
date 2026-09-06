import Foundation
import XCTest

final class AppSourceRegressionTests: XCTestCase {
    func testGeneralSettingsSurfacesRetryablePreferenceSaveFailure() throws {
        let source = try read("Sources/Vifty/SettingsGeneralView.swift")

        XCTAssertTrue(source.contains("model.appPreferencesPersistenceMessage"))
        XCTAssertTrue(source.contains("Button(\"Retry Save\")"))
        XCTAssertTrue(source.contains("model.retryAppPreferencesSave()"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Settings were not saved\")"))
    }

    func testPreferenceStoreDoesNotKeepSilentSaveOrIgnoreSecurityFailures() throws {
        let store = try read("Sources/Vifty/AppPreferencesStore.swift")
        let model = try read("Sources/Vifty/AppModel.swift")
        let general = try read("Sources/Vifty/SettingsGeneralView.swift")

        XCTAssertFalse(store.contains("func save(_ preferences: AppPreferences)"))
        XCTAssertFalse(store.contains("try? restrictDirectoryPermissions()"))
        XCTAssertFalse(store.contains("try? restrictFilePermissions(at:"))
        XCTAssertTrue(model.contains("appPreferencesRecoveryMessage"))
        XCTAssertTrue(general.contains("Settings recovered"))
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
