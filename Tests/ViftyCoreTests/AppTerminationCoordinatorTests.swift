import XCTest
@testable import Vifty

@MainActor
final class AppTerminationCoordinatorTests: XCTestCase {
    func testSuccessfulRestoreAllowsTermination() async {
        let coordinator = AppTerminationCoordinator()
        var replies: [Bool] = []

        XCTAssertTrue(coordinator.beginTermination(
            restore: { .restored },
            completion: { replies.append($0.canTerminate) }
        ))
        await waitUntilIdle(coordinator)

        XCTAssertEqual(replies, [true])
    }

    func testFailedRestoreCancelsTermination() async {
        let coordinator = AppTerminationCoordinator()
        var replies: [Bool] = []

        XCTAssertTrue(coordinator.beginTermination(
            restore: { .failed(message: "restore refused") },
            completion: { replies.append($0.canTerminate) }
        ))
        await waitUntilIdle(coordinator)

        XCTAssertEqual(replies, [false])
    }

    func testSecondQuitRequestReusesInFlightTermination() async {
        let coordinator = AppTerminationCoordinator()
        let gate = AsyncTerminationGate()
        var replies: [Bool] = []

        XCTAssertTrue(coordinator.beginTermination(
            restore: {
                await gate.wait()
                return .restored
            },
            completion: { replies.append($0.canTerminate) }
        ))
        XCTAssertFalse(coordinator.beginTermination(
            restore: { .restored },
            completion: { replies.append($0.canTerminate) }
        ))

        await gate.open()
        await waitUntilIdle(coordinator)
        XCTAssertEqual(replies, [true])
    }

    private func waitUntilIdle(_ coordinator: AppTerminationCoordinator) async {
        for _ in 0..<100 where coordinator.isTerminationInProgress {
            await Task.yield()
        }
    }
}

private actor AsyncTerminationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
