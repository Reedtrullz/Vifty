import Foundation
import XCTest

final class AppSourceRegressionTests: XCTestCase {
    func testMenuBarHelperHealthOffersRepairAndRefreshesAfterAction() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")

        XCTAssertTrue(menuBarView.contains("@StateObject private var daemonInstaller = DaemonInstaller()"))
        XCTAssertTrue(menuBarView.contains("@State private var helperRefreshTask: Task<Void, Never>?"))
        XCTAssertTrue(menuBarView.contains("Button(daemonInstaller.actionTitle)"))
        XCTAssertTrue(menuBarView.contains(".disabled(!model.helperHealthNeedsAttention || !daemonInstaller.canInstall)"))
        XCTAssertTrue(menuBarView.contains("daemonInstaller.installOrOpenApproval()"))
        XCTAssertTrue(menuBarView.contains("try? await Task.sleep(for: .milliseconds(750))"))
        XCTAssertTrue(menuBarView.contains("daemonInstaller.refresh()"))
        XCTAssertEqual(menuBarView.components(separatedBy: "await model.pollOnce()").count - 1, 2)
        XCTAssertTrue(menuBarView.contains("helperRefreshTask?.cancel()"))
    }

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
