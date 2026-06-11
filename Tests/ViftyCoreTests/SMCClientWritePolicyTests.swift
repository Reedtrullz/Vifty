import XCTest
@testable import ViftyCore

final class SMCClientWritePolicyTests: XCTestCase {
    func testFanControlKeyHelpersAcceptOnlySingleDigitFanIDs() {
        for fanID in 0...9 {
            XCTAssertTrue(SMCFanControlKeys.isValidFanID(fanID), "\(fanID) should be a valid SMC fan ID")
        }

        for fanID in [-1, 10, 42] {
            XCTAssertFalse(SMCFanControlKeys.isValidFanID(fanID), "\(fanID) should not be a valid SMC fan ID")
        }
    }

    func testWritePolicyAllowsOnlyViftyFanControlKeys() {
        for key in ["F0Md", "F1Md", "F0md", "F1md", "F0Tg", "F1Tg", "Ftst"] {
            XCTAssertTrue(SMCClient.isAllowedWriteKey(key), "\(key) should be writable")
        }

        for key in ["F0Ac", "TC0P", "B0AC", "F0Mn", "F0Mx", "F0ID", "F10Tg", "FtstX", ""] {
            XCTAssertFalse(SMCClient.isAllowedWriteKey(key), "\(key) should not be writable")
        }
    }

    func testRejectedSMCWriteErrorExplainsAllowedScope() {
        let description = ViftyError.smcWriteRejected("TC0P").localizedDescription

        XCTAssertTrue(description.contains("TC0P"))
        XCTAssertTrue(description.contains("fan mode"))
        XCTAssertTrue(description.contains("fan target"))
    }
}
