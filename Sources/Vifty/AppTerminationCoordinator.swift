import Foundation

enum AppTerminationRestoreResult: Sendable, Equatable {
    case restored
    case failed(message: String)

    var canTerminate: Bool {
        self == .restored
    }
}

@MainActor
final class AppTerminationCoordinator {
    private var terminationTask: Task<Void, Never>?

    var isTerminationInProgress: Bool {
        terminationTask != nil
    }

    @discardableResult
    func beginTermination(
        restore: @escaping @MainActor () async -> AppTerminationRestoreResult,
        completion: @escaping @MainActor (AppTerminationRestoreResult) -> Void
    ) -> Bool {
        guard terminationTask == nil else { return false }

        ViftyLog.lifecycle.notice("Application termination requested")
        terminationTask = Task { @MainActor [weak self] in
            let result = await restore()
            if result.canTerminate {
                ViftyLog.lifecycle.notice("Application termination approved")
            } else {
                ViftyLog.lifecycle.error("Application termination canceled after restore failure")
            }
            completion(result)
            self?.terminationTask = nil
        }
        return true
    }
}
