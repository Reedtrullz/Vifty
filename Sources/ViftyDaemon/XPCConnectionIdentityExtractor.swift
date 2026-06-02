import Foundation
import Security
import ViftyCore

struct XPCConnectionIdentityExtractor {
    func identity(for connection: NSXPCConnection) -> XPCClientIdentity? {
        // The public Foundation API available in this Swift SDK exposes the
        // peer process identifier, not an audit token property. Keep the
        // Security.framework lookup isolated here so listener code still
        // rejects the connection whenever identity extraction fails.
        identity(forProcessIdentifier: connection.processIdentifier)
    }

    private func identity(forProcessIdentifier processIdentifier: pid_t) -> XPCClientIdentity? {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary

        var dynamicCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            return nil
        }

        guard SecCodeCheckValidity(dynamicCode, SecCSFlags(), nil) == errSecSuccess else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let signingInformation = information as? [String: Any] else {
            return nil
        }

        let signingIdentifier = signingInformation[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = signingInformation[kSecCodeInfoTeamIdentifier as String] as? String
        let isPlatformBinary = signingInformation[kSecCodeInfoPlatformIdentifier as String] != nil

        return XPCClientIdentity(
            signingIdentifier: signingIdentifier,
            teamIdentifier: teamIdentifier,
            isPlatformBinary: isPlatformBinary
        )
    }
}
