import Foundation
import ServiceManagement
import ViftyCore

enum DaemonInstallerBackendStatus: Equatable {
    case enabled
    case notRegistered
    case notFound
    case requiresApproval
    case unknown
}

enum HelperActionKind: Equatable {
    case install
    case approve
    case reinstall
    case repair
    case unavailable
}

struct HelperActionPresentation: Equatable {
    let kind: HelperActionKind
    let title: String
    let help: String
    let description: String
    let isAvailable: Bool

    static func resolve(
        backendStatus: DaemonInstallerBackendStatus,
        canInstall: Bool,
        isWorking: Bool,
        unavailableMessage: String
    ) -> HelperActionPresentation {
        if !canInstall && !isWorking {
            return HelperActionPresentation(
                kind: .unavailable,
                title: "Helper Unavailable",
                help: unavailableMessage,
                description: unavailableMessage,
                isAvailable: false
            )
        }

        let actionIsAvailable = canInstall && !isWorking
        switch backendStatus {
        case .notRegistered:
            return HelperActionPresentation(
                kind: .install,
                title: "Install Helper",
                help: "Install the privileged fan helper",
                description: "Registers the bundled root LaunchDaemon with macOS. Fan writes stay blocked until the daemon responds; later repair or replacement requires verified Auto/System ownership.",
                isAvailable: actionIsAvailable
            )
        case .requiresApproval:
            return HelperActionPresentation(
                kind: .approve,
                title: "Approve Helper",
                help: "Open Login Items approval for the fan helper",
                description: "Opens Login Items approval. Approve Vifty's fan helper, then return to Vifty. Fan writes stay blocked until the daemon responds.",
                isAvailable: actionIsAvailable
            )
        case .enabled:
            return HelperActionPresentation(
                kind: .reinstall,
                title: "Reinstall Helper",
                help: "Safely reinstall or repair the privileged fan helper",
                description: "Requires verified Auto/System ownership before any helper teardown or replacement. Fan writes stay blocked until the daemon responds.",
                isAvailable: actionIsAvailable
            )
        case .unknown:
            return HelperActionPresentation(
                kind: .unavailable,
                title: "Helper Status Unknown",
                help: "Wait for a confirmed helper status before repair",
                description: "Vifty cannot safely choose install, approval, or repair until macOS reports a confirmed registration state. Fan writes stay blocked; copy support evidence or restore Auto and reboot.",
                isAvailable: false
            )
        case .notFound:
            return HelperActionPresentation(
                kind: .unavailable,
                title: "Helper Unavailable",
                help: unavailableMessage,
                description: unavailableMessage,
                isAvailable: false
            )
        }
    }
}

enum DaemonInstallerActionResult: Equatable {
    case approvalOpened
    case completed
    case blocked
    case failed
    case unavailable
    case alreadyInProgress

    var shouldRefreshHelperState: Bool {
        self == .approvalOpened || self == .completed
    }
}

@MainActor
protocol DaemonInstallerBackend: AnyObject {
    var status: DaemonInstallerBackendStatus { get }
    var requiresBundledDaemonResources: Bool { get }

    func register() throws
    func openLoginItemsSettings()
}

@MainActor
final class SystemDaemonInstallerBackend: DaemonInstallerBackend {
    private var service: SMAppService {
        SMAppService.daemon(plistName: ViftyDaemonConstants.plistName)
    }

    var status: DaemonInstallerBackendStatus {
        switch service.status {
        case .enabled:
            .enabled
        case .notRegistered:
            .notRegistered
        case .notFound:
            .notFound
        case .requiresApproval:
            .requiresApproval
        @unknown default:
            .unknown
        }
    }

    let requiresBundledDaemonResources = true

