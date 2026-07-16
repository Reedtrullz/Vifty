import Darwin
import Foundation
import ViftyCore
import ViftyFanControlSafety

public struct HelperCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol OfflineMaintenanceRestoring: Sendable {
    func restoreCompleteFanSetAndSnapshot() async throws -> HardwareSnapshot
}

/// Auto-only recovery for the exceptional case where the daemon is already
/// absent. Acquiring the same kernel lock is the exclusion proof; a ping/check
/// alone is never accepted. Its report cannot authorize teardown after this
/// process releases the lock, so it deliberately has no token and safeToStop is
/// false even after successful Auto recovery.
public struct OfflineHelperMaintenanceService: Sendable {
    private let effectiveUID: @Sendable () -> uid_t
    private let lockFactory: @Sendable () throws -> FanControlExclusiveLock
    private let restorerFactory: @Sendable (FanControlExclusiveLock) -> any OfflineMaintenanceRestoring

    public init(
        effectiveUID: @escaping @Sendable () -> uid_t,
        lockFactory: @escaping @Sendable () throws -> FanControlExclusiveLock,
        restorerFactory: @escaping @Sendable (FanControlExclusiveLock) -> any OfflineMaintenanceRestoring
    ) {
        self.effectiveUID = effectiveUID
        self.lockFactory = lockFactory
        self.restorerFactory = restorerFactory
    }

    public static let live = OfflineHelperMaintenanceService(
        effectiveUID: { geteuid() },
        lockFactory: { try FanControlExclusiveLock() },
        restorerFactory: { lock in LiveOfflineMaintenanceRestorer(exclusiveLock: lock) }
    )

    public func prepare() async -> HelperMaintenanceReport {
        await restore(operation: .offlineRecovery, authorizeOfflineTeardown: false)
    }

    /// Protocol-v1 migration authority is created only after the root lifecycle
    /// worker has disabled/unregistered the service and proved the launchd label
    /// absent. This process then holds the shared writer lock across full-set
    /// Auto restoration and fresh readback. The root worker validates this
    /// trusted executable's report before deleting any legacy artifact.
    public func authorizeLegacyTeardown(
        operation: HelperMaintenanceOperation
    ) async -> HelperMaintenanceReport {
        guard operation == .repair || operation == .uninstall else {
            return blockedReport(
                operation: operation,
                restoreAttempted: false,
                blocker: HelperMaintenanceBlocker(
                    code: .offlineAuthorizationUnavailable,
                    message: "Offline teardown authority accepts only repair or uninstall.",
                    recommendedRecoveryAction: "Use the reviewed helper lifecycle command without altering its operation."
                )
            )
        }
        return await restore(operation: operation, authorizeOfflineTeardown: true)
    }

    private func restore(
        operation: HelperMaintenanceOperation,
        authorizeOfflineTeardown: Bool
    ) async -> HelperMaintenanceReport {
        guard effectiveUID() == 0 else {
            return blockedReport(
                operation: operation,
                restoreAttempted: false,
                blocker: HelperMaintenanceBlocker(
                    code: .offlineAuthorizationUnavailable,
                    message: "Offline Auto recovery requires root and the daemon safety lock.",
                    recommendedRecoveryAction: "Use the live daemon maintenance flow or run the installed recovery helper through the reviewed administrator path."
                )
            )
        }

        let exclusiveLock: FanControlExclusiveLock
        do {
            exclusiveLock = try lockFactory()
        } catch {
            return blockedReport(
                operation: operation,
                restoreAttempted: false,
                blocker: HelperMaintenanceBlocker(
                    code: .offlineAuthorizationUnavailable,
                    message: "Offline safety lock unavailable: \(error.localizedDescription)",
                    recommendedRecoveryAction: "Keep the helper installed. Use the live daemon maintenance flow or stop the daemon through its verified quiesce path first."
                )
            )
        }

        do {
            // `exclusiveLock` remains strongly retained through restoration and
            // fresh confirmation; no second local writer can enter this scope.
            let snapshot = try await restorerFactory(exclusiveLock)
                .restoreCompleteFanSetAndSnapshot()
            let analysis = HelperMaintenanceSnapshotAnalyzer.analyze(snapshot)
            var blockers = analysis.blockers
            if !authorizeOfflineTeardown {
                blockers.append(HelperMaintenanceBlocker(
                    code: .offlineAuthorizationUnavailable,
                    message: "Offline Auto recovery completed, but its process-scoped lock cannot mint a live daemon teardown token.",
                    recommendedRecoveryAction: "Restart the daemon and request a short-lived single-use maintenance token before bootout, replacement, or deletion."
                ))
            }
            let complete = analysis.blockers.isEmpty
                && !analysis.expectedFanIDs.isEmpty
                && analysis.fanResults.allSatisfy(\.confirmedOSManaged)
            return HelperMaintenanceReport(
                operation: operation,
                safeToStop: authorizeOfflineTeardown && complete,
                quiesced: authorizeOfflineTeardown && complete,
                restoreAttempted: true,
                restoreSucceeded: analysis.blockers.isEmpty,
                completeExpectedSetConfirmed: complete,
                fanResults: analysis.fanResults,
                blockers: blockers,
                token: nil
            )
        } catch {
            return blockedReport(
                operation: operation,
                restoreAttempted: true,
                blocker: HelperMaintenanceBlocker(
                    code: .restoreFailed,
                    message: error.localizedDescription,
                    recommendedRecoveryAction: "Do not remove the helper. Reboot or restore Auto through the live daemon recovery flow."
                )
            )
        }
    }

