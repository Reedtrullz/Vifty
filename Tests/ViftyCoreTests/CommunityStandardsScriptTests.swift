import Foundation
import XCTest

final class CommunityStandardsScriptTests: XCTestCase {
    func testCheckerAcceptsCurrentCommunitySurface() throws {
        let harness = try CommunityStandardsHarness()

        let result = try harness.runChecker(root: harness.repositoryRoot, json: true)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "passed")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "support-safe-to-request", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "support-agent-evidence-collector", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "support-agent-launchd-evidence", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "support-agent-no-sudo", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "support-agent-privacy-review", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "bug-template-evidence-collector", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "bug-template-helper-hotfix", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "bug-template-no-retag", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "agent-template-evidence-collector", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "agent-template-launchd-evidence", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "agent-template-privacy-review", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "hardware-template-agent-run-smoke", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-template-source-first", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "codeowners-support", in: checks), "passed")
    }

    func testCheckerRejectsMissingSupportFile() throws {
        let harness = try CommunityStandardsHarness()
        try harness.copyCommunitySurface()
        try FileManager.default.removeItem(at: harness.rootURL.appendingPathComponent("SUPPORT.md"))

        let result = try harness.runChecker(root: harness.rootURL, json: true)

        XCTAssertNotEqual(result.exitCode, 0)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "blocked")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "file:SUPPORT.md", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "support-safe-to-request", in: checks), "blocked")
    }

    func testCheckerRejectsUnsafeSupportDrift() throws {
        let harness = try CommunityStandardsHarness()
        try harness.copyCommunitySurface()
        let supportURL = harness.rootURL.appendingPathComponent("SUPPORT.md")
        let support = try String(contentsOf: supportURL, encoding: .utf8)
            .replacingOccurrences(of: "safeToRequestCooling: false", with: "safeToRequestCooling can be ignored")
        try support.write(to: supportURL, atomically: true, encoding: .utf8)

        let result = try harness.runChecker(root: harness.rootURL, json: true)

        XCTAssertEqual(result.exitCode, 1)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "blocked")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "support-safe-to-request", in: checks), "blocked")
    }

    func testCheckerRejectsMissingDaemonControlPathSupportGate() throws {
        let harness = try CommunityStandardsHarness()
        try harness.copyCommunitySurface()
        let supportURL = harness.rootURL.appendingPathComponent("SUPPORT.md")
        let support = try String(contentsOf: supportURL, encoding: .utf8)
            .replacingOccurrences(of: " or `daemonControlPathReady: false`", with: "")
        try support.write(to: supportURL, atomically: true, encoding: .utf8)

        let result = try harness.runChecker(root: harness.rootURL, json: true)

        XCTAssertEqual(result.exitCode, 1)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "blocked")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "support-daemon-control-path", in: checks), "blocked")
    }

    func testCheckerRejectsGenericBugTemplateWithoutHelperEvidenceCollector() throws {
        let harness = try CommunityStandardsHarness()
        try harness.copyCommunitySurface()
        let templateURL = harness.rootURL.appendingPathComponent(".github/ISSUE_TEMPLATE/bug-report.yml")
        let template = try String(contentsOf: templateURL, encoding: .utf8)
            .replacingOccurrences(of: "scripts/collect-agent-cooling-evidence.sh", with: "manual diagnostics")
        try template.write(to: templateURL, atomically: true, encoding: .utf8)

        let result = try harness.runChecker(root: harness.rootURL, json: true)

        XCTAssertEqual(result.exitCode, 1)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "blocked")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "bug-template-evidence-collector", in: checks), "blocked")
    }

    private func checkStatus(named name: String, in checks: [[String: Any]]) -> String? {
        checks.first { $0["name"] as? String == name }?["status"] as? String
    }
}

private struct CommunityStandardsProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    func json() throws -> [String: Any] {
        let data = Data(stdout.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class CommunityStandardsHarness {
    let repositoryRoot: URL
    let rootURL: URL

    init() throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-community-standards-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func copyCommunitySurface() throws {
        for relativePath in Self.requiredPaths {
            let source = repositoryRoot.appendingPathComponent(relativePath)
            let destination = rootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func runChecker(root: URL, json: Bool) throws -> CommunityStandardsProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/check-community-standards.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [
            script.path,
            "--root",
            root.path
        ] + (json ? ["--json"] : [])

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return CommunityStandardsProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private static let requiredPaths = [
        "README.md",
        "LICENSE",
        "CODE_OF_CONDUCT.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "SUPPORT.md",
        ".github/CODEOWNERS",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/ISSUE_TEMPLATE/config.yml",
        ".github/ISSUE_TEMPLATE/bug-report.yml",
        ".github/ISSUE_TEMPLATE/feature-request.yml",
        ".github/ISSUE_TEMPLATE/agent-cooling.yml",
        ".github/ISSUE_TEMPLATE/hardware-validation.yml",
        ".github/ISSUE_TEMPLATE/release-trust.yml"
    ]
}