    func register() throws {
        try service.register()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class DaemonInstaller: ObservableObject {
    @Published var statusText = "Checking helper"
    @Published var canInstall = true
    @Published private(set) var isWorking = false

    private static let missingBundledPlistMessage = "Vifty is missing its bundled LaunchDaemon plist. Rebuild or reinstall Vifty from source before installing the helper."
    private let backend: any DaemonInstallerBackend
    private let installService: any DaemonInstallServicing
    private let bundleURL: URL
    private let lifecycleScriptURL: URL

    init(
        backend: any DaemonInstallerBackend = SystemDaemonInstallerBackend(),
        installService: any DaemonInstallServicing = DaemonInstallService(),
        bundleURL: URL = Bundle.main.bundleURL,
        lifecycleScriptURL: URL? = nil
    ) {
        self.backend = backend
        self.installService = installService
        self.bundleURL = bundleURL
        self.lifecycleScriptURL = lifecycleScriptURL
            ?? bundleURL.appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")
    }

    var actionPresentation: HelperActionPresentation {
        HelperActionPresentation.resolve(
            backendStatus: backend.status,
            canInstall: canInstall,
            isWorking: isWorking,
            unavailableMessage: unavailableActionMessage
        )
    }

    var actionTitle: String { actionPresentation.title }

    var actionHelp: String { actionPresentation.help }

    var helperStatusSummary: String {
        let status = statusText.lowercased()
        if !canInstall {
            if status.contains("plist not found") || status.contains("missing its bundled launchdaemon plist") {
                return "macOS helper status: bundled plist missing"
            }
            if status.contains("macos 13") {
                return "macOS helper status: unsupported macOS version"
            }
            return "macOS helper status: \(statusText)"
        }
        if status == "checking helper" {
            return "macOS helper status: checking install state"
        }
        if status.contains("approve") {
            return "macOS helper status: waiting for Login Items approval"
        }
        if status.contains("not installed") {
            return "macOS helper status: not installed"
        }
        if status.contains("install failed")
            || status.contains("repair failed")
            || status.contains("cancelled")
            || status.contains("canceled")
            || status.contains("was denied") {
            return "macOS helper status: last install or repair failed"
        }
        if status.contains("enabled") || status.contains("fan helper installed") {
            return "macOS helper status: installed"
        }
        if status.contains("unknown") {
            return "macOS helper status: unknown"
        }
        return "macOS helper status: \(statusText)"
    }

    var actionDescription: String { actionPresentation.description }

    private var unavailableActionMessage: String {
        let status = statusText.lowercased()
        if status.contains("plist not found") || status.contains("missing its bundled launchdaemon plist") {
            return Self.missingBundledPlistMessage
        }
        return statusText
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            switch backend.status {
            case .enabled:
                statusText = "Fan helper enabled"
                canInstall = true
            case .notRegistered:
                statusText = "Fan helper not installed"
                canInstall = true
            case .notFound:
                statusText = "Fan helper plist not found in app bundle"
                canInstall = false
            case .requiresApproval:
                statusText = "Approve fan helper in Login Items"
                canInstall = true
            case .unknown:
                statusText = "Fan helper status unknown"
                canInstall = true
            }
        } else {
            statusText = "macOS 13 or newer is required for bundled daemon install"
            canInstall = false
        }
    }

    @discardableResult
    func installOrOpenApproval() async -> DaemonInstallerActionResult {
        guard #available(macOS 13.0, *) else {
            statusText = "macOS 13 or newer is required for safe helper lifecycle operations"
            canInstall = false
            return .unavailable
        }

        switch backend.status {
        case .requiresApproval:
            backend.openLoginItemsSettings()
            refresh()
            return .approvalOpened
        case .notFound:
            statusText = "Fan helper plist not found in app bundle"
            canInstall = false
            return .unavailable
        case .notRegistered:
            do {
                try backend.register()
                refresh()
                switch backend.status {
                case .enabled:
                    return .completed
                case .requiresApproval:
                    backend.openLoginItemsSettings()
                    return .approvalOpened
                case .notRegistered, .notFound, .unknown:
                    statusText = "Helper registration did not reach an enabled or approval-pending state"
                    return .blocked
                }
            } catch {
                statusText = "Helper registration failed; fan writes stay blocked"
                return .failed
            }
        case .enabled:
            return await runSafeLifecycle()
        case .unknown:
            statusText = "Helper registration state is unknown; restore Auto or reboot before repair"
            return .blocked
        }
    }

    private func runSafeLifecycle() async -> DaemonInstallerActionResult {
        guard !isWorking else { return .alreadyInProgress }
        if backend.requiresBundledDaemonResources {
            guard bundleURL.pathExtension == "app" else {
                statusText = "Could not locate Vifty app bundle"
                return .unavailable
            }
        }

        isWorking = true
        canInstall = false
        statusText = "Checking safe helper maintenance preconditions"
        let result = await installService.perform(
            operation: .repair,
            appBundleURL: bundleURL,
            lifecycleScriptURL: lifecycleScriptURL
        )
        isWorking = false
        canInstall = true
        switch result.outcome {
        case .completed:
            statusText = "Fan helper lifecycle completed; waiting for daemon response"
            return .completed
        case .blocked:
            statusText = result.operatorMessage
            return .blocked
        case .failed:
            statusText = result.operatorMessage
            return .failed
        }
    }
}