    private func blockedReport(
        operation: HelperMaintenanceOperation = .offlineRecovery,
        restoreAttempted: Bool,
        blocker: HelperMaintenanceBlocker
    ) -> HelperMaintenanceReport {
        HelperMaintenanceReport(
            operation: operation,
            safeToStop: false,
            quiesced: false,
            restoreAttempted: restoreAttempted,
            restoreSucceeded: false,
            completeExpectedSetConfirmed: false,
            fanResults: [],
            blockers: [blocker],
            token: nil
        )
    }
}

public struct HelperCommandRunner: Sendable {
    public static let usage = "Usage: ViftyHelper probe | probeLocal | smcDiagnostics | readKey <SMC key> | prepareMaintenance --json | authorizeLegacyTeardown --operation repair|uninstall --json"

    private let daemonSnapshot: @Sendable () async throws -> HardwareSnapshot
    private let localSnapshot: @Sendable () throws -> HardwareSnapshot
    private let readKey: @Sendable (String) throws -> String
    private let diagnostics: @Sendable () -> [String]
    private let prepareOfflineMaintenance: @Sendable () async -> HelperMaintenanceReport
    private let authorizeLegacyTeardown: @Sendable (
        HelperMaintenanceOperation
    ) async -> HelperMaintenanceReport

    public init(
        daemonSnapshot: @escaping @Sendable () async throws -> HardwareSnapshot,
        localSnapshot: @escaping @Sendable () throws -> HardwareSnapshot,
        readKey: @escaping @Sendable (String) throws -> String,
        diagnostics: @escaping @Sendable () -> [String],
        prepareOfflineMaintenance: @escaping @Sendable () async -> HelperMaintenanceReport,
        authorizeLegacyTeardown: @escaping @Sendable (
            HelperMaintenanceOperation
        ) async -> HelperMaintenanceReport
    ) {
        self.daemonSnapshot = daemonSnapshot
        self.localSnapshot = localSnapshot
        self.readKey = readKey
        self.diagnostics = diagnostics
        self.prepareOfflineMaintenance = prepareOfflineMaintenance
        self.authorizeLegacyTeardown = authorizeLegacyTeardown
    }

    public static let live = HelperCommandRunner(
        daemonSnapshot: { try await ViftyDaemonClient().snapshot() },
        localSnapshot: { try RealMacHardwareService(preferDaemon: false).localSnapshot() },
        readKey: { key in
            let value = try SMCClient().read(key)
            let bytes = value.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            let decoded = SMCDecoding.decodeFloat(value).map { String(format: "%.2f", $0) } ?? "nil"
            return "key=\(value.key) type=\(value.dataType) size=\(value.bytes.count) bytes=\(bytes) decoded=\(decoded)"
        },
        diagnostics: SMCClient.diagnostics,
        prepareOfflineMaintenance: { await OfflineHelperMaintenanceService.live.prepare() },
        authorizeLegacyTeardown: {
            await OfflineHelperMaintenanceService.live.authorizeLegacyTeardown(operation: $0)
        }
    )

