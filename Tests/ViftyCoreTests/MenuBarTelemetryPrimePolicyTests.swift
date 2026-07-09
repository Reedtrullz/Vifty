import XCTest
@testable import Vifty

final class MenuBarTelemetryPrimePolicyTests: XCTestCase {
    @MainActor
    func testRunningLaunchPrimeSatisfiesPopoverPrimeRequestWithoutStartingAnotherLoop() async {
        let scheduler = MenuBarTelemetryPrimeScheduler()
        let gate = PrimeGate()
        let started = expectation(description: "launch prime started")
        let finished = expectation(description: "launch prime finished")
        var starts = 0

        XCTAssertTrue(scheduler.schedule {
            starts += 1
            started.fulfill()
            await gate.wait()
            finished.fulfill()
        })
        await fulfillment(of: [started], timeout: 1.0)

        XCTAssertFalse(scheduler.schedule {
            starts += 1
        })

        XCTAssertEqual(starts, 1)

        await gate.open()
        await fulfillment(of: [finished], timeout: 1.0)
        await Task.yield()
        XCTAssertFalse(scheduler.isPriming)
    }

    @MainActor
    func testPopoverPrimeCanStartAgainAfterPriorPrimeFinishes() async {
        let scheduler = MenuBarTelemetryPrimeScheduler()
        let gate = PrimeGate()
        let firstStarted = expectation(description: "first prime started")
        let firstFinished = expectation(description: "first prime finished")
        let secondFinished = expectation(description: "second prime finished")
        var starts = 0

        XCTAssertTrue(scheduler.schedule {
            starts += 1
            firstStarted.fulfill()
            await gate.wait()
            firstFinished.fulfill()
        })
        await fulfillment(of: [firstStarted], timeout: 1.0)

        await gate.open()
        await fulfillment(of: [firstFinished], timeout: 1.0)
        await Task.yield()
        XCTAssertFalse(scheduler.isPriming)

        XCTAssertTrue(scheduler.schedule {
            starts += 1
            secondFinished.fulfill()
        })
        await fulfillment(of: [secondFinished], timeout: 1.0)
        await Task.yield()
        XCTAssertFalse(scheduler.isPriming)

        XCTAssertEqual(starts, 2)
    }

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

private actor PrimeGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
