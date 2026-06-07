import Foundation
import Security
import ViftyCore

struct XPCConnectionIdentityExtractor {
    func identity(for connection: NSXPCConnection) -> XPCClientIdentity? {
        // auditToken is available at runtime on macOS 13+ but not exposed as a
        // public Swift property in all SDK versions. Use key-value access and
        // bridge the Data bytes to an audit_token_t.
        guard let tokenData = connection.value(forKey: "auditToken") as? Data,
              tokenData.count == MemoryLayout<audit_token_t>.size else {
            return nil
        }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { tokenData.copyBytes(to: $0) }
        return identity(forAuditToken: token)
    }

    private func identity(forAuditToken auditToken: audit_token_t) -> XPCClientIdentity? {
        var token = auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary

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
