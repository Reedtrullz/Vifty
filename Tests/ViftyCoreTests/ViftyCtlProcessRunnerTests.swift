import Darwin
import XCTest
@testable import ViftyCtl

final class ViftyCtlProcessRunnerTests: XCTestCase {
    func testExitCodeReturnsNormalChildExitStatus() {
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .exit, status: 7),
            7
        )
    }

    func testExitCodeMapsUncaughtSignalToShellStyleExitCode() {
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .uncaughtSignal, status: SIGINT),
            130
        )
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .uncaughtSignal, status: SIGTERM),
            143
        )
    }
}
