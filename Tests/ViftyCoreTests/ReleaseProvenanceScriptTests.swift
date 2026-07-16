import Foundation
import XCTest

final class ReleaseProvenanceScriptTests: XCTestCase {
    func testCheckerRejectsPullRequestCIForExactCandidateCommit() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([
            [
                "databaseId": 12345,
                "headBranch": "feature/release-candidate",
                "headSha": fixture.commitSHA,
                "status": "completed",
                "conclusion": "success",
                "event": "pull_request",
                "url": "https://example.invalid/actions/runs/12345"
            ]
        ])

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("no successful completed push CI run on main for exact commit"),
            result.stderr
        )
    }

    func testCheckerAcceptsOnlySuccessfulMainPushCIForExactCandidateCommit() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([
            [
                "databaseId": 12345,
                "headBranch": "feature/release-candidate",
                "headSha": fixture.commitSHA,
                "status": "completed",
                "conclusion": "success",
                "event": "pull_request",
                "url": "https://example.invalid/actions/runs/12345"
            ],
            [
                "databaseId": 67890,
                "headBranch": "main",
                "headSha": fixture.commitSHA,
                "status": "completed",
                "conclusion": "success",
                "event": "push",
                "url": "https://example.invalid/actions/runs/67890"
            ]
        ])

        let result = try fixture.runChecker(json: true)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try result.json()
        XCTAssertEqual(summary["sourceCIRunID"] as? Int, 67890)
        XCTAssertEqual(summary["sourceCIHeadBranch"] as? String, "main")
        XCTAssertEqual(summary["sourceCIEvent"] as? String, "push")
        XCTAssertEqual(summary["checkoutCommitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(summary["signatureVerified"] as? Bool, false)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
    }

    func testCheckerRejectsCheckoutThatDoesNotMatchSignedTagCommit() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.advanceHeadAfterTag()
        try fixture.writeCIRuns([
            [
                "databaseId": 67890,
                "headBranch": "main",
                "headSha": fixture.commitSHA,
                "status": "completed",
                "conclusion": "success",
                "event": "push",
                "url": "https://example.invalid/actions/runs/67890"
            ]
        ])

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("does not match v1.3.3 commit"), result.stderr)
    }

    func testCheckerCanRemainAtExplicitTrustedWorkflowRef() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.advanceHeadAfterTag()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])

        let result = try fixture.runChecker(json: true, trustedWorkflowRef: "main")

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try result.json()
        XCTAssertNotEqual(summary["checkoutCommitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(summary["tagCommitSHA"] as? String, fixture.commitSHA)
    }
}

private struct ReleaseProvenanceProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    func json() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any])
    }
}

private final class ReleaseProvenanceFixture {
    let rootURL: URL
    let commitSHA: String

    private let ciRunsURL: URL
    private let remoteRefsURL: URL

