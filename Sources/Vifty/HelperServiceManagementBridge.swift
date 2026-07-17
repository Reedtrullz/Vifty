import Darwin
import Foundation
import ServiceManagement
import ViftyCore

enum HelperServiceManagementBridgeError: Error, LocalizedError, Equatable {
    case invalidArguments
    case invalidMainBundle(String)
    case transitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "The helper service bridge requires exactly --helper-service-management register|unregister --json."
        case .invalidMainBundle(let reason):
            "Helper service management requires the signed Vifty.app main executable: \(reason)"
        case .transitionFailed(let reason):
            "Helper service registration did not reach the required state: \(reason)"
        }
    }
}

enum HelperServiceManagementRequest: Equatable, Sendable {
    case register
    case unregister(operation: HelperMaintenanceOperation, reportPath: String)
    case unregisterLegacy(operation: HelperMaintenanceOperation, rootRecordPath: String)

    static func parse(arguments: [String]) throws -> Self? {
        guard arguments.contains("--helper-service-management") else { return nil }
        guard arguments.count >= 3,
              arguments[1] == "--helper-service-management" else {
            throw HelperServiceManagementBridgeError.invalidArguments
        }
        switch arguments[2] {
        case "register":
            guard arguments.count == 4,
                  arguments[1] == "--helper-service-management",
                  arguments[3] == "--json" else {
                throw HelperServiceManagementBridgeError.invalidArguments
            }
            return .register
        case "unregister":
            guard arguments.count == 8,
                  arguments[1] == "--helper-service-management",
                  arguments[3] == "--operation",
                  let operation = HelperMaintenanceOperation(rawValue: arguments[4]),
                  operation == .repair || operation == .uninstall,
                  arguments[5] == "--report",
                  arguments[6].hasPrefix("/"),
                  arguments[7] == "--json" else {
                throw HelperServiceManagementBridgeError.invalidArguments
            }
            return .unregister(operation: operation, reportPath: arguments[6])
        case "unregister-legacy":
            guard arguments.count == 8,
                  arguments[1] == "--helper-service-management",
                  arguments[3] == "--operation",
                  let operation = HelperMaintenanceOperation(rawValue: arguments[4]),
                  operation == .uninstall,
                  arguments[5] == "--root-record",
                  arguments[6] == HelperPrivilegedExecutionEvidence.defaultURL.path,
                  arguments[7] == "--json" else {
                throw HelperServiceManagementBridgeError.invalidArguments
            }
            return .unregisterLegacy(operation: operation, rootRecordPath: arguments[6])
        default: throw HelperServiceManagementBridgeError.invalidArguments
        }
    }
}

struct HelperPrivilegedExecutionPhase: Codable, Equatable, Sendable {
    var phase: String
    var attempted: Bool
    var succeeded: Bool
}

struct HelperPrivilegedExecutionEvidence: Codable, Equatable, Sendable {
    static let schemaID = "https://vifty.app/schemas/helper-maintenance-execution-v1.json"
    static let defaultURL = URL(
        fileURLWithPath: "/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json"
    )

    var schemaVersion: Int
    var schemaID: String
    var operation: HelperMaintenanceOperation
    var status: String
    var blocker: String
    var authorityMode: String
    var requestingUserID: uid_t
    var requestingProcessID: pid_t
    var updatedAt: Date
    var phases: [HelperPrivilegedExecutionPhase]

    func authorizesLegacyUnregister(
        operation: HelperMaintenanceOperation,
        requestingUserID: uid_t,
        requestingProcessID: pid_t,
        now: Date
    ) -> Bool {
        guard schemaVersion == 1,
              schemaID == Self.schemaID,
              self.operation == operation,
              operation == .uninstall,
              status == "completed",
              blocker.isEmpty,
              self.requestingUserID == requestingUserID,
              self.requestingProcessID == requestingProcessID,
              requestingProcessID > 1,
              abs(updatedAt.timeIntervalSince(now)) <= 120 else {
            return false
        }
        let succeeded = Set(phases.filter { $0.attempted && $0.succeeded }.map(\.phase))
        guard succeeded.contains("verify-privileged-authority"),
              succeeded.contains("disable-service-and-confirm-offline"),
              succeeded.contains("post-freeze-offline-auto-confirm"),
              succeeded.contains("remove-legacy-helper-plist-and-logs") else {
            return false
        }
        switch authorityMode {
        case "daemon-receipt", "offline-auto":
            return true
        default:
            return false
        }
    }
}

