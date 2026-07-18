import Combine
import Foundation

protocol CopyFeedbackSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousCopyFeedbackSleeper: CopyFeedbackSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

@MainActor
final class CopyFeedbackScheduler: ObservableObject {
    private let delay: Duration
    private let sleeper: any CopyFeedbackSleeping
    private var resetTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        delay: Duration = .seconds(2),
        sleeper: any CopyFeedbackSleeping = ContinuousCopyFeedbackSleeper()
    ) {
        self.delay = delay
        self.sleeper = sleeper
    }

    func schedule(reset: @escaping @MainActor () -> Void) {
        cancel()
        let generation = generation
        let delay = delay
        let sleeper = sleeper
        resetTask = Task { [weak self] in
            do {
                try await sleeper.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.generation == generation else {
                return
            }
            reset()
            resetTask = nil
        }
    }

    func cancel() {
        generation &+= 1
        resetTask?.cancel()
        resetTask = nil
    }
}