    init() throws {
        let repositoryRoot = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-provenance-\(UUID().uuidString)", isDirectory: true)
        ciRunsURL = rootURL.appendingPathComponent("ci-runs.json")
        remoteRefsURL = rootURL.appendingPathComponent("remote-refs.json")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for relativePath in [
            "scripts/check-release-provenance.sh",
            "scripts/check-release-manifest.sh",
            ".github/release-manifest.json",
            ".github/release-signers.allowed",
            "docs/schemas/release-manifest.schema.json",
            "Resources/Info.plist",
            "Resources/tech.reidar.vifty.daemon.plist",
            "Casks/vifty.rb",
            "Package.swift"
        ] {
            let destination = rootURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(
                at: repositoryRoot.appendingPathComponent(relativePath),
                to: destination
            )
        }

        try Self.writeCandidateManifest(at: rootURL.appendingPathComponent(".github/release-manifest.json"))
        try Self.runRequired(
            executable: "/usr/libexec/PlistBuddy",
            arguments: ["-c", "Set :CFBundleShortVersionString 1.3.3", rootURL.appendingPathComponent("Resources/Info.plist").path],
            currentDirectory: rootURL
        )
        try Self.runRequired(
            executable: "/usr/libexec/PlistBuddy",
            arguments: ["-c", "Set :CFBundleVersion 8", rootURL.appendingPathComponent("Resources/Info.plist").path],
            currentDirectory: rootURL
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: rootURL.appendingPathComponent("scripts/check-release-manifest.sh").path
        )

        try Self.runRequired(executable: "/usr/bin/git", arguments: ["init"], currentDirectory: rootURL)
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["checkout", "-b", "main"], currentDirectory: rootURL)
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["config", "user.name", "Vifty Test"], currentDirectory: rootURL)
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["config", "user.email", "vifty-test@example.invalid"], currentDirectory: rootURL)
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["add", "."], currentDirectory: rootURL)
        try Self.runRequired(
            executable: "/usr/bin/git",
            arguments: ["-c", "commit.gpgsign=false", "commit", "-m", "candidate"],
            currentDirectory: rootURL
        )
        try Self.runRequired(
            executable: "/usr/bin/git",
            arguments: ["-c", "tag.gpgSign=false", "tag", "-a", "v1.3.3", "-m", "candidate"],
            currentDirectory: rootURL
        )

        commitSHA = try Self.capture(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "v1.3.3^{commit}"],
            currentDirectory: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let tagObjectSHA = try Self.capture(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "v1.3.3^{tag}"],
            currentDirectory: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.writeJSON(
            ["tagObjectSHA": tagObjectSHA, "tagCommitSHA": commitSHA],
            to: remoteRefsURL
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeCIRuns(_ runs: [[String: Any]]) throws {
        try Self.writeJSON(runs, to: ciRunsURL)
    }

    func advanceHeadAfterTag() throws {
        try "post-tag\n".write(
            to: rootURL.appendingPathComponent("post-tag.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["add", "post-tag.txt"], currentDirectory: rootURL)
        try Self.runRequired(
            executable: "/usr/bin/git",
            arguments: ["-c", "commit.gpgsign=false", "commit", "-m", "post-tag"],
            currentDirectory: rootURL
        )
    }

    func runChecker(
        json: Bool = false,
        trustedWorkflowRef: String? = nil
    ) throws -> ReleaseProvenanceProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = rootURL
        process.arguments = [
            rootURL.appendingPathComponent("scripts/check-release-provenance.sh").path,
            "--tag", "v1.3.3",
            "--main-ref", "main",
            "--ci-runs-file", ciRunsURL.path,
            "--remote-refs-file", remoteRefsURL.path,
            "--skip-signature-for-fixture"
        ]
            + (trustedWorkflowRef.map { ["--trusted-workflow-ref", $0] } ?? [])
            + (json ? ["--json"] : [])
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_PROVENANCE_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ReleaseProvenanceProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private static func writeCandidateManifest(at url: URL) throws {
        let data = try Data(contentsOf: url)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        manifest["candidate"] = [
            "version": "1.3.3",
            "build": 8,
            "tag": "v1.3.3",
            "artifact": "Vifty-v1.3.3.zip",
            "checksumAsset": "Vifty-v1.3.3.zip.sha256",
            "artifactSummary": "Vifty-v1.3.3-artifact-summary.json",
            "releaseChecklist": "Vifty-v1.3.3-release-checklist.md",
            "sha256": NSNull(),
            "artifactTrust": "pending",
            "signingTrust": "pending",
            "tagTrust": "signed-required",
            "installedReleaseReview": "pending",
            "manualCompatibility": "pending",
            "manualCompatibilityScope": NSNull()
        ]
        try writeJSON(manifest, to: url)
    }

    private static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private static func runRequired(
        executable: String,
        arguments: [String],
        currentDirectory: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, errorText)
    }

    private static func capture(
        executable: String,
        arguments: [String],
        currentDirectory: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, errorText)
        return String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
