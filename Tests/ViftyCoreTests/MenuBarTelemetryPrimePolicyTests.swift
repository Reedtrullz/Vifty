import XCTest
@testable import Vifty

final class MenuBarTelemetryPrimePolicyTests: XCTestCase {
    func testLaunchPolicyCapsAttemptsBeforeFirstCompletedPoll() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertTrue(policy.shouldAttempt(8, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(9, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(1, needsTelemetryPrime: false, hasCompletedHardwarePoll: false))
    }

    func testLaunchPolicyStopsQuicklyAfterCompletedPollStillHasNoTelemetry() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
        XCTAssertTrue(policy.shouldAttempt(2, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
        XCTAssertFalse(policy.shouldAttempt(3, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
    }

    func testLaunchPolicyUsesBoundedExponentialBackoff() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertEqual(policy.retryDelaySeconds(after: 1), 0.75, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 2), 1.5, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 3), 3.0, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 4), 6.0, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 5), 10.0, accuracy: 0.001)
    }

    func testPopoverPolicyStaysShortAndResponsive() {
        let policy = MenuBarTelemetryPrimePolicy.popover

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertTrue(policy.shouldAttempt(3, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(4, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertEqual(policy.retryDelaySeconds(after: 1), 0.25, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 3), 1.0, accuracy: 0.001)
    }
}
