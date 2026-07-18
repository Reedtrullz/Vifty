import Foundation

public struct XPCClientIdentity: Equatable, Sendable {
    public let signingIdentifier: String?
    public let teamIdentifier: String?
    public let isPlatformBinary: Bool
    public let effectiveUserID: UInt32?
    public let executablePath: String?

    public init(
        signingIdentifier: String?,
        teamIdentifier: String?,
        isPlatformBinary: Bool = false,
        effectiveUserID: UInt32? = nil,
        executablePath: String? = nil
    ) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.isPlatformBinary = isPlatformBinary
        self.effectiveUserID = effectiveUserID
        self.executablePath = executablePath
    }
}

public struct XPCAllowedClient: Equatable, Sendable {
    public let signingIdentifier: String
    public let teamIdentifier: String?
    public let effectiveUserID: UInt32?
    public let executablePath: String?

    public init(
        signingIdentifier: String,
        teamIdentifier: String?,
        effectiveUserID: UInt32? = nil,
        executablePath: String? = nil
    ) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.effectiveUserID = effectiveUserID
        self.executablePath = executablePath
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

            // Teamless/ad-hoc code identities can be minted locally. They are
            // accepted only through an explicit development allowlist bound to
            // both the audit-token EUID and the exact executable path.
            guard identity.teamIdentifier == nil,
                  let allowedUserID = allowedClient.effectiveUserID,
                  let allowedExecutablePath = allowedClient.executablePath,
                  identity.effectiveUserID == allowedUserID,
                  let executablePath = identity.executablePath else {
                return false
            }
            return Self.canonicalPath(executablePath) == Self.canonicalPath(allowedExecutablePath)
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}

public enum XPCTrustConfiguration {
    public static let appSigningIdentifier = "tech.reidar.vifty"
    public static let ctlSigningIdentifier = "tech.reidar.vifty.ctl"
    public static let teamEnvironmentKey = "VIFTY_XPC_ALLOWED_TEAM_ID"
    public static let developmentEnableEnvironmentKey = "VIFTY_XPC_ADHOC_DEVELOPMENT"
    public static let developmentUIDEnvironmentKey = "VIFTY_XPC_ADHOC_ALLOWED_UID"
    public static let developmentAppPathEnvironmentKey = "VIFTY_XPC_ADHOC_APP_PATH"
    public static let developmentCtlPathEnvironmentKey = "VIFTY_XPC_ADHOC_CTL_PATH"
    private static let unsupportedDevelopmentHelperPathEnvironmentKey = "VIFTY_XPC_ADHOC_HELPER_PATH"

    public static func releaseTeamIdentifier(from environment: [String: String]) -> String? {
        guard let rawValue = environment[teamEnvironmentKey] else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func allowedClients(releaseTeamIdentifier: String?) -> [XPCAllowedClient] {
        guard let releaseTeamIdentifier else { return [] }
        return [
            XPCAllowedClient(signingIdentifier: appSigningIdentifier, teamIdentifier: releaseTeamIdentifier),
            XPCAllowedClient(signingIdentifier: ctlSigningIdentifier, teamIdentifier: releaseTeamIdentifier)
        ]
    }

    public static func allowedClients(from environment: [String: String]) -> [XPCAllowedClient] {
        if let releaseTeamIdentifier = releaseTeamIdentifier(from: environment) {
            let developmentKeys = [
                developmentEnableEnvironmentKey,
                developmentUIDEnvironmentKey,
                developmentAppPathEnvironmentKey,
                developmentCtlPathEnvironmentKey,
                unsupportedDevelopmentHelperPathEnvironmentKey
            ]
            guard developmentKeys.allSatisfy({ trimmed(environment[$0]) == nil }) else {
                return []
            }
            return allowedClients(releaseTeamIdentifier: releaseTeamIdentifier)
        }

        guard trimmed(environment[developmentEnableEnvironmentKey]) == "1",
              let rawUserID = trimmed(environment[developmentUIDEnvironmentKey]),
              let parsedUserID = UInt32(rawUserID),
              trimmed(environment[unsupportedDevelopmentHelperPathEnvironmentKey]) == nil,
              let appPath = absolutePath(environment[developmentAppPathEnvironmentKey]),
              let ctlPath = absolutePath(environment[developmentCtlPathEnvironmentKey]) else {
            return []
        }

        return [
            XPCAllowedClient(
                signingIdentifier: appSigningIdentifier,
                teamIdentifier: nil,
                effectiveUserID: parsedUserID,
                executablePath: appPath
            ),
            XPCAllowedClient(
                signingIdentifier: ctlSigningIdentifier,
                teamIdentifier: nil,
                effectiveUserID: parsedUserID,
                executablePath: ctlPath
            )
        ]
    }

    private static func absolutePath(_ value: String?) -> String? {
        guard let value = trimmed(value), value.hasPrefix("/") else { return nil }
        return value
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
