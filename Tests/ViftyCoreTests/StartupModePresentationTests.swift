import XCTest
@testable import Vifty

final class StartupModePresentationTests: XCTestCase {
    func testAutoExplainsSafeSystemControl() {
        let detail = StartupModePresentation.detail(for: .auto)

        XCTAssertEqual(detail, "Starts in macOS Auto control.")
    }

    func testFixedAndCurveRequireExplicitApply() {
        for mode in [ModeSelection.fixed, .curve] {
            let detail = StartupModePresentation.detail(for: mode)

            XCTAssertTrue(detail.contains("Apply"))
            XCTAssertTrue(detail.contains("does not change fan control at launch"))
        }
    }
}
