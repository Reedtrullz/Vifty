import Darwin
import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyFanControlSafety
@testable import ViftyHelperSupport

final class HelperCommandRunnerTests: XCTestCase {
    func testPrepareMaintenanceAcceptsOnlyJSONAndNeverTargetArguments() async throws {
        let recorder = HelperRunnerRecorder()
        let runner = makeRunner(recorder: recorder)

        let invalid = await runner.run(arguments: [
            "prepareMaintenance", "--json", "--fan", "0", "--rpm", "4000"
        ])

        XCTAssertEqual(invalid.exitCode, 64)
        XCTAssertTrue(invalid.standardError.contains("never accepts RPM"))
        XCTAssertEqual(recorder.prepareCount, 0)

        let valid = await runner.run(arguments: ["prepareMaintenance", "--json"])
        XCTAssertEqual(valid.exitCode, 75)
        XCTAssertEqual(recorder.prepareCount, 1)
        let data = try XCTUnwrap(valid.standardOutput.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let report = try decoder.decode(HelperMaintenanceReport.self, from: data)
        XCTAssertEqual(report.operation, .offlineRecovery)
        XCTAssertFalse(report.safeToStop)
        XCTAssertNil(report.token)
    }

    func testDirectFixedAndAutoCommandsRemainDisabledWithoutCallingDependencies() async {
        let recorder = HelperRunnerRecorder()
        let runner = makeRunner(recorder: recorder)

        let fixed = await runner.run(arguments: ["setFixed", "0", "4000"])
        let auto = await runner.run(arguments: ["auto", "0"])

        XCTAssertEqual(fixed.exitCode, 75)
        XCTAssertEqual(auto.exitCode, 75)
        XCTAssertEqual(recorder.totalCalls, 0)
    }

    func testLegacyTeardownCommandAcceptsOnlyRootScopedOperationAndJSON() async throws {
        let recorder = HelperRunnerRecorder()
        let runner = makeRunner(recorder: recorder)

        let invalid = await runner.run(arguments: [
            "authorizeLegacyTeardown", "--operation", "offlineRecovery", "--json"
        ])
        XCTAssertEqual(invalid.exitCode, 64)
        XCTAssertEqual(recorder.legacyAuthorizeCount, 0)

        let valid = await runner.run(arguments: [
            "authorizeLegacyTeardown", "--operation", "repair", "--json"
        ])
        XCTAssertEqual(valid.exitCode, 0)
        XCTAssertEqual(recorder.legacyAuthorizeCount, 1)
        let data = try XCTUnwrap(valid.standardOutput.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let report = try decoder.decode(HelperMaintenanceReport.self, from: data)
        XCTAssertEqual(report.operation, .repair)
        XCTAssertTrue(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertNil(report.token)
    }

    func testProbeAndReadOnlyCommandsUseInjectedReaders() async {
        let recorder = HelperRunnerRecorder()
        let runner = makeRunner(recorder: recorder)

        let probe = await runner.run(arguments: ["probe"])
        let local = await runner.run(arguments: ["probeLocal"])
        let key = await runner.run(arguments: ["readKey", "F0Ac"])
        let diagnostics = await runner.run(arguments: ["smcDiagnostics"])

        XCTAssertEqual(probe.exitCode, 0)
        XCTAssertEqual(local.exitCode, 0)
        XCTAssertTrue(key.standardOutput.contains("key=F0Ac"))
        XCTAssertEqual(diagnostics.standardOutput, "diagnostic\n")
        XCTAssertEqual(recorder.daemonSnapshotCount, 1)
        XCTAssertEqual(recorder.localSnapshotCount, 1)
        XCTAssertEqual(recorder.readKeyCount, 1)
        XCTAssertEqual(recorder.diagnosticsCount, 1)
    }

    func testOfflineRecoveryRequiresRootBeforeLockOrRestoreConstruction() async {
        let recorder = OfflineServiceRecorder()
        let service = OfflineHelperMaintenanceService(
            effectiveUID: { 501 },
            lockFactory: {
                recorder.lockFactoryCount += 1
                throw ViftyError.helperRejected("must not run")
            },
            restorerFactory: { _ in
                recorder.restorerFactoryCount += 1
                return FakeOfflineRestorer(snapshot: Self.snapshot())
            }
        )

        let report = await service.prepare()

        XCTAssertFalse(report.restoreAttempted)
        XCTAssertFalse(report.safeToStop)
        XCTAssertEqual(recorder.lockFactoryCount, 0)
        XCTAssertEqual(recorder.restorerFactoryCount, 0)
    }

    func testOfflineRecoveryLockContentionProvesZeroRestoreCalls() async throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("writer.lock")
        let held = try FanControlExclusiveLock(url: lockURL, requiredOwnerID: geteuid())
        defer { held.release() }
        let recorder = OfflineServiceRecorder()
        let service = OfflineHelperMaintenanceService(
            effectiveUID: { 0 },
            lockFactory: {
                recorder.lockFactoryCount += 1
                return try FanControlExclusiveLock(url: lockURL, requiredOwnerID: geteuid())
            },
            restorerFactory: { _ in
                recorder.restorerFactoryCount += 1
                return FakeOfflineRestorer(snapshot: Self.snapshot(), recorder: recorder)
            }
        )

        let report = await service.prepare()

        XCTAssertFalse(report.restoreAttempted)
        XCTAssertFalse(report.safeToStop)
        XCTAssertEqual(recorder.lockFactoryCount, 1)
        XCTAssertEqual(recorder.restorerFactoryCount, 0)
        XCTAssertEqual(recorder.restoreCount, 0)
    }

    func testOfflineRecoveryUsesExclusiveLockAndFullAutoProofButCannotMintToken() async throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent("writer.lock")
        let recorder = OfflineServiceRecorder()
        let service = OfflineHelperMaintenanceService(
            effectiveUID: { 0 },
            lockFactory: {
                recorder.lockFactoryCount += 1
                return try FanControlExclusiveLock(url: lockURL, requiredOwnerID: geteuid())
            },
            restorerFactory: { lock in
                recorder.restorerFactoryCount += 1
                XCTAssertTrue(lock.isHeld)
                return FakeOfflineRestorer(snapshot: Self.snapshot(), recorder: recorder)
            }
        )

        let report = await service.prepare()

        XCTAssertTrue(report.restoreAttempted)
        XCTAssertTrue(report.restoreSucceeded)
        XCTAssertTrue(report.completeExpectedSetConfirmed)
        XCTAssertFalse(report.safeToStop)
        XCTAssertFalse(report.quiesced)
        XCTAssertNil(report.token)
        XCTAssertEqual(report.fanResults.map(\.fanID), [0, 1])
        XCTAssertTrue(report.blockers.contains { $0.code == .offlineAuthorizationUnavailable })
        XCTAssertEqual(recorder.restoreCount, 1)
    }

    func testOfflineRecoveryFailureStaysBlockedAndCarriesNoToken() async throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = OfflineHelperMaintenanceService(
            effectiveUID: { 0 },
            lockFactory: {
                try FanControlExclusiveLock(
                    url: root.appendingPathComponent("writer.lock"),
                    requiredOwnerID: geteuid()
                )
            },
            restorerFactory: { _ in
                FakeOfflineRestorer(
                    snapshot: Self.snapshot(),
                    errorMessage: "readback mismatch"
                )
            }
        )

        let report = await service.prepare()

        XCTAssertTrue(report.restoreAttempted)
        XCTAssertFalse(report.restoreSucceeded)
        XCTAssertFalse(report.safeToStop)
        XCTAssertNil(report.token)
        XCTAssertTrue(report.blockers.contains { $0.code == .restoreFailed })
    }

