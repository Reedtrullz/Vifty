import XCTest
@testable import Vifty

@MainActor
final class CopyFeedbackSchedulerTests: XCTestCase {
    func testScheduledResetUsesInjectedDelayAndSleeper() async {
        let sleeper = ManualCopyFeedbackSleeper()
        let scheduler = CopyFeedbackScheduler(
            delay: .milliseconds(750),
            sleeper: sleeper
        )
        let reset = expectation(description: "copy feedback reset")
        var resetCount = 0

        scheduler.schedule {
            resetCount += 1
            reset.fulfill()
        }

        let requestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(requestedDuration, .milliseconds(750))
        await sleeper.resumeNext()
        await fulfillment(of: [reset], timeout: 1)
        XCTAssertEqual(resetCount, 1)
    }

    func testReplacementCancelsStaleResetAndOnlyRunsLatestCallback() async {
        let sleeper = ManualCopyFeedbackSleeper()
        let scheduler = CopyFeedbackScheduler(sleeper: sleeper)
        let latestReset = expectation(description: "latest reset")
        var callbacks: [String] = []

        scheduler.schedule { callbacks.append("stale") }
        let firstRequestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(firstRequestedDuration, .seconds(2))

        scheduler.schedule {
            callbacks.append("latest")
            latestReset.fulfill()
        }
        let secondRequestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(secondRequestedDuration, .seconds(2))

        await sleeper.resumeNext()
        await sleeper.resumeNext()
        await fulfillment(of: [latestReset], timeout: 1)
        XCTAssertEqual(callbacks, ["latest"])
    }
}

private actor ManualCopyFeedbackSleeper: CopyFeedbackSleeping {
    private var requestedDurations: [Duration] = []
    private var durationWaiters: [CheckedContinuation<Duration, Never>] = []
    private var sleepWaiters: [CheckedContinuation<Void, Error>] = []

    func sleep(for duration: Duration) async throws {
        if let waiter = durationWaiters.first {
            durationWaiters.removeFirst()
            waiter.resume(returning: duration)
        } else {
            requestedDurations.append(duration)
        }
        try await withCheckedThrowingContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func nextRequestedDuration() async -> Duration {
        if !requestedDurations.isEmpty {
            return requestedDurations.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            durationWaiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !sleepWaiters.isEmpty else { return }
        sleepWaiters.removeFirst().resume()
    }
}
