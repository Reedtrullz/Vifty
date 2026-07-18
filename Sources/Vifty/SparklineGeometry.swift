import CoreGraphics
import Foundation

struct SparklinePlotPoint: Equatable, Sendable {
    let sourceIndex: Int
    let value: Double
    let x: Double
    let y: Double
}

enum SparklineGeometry {
    /// Converts the exact captured samples into plot coordinates. Values are
    /// deliberately not averaged or resampled: a short spike is evidence and
    /// must remain visible in the rendered history.
    static func points(
        for values: [Double],
        width: Double,
        height: Double
    ) -> [SparklinePlotPoint] {
        guard values.count > 1,
              values.allSatisfy(\.isFinite),
              let minimum = values.min(),
              let maximum = values.max()
        else { return [] }

        let boundedWidth = max(width, 1)
        let boundedHeight = max(height, 1)
        let valueSpan = maximum - minimum
        let isFlat = abs(valueSpan) < 0.0001
        let xStep = boundedWidth / Double(values.count - 1)

        return values.enumerated().map { index, value in
            let normalized = isFlat ? 0.5 : (value - minimum) / valueSpan
            return SparklinePlotPoint(
                sourceIndex: index,
                value: value,
                x: Double(index) * xStep,
                y: boundedHeight - (normalized * boundedHeight)
            )
        }
    }
}
