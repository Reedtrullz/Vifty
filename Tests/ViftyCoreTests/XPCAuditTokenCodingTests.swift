import XCTest
@testable import ViftyCore

final class XPCAuditTokenCodingTests: XCTestCase {
    func testEncodeDecodeRoundTripsAuditTokenBytes() {
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { bytes in
            for index in bytes.indices {
                bytes[index] = UInt8(index + 1)
            }
        }

        let data = XPCAuditTokenCoding.encode(token)
        let decoded = XPCAuditTokenCoding.decode(data)

        XCTAssertEqual(data.count, XPCAuditTokenCoding.byteCount)
        XCTAssertEqual(XPCAuditTokenCoding.encode(try XCTUnwrap(decoded)), data)
    }

    func testDecodeRejectsWrongByteCount() {
        XCTAssertNil(XPCAuditTokenCoding.decode(Data(repeating: 0, count: XPCAuditTokenCoding.byteCount - 1)))
        XCTAssertNil(XPCAuditTokenCoding.decode(Data(repeating: 0, count: XPCAuditTokenCoding.byteCount + 1)))
    }

    func testDecodeRejectsNonDataValues() {
        XCTAssertNil(XPCAuditTokenCoding.decode(nil))
        XCTAssertNil(XPCAuditTokenCoding.decode("not audit token data"))
    }
}
