import XCTest
@testable import ViftyCore

final class ViftyCtlArgumentsTests: XCTestCase {
    func testMissingCommandThrows() {
        assertParseError([], equals: .missingCommand)
    }

    func testUnknownCommandThrows() {
        assertParseError(["frobnicate"], equals: .unknownCommand("frobnicate"))
    }

    func testParsesStatusJSON() throws {
        let command = try ViftyCtlArguments.parse(["status", "--json"])

        XCTAssertEqual(command, .status(json: true))
    }

    func testInvalidWorkloadThrows() {
        assertParseError([
            "prepare",
            "--workload", "compile",
            "--duration", "45m",
            "--max-rpm-percent", "75"
        ], equals: .invalidWorkload)
    }

    func testInvalidDurationThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "0",
            "--max-rpm-percent", "75"
        ], equals: .invalidDuration)
    }

    func testParsesDurationMinutesSuffix() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "5m",
            "--max-rpm-percent", "75"
        ])

        guard case let .prepare(request, _) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertEqual(request.durationSeconds, 300)
    }

    func testParsesDurationHoursSuffix() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "1h",
            "--max-rpm-percent", "75"
        ])

        guard case let .prepare(request, _) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertEqual(request.durationSeconds, 3_600)
    }

    func testOverflowSuffixedDurationThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "999999999999999999m",
            "--max-rpm-percent", "75"
        ], equals: .invalidDuration)
    }

    func testMissingRPMPercentThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m"
        ], equals: .invalidRPMPercent)
    }

    func testInvalidRPMPercentThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "fast"
        ], equals: .invalidRPMPercent)
    }

    func testNegativeRPMPercentThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "-1"
        ], equals: .invalidRPMPercent)
    }

    func testRPMPercentAboveOneHundredThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "101"
        ], equals: .invalidRPMPercent)
    }

    func testParsesPrepareRequest() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "75",
            "--reason", "Release build",
            "--idempotency-key", "key-1",
            "--json"
        ])

        guard case let .prepare(request, json) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertTrue(json)
        XCTAssertEqual(request.workload, .build)
        XCTAssertEqual(request.durationSeconds, 2_700)
        XCTAssertEqual(request.maxRPMPercent, 75)
        XCTAssertEqual(request.reason, "Release build")
        XCTAssertEqual(request.idempotencyKey, "key-1")
    }

    func testPrepareUsesDefaultReasonAndIdempotencyKey() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "1h",
            "--max-rpm-percent", "100"
        ])

        guard case let .prepare(request, json) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertFalse(json)
        XCTAssertEqual(request.reason, "Agent workload")
        XCTAssertFalse(request.idempotencyKey.isEmpty)
    }

    func testFlagCannotBeUsedAsOptionValue() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "1h",
            "--max-rpm-percent", "80",
            "--reason", "--json"
        ])

        guard case let .prepare(request, json) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertTrue(json)
        XCTAssertEqual(request.reason, "Agent workload")
    }

    func testRunWithoutSeparatorThrowsMissingChildCommand() {
        assertParseError([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "swift", "test"
        ], equals: .missingChildCommand)
    }

    func testRunWithEmptyChildArgumentsThrowsMissingChildCommand() {
        assertParseError([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--"
        ], equals: .missingChildCommand)
    }

    func testParsesRunCommandAndChildArguments() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--reason", "swift test",
            "--",
            "swift", "test", "--json", "--filter", "ViftyCtlArgumentsTests"
        ])

        guard case let .run(request, childArguments) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertEqual(request.workload, .test)
        XCTAssertEqual(request.durationSeconds, 600)
        XCTAssertEqual(request.maxRPMPercent, 70)
        XCTAssertEqual(request.reason, "swift test")
        XCTAssertEqual(childArguments, ["swift", "test", "--json", "--filter", "ViftyCtlArgumentsTests"])
    }

    private func assertParseError(
        _ arguments: [String],
        equals expectedError: ViftyCtlParseError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try ViftyCtlArguments.parse(arguments), file: file, line: line) { error in
            XCTAssertEqual(error as? ViftyCtlParseError, expectedError, file: file, line: line)
        }
    }
}
