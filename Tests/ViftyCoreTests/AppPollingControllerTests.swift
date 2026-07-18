import XCTest
@testable import Vifty

@MainActor
final class AppPollingControllerTests: XCTestCase {
    func testStartIsIdempotentAndStopCancelsTheLoop() async {
        let sleeper = ManualPollingSleeper()
        let controller = AppPollingController(sleeper: sleeper)
        let started = expectation(description: "initial operation")
        var initialRuns = 0

        XCTAssertTrue(controller.start(
            initialOperation: {
                initialRuns += 1
                started.fulfill()
            },
            interval: { .seconds(5) },
            poll: { _ in }
        ))
        XCTAssertFalse(controller.start(interval: { .seconds(1) }, poll: { _ in }))
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(initialRuns, 1)
        XCTAssertTrue(controller.isRunning)
        XCTAssertTrue(controller.stop())
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.stop())
        await sleeper.cancelAll()
    }

    func testOverlappingPollsCoalesceOntoOneOperation() async {
        let controller = AppPollingController()
        let gate = PollingGate()
        let started = expectation(description: "poll started")
        var operationRuns = 0

        let first = Task { @MainActor in
            await controller.pollOnce { _ in
                operationRuns += 1
                started.fulfill()
                await gate.wait()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { @MainActor in
            await controller.pollOnce { _ in
                operationRuns += 1
            }
        }

        await gate.open()
        await first.value
        await second.value

        XCTAssertEqual(operationRuns, 1)
    }

    func testSafetyPollSupersedesInFlightPollAndInvalidatesItsPublicationToken() async {
        let controller = AppPollingController()
        let gate = PollingGate()
        let firstStarted = expectation(description: "first poll started")
        var publications: [String] = []

        let first = Task { @MainActor in
            await controller.pollOnce { operation in
                firstStarted.fulfill()
                await gate.wait()
                guard controller.isCurrent(operation) else { return }
                publications.append("stale")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        XCTAssertTrue(controller.supersedeActivePoll())
        await controller.pollOnce { operation in
            guard controller.isCurrent(operation) else { return }
            publications.append("safety")
        }
        await gate.open()
        await first.value

        XCTAssertEqual(publications, ["safety"])
        XCTAssertFalse(controller.supersedeActivePoll())
    }

    func testFreshPollInvalidatesOlderPublicationAndRunsDistinctOperation() async {
        let controller = AppPollingController()
        let gate = PollingGate()
        let firstStarted = expectation(description: "older poll started")
        let freshRequested = expectation(description: "fresh poll requested")
        var operationRuns = 0
        var publications: [String] = []

        let first = Task { @MainActor in
            await controller.pollOnce { operation in
                operationRuns += 1
                firstStarted.fulfill()
                await gate.wait()
                guard controller.isCurrent(operation) else { return }
                publications.append("stale")
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        let fresh = Task { @MainActor in
            freshRequested.fulfill()
            await controller.freshPollOnce { operation in
                operationRuns += 1
                guard controller.isCurrent(operation) else { return }
                publications.append("fresh")
            }
        }
        await fulfillment(of: [freshRequested], timeout: 1)

        XCTAssertEqual(operationRuns, 1)
        XCTAssertTrue(publications.isEmpty)

        await gate.open()
        await first.value
        await fresh.value

        XCTAssertEqual(operationRuns, 2)
        XCTAssertEqual(publications, ["fresh"])
    }

    func testIntervalProviderIsReadAgainAfterEveryPoll() async {
        let sleeper = ManualPollingSleeper()
        let controller = AppPollingController(sleeper: sleeper)
        let polled = expectation(description: "first repeat poll")
        var interval = Duration.seconds(10)

        XCTAssertTrue(controller.start(
            interval: { interval },
            poll: { _ in polled.fulfill() }
        ))
        let firstRequestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(firstRequestedDuration, .seconds(10))

        interval = .seconds(5)
        await sleeper.resumeNext()
        await fulfillment(of: [polled], timeout: 1)
        let secondRequestedDuration = await sleeper.nextRequestedDuration()
        XCTAssertEqual(secondRequestedDuration, .seconds(5))

        controller.stop()
        await sleeper.cancelAll()
    }

    func testStopInvalidatesInFlightPublicationToken() async {
        let controller = AppPollingController()
        let gate = PollingGate()
        let started = expectation(description: "poll started")
        var publishedValues: [String] = []

        let task = Task { @MainActor in
            await controller.pollOnce { operation in
                started.fulfill()
                await gate.wait()
                guard controller.isCurrent(operation) else { return }
                publishedValues.append("stale")
            }
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertTrue(controller.stop())
        await gate.open()
        await task.value

        XCTAssertTrue(publishedValues.isEmpty)
    }
}

private actor PollingGate {
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

private actor ManualPollingSleeper: AppPollingSleeping {
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

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepWaiters.append(continuation)
            }
        } onCancel: {
            Task { await self.cancelAll() }
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

    func cancelAll() {
        let waiters = sleepWaiters
        sleepWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: CancellationError()) }
    }
}
