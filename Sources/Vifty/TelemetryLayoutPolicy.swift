import Foundation

struct TelemetryLayoutPolicy {
    static func metricColumnCount(for width: CGFloat) -> Int {
        if width < 520 {
            return 2
        }
        if width < 860 {
            return 3
        }
        return 4
    }
}
