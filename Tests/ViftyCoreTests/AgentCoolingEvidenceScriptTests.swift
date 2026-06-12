import Foundation
import XCTest

final class AgentCoolingEvidenceScriptTests: XCTestCase {
    func testCollectorCapturesOnlyReadOnlyAgentEvidence() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent cooling evidence written"))
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertFalse(try harness.loggedArguments().contains { invocation in
            ["prepare", "run", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })

        XCTAssertTrue(try harness.read("README.txt").contains("does not request cooling leases"))
        XCTAssertTrue(try harness.read("README.txt").contains("use sudo, or write SMC keys"))
        XCTAssertTrue(try harness.read("README.txt").contains("safeToRequestCooling=false"))
        XCTAssertTrue(try harness.read("README.txt").contains("privacy-review.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("launchctl-print-daemon.txt"))
        XCTAssertTrue(try harness.read("README.txt").contains("Nonzero status rows for these files are evidence"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("readOnly=true"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("coolingCommandsRun=false"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("auditLimit=20"))

        let manifest = try harness.read("manifest.tsv")
        XCTAssertTrue(manifest.contains("name\tstatus\tstdout\tstderr"))
        XCTAssertTrue(manifest.contains("viftyctl-capabilities\t0\tviftyctl-capabilities.json\tviftyctl-capabilities.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-diagnose\t0\tviftyctl-diagnose.json\tviftyctl-diagnose.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-status\t0\tviftyctl-status.json\tviftyctl-status.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-audit\t0\tviftyctl-audit.json\tviftyctl-audit.stderr"))
        XCTAssertTrue(manifest.contains("launchctl-print-daemon\t"))
        XCTAssertTrue(manifest.contains("\tlaunchctl-print-daemon.txt\tlaunchctl-print-daemon.stderr"))
        XCTAssertTrue(manifest.contains("launchdaemon-plist\t"))
        XCTAssertTrue(manifest.contains("\tlaunchdaemon-plist.txt\tlaunchdaemon-plist.stderr"))
        XCTAssertTrue(manifest.contains("helper-file-metadata\t"))
        XCTAssertTrue(manifest.contains("\thelper-file-metadata.txt\thelper-file-metadata.stderr"))
        XCTAssertTrue(manifest.contains("privacy-review\t0\tprivacy-review.tsv\tprivacy-review.stderr"))
        XCTAssertEqual(try harness.read("viftyctl-diagnose.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")
        XCTAssertEqual(try harness.read("privacy-review.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("none\t-\t-\tpassed"))
        XCTAssertFalse(try harness.read("launchctl-print-daemon.status").isEmpty)
        XCTAssertFalse(try harness.read("launchdaemon-plist.status").isEmpty)
        XCTAssertFalse(try harness.read("helper-file-metadata.status").isEmpty)

        XCTAssertTrue(try harness.read("viftyctl-capabilities.json").contains("\"daemonStatusAvailable\":true"))
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"ready\""))
        XCTAssertTrue(try harness.read("viftyctl-audit.json").contains("\"coolingCommandsRun\":false"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["auditLimit"] as? Int, 20)
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 8)
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "viftyctl-audit"
                && command["status"] as? Int == 0
                && command["stdout"] as? String == "viftyctl-audit.json"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "launchctl-print-daemon"
                && command["stdout"] as? String == "launchctl-print-daemon.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "launchdaemon-plist"
                && command["stdout"] as? String == "launchdaemon-plist.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "helper-file-metadata"
                && command["stdout"] as? String == "helper-file-metadata.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "privacy-review"
                && command["status"] as? Int == 0
                && command["stdout"] as? String == "privacy-review.tsv"
        })

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("sha256\tbytes\tfile"))
        XCTAssertTrue(checksums.contains("\tREADME.txt"))
        XCTAssertTrue(checksums.contains("\tmetadata.txt"))
        XCTAssertTrue(checksums.contains("\tmanifest.tsv"))
        XCTAssertTrue(checksums.contains("\tagent-cooling-evidence-summary.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-capabilities.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-diagnose.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-status.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-audit.json"))
        XCTAssertTrue(checksums.contains("\tlaunchctl-print-daemon.txt"))
        XCTAssertTrue(checksums.contains("\tlaunchctl-print-daemon.status"))
        XCTAssertTrue(checksums.contains("\tlaunchdaemon-plist.txt"))
        XCTAssertTrue(checksums.contains("\thelper-file-metadata.txt"))
        XCTAssertTrue(checksums.contains("\tprivacy-review.tsv"))
        XCTAssertTrue(checksums.contains("\tprivacy-review.status"))
        XCTAssertFalse(checksums.contains("\tchecksums.tsv"))
    }

    func testCollectorPreservesBlockedDiagnoseExitAsEvidence() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"blocked","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--audit-limit", "7"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 7 --json"
            ]
        )
        XCTAssertEqual(try harness.read("viftyctl-diagnose.status").trimmingCharacters(in: .whitespacesAndNewlines), "75")
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"blocked\""))
        XCTAssertTrue(try harness.read("README.txt").contains("readiness was blocked"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        XCTAssertEqual(summary["auditLimit"] as? Int, 7)
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "viftyctl-diagnose"
                && command["status"] as? Int == 75
        })
    }

    func testCollectorFlagsLikelyPrivateIdentifiersWithoutRunningCoolingCommands() throws {
        let harness = try AgentCoolingEvidenceHarness(includePrivacyLeak: true)

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("redaction-needed\tviftyctl-status.json"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("serial-number-label"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("user-home-path"))
        XCTAssertTrue(try harness.read("privacy-review.stderr").contains("privacy review found local identifiers"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("privacy-review\t1\tprivacy-review.tsv"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "privacy-review"
                && command["status"] as? Int == 1
                && command["stdout"] as? String == "privacy-review.tsv"
        })
    }

    func testCollectorRejectsUnboundedAuditLimitBeforeCallingViftyCtl() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--audit-limit", "1000"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("--audit-limit must be an integer from 1 through 200"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outputURL.path))
    }
}

private struct AgentCoolingEvidenceProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class AgentCoolingEvidenceHarness {
    let repositoryRoot: URL
    let rootURL: URL
    let outputURL: URL
    let viftyctlURL: URL
    let logURL: URL
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int
    private let includePrivacyLeak: Bool

    init(
        diagnoseJSON: String = #"{"state":"ready","safeToRequestCooling":true,"daemonControlPathReady":true,"recommendedRecoveryAction":"none","checks":[]}"#,
        diagnoseExitCode: Int = 0,
        includePrivacyLeak: Bool = false
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-agent-evidence-\(UUID().uuidString)", isDirectory: true)
        outputURL = rootURL.appendingPathComponent("evidence", isDirectory: true)
        viftyctlURL = rootURL.appendingPathComponent("fake-viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        self.diagnoseJSON = diagnoseJSON
        self.diagnoseExitCode = diagnoseExitCode
        self.includePrivacyLeak = includePrivacyLeak

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try writeFakeViftyCtl()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runCollector(_ arguments: [String]) throws -> AgentCoolingEvidenceProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/collect-agent-cooling-evidence.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_FAKE_DIAGNOSE_JSON": diagnoseJSON,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)"
        ]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return AgentCoolingEvidenceProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: outputURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func readJSON(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: outputURL.appendingPathComponent(relativePath))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func loggedArguments() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return []
        }
        return try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeFakeViftyCtl() throws {
        let script = """
        #!/bin/sh
        set -eu

        printf '%s\\n' "$*" >> "${VIFTY_FAKE_LOG}"

        case "$1" in
          capabilities)
            test "${2:-}" = "--json"
            printf '%s\\n' '{"daemonStatusAvailable":true,"commands":["capabilities","diagnose","status","audit"],"exitCodes":{"unavailable":69}}'
            ;;
          diagnose)
            test "${2:-}" = "--json"
            printf '%s\\n' "${VIFTY_FAKE_DIAGNOSE_JSON}"
            exit "${VIFTY_FAKE_DIAGNOSE_EXIT}"
            ;;
          status)
            test "${2:-}" = "--json"
            if [ "\(includePrivacyLeak ? "1" : "0")" = "1" ]; then
              printf '%s\\n' '{"enabled":true,"activeLease":null,"lastDecision":null,"debug":"Serial Number: C02SECRET1234 /Users/private-user/Vifty.app"}'
            else
              printf '%s\\n' '{"enabled":true,"activeLease":null,"lastDecision":null}'
            fi
            ;;
          audit)
            test "${2:-}" = "--limit"
            test "${4:-}" = "--json"
            printf '{"readOnly":true,"coolingCommandsRun":false,"requestedLimit":%s,"events":[]}' "$3"
            printf '\\n'
            ;;
          *)
            echo "unexpected mutating or unsupported command: $*" >&2
            exit 99
            ;;
        esac
        """
        try script.write(to: viftyctlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: viftyctlURL.path
        )
    }
}
