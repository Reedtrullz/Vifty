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
        XCTAssertTrue(source.contains("DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)"))
    }

    func testDaemonMainKeepsTheMachListenerAliveWithoutBlockingAsyncMainQueue() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ViftyDaemon/main.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("while !Task.isCancelled"), "The async daemon main must stay suspended after registering its Mach listener.")
        XCTAssertTrue(source.contains("Task.sleep"), "The async daemon main must keep its task alive without blocking the main queue.")
        XCTAssertTrue(source.contains("Task.detached"), "SIGTERM cleanup must not inherit an unsafe actor/queue context.")
        XCTAssertFalse(source.contains("dispatchMain()"), "dispatchMain cannot be called from Swift async main's main-queue block on macOS 27.")
        XCTAssertFalse(source.contains("RunLoop.main.run()"), "RunLoop.main.run() returns on the current launchd/XPC path.")
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
