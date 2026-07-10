import Foundation
import ViftyCore

struct PollSchedulePolicy: Equatable {
    let activeInterval: Duration
    let idleInterval: Duration

    static let standard = PollSchedulePolicy(
        activeInterval: .seconds(5),
        idleInterval: .seconds(10)
    )

    func interval(
        selectedMode: ModeSelection,
        controlMode: FanMode,
        hasAgentLease: Bool
    ) -> Duration {
        if selectedMode != .auto || controlMode != .auto || hasAgentLease {
            return activeInterval
        }
        return idleInterval
    }
}
