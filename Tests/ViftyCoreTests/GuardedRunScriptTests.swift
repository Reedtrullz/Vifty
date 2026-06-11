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
                "--reason", "swift test",
                "--",
                "swift", "test"
            ]
        )
    }

    func testGuardedRunForceRetryIsOptIn() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "1"
        )

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

    func testGuardedRunRejectsInvalidForceRetryEnvironmentBeforeDiagnose() throws {
        let harness = try ScriptHarness(state: "ready")

        let result = try harness.runGuardedRun(
            ["test", "20m", "70", "swift test", "--", "swift", "test"],
            forceRetry: "maybe"
        )

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("VIFTY_GUARDED_RUN_FORCE_RETRY"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
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

    func testGuardedRunTreatsNullAgentDecisionFieldsAsMissing() throws {
        let harness = try ScriptHarness(
            state: "degraded",
            decisionFieldsOverride: #","recommendedAgentAction":null,"safeToRequestCooling":null"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("missing agent decision fields"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
    }

    func testGuardedRunTreatsNullStateAsDiagnoseFailureWhenDiagnoseFails() throws {
        let harness = try ScriptHarness(
            state: "ready",
            diagnoseExitCode: 1,
            commandErrorOverride: #"{"state":null,"command":"diagnose","safeToProceed":false,"message":"daemon unavailable"}"#
        )

        let result = try harness.runGuardedRun([
            "test", "20m", "70", "swift test", "--", "swift", "test"
        ])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(result.stderr.contains("diagnose failed"), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"command\":\"diagnose\""), result.stderr)
        XCTAssertTrue(result.stderr.contains("\"safeToProceed\":false"), result.stderr)
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

    func testWorkloadExampleScriptsDelegateThroughGuardedRun() throws {
        let cases: [(script: String, arguments: [String], expected: [String])] = [
            (
                "examples/viftyctl/swift-test.sh",
                ["--filter", "AgentTests"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "swift test", "--", "swift", "test", "--filter", "AgentTests"]
            ),
            (
                "examples/viftyctl/swift-release-build.sh",
                ["--product", "Vifty"],
                ["run", "--json", "--workload", "build", "--duration", "25m", "--max-rpm-percent", "75", "--reason", "swift release build", "--", "swift", "build", "-c", "release", "--product", "Vifty"]
            ),
            (
                "examples/viftyctl/xcode-test.sh",
                ["-scheme", "MyApp", "-destination", "platform=macOS"],
                ["run", "--json", "--workload", "test", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "xcodebuild test", "--", "xcodebuild", "test", "-scheme", "MyApp", "-destination", "platform=macOS"]
            ),
            (
                "examples/viftyctl/npm-test.sh",
                ["--", "--watch=false"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "npm test", "--", "npm", "test", "--", "--watch=false"]
            ),
            (
                "examples/viftyctl/cargo-test.sh",
                ["--locked"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "cargo test", "--", "cargo", "test", "--locked"]
            ),
            (
                "examples/viftyctl/pytest.sh",
                ["Tests"],
                ["run", "--json", "--workload", "test", "--duration", "20m", "--max-rpm-percent", "70", "--reason", "pytest", "--", "python3", "-m", "pytest", "Tests"]
            ),
            (
                "examples/viftyctl/local-model.sh",
                ["--", "./run-local-model.sh", "--prompt", "smoke"],
                ["run", "--json", "--workload", "localModel", "--duration", "30m", "--max-rpm-percent", "75", "--reason", "local model run", "--", "./run-local-model.sh", "--prompt", "smoke"]
            ),
            (
                "examples/viftyctl/custom-workload.sh",
                ["15m", "65", "project smoke test", "--", "./scripts/smoke-test.sh"],
                ["run", "--json", "--workload", "custom", "--duration", "15m", "--max-rpm-percent", "65", "--reason", "project smoke test", "--", "./scripts/smoke-test.sh"]
            )
        ]

        for testCase in cases {
            let harness = try ScriptHarness(state: "ready")

            let result = try harness.runScript(testCase.script, arguments: testCase.arguments)

            XCTAssertEqual(result.exitCode, 0, testCase.script)
            XCTAssertEqual(try harness.loggedArguments(), testCase.expected, testCase.script)
        }
    }

    func testWorkloadExampleScriptsStayOnGuardedRunPath() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("examples/viftyctl")
        let scripts = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sh" }

        XCTAssertGreaterThanOrEqual(scripts.count, 9)

        for script in scripts {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path), script.lastPathComponent)
            let contents = try String(contentsOf: script, encoding: .utf8)
            XCTAssertFalse(contents.contains("ViftyHelper setFixed"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("ViftyHelper auto"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("sudo"), script.lastPathComponent)
            XCTAssertFalse(contents.contains("smc"), script.lastPathComponent)
            if script.lastPathComponent != "guarded-run.sh" {
                XCTAssertTrue(contents.contains("guarded-run.sh"), script.lastPathComponent)
            }
        }
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
        decisionFieldsOverride: String? = nil,
        commandErrorOverride: String? = nil,
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
                includeDecisionFields: includeDecisionFields,
                decisionFieldsOverride: decisionFieldsOverride,
                commandErrorOverride: commandErrorOverride
            )
        }
    }

    func runGuardedRun(_ arguments: [String], forceRetry: String? = nil) throws -> ProcessResult {
        try runScript("examples/viftyctl/guarded-run.sh", arguments: arguments, forceRetry: forceRetry)
    }

    func runScript(_ relativePath: String, arguments: [String], forceRetry: String? = nil) throws -> ProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["VIFTYCTL"] = fakeViftyCtlURL.path
        environment["FAKE_VIFTYCTL_LOG"] = logURL.path
        if let forceRetry {
            environment["VIFTY_GUARDED_RUN_FORCE_RETRY"] = forceRetry
        }
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
        includeDecisionFields: Bool,
        decisionFieldsOverride: String?,
        commandErrorOverride: String?
    ) throws {
        let emitReadinessOnDiagnoseFailureValue = emitReadinessOnDiagnoseFailure ? "1" : "0"
        let decisionFields = decisionFieldsOverride ?? (includeDecisionFields
            ? #","recommendedAgentAction":"\#(recommendedAction)","safeToRequestCooling":\#(safeToRequestCooling)"#
            : "")
        let commandError = commandErrorOverride ?? #"{"command":"diagnose","safeToProceed":false,"message":"daemon unavailable"}"#
        let script = """
        #!/bin/sh
        set -eu

        if [ "$#" -ge 2 ] && [ "$1" = "diagnose" ] && [ "$2" = "--json" ]; then
          if [ "\(diagnoseExitCode)" -eq 0 ] || [ "\(emitReadinessOnDiagnoseFailureValue)" -eq 1 ]; then
            printf '{"state":"\(state)"\(decisionFields),"checks":[]}\n'
          else
            printf '\(commandError)\n'
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
