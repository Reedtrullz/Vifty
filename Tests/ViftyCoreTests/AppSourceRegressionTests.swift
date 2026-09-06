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
