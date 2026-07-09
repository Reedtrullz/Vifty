import Foundation

struct MenuBarTelemetryPrimePolicy: Equatable {
    let maxAttempts: Int
    let completedPollGraceAttempts: Int
    let initialRetryDelaySeconds: Double
    let maxRetryDelaySeconds: Double

    static let launch = MenuBarTelemetryPrimePolicy(
        maxAttempts: 8,
        completedPollGraceAttempts: 2,
        initialRetryDelaySeconds: 0.75,
        maxRetryDelaySeconds: 10.0
    )

    static let popover = MenuBarTelemetryPrimePolicy(
        maxAttempts: 3,
        completedPollGraceAttempts: 1,
        initialRetryDelaySeconds: 0.25,
        maxRetryDelaySeconds: 1.0
    )

    func shouldAttempt(
        _ attempt: Int,
        needsTelemetryPrime: Bool,
        hasCompletedHardwarePoll: Bool
    ) -> Bool {
        guard needsTelemetryPrime else { return false }
        guard attempt >= 1, attempt <= maxAttempts else { return false }
        guard hasCompletedHardwarePoll else { return true }
        return attempt <= completedPollGraceAttempts
    }

    func retryDelaySeconds(after attempt: Int) -> Double {
        let exponent = max(0, attempt - 1)
        let delay = initialRetryDelaySeconds * pow(2.0, Double(exponent))
        return min(delay, maxRetryDelaySeconds)
    }

    func retryDelay(after attempt: Int) -> Duration {
        .milliseconds(Int((retryDelaySeconds(after: attempt) * 1000).rounded()))
    }
}
