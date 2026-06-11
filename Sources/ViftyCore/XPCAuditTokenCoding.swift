import Foundation

public enum XPCAuditTokenCoding {
    public static let byteCount = MemoryLayout<audit_token_t>.size

    public static func decode(_ value: Any?) -> audit_token_t? {
        guard let data = value as? Data, data.count == byteCount else {
            return nil
        }

        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { tokenBytes in
            data.copyBytes(to: tokenBytes)
        }
        return token
    }

    public static func encode(_ token: audit_token_t) -> Data {
        var mutableToken = token
        return Data(bytes: &mutableToken, count: byteCount)
    }
}
