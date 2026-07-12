import XCTest
@testable import Vifty

final class StartupModePresentationTests: XCTestCase {
    func testAutoExplainsSafeSystemControl() {
        let presentation = StartupModePresentation.resolve(.auto)

        XCTAssertEqual(presentation.detail, "Starts in macOS Auto control.")
        XCTAssertFalse(presentation.requiresExplicitApply)
    }

    func testFixedAndCurveRequireExplicitApply() {
        for mode in [ModeSelection.fixed, .curve] {
            let presentation = StartupModePresentation.resolve(mode)

            XCTAssertTrue(presentation.requiresExplicitApply)
            XCTAssertTrue(presentation.detail.contains("Apply"))
            XCTAssertTrue(presentation.detail.contains("does not change fan control at launch"))
        }
    }
}
