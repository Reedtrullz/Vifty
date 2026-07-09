import Foundation

@MainActor
final class MenuBarTelemetryPrimeScheduler {
    private var currentOperation: (@MainActor () async -> Void)?
    private var task: Task<Void, Never>?

    var isPriming: Bool {
        task != nil
    }

    @discardableResult
    func schedule(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard task == nil else { return false }
        currentOperation = operation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let operation = self.currentOperation
            defer {
                self.currentOperation = nil
                self.task = nil
            }
            await operation?()
        }
        return true
    }
}
