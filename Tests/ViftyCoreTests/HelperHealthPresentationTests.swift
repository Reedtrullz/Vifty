import XCTest
@testable import Vifty

final class HelperHealthPresentationTests: XCTestCase {
    func testInitialUnobservedStateChecksBeforeReportingUnreachable() {
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input()),
            .checking
        )
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(hasCompletedHardwarePoll: true)),
            .unreachable
        )
    }

    func testUnsupportedHardwareAndRuntimeMismatchTakePriority() {
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: false,
                lastError: "daemonRuntime mismatch"
            )),
            .unsupported
        )
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                daemonReachable: true,
                daemonResponding: true,
                fanCount: 2,
                hasControllableFan: true,
                lastError: "installed privileged fan helper does not match"
            )),
            .runtimeMismatch
        )
    }

    func testFanTelemetrySeparatesReadOnlyHealthyAndNoControllableStates() {
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                daemonReachable: true,
                fanCount: 2
            )),
            .telemetryOnly
        )
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                daemonReachable: true,
                daemonResponding: true,
                fanCount: 2
            )),
            .noControllableFans(fanCount: 2)
        )
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                daemonReachable: true,
                daemonResponding: true,
                fanCount: 2,
                hasControllableFan: true
            )),
            .healthy(fanCount: 2)
        )
    }

    func testHelperErrorsRemainDistinctFromEmptyFanData() {
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                hasCompletedHardwarePoll: true,
                daemonReachable: true,
                daemonResponding: true,
                lastError: "fan helper rejected request"
            )),
            .error
        )
        XCTAssertEqual(
            HelperHealthPresentation.resolve(input(
                hardwareIsSupported: true,
                hasCompletedHardwarePoll: true,
                daemonReachable: true,
                daemonResponding: true
            )),
            .noFanData
        )
    }

    func testStateOwnsConsistentRecoveryAndWritePathCopy() {
        XCTAssertEqual(
            HelperHealthState.telemetryOnly.writePathBlockedSummary,
            "Read-only fan telemetry; repair helper for fan writes"
        )
        XCTAssertTrue(HelperHealthState.telemetryOnly.repairActionAvailable)
        XCTAssertNotNil(HelperHealthState.telemetryOnly.installRuntimeContext)
        XCTAssertNil(HelperHealthState.healthy(fanCount: 1).recoverySuggestion)
        XCTAssertEqual(
            HelperHealthState.noControllableFans(fanCount: 2).menuSummary,
            "No controllable fans"
        )
    }

    private func input(
        hardwareIsSupported: Bool? = nil,
        hasCompletedHardwarePoll: Bool = false,
        daemonReachable: Bool = false,
        daemonResponding: Bool = false,
        fanCount: Int = 0,
        hasControllableFan: Bool = false,
        lastError: String? = nil
    ) -> HelperHealthPresentationInput {
        HelperHealthPresentationInput(
            hardwareIsSupported: hardwareIsSupported,
            hasCompletedHardwarePoll: hasCompletedHardwarePoll,
            daemonReachable: daemonReachable,
            daemonResponding: daemonResponding,
            fanCount: fanCount,
            hasControllableFan: hasControllableFan,
            lastError: lastError
        )
    }
}
