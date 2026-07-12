import Foundation

struct TelemetryLayoutPolicy {
    private static let threeColumnMinimumWidth: CGFloat = 520
    private static let fourColumnMinimumWidth: CGFloat = 860

    static func metricColumnCount(for width: CGFloat) -> Int {
        if width < threeColumnMinimumWidth {
            return 2
        }
        if width < fourColumnMinimumWidth {
            return 3
        }
        return 4
    }
}
