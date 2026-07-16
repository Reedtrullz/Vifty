import Foundation

protocol AppPollingSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousAppPollingSleeper: AppPollingSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct AppPollingOperation: Equatable, Sendable {
    fileprivate let generation: UInt64
}

@MainActor
final class AppPollingController {
    typealias Operation = @MainActor @Sendable (AppPollingOperation) async -> Void
    typealias InitialOperation = @MainActor @Sendable () async -> Void
    typealias IntervalProvider = @MainActor @Sendable () -> Duration

    private let sleeper: any AppPollingSleeping
    private var loopTask: Task<Void, Never>?
    private var activePollTask: Task<Void, Never>?
    private var activePollGeneration: UInt64?
    private var lifecycleGeneration: UInt64 = 0
    private var pollGeneration: UInt64 = 0

    init(sleeper: any AppPollingSleeping = ContinuousAppPollingSleeper()) {
        self.sleeper = sleeper
    }

    var isRunning: Bool {
        loopTask != nil
    }

    @discardableResult
    func start(
        initialOperation: InitialOperation? = nil,
        interval: @escaping IntervalProvider,
        poll: @escaping Operation
    ) -> Bool {
        guard loopTask == nil else { return false }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let sleeper = self.sleeper
        loopTask = Task { @MainActor [weak self] in
            defer {
                if let self, self.lifecycleGeneration == generation {
                    self.loopTask = nil
                }
            }

            await initialOperation?()
            guard let self,
                  self.lifecycleGeneration == generation,
                  !Task.isCancelled else {
                return
            }

            while !Task.isCancelled {
                let delay = interval()
                do {
                    try await sleeper.sleep(for: delay)
                } catch {
                    return
                }
                guard self.lifecycleGeneration == generation,
                      !Task.isCancelled else {
                    return
                }
                await self.pollOnce(poll)
            }
        }
        return true
    }

    @discardableResult
    func stop() -> Bool {
        guard loopTask != nil || activePollTask != nil else { return false }
        lifecycleGeneration &+= 1
        pollGeneration &+= 1
        loopTask?.cancel()
        loopTask = nil
        activePollTask?.cancel()
        activePollTask = nil
        activePollGeneration = nil
        return true
    }

    func pollOnce(_ operation: @escaping Operation) async {
        if let activePollTask {
            await activePollTask.value
            return
        }

        pollGeneration &+= 1
        let generation = pollGeneration
        let token = AppPollingOperation(generation: generation)
        let task = Task { @MainActor in
            await operation(token)
        }
        activePollTask = task
        activePollGeneration = generation
        await task.value
        if pollGeneration == generation {
            activePollTask = nil
            activePollGeneration = nil
        }
    }

    /// Invalidates any older publication token, waits for its hardware work to
    /// unwind, and then starts a distinct poll. Explicit Apply uses this as a
    /// post-configuration barrier so it can never coalesce onto a poll that
    /// began before the user's manual-control request.
    func freshPollOnce(_ operation: @escaping Operation) async {
        if let activePollTask, let activePollGeneration {
            pollGeneration &+= 1
            activePollTask.cancel()
            await activePollTask.value
            if self.activePollGeneration == activePollGeneration {
                self.activePollTask = nil
                self.activePollGeneration = nil
            }
        }
        await pollOnce(operation)
    }

    /// Invalidates publication from the current poll and allows a safety-
    /// critical replacement poll to start immediately. Cancellation does not
    /// assume the suspended hardware request stops; its operation token remains
    /// stale when it eventually returns.
    @discardableResult
    func supersedeActivePoll() -> Bool {
        guard let activePollTask else { return false }
        pollGeneration &+= 1
        activePollTask.cancel()
        self.activePollTask = nil
        activePollGeneration = nil
        return true
    }

    func isCurrent(_ operation: AppPollingOperation) -> Bool {
        pollGeneration == operation.generation && !Task.isCancelled
    }

    func wait(for duration: Duration) async throws {
        try await sleeper.sleep(for: duration)
    }
}
