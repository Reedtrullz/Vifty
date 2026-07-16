import XCTest
@testable import ViftyCore

final class SMCClientWritePolicyTests: XCTestCase {
    func testFanControlKeyHelpersAcceptOnlySingleDigitFanIDs() {
        for fanID in 0...9 {
            XCTAssertTrue(SMCFanControlKeys.isValidFanID(fanID), "\(fanID) should be a valid SMC fan ID")
        }

        for fanID in [-1, 10, 42] {
            XCTAssertFalse(SMCFanControlKeys.isValidFanID(fanID), "\(fanID) should not be a valid SMC fan ID")
        }
    }

    func testWritePolicyAllowsOnlyViftyFanControlKeys() {
        for key in ["F0Md", "F1Md", "F0md", "F1md", "F0Tg", "F1Tg", "Ftst"] {
            XCTAssertTrue(SMCClient.isAllowedWriteKey(key), "\(key) should be writable")
        }

        for key in ["F0Ac", "TC0P", "B0AC", "F0Mn", "F0Mx", "F0ID", "F10Tg", "FtstX", ""] {
            XCTAssertFalse(SMCClient.isAllowedWriteKey(key), "\(key) should not be writable")
        }
    }

    func testRejectedSMCWriteErrorExplainsAllowedScope() {
        let description = ViftyError.smcWriteRejected("TC0P").localizedDescription

        XCTAssertTrue(description.contains("TC0P"))
        XCTAssertTrue(description.contains("fan mode"))
        XCTAssertTrue(description.contains("fan target"))
    }

    func testLowLevelWriteLayoutRequiresExactDiscoveredTypeAndSize() throws {
        XCTAssertNoThrow(try SMCClient.validateWriteLayout(
            key: "F0Tg",
            requestedDataType: "fpe2",
            bytes: [0x46, 0x50],
            discoveredDataType: "fpe2",
            discoveredSize: 2
        ))
        XCTAssertThrowsError(try SMCClient.validateWriteLayout(
            key: "F0Tg",
            requestedDataType: "fpe2",
            bytes: [0x46, 0x50],
            discoveredDataType: "flt ",
            discoveredSize: 2
        ))
        XCTAssertThrowsError(try SMCClient.validateWriteLayout(
            key: "F0Tg",
            requestedDataType: "fpe2",
            bytes: [0x46],
            discoveredDataType: "fpe2",
            discoveredSize: 2
        ))
        XCTAssertThrowsError(try SMCClient.validateWriteLayout(
            key: "F0Tg",
            requestedDataType: "fpe2",
            bytes: Array(repeating: 0, count: 33),
            discoveredDataType: "fpe2",
            discoveredSize: 33
        ))
    }

    func testSMCWriteAuthorityIsPackageScopedAndOnlySafetyTargetInvokesIt() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let clientSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/ViftyCore/SMCClient.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(clientSource.contains("package func write("))
        XCTAssertFalse(clientSource.contains("public func write("))

        let sources = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var directCallers: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("smc.write(") {
                directCallers.append(fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: ""))
            }
        }
        XCTAssertEqual(directCallers, ["Sources/ViftyFanControlSafety/LocalFanHelperClient.swift"])
    }

    func testStrictFanControlByteCodecAcceptsOnlyKnownExactLayouts() throws {
        let layouts = [
            (dataType: "ui8 ", size: 1),
            (dataType: "ui16", size: 2),
            (dataType: "flt ", size: 4)
        ]

        for layout in layouts {
            let bytes = try XCTUnwrap(
                SMCDecoding.encodeFanControlByte(
                    3,
                    dataType: layout.dataType,
                    size: layout.size
                )
            )
            XCTAssertEqual(
                SMCDecoding.decodeFanControlByte(
                    SMCValue(key: "F0Md", dataType: layout.dataType, bytes: bytes)
                ),
                3
            )
        }

        XCTAssertNil(SMCDecoding.encodeFanControlByte(1, dataType: "ui8 ", size: 2))
        XCTAssertNil(SMCDecoding.encodeFanControlByte(1, dataType: "fpe2", size: 2))
        XCTAssertNil(
            SMCDecoding.decodeFanControlByte(
                SMCValue(key: "F0Md", dataType: "flt ", bytes: Self.floatBytes(1.5))
            )
        )
    }

    func testStrictFanTargetCodecRejectsOverflowFractionalAndUnknownLayouts() throws {
        for layout in [(dataType: "fpe2", size: 2), (dataType: "flt ", size: 4)] {
            let bytes = try XCTUnwrap(
                SMCDecoding.encodeFanTargetRPM(
                    4_500,
                    dataType: layout.dataType,
                    size: layout.size
                )
            )
            XCTAssertEqual(
                SMCDecoding.decodeFanTargetRPM(
                    SMCValue(key: "F0Tg", dataType: layout.dataType, bytes: bytes)
                ),
                4_500
            )
        }

        XCTAssertNil(SMCDecoding.encodeFanTargetRPM(-1, dataType: "fpe2", size: 2))
        XCTAssertNil(SMCDecoding.encodeFanTargetRPM(16_384, dataType: "fpe2", size: 2))
        XCTAssertNil(SMCDecoding.encodeFanTargetRPM(4_500, dataType: "ui16", size: 2))
        XCTAssertNil(
            SMCDecoding.decodeFanTargetRPM(
                SMCValue(key: "F0Tg", dataType: "fpe2", bytes: [0, 1])
            )
        )
        XCTAssertNil(
            SMCDecoding.decodeFanTargetRPM(
                SMCValue(key: "F0Tg", dataType: "flt ", bytes: Self.floatBytes(4_500.5))
            )
        )
    }

    private static func floatBytes(_ value: Float) -> [UInt8] {
        var value = value
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
