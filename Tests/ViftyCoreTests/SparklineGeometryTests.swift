import XCTest
@testable import Vifty

final class SparklineGeometryTests: XCTestCase {
    func testRawSpikeIsPreservedAtItsOriginalSample() {
        let points = SparklineGeometry.points(
            for: [0, 0, 100, 0, 0],
            width: 100,
            height: 40
        )

        XCTAssertEqual(points.map(\.value), [0, 0, 100, 0, 0])
        XCTAssertEqual(points.map(\.sourceIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(points[2].y, 0, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 40, accuracy: 0.001)
        XCTAssertEqual(points[3].y, 40, accuracy: 0.001)
    }

    func testFirstLatestAndRangeUseExactRawValues() {
        let values = [21.5, 90, 18.25, 33.75]
        let points = SparklineGeometry.points(for: values, width: 90, height: 30)

        XCTAssertEqual(points.first?.value, values.first)
        XCTAssertEqual(points.last?.value, values.last)
        XCTAssertEqual(points.map(\.value).min(), values.min())
        XCTAssertEqual(points.map(\.value).max(), values.max())
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 90)
    }

    func testFlatSeriesUsesMidlineWithoutChangingSamples() {
        let points = SparklineGeometry.points(for: [7, 7, 7], width: 20, height: 10)

        XCTAssertEqual(points.map(\.value), [7, 7, 7])
        XCTAssertEqual(points.map(\.y), [5, 5, 5])
    }

    func testNonFiniteEvidenceIsRefused() {
        XCTAssertTrue(
            SparklineGeometry.points(for: [1, .nan, 2], width: 20, height: 10).isEmpty
        )
    }
}
