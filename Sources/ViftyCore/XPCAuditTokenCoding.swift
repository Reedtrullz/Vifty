import Foundation

public enum XPCAuditTokenCoding {
    public static let byteCount = MemoryLayout<audit_token_t>.size
    private static let nsValueObjCType = "{?=[8I]}"

    public static func decode(_ value: Any?) -> audit_token_t? {
        if let data = value as? Data {
            guard data.count == byteCount else {
                return nil
            }

            var token = audit_token_t()
            _ = withUnsafeMutableBytes(of: &token) { tokenBytes in
                data.copyBytes(to: tokenBytes)
            }
            return token
        }

        if let value = value as? NSValue {
            guard String(cString: value.objCType) == nsValueObjCType else {
                return nil
            }

            var token = audit_token_t()
            value.getValue(&token)
            return token
        }

        return nil
    }

    public static func encode(_ token: audit_token_t) -> Data {
        var mutableToken = token
        return Data(bytes: &mutableToken, count: byteCount)
    }
}
