import Foundation

@MainActor
final class MenuBarTelemetryPrimeScheduler {
    private var task: Task<Void, Never>?

    var isPriming: Bool {
        task != nil
    }

    @discardableResult
    func schedule(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard task == nil else { return false }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
            }
            await operation()
        }
        return true
    }
}
