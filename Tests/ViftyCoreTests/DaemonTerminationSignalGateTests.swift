import Foundation
import XCTest
@testable import ViftyDaemonSupport

final class DaemonTerminationSignalGateTests: XCTestCase {
    func testTerminationRequestedDuringBootstrapIsDeliveredAfterHandlerInstallation() {
        let gate = DaemonTerminationSignalGate()
        let observation = LockedTerminationObservation()

        gate.requestTermination()
        XCTAssertEqual(observation.count, 0)

        gate.installHandler { observation.record() }

        XCTAssertEqual(observation.count, 1)
    }

    func testInstalledHandlerReceivesLaterTerminationRequests() {
        let gate = DaemonTerminationSignalGate()
        let observation = LockedTerminationObservation()
        gate.installHandler { observation.record() }

        gate.requestTermination()
        gate.requestTermination()

        XCTAssertEqual(observation.count, 2)
    }

    func testDaemonMainArmsSIGTERMBeforeAwaitingServiceBootstrap() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ViftyDaemon/main.swift"),
            encoding: .utf8
        )

        let ignoreRange = try XCTUnwrap(source.range(of: "signal(SIGTERM, SIG_IGN)"))
        let sourceRange = try XCTUnwrap(source.range(of: "DispatchSource.makeSignalSource(signal: SIGTERM"))
        let bootstrapRange = try XCTUnwrap(source.range(of: "try await DaemonService.bootstrap()"))

        XCTAssertLessThan(ignoreRange.lowerBound, bootstrapRange.lowerBound)
        XCTAssertLessThan(sourceRange.lowerBound, bootstrapRange.lowerBound)
    }
}

private final class LockedTerminationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }

    func record() {
        lock.withLock { storedCount += 1 }
    }
}
