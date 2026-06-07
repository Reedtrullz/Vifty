import XCTest
@testable import ViftyCore

final class ViftyCtlArgumentsTests: XCTestCase {
    func testParsesStatusJSON() throws {
        let command = try ViftyCtlArguments.parse(["status", "--json"])

        XCTAssertEqual(command, .status(json: true))
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

    func testParsesRunCommandAndChildArguments() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--reason", "swift test",
            "--",
            "swift", "test"
        ])

        guard case let .run(request, childArguments) = command else {
            return XCTFail("Expected run command")
        }

        XCTAssertEqual(request.workload, .test)
        XCTAssertEqual(request.durationSeconds, 600)
        XCTAssertEqual(request.maxRPMPercent, 70)
        XCTAssertEqual(request.reason, "swift test")
        XCTAssertEqual(childArguments, ["swift", "test"])
    }
}