    public func run(arguments: [String]) async -> HelperCommandResult {
        guard let command = arguments.first else { return usageFailure() }
        do {
            switch command {
            case "probe":
                guard arguments.count == 1 else { return usageFailure() }
                return .init(
                    exitCode: 0,
                    standardOutput: HardwareSnapshotProbeFormatter.string(for: try await daemonSnapshot()) + "\n"
                )
            case "probeLocal":
                guard arguments.count == 1 else { return usageFailure() }
                return .init(
                    exitCode: 0,
                    standardOutput: HardwareSnapshotProbeFormatter.string(for: try localSnapshot()) + "\n"
                )
            case "readKey":
                guard arguments.count == 2,
                      arguments[1].utf8.count == 4 else { return usageFailure() }
                return .init(exitCode: 0, standardOutput: try readKey(arguments[1]) + "\n")
            case "smcDiagnostics":
                guard arguments.count == 1 else { return usageFailure() }
                let lines = diagnostics()
                return .init(exitCode: 0, standardOutput: lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            case "prepareMaintenance":
                guard arguments == ["prepareMaintenance", "--json"] else {
                    return usageFailure(
                        detail: "prepareMaintenance accepts only --json and never accepts RPM or fan-target arguments."
                    )
                }
                let report = await prepareOfflineMaintenance()
                return .init(
                    exitCode: 75,
                    standardOutput: try encode(report) + "\n",
                    standardError: "Offline maintenance recovery never authorizes helper teardown; a live daemon token is still required.\n"
                )
            case "authorizeLegacyTeardown":
                guard arguments.count == 4,
                      arguments[1] == "--operation",
                      let operation = HelperMaintenanceOperation(rawValue: arguments[2]),
                      operation == .repair || operation == .uninstall,
                      arguments[3] == "--json" else {
                    return usageFailure(
                        detail: "authorizeLegacyTeardown requires --operation repair|uninstall --json."
                    )
                }
                let report = await authorizeLegacyTeardown(operation)
                return .init(
                    exitCode: report.safeToStop ? 0 : 75,
                    standardOutput: try encode(report) + "\n",
                    standardError: report.safeToStop
                        ? ""
                        : "Offline legacy teardown authority was not established; no cleanup is authorized.\n"
                )
            case "setFixed", "auto":
                return .init(
                    exitCode: 75,
                    standardError: "Direct ViftyHelper fan writes are disabled; use the daemon-owned transactional recovery workflow.\n"
                )
            default:
                return usageFailure()
            }
        } catch {
            return .init(
                exitCode: 1,
                standardError: "ViftyHelper failed: \(error.localizedDescription)\n"
            )
        }
    }

    private func encode(_ report: HelperMaintenanceReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func usageFailure(detail: String? = nil) -> HelperCommandResult {
        let prefix = detail.map { "\($0)\n" } ?? ""
        return .init(exitCode: 64, standardError: prefix + Self.usage + "\n")
    }
}

private final class LiveOfflineMaintenanceRestorer: OfflineMaintenanceRestoring, @unchecked Sendable {
    private let arbiter: FanControlArbiter
    private let snapshotProvider: @Sendable () throws -> HardwareSnapshot

    init(exclusiveLock: FanControlExclusiveLock) {
        let readHardware = RealMacHardwareService(preferDaemon: false)
        let snapshotProvider: @Sendable () throws -> HardwareSnapshot = {
            try readHardware.localSnapshot()
        }
        self.snapshotProvider = snapshotProvider
        self.arbiter = FanControlArbiter(
            hardware: LocalPrivilegedFanControlHardware(snapshotProvider: snapshotProvider),
            journalStore: FanControlJournalStore(),
            exclusiveLock: exclusiveLock
        )
    }

    func restoreCompleteFanSetAndSnapshot() async throws -> HardwareSnapshot {
        _ = try await arbiter.restoreAuto(AutoRestoreRequest(
            transactionID: "offline-maintenance-\(UUID().uuidString)",
            expectedFanIDs: [],
            reason: "Offline Auto-only helper maintenance recovery",
            allowRestoreAllTrustedFans: true
        ))
        return try snapshotProvider()
    }
}
