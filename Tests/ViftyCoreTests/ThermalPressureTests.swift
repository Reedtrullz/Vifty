import XCTest
@testable import ViftyCore

final class ThermalPressureTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(ThermalPressure.nominal.displayName, "Nominal")
        XCTAssertEqual(ThermalPressure.fair.displayName, "Fair")
        XCTAssertEqual(ThermalPressure.serious.displayName, "Serious")
        XCTAssertEqual(ThermalPressure.critical.displayName, "Critical")
    }

    func testMenuSummaryOnlyShowsElevatedStates() {
        XCTAssertNil(ThermalPressure.nominal.menuSummary)
        XCTAssertEqual(ThermalPressure.serious.menuSummary, "Thermal: Serious")
    }
}
