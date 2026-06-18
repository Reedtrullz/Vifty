import Foundation
import XCTest
@testable import ViftyCore

final class ViftyAppPreferencesDiagnosticTests: XCTestCase {
    func testMissingPreferencesFileFallsBackToAutoWithMissingFileSource() {
        let reader = ViftyAppPreferencesDiagnosticReader(url: temporaryPreferencesURL())

        let diagnostic = reader.read()

        XCTAssertEqual(diagnostic.startupMode, .auto)
        XCTAssertEqual(diagnostic.startupModeSource, .defaultMissingFile)
        XCTAssertNil(diagnostic.readError)
    }

    func testPersistedStartupModeIsReportedReadOnly() throws {
        let url = temporaryPreferencesURL()
        try write(#"{"startupMode":"Curve"}"#, to: url)
        let reader = ViftyAppPreferencesDiagnosticReader(url: url)

        let diagnostic = reader.read()

        XCTAssertEqual(diagnostic.startupMode, .curve)
        XCTAssertEqual(diagnostic.startupModeSource, .persisted)
        XCTAssertNil(diagnostic.readError)
    }

    func testMissingStartupModeKeyFallsBackToAutoWithMissingKeySource() throws {
        let url = temporaryPreferencesURL()
        try write(#"{"menuBarDisplayMode":"ownerTemperatureAndRPM"}"#, to: url)
        let reader = ViftyAppPreferencesDiagnosticReader(url: url)

        let diagnostic = reader.read()

        XCTAssertEqual(diagnostic.startupMode, .auto)
        XCTAssertEqual(diagnostic.startupModeSource, .defaultMissingKey)
        XCTAssertNil(diagnostic.readError)
    }

    func testUnreadablePreferencesReturnConservativeDiagnostic() throws {
        let url = temporaryPreferencesURL()
        try write(#"{"startupMode":"Turbo"}"#, to: url)
        let reader = ViftyAppPreferencesDiagnosticReader(url: url)

        let diagnostic = reader.read()

        XCTAssertNil(diagnostic.startupMode)
        XCTAssertEqual(diagnostic.startupModeSource, .unreadable)
        XCTAssertTrue(diagnostic.readError?.isEmpty == false)
    }

    private func temporaryPreferencesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-preferences.json")
    }

    private func write(_ string: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try string.data(using: .utf8)?.write(to: url)
    }
}
