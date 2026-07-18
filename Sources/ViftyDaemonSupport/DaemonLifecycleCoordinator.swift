import CryptoKit
import Darwin
import Foundation
import ViftyCore
import ViftyFanControlSafety

public enum DaemonLifecycleCoordinatorError: Error, Equatable, LocalizedError, Sendable {
    case maintenanceQuiesced
    case maintenanceNotQuiesced
    case maintenancePreparationInProgress
    case tokenUnavailable
    case tokenAlreadyConsumed
    case tokenMismatch
    case operationMismatch
    case unsupportedOperation
    case tokenExpired
    case bindingChanged(String)
    case safetyStateChanged(String)
    case consumedMaintenanceCannotResume

    public var errorDescription: String? {
        switch self {
        case .maintenanceQuiesced:
            "MAINTENANCE_QUIESCED: new fan-control ownership is blocked."
        case .maintenanceNotQuiesced:
            "MAINTENANCE_NOT_QUIESCED: helper maintenance was not prepared."
        case .maintenancePreparationInProgress:
            "MAINTENANCE_PREPARATION_IN_PROGRESS: wait for helper maintenance preparation to finish before cancelling or preparing again."
        case .tokenUnavailable:
            "MAINTENANCE_TOKEN_UNAVAILABLE: no daemon-owned maintenance token is active."
        case .tokenAlreadyConsumed:
            "MAINTENANCE_TOKEN_CONSUMED: the maintenance token is single-use and was already consumed."
        case .tokenMismatch:
            "MAINTENANCE_TOKEN_MISMATCH: the supplied token is not the daemon-owned active token."
        case .operationMismatch:
            "MAINTENANCE_OPERATION_MISMATCH: the token is bound to a different operation."
        case .unsupportedOperation:
            "MAINTENANCE_OPERATION_UNSUPPORTED: the live daemon accepts only repair, uninstall, or voluntary termination."
        case .tokenExpired:
            "MAINTENANCE_TOKEN_EXPIRED: prepare helper maintenance again."
        case .bindingChanged(let reason):
            "MAINTENANCE_BINDING_CHANGED: \(reason)"
        case .safetyStateChanged(let reason):
            "MAINTENANCE_SAFETY_CHANGED: \(reason)"
        case .consumedMaintenanceCannotResume:
            "MAINTENANCE_ALREADY_AUTHORIZED: the daemon must remain quiesced for teardown."
        }
    }
}

public enum HelperBinaryIdentity {
    public static let maximumHelperBytes = 128 * 1_024 * 1_024
    public static let installedDaemonURL = URL(
        fileURLWithPath: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
        isDirectory: false
    )

    public static func runningExecutableURL() throws -> URL {
        var requiredSize: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &requiredSize)
        guard requiredSize > 1, requiredSize <= UInt32(PATH_MAX * 4) else {
            throw ViftyError.helperRejected("Running helper executable path length is invalid.")
        }
        var buffer = [CChar](repeating: 0, count: Int(requiredSize))
        guard _NSGetExecutablePath(&buffer, &requiredSize) == 0 else {
            throw ViftyError.helperRejected("Could not resolve the running helper executable path.")
        }
        guard let terminator = buffer.firstIndex(of: 0), terminator > 0 else {
            throw ViftyError.helperRejected("Running helper executable path is not null-terminated.")
        }
        let path = String(
            decoding: buffer[..<terminator].map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        return URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
    }

