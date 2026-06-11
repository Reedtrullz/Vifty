import Foundation
import XCTest

final class GuardedRunScriptTests: XCTestCase {
    func testGuardedRunDelegatesToJSONViftyCtlRunWhenReady() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "run",
                "--json",
                "--workload", "test",
                "--duration", "20m",
                "--max-rpm-percent", "70",
                "--force",
                "--reason", "swift test",
                "--",
                "swift", "test"
            ]
        )
    }

    func testGuardedRunWarnsAndDelegatesWhenDegraded() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            recommendedAction: "requestCoolingWithCaution",
            safeToRequestCooling: true
        )

        let result = try harness.runGuardedRun([
            "build", "15m", "60", "cautious build", "--", "swift", "build"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("recommends caution"))
        let loggedArguments = try harness.loggedArguments()
        XCTAssertTrue(loggedArguments.contains("run"))
        XCTAssertTrue(loggedArguments.contains("--json"))
    }

    func testGuardedRunBlocksBeforeRunWhenDiagnoseRecommendsRestoreAutoFirst() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            recommendedAction: "restoreAutoBeforeRequestingCooling",
            safeToRequestCooling: false
        )

        let result = try harness.runGuardedRun([
            "build", "15m", "60", "cautious build", "--", "swift", "build"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("restoring Auto before requesting new cooling"))
        XCTAssertTrue(result.stderr.contains("\"recommendedAgentAction\":\"restoreAutoBeforeRequestingCooling\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunBlocksBeforeRunWhenDiagnoseBlocks() throws {
        let harness = try ScriptHarness(state: "blocked")

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("readiness is blocked"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunTreatsNonzeroBlockedDiagnoseAsReadinessBlock() throws {
        let harness = try ScriptHarness(state: "blocked", diagnoseExitCode: 75, emitReadinessOnDiagnoseFailure: true)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("readiness is blocked"))
        XCTAssertFalse(result.stderr.contains("diagnose failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedWhenAgentDecisionFieldsAreMissing() throws {
        let harness = try ScriptHarness(state: "degraded", includeDecisionFields: false)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("missing agent decision fields"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsClosedAndPreservesDiagnoseJSONWhenDiagnoseFails() throws {
        let harness = try ScriptHarness(state: "ready", diagnoseExitCode: 1)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("diagnose failed"))
        XCTAssertTrue(result.stderr.contains("\"command\":\"diagnose\""))
        XCTAssertTrue(result.stderr.contains("\"safeToProceed\":false"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunFailsWhenViftyCtlIsMissing() throws {
        let harness = try ScriptHarness(state: "ready", createFakeViftyCtl: false)

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertTrue(result.stderr.contains("viftyctl is not executable"))
    }
}

private struct ProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class ScriptHarness {
    let rootURL: URL
    let fakeViftyCtlURL: URL
    let logURL: URL

    init(
        state: String,
        recommendedAction: String? = nil,
        safeToRequestCooling: Bool? = nil,
        diagnoseExitCode: Int = 0,
        emitReadinessOnDiagnoseFailure: Bool = false,
        includeDecisionFields: Bool = true,
        createFakeViftyCtl: Bool = true
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-guarded-run-\(UUID().uuidString)", isDirectory: true)
        fakeViftyCtlURL = rootURL.appendingPathComponent("viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl-args.log")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if createFakeViftyCtl {
            try writeFakeViftyCtl(
                state: state,
                recommendedAction: recommendedAction ?? Self.defaultRecommendedAction(for: state),
                safeToRequestCooling: safeToRequestCooling ?? Self.defaultSafeToRequestCooling(for: state),
                diagnoseExitCode: diagnoseExitCode,
                emitReadinessOnDiagnoseFailure: emitReadinessOnDiagnoseFailure,
                includeDecisionFields: includeDecisionFields
            )
        }
    }

    func runGuardedRun(_ arguments: [String]) throws -> ProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("examples/viftyctl/guarded-run.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["VIFTYCTL"] = fakeViftyCtlURL.path
        environment["FAKE_VIFTYCTL_LOG"] = logURL.path
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func loggedArguments() throws -> [String] {
        let data = try Data(contentsOf: logURL)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeFakeViftyCtl(
        state: String,
        recommendedAction: String,
        safeToRequestCooling: Bool,
        diagnoseExitCode: Int,
        emitReadinessOnDiagnoseFailure: Bool,
        includeDecisionFields: Bool
    ) throws {
        let emitReadinessOnDiagnoseFailureValue = emitReadinessOnDiagnoseFailure ? "1" : "0"
        let decisionFields = includeDecisionFields
            ? #","recommendedAgentAction":"\#(recommendedAction)","safeToRequestCooling":\#(safeToRequestCooling)"#
            : ""
        let script = """
        #!/bin/sh
        set -eu

        if [ "$#" -ge 2 ] && [ "$1" = "diagnose" ] && [ "$2" = "--json" ]; then
          if [ "\(diagnoseExitCode)" -eq 0 ] || [ "\(emitReadinessOnDiagnoseFailureValue)" -eq 1 ]; then
            printf '{"state":"\(state)"\(decisionFields),"checks":[]}\n'
          else
            printf '{"command":"diagnose","safeToProceed":false,"message":"daemon unavailable"}\n'
          fi
          exit \(diagnoseExitCode)
        fi

        if [ "$#" -ge 1 ] && [ "$1" = "run" ]; then
          for arg in "$@"; do
            printf '%s\n' "$arg"
          done > "${FAKE_VIFTYCTL_LOG:?}"
          exit 0
        fi

        echo "unexpected fake viftyctl invocation: $*" >&2
        exit 99
        """

        try script.write(to: fakeViftyCtlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeViftyCtlURL.path
        )
    }

    private static func defaultRecommendedAction(for state: String) -> String {
        switch state {
        case "ready":
            return "requestCooling"
        case "degraded":
            return "requestCoolingWithCaution"
        default:
            return "doNotRequestCooling"
        }
    }

    private static func defaultSafeToRequestCooling(for state: String) -> Bool {
        state == "ready" || state == "degraded"
    }
}
