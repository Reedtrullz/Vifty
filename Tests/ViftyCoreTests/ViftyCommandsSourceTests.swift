import Foundation
import XCTest

final class ViftyCommandsSourceTests: XCTestCase {
    func testCommandsRouteThroughAppModelAndRestoreHasNoShortcut() throws {
        let source = try read("Sources/Vifty/ViftyCommands.swift")

        XCTAssertTrue(source.contains("model.restoreAuto()"))
        XCTAssertTrue(source.contains("openWindow(id: \"main\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"0\", modifiers: .command)"))
        XCTAssertTrue(source.contains("softwareUpdates.menuActionTitle"))
        XCTAssertTrue(source.contains("await softwareUpdates.performPrimaryAction()"))
        XCTAssertTrue(source.contains("!softwareUpdates.canCheck || softwareUpdates.isChecking"))
        XCTAssertTrue(source.contains("openSettings()"))
        XCTAssertTrue(source.contains(".help(softwareUpdates.primaryActionHint)"))

        let restoreBlock = source.components(separatedBy: "Button(\"Restore Auto\")").dropFirst().first ?? ""
        XCTAssertFalse(restoreBlock.prefix(300).contains("keyboardShortcut"))
        XCTAssertFalse(source.contains("FanControlCoordinator("))
        XCTAssertFalse(source.contains("SMCClient"))
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