    /// The copied legacy helper must remain root-owned. An SMAppService daemon
    /// executes Vifty.app's signed BundleProgram in place, so that file may be
    /// owned by the installing user; both forms must still be non-symlink,
    /// singly linked, non-group/world-writable executable regular files.
    public static func daemonExecutableSHA256(
        at url: URL,
        legacyURL: URL = installedDaemonURL,
        legacyOwnerID: uid_t = 0
    ) throws -> String {
        let normalized = url.standardizedFileURL
        if normalized.path == legacyURL.standardizedFileURL.path {
            return try sha256(at: normalized, requiredOwnerID: legacyOwnerID)
        }
        let components = normalized.pathComponents
        guard normalized.lastPathComponent == "ViftyDaemon",
              let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }),
              Array(components.dropFirst(appIndex + 1)) == ["Contents", "MacOS", "ViftyDaemon"] else {
            throw ViftyError.helperRejected(
                "Running helper is neither the legacy root helper nor Vifty.app's BundleProgram."
            )
        }
        return try sha256(at: normalized, requiredOwnerID: nil)
    }

    public static func bundledHelperSHA256ForRunningDaemon() throws -> String {
        let daemonURL = try runningExecutableURL().standardizedFileURL
        let components = daemonURL.pathComponents
        guard daemonURL.lastPathComponent == "ViftyDaemon",
              let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }),
              Array(components.dropFirst(appIndex + 1)) == ["Contents", "MacOS", "ViftyDaemon"] else {
            throw ViftyError.helperRejected(
                "The running daemon is not Vifty.app's canonical BundleProgram; protocol-v2 helper identity is unavailable."
            )
        }
        return try sha256(
            at: daemonURL.deletingLastPathComponent()
                .appendingPathComponent("ViftyHelper", isDirectory: false),
            requiredOwnerID: nil
        )
    }

    public static func sha256(
        at url: URL,
        requiredOwnerID: uid_t? = 0,
        maximumBytes: Int = maximumHelperBytes
    ) throws -> String {
        guard maximumBytes > 0 else {
            throw ViftyError.helperRejected("Helper identity byte limit is invalid.")
        }

        var pathMetadata = stat()
        guard lstat(url.path, &pathMetadata) == 0 else {
            throw identityFailure("lstat", path: url.path)
        }
        try validateExecutable(
            pathMetadata,
            requiredOwnerID: requiredOwnerID,
            maximumBytes: maximumBytes,
            context: "helper path"
        )

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw identityFailure("open", path: url.path) }
        defer { close(descriptor) }

        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0 else {
            throw identityFailure("fstat", path: url.path)
        }
        try validateExecutable(
            openedMetadata,
            requiredOwnerID: requiredOwnerID,
            maximumBytes: maximumBytes,
            context: "opened helper"
        )
        guard openedMetadata.st_dev == pathMetadata.st_dev,
              openedMetadata.st_ino == pathMetadata.st_ino else {
            throw ViftyError.helperRejected("Helper identity path changed while it was opened.")
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var totalBytes = 0
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw identityFailure("read", path: url.path)
            }
            totalBytes += count
            guard totalBytes <= maximumBytes else {
                throw ViftyError.helperRejected("Helper executable exceeds the bounded identity size limit.")
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }

        var finalMetadata = stat()
        guard fstat(descriptor, &finalMetadata) == 0 else {
            throw identityFailure("final fstat", path: url.path)
        }
        guard finalMetadata.st_dev == openedMetadata.st_dev,
              finalMetadata.st_ino == openedMetadata.st_ino,
              finalMetadata.st_size == openedMetadata.st_size,
              totalBytes == Int(openedMetadata.st_size) else {
            throw ViftyError.helperRejected("Helper executable changed while its identity was read.")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func liveBootSessionID() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 {
            return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
        }
        let estimatedBoot = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        return String(Int64(estimatedBoot * 1_000_000))
    }

    private static func validateExecutable(
        _ metadata: stat,
        requiredOwnerID: uid_t?,
        maximumBytes: Int,
        context: String
    ) throws {
        guard metadata.st_mode & S_IFMT == S_IFREG,
              (requiredOwnerID == nil || metadata.st_uid == requiredOwnerID),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o022 == 0,
              metadata.st_mode & 0o111 != 0,
              metadata.st_size > 0,
              metadata.st_size <= off_t(maximumBytes) else {
            throw ViftyError.helperRejected(
                "\(context) must be a bounded, singly linked, non-writable executable regular file with the required ownership."
            )
        }
    }

    private static func identityFailure(_ operation: String, path: String) -> ViftyError {
        .helperRejected("Helper identity \(operation) failed for \(path): \(String(cString: strerror(errno)))")
    }
}