    func testLegacyOfflineAuthorityAcceptsOneCompleteTrustedFan() async throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = OfflineHelperMaintenanceService(
            effectiveUID: { 0 },
            lockFactory: {
                try FanControlExclusiveLock(
                    url: root.appendingPathComponent("writer.lock"),
                    requiredOwnerID: geteuid()
                )
            },
            restorerFactory: { lock in
                XCTAssertTrue(lock.isHeld)
                return FakeOfflineRestorer(snapshot: Self.snapshot(fans: [Self.fan(id: 0, mode: .automatic)]))
            }
        )

        let report = await service.authorizeLegacyTeardown(operation: .uninstall)

        XCTAssertTrue(report.safeToStop)
        XCTAssertTrue(report.quiesced)
        XCTAssertTrue(report.restoreSucceeded)
        XCTAssertTrue(report.completeExpectedSetConfirmed)
        XCTAssertEqual(report.fanResults.map(\.fanID), [0])
        XCTAssertTrue(report.blockers.isEmpty)
    }

    private func makeRunner(recorder: HelperRunnerRecorder) -> HelperCommandRunner {
        HelperCommandRunner(
            daemonSnapshot: {
                recorder.daemonSnapshotCount += 1
                return Self.snapshot()
            },
            localSnapshot: {
                recorder.localSnapshotCount += 1
                return Self.snapshot()
            },
            readKey: { key in
                recorder.readKeyCount += 1
                return "key=\(key)"
            },
            diagnostics: {
                recorder.diagnosticsCount += 1
                return ["diagnostic"]
            },
            prepareOfflineMaintenance: {
                recorder.prepareCount += 1
                return Self.offlineBlockedReport()
            },
            authorizeLegacyTeardown: { operation in
                recorder.legacyAuthorizeCount += 1
                return HelperMaintenanceReport(
                    operation: operation,
                    safeToStop: true,
                    quiesced: true,
                    restoreAttempted: true,
                    restoreSucceeded: true,
                    completeExpectedSetConfirmed: true,
                    fanResults: [],
                    blockers: [],
                    token: nil
                )
            }
        )
    }

    private static func offlineBlockedReport() -> HelperMaintenanceReport {
        HelperMaintenanceReport(
            operation: .offlineRecovery,
            safeToStop: false,
            quiesced: false,
            restoreAttempted: false,
            restoreSucceeded: false,
            completeExpectedSetConfirmed: false,
            fanResults: [],
            blockers: [HelperMaintenanceBlocker(
                code: .offlineAuthorizationUnavailable,
                message: "fixture",
                recommendedRecoveryAction: "fixture"
            )],
            token: nil
        )
    }

    private static func snapshot(
        fans: [Fan] = [fan(id: 0, mode: .automatic), fan(id: 1, mode: .system)]
    ) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: fans,
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU", celsius: 50, source: .synthetic)
            ],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private static func fan(id: Int, mode: FanHardwareMode) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: 1_400,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: mode,
            hardwareModeKey: "F\(id)Md",
            targetRPM: 1_400,
            controlEligibility: .trusted
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("helper-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard chmod(root.path, 0o700) == 0 else {
            throw ViftyError.helperRejected("Could not tighten helper runner test directory")
        }
        return root
    }
}

