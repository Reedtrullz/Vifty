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