/// Owns the live-daemon side of destructive helper maintenance. Quiescence is
/// shared with the arbiter's final physical-write gate; report JSON is evidence
/// only, while `consume` revalidates and atomically authorizes one operation.
public actor DaemonLifecycleCoordinator {
    public typealias RestoreAllAuto = @Sendable (AutoRestoreRequest) async throws -> FanControlTransactionResult
    public typealias OwnershipStatus = @Sendable () async -> FanControlOwnershipStatus
    public typealias JournalGeneration = @Sendable () async -> UInt64
    public typealias PersistAuthority = @Sendable (HelperMaintenanceAuthorityReceipt) throws -> Void
    public typealias ClearAuthority = @Sendable () throws -> Void

    private let restoreSignal: FanControlRestoreSignal
    private let restoreAllAuto: RestoreAllAuto
    private let ownershipStatus: OwnershipStatus
    private let freshSnapshot: @Sendable () throws -> HardwareSnapshot
    private let journalGeneration: JournalGeneration
    private let persistAuthority: PersistAuthority
    private let clearAuthority: ClearAuthority
    private let helperIdentity: @Sendable () throws -> String
    private let bootSessionID: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let tokenTTL: TimeInterval
    private let authorityTTL: TimeInterval
    private let daemonSessionID: String

    private var activeToken: HelperMaintenanceToken?
    private var activePreparationID: String?
    private var reservedTokenID: String?
    private var consumedTokenID: String?
    private var activeQuiesceGeneration: UInt64?

    public init(
        restoreSignal: FanControlRestoreSignal,
        restoreAllAuto: @escaping RestoreAllAuto,
        ownershipStatus: @escaping OwnershipStatus,
        freshSnapshot: @escaping @Sendable () throws -> HardwareSnapshot,
        journalGeneration: @escaping JournalGeneration,
        persistAuthority: @escaping PersistAuthority,
        clearAuthority: @escaping ClearAuthority,
        helperIdentity: @escaping @Sendable () throws -> String = {
            try HelperBinaryIdentity.bundledHelperSHA256ForRunningDaemon()
        },
        bootSessionID: @escaping @Sendable () -> String = HelperBinaryIdentity.liveBootSessionID,
        now: @escaping @Sendable () -> Date = Date.init,
        tokenTTL: TimeInterval = 30,
        authorityTTL: TimeInterval = 300,
        daemonSessionID: String = UUID().uuidString
    ) {
        self.restoreSignal = restoreSignal
        self.restoreAllAuto = restoreAllAuto
        self.ownershipStatus = ownershipStatus
        self.freshSnapshot = freshSnapshot
        self.journalGeneration = journalGeneration
        self.persistAuthority = persistAuthority
        self.clearAuthority = clearAuthority
        self.helperIdentity = helperIdentity
        self.bootSessionID = bootSessionID
        self.now = now
        self.tokenTTL = min(max(tokenTTL, 1), 120)
        self.authorityTTL = min(max(authorityTTL, 30), 600)
        self.daemonSessionID = daemonSessionID
    }

    public nonisolated func requireControlAllowed() throws {
        guard !restoreSignal.isMaintenanceQuiesced else {
            throw DaemonLifecycleCoordinatorError.maintenanceQuiesced
        }
    }

    public nonisolated func beginExternalMutation() throws -> FanControlMutationPermit {
        try restoreSignal.beginExternalMutation()
    }

    public var isQuiesced: Bool {
        restoreSignal.isMaintenanceQuiesced
    }

    public func prepare(
        operation: HelperMaintenanceOperation,
        helperSHA256: String? = nil
    ) async throws -> HelperMaintenanceReport {
        guard operation == .repair
                || operation == .uninstall
                || operation == .voluntaryTermination else {
            throw DaemonLifecycleCoordinatorError.unsupportedOperation
        }
        guard activePreparationID == nil else {
            throw DaemonLifecycleCoordinatorError.maintenancePreparationInProgress
        }
        if reservedTokenID != nil || consumedTokenID != nil {
            throw DaemonLifecycleCoordinatorError.consumedMaintenanceCannotResume
        }
        // `prepare` awaits restore and live-state confirmation below, so actor
        // reentrancy would otherwise let `cancel` end this quiesce generation
        // before preparation later publishes a token for it. Reserve the whole
        // preparation synchronously and release only this invocation's
        // reservation when it finishes.
        let preparationID = UUID().uuidString
        activePreparationID = preparationID
        defer {
            if activePreparationID == preparationID {
                activePreparationID = nil
            }
        }
        let normalizedHelperIdentity: String?
        if operation == .repair || operation == .uninstall {
            guard let helperSHA256 else {
                throw DaemonLifecycleCoordinatorError.bindingChanged(
                    "the exact bundled ViftyHelper digest is missing"
                )
            }
            let requestedIdentity = try Self.validateHelperIdentity(helperSHA256)
            let daemonIdentity = try Self.validateHelperIdentity(helperIdentity())
            guard requestedIdentity == daemonIdentity else {
                throw DaemonLifecycleCoordinatorError.bindingChanged(
                    "the requesting client helper digest does not match the running daemon app's canonical ViftyHelper"
                )
            }
            normalizedHelperIdentity = daemonIdentity
        } else {
            normalizedHelperIdentity = nil
        }
        if operation == .repair || operation == .uninstall {
            do {
                try clearAuthority()
            } catch {
                throw DaemonLifecycleCoordinatorError.bindingChanged(
                    "stale privileged maintenance authority could not be revoked: \(error.localizedDescription)"
                )
            }
        }

        let quiesceGeneration = restoreSignal.beginMaintenanceQuiesce()
        activeQuiesceGeneration = quiesceGeneration
        activeToken = nil
        restoreSignal.requestRestore()

        var blockers: [HelperMaintenanceBlocker] = []
        let restoreSucceeded: Bool
        do {
            _ = try await restoreAllAuto(AutoRestoreRequest(
                transactionID: "maintenance-\(UUID().uuidString)",
                expectedFanIDs: [],
                reason: "Prepare \(operation.rawValue) helper maintenance",
                allowRestoreAllTrustedFans: true
            ))
            restoreSucceeded = true
        } catch {
            restoreSucceeded = false
            blockers.append(HelperMaintenanceBlocker(
                code: .restoreFailed,
                message: error.localizedDescription,
                recommendedRecoveryAction: "Use Restore Auto again or reboot into a known OS-managed fan state; do not remove the helper."
            ))
        }

        let status = await ownershipStatus()
        if !Self.isCleanOSOwnership(status) {
            blockers.append(HelperMaintenanceBlocker(
                code: .ownershipUnresolved,
                message: "Daemon ownership is \(status.owner?.type ?? "unresolved") with recoveryPending=\(status.recoveryPending).",
                recommendedRecoveryAction: "Resolve daemon recovery and confirm macOS ownership before helper maintenance."
            ))
        }

        let snapshot: HardwareSnapshot?
        do {
            snapshot = try freshSnapshot()
        } catch {
            snapshot = nil
            blockers.append(HelperMaintenanceBlocker(
                code: .snapshotUnavailable,
                message: error.localizedDescription,
                recommendedRecoveryAction: "Restore fresh trusted fan telemetry or reboot; destructive helper maintenance remains blocked."
            ))
        }

        let analysis = snapshot.map(HelperMaintenanceSnapshotAnalyzer.analyze)
            ?? HelperMaintenanceSnapshotAnalysis(expectedFanIDs: [], fanResults: [], blockers: [])
        blockers.append(contentsOf: analysis.blockers)
        let completeExpectedSetConfirmed = snapshot != nil
            && analysis.blockers.isEmpty
            && !analysis.expectedFanIDs.isEmpty
            && analysis.fanResults.allSatisfy(\.confirmedOSManaged)

        var token: HelperMaintenanceToken?
        if restoreSucceeded,
           blockers.isEmpty,
           completeExpectedSetConfirmed {
            if operation == .voluntaryTermination {
                token = nil
            } else {
                do {
                    guard let normalizedIdentity = normalizedHelperIdentity else {
                        throw ViftyError.helperRejected(
                            "The exact bundled ViftyHelper digest is unavailable."
                        )
                    }
                    let issuedAt = now()
                    token = HelperMaintenanceToken(
                        tokenID: UUID().uuidString,
                        operation: operation,
                        issuedAt: issuedAt,
                        expiresAt: issuedAt.addingTimeInterval(tokenTTL),
                        bootSessionID: bootSessionID(),
                        daemonSessionID: daemonSessionID,
                        journalGeneration: await journalGeneration(),
                        expectedFanIDs: analysis.expectedFanIDs,
                        helperSHA256: normalizedIdentity,
                        quiesceGeneration: quiesceGeneration
                    )
                    activeToken = token
                } catch {
                    blockers.append(HelperMaintenanceBlocker(
                        code: .helperIdentityUnavailable,
                        message: error.localizedDescription,
                        recommendedRecoveryAction: "Repair the installed helper identity through a trusted recovery path; do not authorize teardown from report JSON."
                    ))
                }
            }
        }

        let safeToStop = restoreSucceeded
            && blockers.isEmpty
            && completeExpectedSetConfirmed
            && (operation == .voluntaryTermination || token != nil)
        return HelperMaintenanceReport(
            operation: operation,
            safeToStop: safeToStop,
            quiesced: restoreSignal.isMaintenanceQuiesced,
            restoreAttempted: true,
            restoreSucceeded: restoreSucceeded,
            completeExpectedSetConfirmed: completeExpectedSetConfirmed,
            fanResults: analysis.fanResults,
            blockers: blockers,
            token: token
        )
    }

    public func prepareVoluntaryTermination() async throws -> HelperMaintenanceReport {
        guard let consumedTokenID else {
            return try await prepare(operation: .voluntaryTermination)
        }
        guard restoreSignal.isMaintenanceQuiesced,
              let activeToken,
              activeToken.tokenID == consumedTokenID,
              activeQuiesceGeneration == activeToken.quiesceGeneration,
              restoreSignal.currentMaintenanceGeneration == activeToken.quiesceGeneration else {
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "consumed maintenance authorization is no longer quiesced"
            )
        }
        guard await journalGeneration() == activeToken.journalGeneration,
              Self.isCleanOSOwnership(await ownershipStatus()) else {
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "ownership or journal generation changed after maintenance authorization"
            )
        }
        let snapshot: HardwareSnapshot
        do {
            snapshot = try freshSnapshot()
        } catch {
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "fresh termination confirmation failed: \(error.localizedDescription)"
            )
        }
        let analysis = HelperMaintenanceSnapshotAnalyzer.analyze(snapshot)
        guard analysis.blockers.isEmpty,
              analysis.expectedFanIDs == activeToken.expectedFanIDs,
              analysis.fanResults.allSatisfy(\.confirmedOSManaged) else {
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "complete Auto/System fan confirmation changed after authorization"
            )
        }
        return HelperMaintenanceReport(
            operation: .voluntaryTermination,
            safeToStop: true,
            quiesced: true,
            restoreAttempted: false,
            restoreSucceeded: true,
            completeExpectedSetConfirmed: true,
            fanResults: analysis.fanResults,
            blockers: [],
            token: nil,
            tokenConsumed: true
        )
    }

    public func consume(
        _ request: HelperMaintenanceAuthorizationRequest
    ) async throws -> HelperMaintenanceAuthorization {
        guard restoreSignal.isMaintenanceQuiesced,
              let quiesceGeneration = activeQuiesceGeneration else {
            throw DaemonLifecycleCoordinatorError.maintenanceNotQuiesced
        }
        if reservedTokenID == request.token.tokenID
            || consumedTokenID == request.token.tokenID {
            throw DaemonLifecycleCoordinatorError.tokenAlreadyConsumed
        }
        guard let authoritativeToken = activeToken else {
            throw DaemonLifecycleCoordinatorError.tokenUnavailable
        }
        guard request.operation == request.token.operation,
              request.operation == authoritativeToken.operation else {
            throw DaemonLifecycleCoordinatorError.operationMismatch
        }
        guard request.token == authoritativeToken else {
            throw DaemonLifecycleCoordinatorError.tokenMismatch
        }
        let validationTime = now()
        guard validationTime >= authoritativeToken.issuedAt,
              validationTime <= authoritativeToken.expiresAt else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.tokenExpired
        }
        guard authoritativeToken.schemaVersion == HelperMaintenanceToken.currentSchemaVersion,
              authoritativeToken.bootSessionID == bootSessionID(),
              authoritativeToken.daemonSessionID == daemonSessionID,
              authoritativeToken.quiesceGeneration == quiesceGeneration,
              restoreSignal.currentMaintenanceGeneration == quiesceGeneration else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.bindingChanged(
                "boot, daemon-session, schema, or quiesce generation changed"
            )
        }

        // Actor methods are reentrant at every await below. Reserve this
        // single-use token while still executing synchronously so a second
        // consumer cannot pass validation before the first one commits its
        // root-owned authority receipt. The token-specific defer prevents an
        // older failed attempt from clearing a later reservation.
        reservedTokenID = authoritativeToken.tokenID
        defer {
            if reservedTokenID == authoritativeToken.tokenID {
                reservedTokenID = nil
            }
        }

        guard await journalGeneration() == authoritativeToken.journalGeneration else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.bindingChanged("journal generation changed")
        }
        let currentHelperIdentity: String
        do {
            currentHelperIdentity = try Self.validateHelperIdentity(helperIdentity())
        } catch {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.bindingChanged(
                "canonical bundled helper identity is unavailable: \(error.localizedDescription)"
            )
        }
        guard currentHelperIdentity == authoritativeToken.helperSHA256 else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.bindingChanged(
                "canonical bundled helper identity changed"
            )
        }
        guard Self.isCleanOSOwnership(await ownershipStatus()) else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "daemon ownership is no longer clean macOS ownership"
            )
        }

        let snapshot: HardwareSnapshot
        do {
            snapshot = try freshSnapshot()
        } catch {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "fresh confirmation failed: \(error.localizedDescription)"
            )
        }
        let analysis = HelperMaintenanceSnapshotAnalyzer.analyze(snapshot)
        guard analysis.blockers.isEmpty,
              analysis.expectedFanIDs == authoritativeToken.expectedFanIDs,
              analysis.fanResults.allSatisfy(\.confirmedOSManaged) else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.safetyStateChanged(
                "the complete trusted Auto/System fan set changed"
            )
        }

        // Every live-state check above crosses an actor-reentrancy boundary.
        // Re-check expiry at the synchronous persistence commit point and use
        // that final time for both the receipt and returned authorization.
        let commitTime = now()
        guard commitTime >= authoritativeToken.issuedAt,
              commitTime <= authoritativeToken.expiresAt else {
            self.activeToken = nil
            throw DaemonLifecycleCoordinatorError.tokenExpired
        }
        let authorityReceipt = HelperMaintenanceAuthorityReceipt(
            operation: authoritativeToken.operation,
            tokenID: authoritativeToken.tokenID,
            tokenIssuedAt: authoritativeToken.issuedAt,
            authorizedAt: commitTime,
            expiresAt: commitTime.addingTimeInterval(authorityTTL),
            bootSessionID: authoritativeToken.bootSessionID,
            daemonSessionID: authoritativeToken.daemonSessionID,
            journalGeneration: authoritativeToken.journalGeneration,
            expectedFanIDs: authoritativeToken.expectedFanIDs,
            helperSHA256: authoritativeToken.helperSHA256,
            quiesceGeneration: authoritativeToken.quiesceGeneration
        )
        do {
            try persistAuthority(authorityReceipt)
        } catch {
            throw DaemonLifecycleCoordinatorError.bindingChanged(
                "root-owned maintenance authority could not be persisted: \(error.localizedDescription)"
            )
        }
        consumedTokenID = authoritativeToken.tokenID
        reservedTokenID = nil
        return HelperMaintenanceAuthorization(
            authorized: true,
            operation: authoritativeToken.operation,
            tokenID: authoritativeToken.tokenID,
            consumedAt: commitTime,
            quiesced: true,
            tokenConsumed: true
        )
    }

    public func cancel() throws {
        guard activePreparationID == nil else {
            throw DaemonLifecycleCoordinatorError.maintenancePreparationInProgress
        }
        guard reservedTokenID == nil, consumedTokenID == nil else {
            throw DaemonLifecycleCoordinatorError.consumedMaintenanceCannotResume
        }
        guard let activeQuiesceGeneration else {
            throw DaemonLifecycleCoordinatorError.maintenanceNotQuiesced
        }
        do {
            try clearAuthority()
        } catch {
            throw DaemonLifecycleCoordinatorError.bindingChanged(
                "privileged maintenance authority could not be revoked: \(error.localizedDescription)"
            )
        }
        activeToken = nil
        self.activeQuiesceGeneration = nil
        guard restoreSignal.endMaintenanceQuiesce(through: activeQuiesceGeneration) else {
            throw DaemonLifecycleCoordinatorError.bindingChanged("quiesce generation changed")
        }
    }

    private static func isCleanOSOwnership(_ status: FanControlOwnershipStatus) -> Bool {
        status.protocolVersion >= FanControlProtocolVersion.current
            && status.owner == nil
            && status.phase == nil
            && status.transactionID == nil
            && status.expectedFanIDs.isEmpty
            && !status.recoveryPending
            && status.errorCode == nil
    }

    private static func validateHelperIdentity(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (97...102).contains($0.value)
              }) else {
            throw ViftyError.helperRejected("Installed helper SHA-256 is missing or malformed.")
        }
        return normalized
    }

}