enum HelperPrivilegedExecutionEvidenceReader {
    static let maximumBytes = 64 * 1_024

    static func read(atPath path: String) throws -> HelperPrivilegedExecutionEvidence {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == HelperPrivilegedExecutionEvidence.defaultURL.standardizedFileURL.path else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence must use the fixed root-owned path"
            )
        }
        let requiredOwner: uid_t = 0
        var directoryMetadata = stat()
        guard lstat(url.deletingLastPathComponent().path, &directoryMetadata) == 0,
              directoryMetadata.st_mode & S_IFMT == S_IFDIR,
              directoryMetadata.st_uid == requiredOwner,
              directoryMetadata.st_mode & 0o022 == 0 else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence directory is not root-authenticated"
            )
        }
        var pathMetadata = stat()
        guard lstat(url.path, &pathMetadata) == 0,
              pathMetadata.st_mode & S_IFMT == S_IFREG,
              pathMetadata.st_uid == requiredOwner,
              pathMetadata.st_nlink == 1,
              pathMetadata.st_mode & 0o022 == 0,
              pathMetadata.st_size > 0,
              pathMetadata.st_size <= off_t(maximumBytes) else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence is not a bounded, singly linked, owner-authenticated regular file"
            )
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence could not be opened without following links"
            )
        }
        defer { Darwin.close(descriptor) }
        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0,
              openedMetadata.st_dev == pathMetadata.st_dev,
              openedMetadata.st_ino == pathMetadata.st_ino,
              openedMetadata.st_size == pathMetadata.st_size else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence identity changed while opening"
            )
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence has an invalid size"
            )
        }
        var finalMetadata = stat()
        guard fstat(descriptor, &finalMetadata) == 0,
              finalMetadata.st_dev == openedMetadata.st_dev,
              finalMetadata.st_ino == openedMetadata.st_ino,
              finalMetadata.st_size == openedMetadata.st_size else {
            throw HelperServiceManagementBridgeError.transitionFailed(
                "privileged execution evidence changed while reading"
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(HelperPrivilegedExecutionEvidence.self, from: data)
    }
}

@MainActor
protocol HelperServiceManagementBackend: AnyObject {
    var state: HelperServiceRegistrationState { get }
    func register() throws
    func unregister() async throws
}

@MainActor
final class SystemHelperServiceManagementBackend: HelperServiceManagementBackend {
    private let service: SMAppService

    init(bundle: Bundle = .main) throws {
        try Self.validateMainBundle(bundle)
        service = SMAppService.daemon(plistName: ViftyDaemonConstants.plistName)
    }

