import XCTest
@testable import ViftyCore

final class RealMacHardwareServiceTests: XCTestCase {
    func testLocalSnapshotReturnsEmptyFansWhenSMCFails() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable }
        )
        let snapshot = try! service.localSnapshot()

        XCTAssertTrue(snapshot.fans.isEmpty, "Fans should be empty when SMC is unavailable")
        XCTAssertFalse(snapshot.modelIdentifier.isEmpty, "Model identifier should always be populated")
    }

    func testLocalSnapshotReturnsMetadataOnUnsupportedHardware() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable }
        )
        let snapshot = try! service.localSnapshot()

        if !SystemInfo.isMacBookPro {
            XCTAssertTrue(snapshot.fans.isEmpty)
            XCTAssertTrue(snapshot.temperatureSensors.isEmpty)
        }
    }

    func testApplyDoesNotFallbackToUnprivilegedLocalSMCWritesWhenDaemonFails() async {
        let localFallback = SendableFlag()
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonApply: { _, _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            },
            localApply: { _, _ in
                localFallback.mark()
            },
            allowsLocalFanWriteFallback: { false }
        )

        do {
            try await service.apply(FanCommand(fanID: 0, mode: .fixedRPM(2400)), fan: testFan)
            XCTFail("Expected helperRejected when daemon write fails and local SMC writes are not privileged")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Fan helper is unavailable"))
            XCTAssertTrue(message.contains("will not fall back to unprivileged local writes"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(localFallback.value, "App must not attempt direct AppleSMC fan writes as an unprivileged user")
    }

    func testRestoreAutoDoesNotFallbackToUnprivilegedLocalSMCWritesWhenDaemonFails() async {
        let localFallback = SendableFlag()
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonRestoreAuto: { _ in
                throw ViftyError.helperRejected("Daemon request timed out.")
            },
            localRestoreAuto: { _ in
                localFallback.mark()
            },
            allowsLocalFanWriteFallback: { false }
        )

        do {
            try await service.restoreAuto(fan: testFan)
            XCTFail("Expected helperRejected when daemon restore fails and local SMC writes are not privileged")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Fan helper is unavailable"))
            XCTAssertTrue(message.contains("Click Reinstall Helper"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(localFallback.value, "App must not attempt direct AppleSMC Auto restore as an unprivileged user")
    }

    func testLocalSMCWriteFallbackStillWorksWhenCallerIsPrivileged() async throws {
        let localFallback = SendableFlag()
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonApply: { _, _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            },
            localApply: { _, _ in
                localFallback.mark()
            },
            allowsLocalFanWriteFallback: { true }
        )

        try await service.apply(FanCommand(fanID: 0, mode: .fixedRPM(2400)), fan: testFan)
        XCTAssertTrue(localFallback.value, "Root/daemon callers may still use the direct LocalFanHelperClient fallback")
    }

    func testNotPrivilegedSMCErrorNamesIOReturnAndMentionsHelper() {
        let message = ViftyError.smcCallFailed(Int32(bitPattern: 0xe00002c1)).localizedDescription

        XCTAssertTrue(message.contains("kIOReturnNotPrivileged"))
        XCTAssertTrue(message.contains("privileged helper"))
        XCTAssertTrue(message.contains("-536870207"))
    }

    private var testFan: Fan {
        Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 2000,
            minimumRPM: 1400,
            maximumRPM: 6000,
            controllable: true
        )
    }
}

private final class SendableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func mark() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
