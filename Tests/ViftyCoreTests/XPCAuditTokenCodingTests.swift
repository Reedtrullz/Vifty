import XCTest
@testable import ViftyCore

final class XPCAuditTokenCodingTests: XCTestCase {
    func testEncodeDecodeRoundTripsAuditTokenBytes() {
        let token = Self.sampleToken()

        let data = XPCAuditTokenCoding.encode(token)
        let decoded = XPCAuditTokenCoding.decode(data)

        XCTAssertEqual(data.count, XPCAuditTokenCoding.byteCount)
        XCTAssertEqual(XPCAuditTokenCoding.encode(try XCTUnwrap(decoded)), data)
    }

    func testDecodeAcceptsAuditTokenNSValue() {
        var token = Self.sampleToken()
        let value = NSValue(bytes: &token, objCType: "{?=[8I]}")

        let decoded = XPCAuditTokenCoding.decode(value)

        XCTAssertEqual(XPCAuditTokenCoding.encode(try XCTUnwrap(decoded)), XPCAuditTokenCoding.encode(token))
    }

    func testDecodeRejectsWrongByteCount() {
        XCTAssertNil(XPCAuditTokenCoding.decode(Data(repeating: 0, count: XPCAuditTokenCoding.byteCount - 1)))
        XCTAssertNil(XPCAuditTokenCoding.decode(Data(repeating: 0, count: XPCAuditTokenCoding.byteCount + 1)))
    }

    func testDecodeRejectsUnsupportedValues() {
        XCTAssertNil(XPCAuditTokenCoding.decode(nil))
        XCTAssertNil(XPCAuditTokenCoding.decode("not audit token data"))
        XCTAssertNil(XPCAuditTokenCoding.decode(NSNumber(value: 42)))
    }

    private static func sampleToken() -> audit_token_t {
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index + 1)
            }
        }
        return token
    }
}
