import Foundation

public struct XPCClientIdentity: Equatable, Sendable {
    public let signingIdentifier: String?
    public let teamIdentifier: String?
    public let isPlatformBinary: Bool

    public init(signingIdentifier: String?, teamIdentifier: String?, isPlatformBinary: Bool = false) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.isPlatformBinary = isPlatformBinary
    }
}

public struct XPCAllowedClient: Equatable, Sendable {
    public let signingIdentifier: String
    public let teamIdentifier: String?

    public init(signingIdentifier: String, teamIdentifier: String?) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public struct XPCClientValidator: Sendable {
    public let allowedClients: [XPCAllowedClient]

    public var allowedSigningIdentifier: String { allowedClients.first?.signingIdentifier ?? "" }
    public var allowedTeamIdentifier: String? { allowedClients.first?.teamIdentifier }

    public init(allowedClients: [XPCAllowedClient]) {
        self.allowedClients = allowedClients
    }

    public init(allowedSigningIdentifier: String, allowedTeamIdentifier: String?) {
        self.init(allowedClients: [
            XPCAllowedClient(
                signingIdentifier: allowedSigningIdentifier,
                teamIdentifier: allowedTeamIdentifier
            )
        ])
    }

    public func isAllowed(_ identity: XPCClientIdentity?) -> Bool {
        guard let identity, let signingIdentifier = identity.signingIdentifier else { return false }

        return allowedClients.contains { allowedClient in
            guard signingIdentifier == allowedClient.signingIdentifier else { return false }
            if let allowedTeamIdentifier = allowedClient.teamIdentifier {
                return identity.teamIdentifier == allowedTeamIdentifier
            }
            return true // nil team requirement → skip team check entirely
        }
    }
}

public enum XPCTrustConfiguration {
    public static let appSigningIdentifier = "tech.reidar.vifty"
    public static let ctlSigningIdentifier = "tech.reidar.vifty.ctl"
    public static let teamEnvironmentKey = "VIFTY_XPC_ALLOWED_TEAM_ID"

    public static func releaseTeamIdentifier(from environment: [String: String]) -> String? {
        guard let rawValue = environment[teamEnvironmentKey] else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func allowedClients(releaseTeamIdentifier: String?) -> [XPCAllowedClient] {
        [
            XPCAllowedClient(signingIdentifier: appSigningIdentifier, teamIdentifier: releaseTeamIdentifier),
            XPCAllowedClient(signingIdentifier: ctlSigningIdentifier, teamIdentifier: releaseTeamIdentifier)
        ]
    }
}
