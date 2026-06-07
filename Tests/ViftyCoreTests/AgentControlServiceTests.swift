import Foundation
import XCTest
@testable import ViftyCore

final class AgentControlServiceTests: XCTestCase {
    func testPrepareAppliesTargetsStoresLeaseAndReportsStatus() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let status = try await service.prepare(request)

        XCTAssertEqual(status.activeLease?.id, "lease-1")
        XCTAssertEqual(status.activeLease?.expiresAt, Date(timeIntervalSince1970: 1_600))
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        XCTAssertEqual(try store.loadActiveLease()?.id, "lease-1")
    }

    func testRestoreAutoRestoresFansAndClearsLease() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        let status = try await service.restoreAuto(reason: "done")

        XCTAssertNil(status.activeLease)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testPrepareRestoresAlreadyAppliedFansWhenLaterApplyFails() async throws {
        let hardware = AgentServiceFakeHardware(
            snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500),
                Self.fan(id: 1, minimumRPM: 1500, maximumRPM: 5500)
            ]),
            failingApplyFanID: 1
        )
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected prepare to throw")
        } catch AgentServiceFakeHardware.Failure.applyFailed {
            let restored = await hardware.restoredFanIDs
            XCTAssertEqual(restored, [0])
            XCTAssertNil(try store.loadActiveLease())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-service-\(UUID().uuidString)", isDirectory: true)
    }

    private static func fan(id: Int, minimumRPM: Int, maximumRPM: Int) -> Fan {
        Fan(id: id, name: "Fan \(id)", currentRPM: minimumRPM, minimumRPM: minimumRPM, maximumRPM: maximumRPM, controllable: true)
    }

    private static func sensor(_ celsius: Double = 61) -> TemperatureSensor {
        TemperatureSensor(id: "Tp09", name: "CPU Performance Core 1", celsius: celsius, source: .synthetic)
    }

    private static func snapshot(fans: [Fan]) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: fans,
            temperatureSensors: [sensor()],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }
}

private actor AgentServiceFakeHardware: HardwareService {
    enum Failure: Error, Equatable {
        case applyFailed
    }

    var snapshotValue: HardwareSnapshot
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    var failingApplyFanID: Int?

    init(snapshot: HardwareSnapshot, failingApplyFanID: Int? = nil) {
        self.snapshotValue = snapshot
        self.failingApplyFanID = failingApplyFanID
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        if command.fanID == failingApplyFanID {
            throw Failure.applyFailed
        }
        appliedCommands.append(command)
    }

    func restoreAuto(fan: Fan) async throws {
        restoredFanIDs.append(fan.id)
    }
}
