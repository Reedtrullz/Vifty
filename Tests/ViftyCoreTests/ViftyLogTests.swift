import XCTest
@testable import Vifty

final class ViftyLogTests: XCTestCase {
    func testRuntimeLogCategoriesStayStableAndFocused() {
        XCTAssertEqual(
            Set(ViftyLogCategory.allCases.map(\.rawValue)),
            Set(["Lifecycle", "Polling", "XPC", "Notifications", "FanControl", "CodexUsage"])
        )
        XCTAssertEqual(ViftyLog.subsystem, "tech.reidar.vifty")
    }
}