private final class HelperRunnerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    var daemonSnapshotCount: Int {
        get { count("daemon") }
        set { set("daemon", newValue) }
    }
    var localSnapshotCount: Int {
        get { count("local") }
        set { set("local", newValue) }
    }
    var readKeyCount: Int {
        get { count("read") }
        set { set("read", newValue) }
    }
    var diagnosticsCount: Int {
        get { count("diagnostics") }
        set { set("diagnostics", newValue) }
    }
    var prepareCount: Int {
        get { count("prepare") }
        set { set("prepare", newValue) }
    }
    var legacyAuthorizeCount: Int {
        get { count("legacy-authorize") }
        set { set("legacy-authorize", newValue) }
    }
    var totalCalls: Int { lock.withLock { counts.values.reduce(0, +) } }

    private func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
    private func set(_ key: String, _ value: Int) { lock.withLock { counts[key] = value } }
}

private final class OfflineServiceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    var lockFactoryCount: Int {
        get { count("lock") }
        set { set("lock", newValue) }
    }
    var restorerFactoryCount: Int {
        get { count("factory") }
        set { set("factory", newValue) }
    }
    var restoreCount: Int {
        get { count("restore") }
        set { set("restore", newValue) }
    }

    private func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
    private func set(_ key: String, _ value: Int) { lock.withLock { counts[key] = value } }
}

private struct FakeOfflineRestorer: OfflineMaintenanceRestoring {
    var snapshot: HardwareSnapshot
    var errorMessage: String?
    var recorder: OfflineServiceRecorder?

    init(
        snapshot: HardwareSnapshot,
        errorMessage: String? = nil,
        recorder: OfflineServiceRecorder? = nil
    ) {
        self.snapshot = snapshot
        self.errorMessage = errorMessage
        self.recorder = recorder
    }

    func restoreCompleteFanSetAndSnapshot() async throws -> HardwareSnapshot {
        if let recorder { recorder.restoreCount += 1 }
        if let errorMessage { throw ViftyError.helperRejected(errorMessage) }
        return snapshot
    }
}