    var state: HelperServiceRegistrationState {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            service.unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    static func validateMainBundle(_ bundle: Bundle) throws {
        let bundleURL = bundle.bundleURL.standardizedFileURL
        guard bundleURL.pathExtension == "app" else {
            throw HelperServiceManagementBridgeError.invalidMainBundle("Bundle.main is not an app bundle")
        }
        guard bundle.bundleIdentifier == "tech.reidar.vifty" else {
            throw HelperServiceManagementBridgeError.invalidMainBundle("unexpected bundle identifier")
        }
        guard bundle.executableURL?.lastPathComponent == "Vifty" else {
            throw HelperServiceManagementBridgeError.invalidMainBundle("the caller is not the Vifty main executable")
        }
        let plist = bundleURL.appendingPathComponent(
            "Contents/Library/LaunchDaemons/\(ViftyDaemonConstants.plistName)",
            isDirectory: false
        )
        var metadata = stat()
        guard lstat(plist.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG else {
            throw HelperServiceManagementBridgeError.invalidMainBundle("the bundled LaunchDaemon plist is missing or is a symlink")
        }
    }
}

@MainActor
enum HelperServiceManagementBridge {
    static func perform(
        _ request: HelperServiceManagementRequest,
        backend: any HelperServiceManagementBackend,
        maintenanceReportReader: @Sendable (String) throws -> HelperMaintenanceReport,
        maintenanceAuthorizer: @Sendable (
            HelperMaintenanceAuthorizationRequest
        ) async throws -> HelperMaintenanceAuthorization,
        privilegedExecutionReader: @Sendable (
            String
        ) throws -> HelperPrivilegedExecutionEvidence = HelperPrivilegedExecutionEvidenceReader.read,
        now: @Sendable () -> Date = Date.init,
        requestingUserID: uid_t = geteuid(),
        requestingProcessID: pid_t = getppid()
    ) async throws -> HelperServiceManagementReport {
        switch request {
        case .register:
            switch backend.state {
            case .enabled:
                break
            case .notRegistered:
                try backend.register()
            case .requiresApproval:
                return HelperServiceManagementReport(
                    action: .register,
                    state: .requiresApproval,
                    complete: false,
                    operatorActionRequired: true
                )
            case .notFound, .unknown:
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "cannot register from \(backend.state.rawValue)"
                )
            }
            let finalState = backend.state
            return HelperServiceManagementReport(
                action: .register,
                state: finalState,
                complete: finalState == .enabled,
                operatorActionRequired: finalState == .requiresApproval
            )

        case .unregister(let operation, let reportPath):
            let maintenanceReport = try maintenanceReportReader(reportPath)
            guard maintenanceReport.schemaVersion == HelperMaintenanceReport.currentSchemaVersion,
                  maintenanceReport.schemaID == HelperMaintenanceReport.schemaID,
                  maintenanceReport.operation == operation,
                  maintenanceReport.safeToStop,
                  maintenanceReport.quiesced,
                  maintenanceReport.restoreAttempted,
                  maintenanceReport.restoreSucceeded,
                  maintenanceReport.completeExpectedSetConfirmed,
                  maintenanceReport.blockers.isEmpty,
                  !maintenanceReport.tokenConsumed,
                  let token = maintenanceReport.token,
                  token.operation == operation else {
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "maintenance report is missing complete daemon-owned restore proof"
                )
            }
            let authorization = try await maintenanceAuthorizer(
                HelperMaintenanceAuthorizationRequest(operation: operation, token: token)
            )
            guard authorization.authorized,
                  authorization.operation == operation,
                  authorization.tokenID == token.tokenID,
                  authorization.quiesced,
                  authorization.tokenConsumed else {
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "daemon did not authoritatively consume the maintenance token"
                )
            }
            switch backend.state {
            case .notRegistered:
                break
            case .enabled, .requiresApproval:
                try await backend.unregister()
            case .notFound, .unknown:
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "cannot prove unregister from \(backend.state.rawValue)"
                )
            }
            let finalState = backend.state
            guard finalState == .notRegistered else {
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "unregister ended in \(finalState.rawValue)"
                )
            }
            return HelperServiceManagementReport(
                action: .unregister,
                state: finalState,
                complete: true,
                operatorActionRequired: false,
                maintenanceAuthorized: true,
                tokenID: authorization.tokenID
            )

        case .unregisterLegacy(let operation, let rootRecordPath):
            // A protocol-v1 daemon cannot atomically freeze writes and attest a
            // later snapshot. The root lifecycle worker first disables the
            // launchd label, proves it offline, runs the trusted staged
            // Auto-only helper, and removes legacy artifacts. This narrow
            // post-root bridge only finalizes uninstall for the same lifecycle
            // caller process recorded by that root-owned execution.
            let evidence = try privilegedExecutionReader(rootRecordPath)
            guard evidence.authorizesLegacyUnregister(
                operation: operation,
                requestingUserID: requestingUserID,
                requestingProcessID: requestingProcessID,
                now: now()
            ) else {
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "root-owned offline recovery evidence does not authorize legacy unregister"
                )
            }
            switch backend.state {
            case .notRegistered:
                break
            case .enabled, .requiresApproval:
                try await backend.unregister()
            case .notFound, .unknown:
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "cannot prove legacy unregister from \(backend.state.rawValue)"
                )
            }
            let finalState = backend.state
            guard finalState == .notRegistered else {
                throw HelperServiceManagementBridgeError.transitionFailed(
                    "legacy unregister ended in \(finalState.rawValue)"
                )
            }
            return HelperServiceManagementReport(
                action: .unregister,
                state: finalState,
                complete: true,
                operatorActionRequired: false,
                maintenanceAuthorized: false,
                tokenID: nil,
                legacyProtocolGateUsed: true,
                legacyMarkerPresent: false
            )
        }
    }
}
