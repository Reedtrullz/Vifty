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

public struct XPCClientValidator: Sendable {
    public let allowedSigningIdentifier: String
    public let allowedTeamIdentifier: String?

    public init(allowedSigningIdentifier: String, allowedTeamIdentifier: String?) {
        self.allowedSigningIdentifier = allowedSigningIdentifier
        self.allowedTeamIdentifier = allowedTeamIdentifier
    }

    public func isAllowed(_ identity: XPCClientIdentity?) -> Bool {
        guard let identity else { return false }
        guard identity.signingIdentifier == allowedSigningIdentifier else { return false }
        if let allowedTeamIdentifier {
            return identity.teamIdentifier == allowedTeamIdentifier
        }
        return true
    }
}
