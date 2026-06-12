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

    func testParsesDiagnoseJSON() throws {
        let command = try ViftyCtlArguments.parse(["diagnose", "--json"])

        XCTAssertEqual(command, .diagnose(json: true))
    }

    func testParsesAuditJSONWithLimit() throws {
        let command = try ViftyCtlArguments.parse(["audit", "--limit", "7", "--json"])

        XCTAssertEqual(command, .audit(limit: 7, json: true))
    }

    func testAuditUsesDefaultLimit() throws {
        let command = try ViftyCtlArguments.parse(["audit"])

        XCTAssertEqual(command, .audit(limit: ViftyCtlArguments.defaultAuditLimit, json: false))
    }

    func testInvalidAuditLimitThrows() {
        assertParseError(["audit", "--limit", "0"], equals: .invalidLimit)
    }

    func testStatusUnknownOptionThrows() {
        assertParseError(["status", "--yaml"], equals: .unknownOption("--yaml"))
    }

    func testPrepareUnknownOptionThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "75",
            "--rpm", "4000"
        ], equals: .unknownOption("--rpm"))
    }

    func testPrepareDuplicateOptionThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--duration", "20m",
            "--max-rpm-percent", "75"
        ], equals: .duplicateOption("--duration"))
    }

    func testPrepareUnexpectedPositionalArgumentThrows() {
        assertParseError([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "75",
            "swift"
        ], equals: .unexpectedArgument("swift"))
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

        guard case let .prepare(request, _, _) = command else {
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

        guard case let .prepare(request, _, _) = command else {
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

        guard case let .prepare(request, json, _) = command else {
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

        guard case let .prepare(request, json, _) = command else {
            return XCTFail("Expected prepare command")
        }

        XCTAssertFalse(json)
        XCTAssertEqual(request.reason, "Agent workload")
        XCTAssertFalse(request.idempotencyKey.isEmpty)
    }

    func testRestoreAutoRejectsIdempotencyKeyBecauseRestoreIsNotScoped() {
        assertParseError([
            "restore-auto",
            "--reason", "done",
            "--idempotency-key", "key-1",
            "--json"
        ], equals: .unknownOption("--idempotency-key"))
    }

    func testFlagCannotBeUsedAsOptionValue() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "1h",
            "--max-rpm-percent", "80",
            "--reason", "--json"
        ])

        guard case let .prepare(request, json, _) = command else {
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

    func testRunDuplicateWrapperOptionThrowsBeforeChildSeparator() {
        assertParseError([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--max-rpm-percent", "90",
            "--",
            "swift", "test"
        ], equals: .duplicateOption("--max-rpm-percent"))
    }

    func testRunAllowsDuplicateChildOptionsAfterSeparator() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--",
            "swift", "test", "--filter", "A", "--filter", "B"
        ])

        guard case let .run(_, childArguments, _, _) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertEqual(childArguments, ["swift", "test", "--filter", "A", "--filter", "B"])
    }

    func testRequestsJSONDetectsPrepareFlagForParseErrors() {
        XCTAssertTrue(ViftyCtlArguments.requestsJSON([
            "prepare",
            "--workload", "invalid",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--json"
        ]))
    }

    func testRequestsJSONDetectsRunWrapperFlagBeforeSeparator() {
        XCTAssertTrue(ViftyCtlArguments.requestsJSON([
            "run",
            "--json",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--",
            "swift", "test"
        ]))
    }

    func testRequestsJSONIgnoresRunChildFlagAfterSeparator() {
        XCTAssertFalse(ViftyCtlArguments.requestsJSON([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--",
            "swift", "test", "--json"
        ]))
    }

    func testParseErrorReportHelpersProduceStableOutput() {
        XCTAssertEqual(ViftyCtlArguments.commandNameHint([]), "unknown")
        XCTAssertEqual(ViftyCtlArguments.commandNameHint(["prepare", "--json"]), "prepare")
        XCTAssertEqual(ViftyCtlArguments.humanReadableParseError(.invalidDuration), "invalid or missing --duration")
        XCTAssertEqual(ViftyCtlArguments.humanReadableParseError(.duplicateOption("--duration")), "duplicate option '--duration'")
        XCTAssertEqual(
            ViftyCtlArguments.humanReadableParseError(.unknownCommand("frobnicate")),
            "unknown command 'frobnicate'"
        )
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

        guard case let .run(request, childArguments, json, _) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertFalse(json)
        XCTAssertEqual(request.workload, .test)
        XCTAssertEqual(request.durationSeconds, 600)
        XCTAssertEqual(request.maxRPMPercent, 70)
        XCTAssertEqual(request.reason, "swift test")
        XCTAssertEqual(childArguments, ["swift", "test", "--json", "--filter", "ViftyCtlArgumentsTests"])
    }

    func testRunUnknownWrapperOptionBeforeSeparatorThrows() {
        assertParseError([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--cooler",
            "--",
            "swift", "test"
        ], equals: .unknownOption("--cooler"))
    }

    func testRunJSONFlagBeforeSeparatorEnablesWrapperJSON() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--json",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--",
            "swift", "test"
        ])

        guard case let .run(_, childArguments, json, force) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertTrue(json)
        XCTAssertFalse(force)
        XCTAssertEqual(childArguments, ["swift", "test"])
    }

    func testRunForceFlagBeforeSeparatorEnablesForce() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--force",
            "--",
            "swift", "test"
        ])

        guard case let .run(_, _, json, force) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertFalse(json)
        XCTAssertTrue(force)
    }

    func testRunChildForceFlagAfterSeparatorDoesNotEnableForce() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--",
            "swift", "test", "--force"
        ])

        guard case let .run(_, childArguments, json, force) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertEqual(childArguments, ["swift", "test", "--force"])
        XCTAssertFalse(json)
        XCTAssertFalse(force)
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
