import Foundation

enum HelperHealthState: Equatable {
    case checking
    case healthy(fanCount: Int)
    case error
    case runtimeMismatch
    case telemetryOnly
    case unreachable
    case noFanData
    case noControllableFans(fanCount: Int)
    case unsupported

    var needsAttention: Bool {
        switch self {
        case .checking, .healthy:
            false
        case .error, .runtimeMismatch, .telemetryOnly, .unreachable,
             .noFanData, .noControllableFans, .unsupported:
            true
        }
    }

    var repairActionAvailable: Bool {
        switch self {
        case .error, .runtimeMismatch, .telemetryOnly, .unreachable:
            true
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            false
        }
    }

    var notifiesAsHelperFailure: Bool {
        repairActionAvailable
    }

    var summary: String {
        switch self {
        case .checking:
            "Checking fan helper"
        case .healthy(let fanCount):
            "Fan helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
        case .error:
            "Fan helper error · repair needed"
        case .runtimeMismatch:
            "Fan helper build mismatch · repair needed"
        case .telemetryOnly:
            "Read-only fan telemetry · repair daemon for writes"
        case .unreachable:
            "Fan helper not responding · repair or approve"
        case .noFanData:
            "Fan helper reachable · waiting for fan data"
        case .noControllableFans:
            "Fan telemetry available · no controllable fans"
        case .unsupported:
            "Unsupported hardware · fan writes blocked"
        }
    }

    var menuSummary: String {
        switch self {
        case .checking:
            "Checking helper"
        case .healthy(let fanCount):
            "Helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
        case .error:
            "Helper needs repair"
        case .runtimeMismatch:
            "Helper build mismatch"
        case .telemetryOnly:
            "Fan writes blocked"
        case .unreachable:
            "Helper not responding"
        case .noFanData:
            "Waiting for fan data"
        case .noControllableFans:
            "No controllable fans"
        case .unsupported:
            "Unsupported hardware"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .checking, .healthy:
            nil
        case .error:
            "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck."
        case .runtimeMismatch:
            "Use Repair/Reinstall Helper from this Vifty app, approve Login Items if prompted, then rerun diagnose. Fan writes stay blocked until the installed daemon matches this build."
        case .telemetryOnly:
            "Use Repair/Reinstall Helper or approve Login Items if prompted. Fan telemetry is read-only, and manual or agent cooling stays blocked until the daemon responds."
        case .unreachable:
            "Use Repair/Reinstall Helper or approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds."
        case .noFanData:
            "Keep Auto selected and collect read-only diagnostics. Fan writes stay blocked until controllable fans appear."
        case .noControllableFans(let fanCount):
            "The helper can read \(fanCount) fan\(fanCount == 1 ? "" : "s"), but none are marked controllable. Keep fan writes blocked and collect read-only hardware validation evidence before changing support claims."
        case .unsupported:
            "Vifty supports fan control on Apple Silicon MacBook Pro hardware. Keep this machine on read-only diagnostics; do not retry fan writes."
        }
    }

    var menuRecoverySuggestion: String? {
        switch self {
        case .checking, .healthy:
            nil
        case .error, .telemetryOnly, .unreachable:
            "Repair/Reinstall Helper; approve Login Items if prompted."
        case .runtimeMismatch:
            "Repair/Reinstall Helper from this app before fan control."
        case .noFanData:
            "Keep Auto selected and copy diagnose for read-only evidence."
        case .noControllableFans:
            "Keep Auto selected and collect hardware validation evidence."
        case .unsupported:
            "Read-only diagnostics only on this Mac."
        }
    }

    var writePathBlockedSummary: String? {
        switch self {
        case .error, .unreachable:
            "Fan writes blocked until helper responds"
        case .runtimeMismatch:
            "Fan writes blocked until helper matches this app"
        case .telemetryOnly:
            "Read-only fan telemetry; repair helper for fan writes"
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            nil
        }
    }

    var installRuntimeContext: String? {
        switch self {
        case .telemetryOnly:
            "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked."
        case .unreachable:
            "Install status and daemon response are separate; approve or repair before fan writes."
        case .error:
            "The helper may be installed, but the current daemon path still needs repair."
        case .runtimeMismatch:
            "The installed LaunchDaemon does not match this Vifty app; repair the helper before fan writes."
        case .checking, .healthy, .noFanData, .noControllableFans, .unsupported:
            nil
        }
    }
}

struct HelperHealthPresentationInput: Equatable {
    var hardwareIsSupported: Bool?
    var hasCompletedHardwarePoll: Bool
    var daemonReachable: Bool
    var daemonResponding: Bool
    var fanCount: Int
    var hasControllableFan: Bool
    var lastError: String?
}

enum HelperHealthPresentation {
    static func resolve(_ input: HelperHealthPresentationInput) -> HelperHealthState {
        if input.hardwareIsSupported == false {
            return .unsupported
        }
        if !input.hasCompletedHardwarePoll,
           input.hardwareIsSupported == nil,
           !input.daemonReachable {
            return .checking
        }
        if hasRuntimeMismatchError(input.lastError) {
            return .runtimeMismatch
        }
        if input.fanCount > 0 {
            guard input.daemonReachable else {
                return .unreachable
            }
            guard input.daemonResponding else {
                return .telemetryOnly
            }
            if isHelperError(input.lastError) {
                return .error
            }
            guard input.hasControllableFan else {
                return .noControllableFans(fanCount: input.fanCount)
            }
            return .healthy(fanCount: input.fanCount)
        }
        if isHelperError(input.lastError) {
            return .error
        }
        guard input.daemonReachable else {
            return .unreachable
        }
        return .noFanData
    }

    static func hasRuntimeMismatchError(_ error: String?) -> Bool {
        guard let error else { return false }
        let normalized = error.lowercased()
        return normalized.contains("daemonruntimematchesexpected")
            || normalized.contains("daemonruntime")
            || normalized.contains("does not match this vifty build")
            || normalized.contains("daemon differs from the installed app")
            || normalized.contains("helper daemon differs")
            || normalized.contains("installed privileged fan helper does not match")
    }

    private static func isHelperError(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("fan helper") == true
    }
}
