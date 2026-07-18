import Foundation
import ViftyCore

enum ConfirmedFanControlOwner: Equatable, Sendable {
    case macOS
    case viftyManual
    case agent
    case recovery
    case mixedOrUnknown
}

struct FanControlOwnershipPresentation: Equatable, Sendable {
    let owner: ConfirmedFanControlOwner
    let ownerText: String
    let canRequestRestoreAuto: Bool

    var conciseOwnerText: String {
        switch owner {
        case .macOS:
            "Mac"
        case .viftyManual:
            "Me"
        case .agent:
            "Agent"
        case .recovery:
            "Recovery?"
        case .mixedOrUnknown:
            "Owner?"
        }
    }

    static func resolve(
        _ status: FanControlOwnershipStatus?
    ) -> FanControlOwnershipPresentation {
        guard let status,
              status.protocolVersion >= FanControlProtocolVersion.current else {
            return unknown
        }

        if status.recoveryPending
            || status.phase == .restoring
            || status.phase == .restorePending
            || status.owner == .recovery {
            return FanControlOwnershipPresentation(
                owner: .recovery,
                ownerText: "Owner: Recovery pending",
                canRequestRestoreAuto: true
            )
        }

        if status.phase == .active,
           status.transactionID?.isEmpty == false,
           !status.expectedFanIDs.isEmpty {
            switch status.owner {
            case .manual:
                return FanControlOwnershipPresentation(
                    owner: .viftyManual,
                    ownerText: "Owner: Vifty manual control",
                    canRequestRestoreAuto: true
                )
            case .agent:
                return FanControlOwnershipPresentation(
                    owner: .agent,
                    ownerText: "Owner: Agent cooling",
                    canRequestRestoreAuto: true
                )
            case .recovery, .none:
                return unknown
            }
        }

        if status.owner == nil,
           status.phase == nil,
           status.transactionID == nil,
           status.expectedFanIDs.isEmpty,
           !status.recoveryPending {
            return FanControlOwnershipPresentation(
                owner: .macOS,
                ownerText: "Owner: macOS",
                canRequestRestoreAuto: false
            )
        }

        return unknown
    }

    private static let unknown = FanControlOwnershipPresentation(
        owner: .mixedOrUnknown,
        ownerText: "Owner: Confirmation required",
        canRequestRestoreAuto: false
    )
}
