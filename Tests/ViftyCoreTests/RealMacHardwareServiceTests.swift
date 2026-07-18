import XCTest
@testable import ViftyCore

final class RealMacHardwareServiceTests: XCTestCase {
    func testLocalSnapshotReturnsEmptyFansWhenSMCFails() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable },
            hidTemperatureReader: { [] }
        )
        let snapshot = try! service.localSnapshot()

        XCTAssertTrue(snapshot.fans.isEmpty, "Fans should be empty when SMC is unavailable")
        XCTAssertFalse(snapshot.modelIdentifier.isEmpty, "Model identifier should always be populated")
    }

    func testLocalSnapshotReturnsMetadataOnUnsupportedHardware() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable },
            hidTemperatureReader: { [] }
        )
        let snapshot = try! service.localSnapshot()

        if !SystemInfo.isMacBookPro {
            XCTAssertTrue(snapshot.fans.isEmpty)
            XCTAssertTrue(snapshot.temperatureSensors.isEmpty)
        }
    }

    func testApplyDoesNotFallbackToUnprivilegedLocalSMCWritesWhenDaemonFails() async {
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonApply: { _, _ in
                throw ViftyError.helperRejected("Daemon connection invalidated.")
            }
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
    }

    func testRestoreAutoDoesNotFallbackToUnprivilegedLocalSMCWritesWhenDaemonFails() async {
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonRestoreAuto: { _ in
                throw ViftyError.helperRejected("Daemon request timed out.")
            }
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
    }

    func testManualBatchDaemonFailureNeverFallsBackToLocalTransactionWriter() async {
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonApplyManual: { _ in
                throw ViftyError.helperRejected("Legacy daemon does not support protocol v2.")
            }
        )

        do {
            _ = try await service.applyManualFanControl(ManualFanControlRequest(
                transactionID: "manual-1",
                sessionID: "manual-1",
                expectedFanIDs: [0],
                targetRPMByFanID: [0: 2_400],
                reason: "Fixed"
            ))
            XCTFail("Expected daemon transaction failure")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Fan helper is unavailable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFullAutoDaemonFailureNeverFallsBackToLocalTransactionWriter() async {
        let service = RealMacHardwareService(
            preferDaemon: true,
            daemonRestoreAll: { _, _ in
                throw ViftyError.helperRejected("Daemon request timed out.")
            }
        )

        do {
            _ = try await service.restoreAllAuto(AutoRestoreRequest(
                transactionID: "restore-1",
                expectedFanIDs: [0],
                reason: "Auto"
            ))
            XCTFail("Expected daemon restore transaction failure")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertTrue(message.contains("Fan helper is unavailable"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDaemonDisabledServiceIsReadOnlyForEveryWriteEntryPoint() async {
        let service = RealMacHardwareService(preferDaemon: false)
        let manual = ManualFanControlRequest(
            transactionID: "manual-1",
            sessionID: "session-1",
            expectedFanIDs: [0],
            targetRPMByFanID: [0: 2_400],
            reason: "Fixed"
        )

        do { try await service.apply(FanCommand(fanID: 0, mode: .fixedRPM(2_400)), fan: testFan); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("read-only")) }
        do { try await service.restoreAuto(fan: testFan); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("read-only")) }
        do { _ = try await service.applyManualFanControl(manual); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("read-only")) }
        do { _ = try await service.restoreAllAuto(AutoRestoreRequest(transactionID: "restore", reason: "Auto")); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("read-only")) }
    }

    func testSourceExposesNoInjectableLocalWriteClosures() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ViftyCore/RealMacHardwareService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for forbidden in [
            "localApply:",
            "localRestoreAuto:",
            "localApplyManual:",
            "localApplyAgent:",
            "localRestoreAll:"
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
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
