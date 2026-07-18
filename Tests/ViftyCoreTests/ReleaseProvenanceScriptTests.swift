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

        let copiedEvidenceURL = fixture.rootURL.appendingPathComponent("validated-governance-copy.json")
        let result = try fixture.runChecker(json: true, governanceEvidenceOutput: copiedEvidenceURL)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try result.json()
        XCTAssertEqual(summary["sourceCIRunID"] as? Int, 67890)
        XCTAssertEqual(summary["sourceCIHeadBranch"] as? String, "main")
        XCTAssertEqual(summary["sourceCIEvent"] as? String, "push")
        XCTAssertEqual(summary["checkoutCommitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(summary["signatureVerified"] as? Bool, false)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 3)
        XCTAssertEqual(summary["status"] as? String, "test-fixture")
        XCTAssertEqual(summary["authoritative"] as? Bool, false)
        XCTAssertEqual(summary["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(summary["liveRemoteTagReadback"] as? Bool, false)
        XCTAssertEqual(summary["liveSourceCIReadback"] as? Bool, false)
        let governance = try XCTUnwrap(summary["administratorGovernanceEvidence"] as? [String: Any])
        XCTAssertEqual(governance["evidenceScope"] as? String, "administrator-pretag")
        XCTAssertEqual(governance["expectedMainSHA"] as? String, fixture.commitSHA)
        let validation = try XCTUnwrap(summary["administratorGovernanceValidation"] as? [String: Any])
        XCTAssertEqual(validation["status"] as? String, "passed")
        XCTAssertEqual(validation["releaseCommitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(validation["rulesetID"] as? Int, 18_940_029)
        XCTAssertEqual(try Data(contentsOf: copiedEvidenceURL), try Data(contentsOf: fixture.governanceEvidenceURL))
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
    }

    func testFixtureModeNeverPrintsLiveProvenanceSuccessClaim() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])

        let result = try fixture.runChecker()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release provenance TEST FIXTURE only:"), result.stdout)
        XCTAssertFalse(result.stdout.contains("Release provenance OK:"), result.stdout)
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
        XCTAssertTrue(result.stderr.contains("does not match \(fixture.tag) commit"), result.stderr)
    }

    func testCheckerRejectsTrustedWorkflowRefAfterSignedTagCommit() throws {
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

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must resolve to exact signed tag commit"), result.stderr)
    }

    func testCheckerResolvesRelativeGovernanceOutputFromInvocationDirectory() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])
        let invocationURL = fixture.rootURL.appendingPathComponent("invocation", isDirectory: true)
        try FileManager.default.createDirectory(at: invocationURL, withIntermediateDirectories: true)
        let expectedOutput = invocationURL.appendingPathComponent("validated-governance.json")

        let result = try fixture.runChecker(
            governanceEvidenceOutputArgument: "validated-governance.json",
            currentDirectoryURL: invocationURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(try Data(contentsOf: expectedOutput), try Data(contentsOf: fixture.governanceEvidenceURL))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.rootURL.appendingPathComponent("validated-governance.json").path
            )
        )
    }

    func testEarlyFailureRemovesEarlierGovernanceEvidenceOutput() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])
        let outputURL = fixture.rootURL.appendingPathComponent("stale-governance.json")
        XCTAssertEqual(
            try fixture.runChecker(governanceEvidenceOutput: outputURL).exitCode,
            0
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let failed = try fixture.runChecker(
            tag: "invalid-tag",
            governanceEvidenceOutput: outputURL
        )
        XCTAssertEqual(failed.exitCode, 64)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testCheckerRejectsGovernanceOutputInsideGitMetadataWithoutChangingTagRef() throws {
        let fixture = try ReleaseProvenanceFixture()
        let tagRef = fixture.rootURL.appendingPathComponent(".git/refs/tags/\(fixture.tag)")
        let original = try Data(contentsOf: tagRef)

        let result = try fixture.runChecker(
            governanceEvidenceOutputArgument: ".git/refs/tags/\(fixture.tag)"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("governance evidence output must not be inside Git metadata"),
            result.stderr
        )
        XCTAssertEqual(try Data(contentsOf: tagRef), original)
    }

    func testCheckerRejectsGovernanceOutputOverTrackedFileWithoutChangingIt() throws {
        let fixture = try ReleaseProvenanceFixture()
        let trackedFile = fixture.rootURL.appendingPathComponent("Package.swift")
        let original = try Data(contentsOf: trackedFile)

        let result = try fixture.runChecker(
            governanceEvidenceOutputArgument: "Package.swift"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("governance evidence output must not replace a tracked worktree path"),
            result.stderr
        )
        XCTAssertEqual(try Data(contentsOf: trackedFile), original)
    }

    func testCheckerRejectsSignerPolicyChangedFromExactFirstParent() throws {
        let fixture = try ReleaseProvenanceFixture(changeSignerPolicyInCandidate: true)
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])

        let result = try fixture.runChecker()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("release signer policy changed from the exact first parent"),
            result.stderr
        )
    }

    func testCheckerRejectsPartialFixtureMode() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])

        let result = try fixture.runChecker(includeRemoteRefsFixture: false)

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(
            result.stderr.contains("provenance fixture mode requires both CI and remote-ref fixtures"),
            result.stderr
        )
    }

    func testCheckerRejectsTrackedDirtyWorktree() throws {
        let fixture = try ReleaseProvenanceFixture()
        try fixture.writeCIRuns([[
            "databaseId": 67890,
            "headBranch": "main",
            "headSha": fixture.commitSHA,
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "url": "https://example.invalid/actions/runs/67890"
        ]])
        try fixture.makeTrackedWorktreeDirty()

        let result = try fixture.runChecker()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("release provenance requires no tracked or staged worktree changes"),
            result.stderr
        )
    }

    func testLiveReadbackRetriesNotFoundAndUnparseableRefAndTagThenConverges() throws {
        let fixture = try ReleaseProvenanceFixture(liveGitHubMode: "delayed")

        let result = try fixture.runLiveChecker()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release provenance OK:"), result.stdout)
        XCTAssertEqual(try fixture.githubCallCount(named: "ref"), 4)
        XCTAssertEqual(try fixture.githubCallCount(named: "tag"), 2)
    }

    func testLiveReadbackExhaustionFailsAfterBoundedAttempts() throws {
        let fixture = try ReleaseProvenanceFixture(liveGitHubMode: "exhaustion")

        let result = try fixture.runLiveChecker()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("after 30 bounded read attempts"), result.stderr)
        XCTAssertEqual(try fixture.githubCallCount(named: "ref"), 30)
        XCTAssertEqual(try fixture.githubCallCount(named: "tag"), 0)
    }

    func testLiveReadbackSemanticMismatchFailsWithoutRetry() throws {
        let fixture = try ReleaseProvenanceFixture(liveGitHubMode: "mismatch")

        let result = try fixture.runLiveChecker()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("semantic ref, tag-object, or commit mismatch"), result.stderr)
        XCTAssertEqual(try fixture.githubCallCount(named: "ref"), 1)
        XCTAssertEqual(try fixture.githubCallCount(named: "tag"), 0)
    }

    func testTokenUsesFDTransportAndOnlyScopedGitHubCallsReceiveIt() throws {
        let fixture = try ReleaseProvenanceFixture(liveGitHubMode: "success")
        let token = "vifty-fixture-token-0123456789abcdef"

        let result = try fixture.runLiveChecker(token: token)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let cleanExecArguments = try fixture.cleanExecArguments()
        XCTAssertFalse(cleanExecArguments.contains(token), cleanExecArguments)
        XCTAssertTrue(cleanExecArguments.contains("VIFTY_GH_TOKEN_FD=9"), cleanExecArguments)

        let calls = try fixture.githubCalls()
        let configCall = try XCTUnwrap(calls.first { $0.command.contains("config get http_unix_socket") })
        XCTAssertEqual(configCall.ghToken, "")
        XCTAssertEqual(configCall.githubToken, "")
        let authenticatedCalls = calls.filter {
            $0.command.hasPrefix("api ") || $0.command.hasPrefix("run list ")
        }
        XCTAssertFalse(authenticatedCalls.isEmpty)
        XCTAssertTrue(authenticatedCalls.allSatisfy { $0.ghToken == token })
        XCTAssertTrue(authenticatedCalls.allSatisfy { $0.githubToken == "" })
        XCTAssertFalse(calls.contains { $0.command.hasPrefix("auth token ") })
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

private struct RecordedGitHubCall {
    let command: String
    let ghToken: String
    let githubToken: String
}

private final class ReleaseProvenanceFixture {
    let rootURL: URL
    let commitSHA: String
    private(set) var tag = ""

    private let ciRunsURL: URL
    private let remoteRefsURL: URL
    private let supportURL: URL
    private let liveGitHubMode: String?
    let governanceEvidenceURL: URL

    init(
        changeSignerPolicyInCandidate: Bool = false,
        liveGitHubMode: String? = nil
    ) throws {
        let repositoryRoot = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        self.liveGitHubMode = liveGitHubMode
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-provenance-\(UUID().uuidString)", isDirectory: true)
        supportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-provenance-support-\(UUID().uuidString)", isDirectory: true)
        ciRunsURL = rootURL.appendingPathComponent("ci-runs.json")
        remoteRefsURL = rootURL.appendingPathComponent("remote-refs.json")
        governanceEvidenceURL = rootURL.appendingPathComponent("governance-evidence.json")

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        for relativePath in [
            "scripts/check-release-provenance.sh",
            "scripts/check-release-manifest.sh",
            "scripts/check-release-manifest-history-from-git.sh",
            "scripts/check-release-manifest-history.rb",
            "scripts/check-release-governance.sh",
            "scripts/check-release-environment.sh",
            "scripts/check-release-secrets.sh",
            "scripts/verify-release-gh-toolchain.rb",
            "scripts/validate-release-governance-evidence.rb",
            ".github/release-manifest.json",
            ".github/release-gh-toolchain.json",
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

        if let liveGitHubMode {
            try Self.installLiveGitHubSupport(
                rootURL: rootURL,
                supportURL: supportURL,
                mode: liveGitHubMode
            )
        }

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
            arguments: ["-c", "commit.gpgsign=false", "commit", "-m", "trusted release base"],
            currentDirectory: rootURL
        )
        let candidate = try Self.writeCandidateManifest(
            at: rootURL.appendingPathComponent(".github/release-manifest.json")
        )
        tag = candidate.tag
        try Self.runRequired(
            executable: "/usr/libexec/PlistBuddy",
            arguments: [
                "-c",
                "Set :CFBundleShortVersionString \(candidate.version)",
                rootURL.appendingPathComponent("Resources/Info.plist").path
            ],
            currentDirectory: rootURL
        )
        try Self.runRequired(
            executable: "/usr/libexec/PlistBuddy",
            arguments: [
                "-c",
                "Set :CFBundleVersion \(candidate.build)",
                rootURL.appendingPathComponent("Resources/Info.plist").path
            ],
            currentDirectory: rootURL
        )
        if changeSignerPolicyInCandidate {
            let signersURL = rootURL.appendingPathComponent(".github/release-signers.allowed")
            var signerPolicy = try String(contentsOf: signersURL, encoding: .utf8)
            signerPolicy += "\n# fixture signer-policy change\n"
            try signerPolicy.write(to: signersURL, atomically: true, encoding: .utf8)
        }
        try Self.runRequired(executable: "/usr/bin/git", arguments: ["add", "."], currentDirectory: rootURL)
        try Self.runRequired(
            executable: "/usr/bin/git",
            arguments: ["-c", "commit.gpgsign=false", "commit", "-m", "candidate"],
            currentDirectory: rootURL
        )
        commitSHA = try Self.capture(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD^{commit}"],
            currentDirectory: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.writeGovernanceEvidence(
            at: governanceEvidenceURL,
            rootURL: rootURL,
            commitSHA: commitSHA,
            tag: tag
        )
        let governanceBytes = try Data(contentsOf: governanceEvidenceURL)
        let tagMessage = "candidate\n\nVifty-Release-Governance-Base64: \(governanceBytes.base64EncodedString())"
        let tagArguments: [String]
        if liveGitHubMode != nil {
            tagArguments = [
                "-c", "gpg.format=ssh",
                "-c", "gpg.ssh.program=/usr/bin/ssh-keygen",
                "-c", "user.signingkey=\(supportURL.appendingPathComponent("release-signing-key").path)",
                "tag", "-s", tag, "-m", tagMessage
            ]
        } else {
            tagArguments = ["-c", "tag.gpgSign=false", "tag", "-a", tag, "-m", tagMessage]
        }
        try Self.runRequired(
            executable: "/usr/bin/git",
            arguments: tagArguments,
            currentDirectory: rootURL
        )
        let tagObjectSHA = try Self.capture(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "\(tag)^{tag}"],
            currentDirectory: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.writeJSON(
            ["tagObjectSHA": tagObjectSHA, "tagCommitSHA": commitSHA],
            to: remoteRefsURL
        )
        if liveGitHubMode != nil {
            try "\(tag)\n".write(
                to: supportURL.appendingPathComponent("tag-name"),
                atomically: true,
                encoding: .utf8
            )
            try "\(tagObjectSHA)\n".write(
                to: supportURL.appendingPathComponent("tag-object"),
                atomically: true,
                encoding: .utf8
            )
            try "\(commitSHA)\n".write(
                to: supportURL.appendingPathComponent("tag-commit"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
        try? FileManager.default.removeItem(at: supportURL)
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

    func makeTrackedWorktreeDirty() throws {
        let packageURL = rootURL.appendingPathComponent("Package.swift")
        var contents = try String(contentsOf: packageURL, encoding: .utf8)
        contents += "\n// tracked-dirty provenance fixture\n"
        try contents.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    func runLiveChecker(
        token: String = "vifty-fixture-live-token"
    ) throws -> ReleaseProvenanceProcessResult {
        XCTAssertNotNil(liveGitHubMode)
        return try runChecker(
            includeCIRunsFixture: false,
            includeRemoteRefsFixture: false,
            skipSignatureForFixture: false,
            environment: [
                "GH_TOKEN": token,
                "GITHUB_TOKEN": "",
                "GH_HOST": ""
            ]
        )
    }

    func githubCallCount(named name: String) throws -> Int {
        let url = supportURL.appendingPathComponent("\(name)-count")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return 0
        }
        let value = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try XCTUnwrap(Int(value))
    }

    func cleanExecArguments() throws -> String {
        try String(
            contentsOf: supportURL.appendingPathComponent("clean-env-argv"),
            encoding: .utf8
        )
    }

    func githubCalls() throws -> [RecordedGitHubCall] {
        let log = try String(
            contentsOf: supportURL.appendingPathComponent("gh-calls.tsv"),
            encoding: .utf8
        )
        return log.split(separator: "\n").map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return RecordedGitHubCall(
                command: fields.indices.contains(0) ? String(fields[0]) : "",
                ghToken: fields.indices.contains(1) ? String(fields[1]) : "",
                githubToken: fields.indices.contains(2) ? String(fields[2]) : ""
            )
        }
    }

    func runChecker(
        tag: String? = nil,
        json: Bool = false,
        trustedWorkflowRef: String? = nil,
        governanceEvidenceOutput: URL? = nil,
        governanceEvidenceOutputArgument: String? = nil,
        currentDirectoryURL: URL? = nil,
        includeCIRunsFixture: Bool = true,
        includeRemoteRefsFixture: Bool = true,
        skipSignatureForFixture: Bool = true,
        environment: [String: String] = [:]
    ) throws -> ReleaseProvenanceProcessResult {
        let process = Process()
        process.executableURL = rootURL.appendingPathComponent("scripts/check-release-provenance.sh")
        process.currentDirectoryURL = currentDirectoryURL ?? rootURL
        var arguments = [
            "--tag", tag ?? self.tag,
            "--main-ref", "main"
        ]
        if includeCIRunsFixture {
            arguments += ["--ci-runs-file", ciRunsURL.path]
        }
        if includeRemoteRefsFixture {
            arguments += ["--remote-refs-file", remoteRefsURL.path]
        }
        if skipSignatureForFixture {
            arguments.append("--skip-signature-for-fixture")
        }
        if let trustedWorkflowRef {
            arguments += ["--trusted-workflow-ref", trustedWorkflowRef]
        }
        if let governanceEvidenceOutput {
            arguments += ["--governance-evidence-output", governanceEvidenceOutput.path]
        }
        if let governanceEvidenceOutputArgument {
            arguments += ["--governance-evidence-output", governanceEvidenceOutputArgument]
        }
        if json {
            arguments.append("--json")
        }
        process.arguments = arguments
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment.merge([
            "VIFTY_RELEASE_PROVENANCE_ROOT": rootURL.path,
            "GH_TOKEN": "",
            "GITHUB_TOKEN": "",
            "GH_HOST": ""
        ], uniquingKeysWith: { _, new in new })
        processEnvironment.merge(environment, uniquingKeysWith: { _, new in new })
        process.environment = processEnvironment

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

    private static func installLiveGitHubSupport(
        rootURL: URL,
        supportURL: URL,
        mode: String
    ) throws {
        let signingKeyURL = supportURL.appendingPathComponent("release-signing-key")
        try runRequired(
            executable: "/usr/bin/ssh-keygen",
            arguments: [
                "-q", "-t", "ed25519", "-N", "", "-C", "vifty-provenance-fixture",
                "-f", signingKeyURL.path
            ],
            currentDirectory: supportURL
        )
        let publicKey = try String(
            contentsOf: signingKeyURL.appendingPathExtension("pub"),
            encoding: .utf8
        ).split(whereSeparator: { $0.isWhitespace })
        guard publicKey.count >= 2 else {
            throw NSError(
                domain: "ReleaseProvenanceFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "generated fixture public key is malformed"]
            )
        }
        try "vifty-test@example.invalid \(publicKey[0]) \(publicKey[1])\n".write(
            to: rootURL.appendingPathComponent(".github/release-signers.allowed"),
            atomically: true,
            encoding: .utf8
        )

        try "\(mode)\n".write(
            to: supportURL.appendingPathComponent("mode"),
            atomically: true,
            encoding: .utf8
        )

        let fakeEnvironmentURL = supportURL.appendingPathComponent("clean-env")
        let cleanEnvironmentArgumentsURL = supportURL.appendingPathComponent("clean-env-argv")
        let fakeEnvironment = #"""
        #!/bin/bash
        set -eu
        /usr/bin/printf '%s\n' "$@" > '\#(cleanEnvironmentArgumentsURL.path)'
        exec /usr/bin/env "$@"
        """#
        try fakeEnvironment.write(to: fakeEnvironmentURL, atomically: true, encoding: .utf8)

        let fakeGitHubURL = supportURL.appendingPathComponent("gh")
        let fakeGitHub = #"""
        #!/bin/bash
        set -u

        support='\#(supportURL.path)'
        /usr/bin/printf '%s\t%s\t%s\n' "$*" "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}" >> "${support}/gh-calls.tsv"

        increment_counter() {
          local name="$1"
          local path="${support}/${name}-count"
          local count=0
          if [[ -f "${path}" ]]; then
            count="$(/bin/cat "${path}")"
          fi
          count=$((count + 1))
          /usr/bin/printf '%s\n' "${count}" > "${path}"
          /usr/bin/printf '%s' "${count}"
        }

        read_value() {
          /usr/bin/tr -d '\r\n' < "${support}/$1"
        }

        emit_http() {
          /usr/bin/printf 'HTTP/2.0 %s\r\nContent-Type: application/json\r\n\r\n%s' "$1" "$2"
        }

        if [[ "${1:-}" == "config" && "${2:-}" == "get" ]]; then
          exit 0
        fi
        if [[ "${1:-}" == "auth" && "${2:-}" == "token" ]]; then
          exit 1
        fi
        if [[ "${1:-}" == "api" ]]; then
          endpoint="${!#}"
          mode="$(read_value mode)"
          tag="$(read_value tag-name)"
          tag_object="$(read_value tag-object)"
          tag_commit="$(read_value tag-commit)"
          case "${endpoint}" in
            */git/ref/tags/*)
              count="$(increment_counter ref)"
              if [[ "${mode}" == "exhaustion" || ( "${mode}" == "delayed" && "${count}" -eq 1 ) ]]; then
                emit_http '404 Not Found' '{"message":"Not Found"}'
                exit 1
              fi
              if [[ "${mode}" == "delayed" && "${count}" -eq 2 ]]; then
                emit_http '200 OK' '{'
                exit 0
              fi
              if [[ "${mode}" == "mismatch" ]]; then
                emit_http '200 OK' "{\"ref\":\"refs/tags/${tag}\",\"object\":{\"type\":\"tag\",\"sha\":\"ffffffffffffffffffffffffffffffffffffffff\"}}"
                exit 0
              fi
              emit_http '200 OK' "{\"ref\":\"refs/tags/${tag}\",\"object\":{\"type\":\"tag\",\"sha\":\"${tag_object}\"}}"
              exit 0
              ;;
            */git/tags/*)
              count="$(increment_counter tag)"
              if [[ "${mode}" == "delayed" && "${count}" -eq 1 ]]; then
                emit_http '200 OK' '{'
                exit 0
              fi
              emit_http '200 OK' "{\"sha\":\"${tag_object}\",\"tag\":\"${tag}\",\"object\":{\"type\":\"commit\",\"sha\":\"${tag_commit}\"}}"
              exit 0
              ;;
          esac
        fi
        if [[ "${1:-}" == "run" && "${2:-}" == "list" ]]; then
          tag_commit="$(read_value tag-commit)"
          /usr/bin/printf '[{"databaseId":67890,"headBranch":"main","headSha":"%s","status":"completed","conclusion":"success","event":"push","url":"https://example.invalid/actions/runs/67890"}]\n' "${tag_commit}"
          exit 0
        fi

        /usr/bin/printf 'unexpected fake gh invocation: %s\n' "$*" >&2
        exit 64
        """#
        try fakeGitHub.write(to: fakeGitHubURL, atomically: true, encoding: .utf8)

        for executableURL in [fakeEnvironmentURL, fakeGitHubURL] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        }

        let checkerURL = rootURL.appendingPathComponent("scripts/check-release-provenance.sh")
        var checker = try String(contentsOf: checkerURL, encoding: .utf8)
        let originalChecker = checker
        checker = checker.replacingOccurrences(
            of: "/usr/bin/env -i",
            with: "'\(fakeEnvironmentURL.path)' -i"
        )
        let ghDiscovery = """
        GH_BIN=""
        for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
          if [[ -x "${gh_candidate}" ]]; then
            GH_BIN="${gh_candidate}"
            break
          fi
        done
        """
        checker = checker.replacingOccurrences(
            of: ghDiscovery,
            with: "GH_BIN='\(fakeGitHubURL.path)'"
        )
        checker = checker.replacingOccurrences(
            of: #"/bin/sleep "${REMOTE_READBACK_DELAY_SECONDS}""#,
            with: "/usr/bin/true"
        )
        guard checker != originalChecker,
              checker.contains("GH_BIN='\(fakeGitHubURL.path)'"),
              checker.contains("'\(fakeEnvironmentURL.path)' -i"),
              checker.contains("/usr/bin/true") else {
            throw NSError(
                domain: "ReleaseProvenanceFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "failed to install isolated live GitHub fixture"]
            )
        }
        try checker.write(to: checkerURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: checkerURL.path
        )
    }

    private static func writeCandidateManifest(
        at url: URL
    ) throws -> (version: String, build: Int, tag: String) {
        let data = try Data(contentsOf: url)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
        let base = (manifest["candidate"] as? [String: Any]) ?? published
        let baseVersion = try XCTUnwrap(base["version"] as? String)
        let versionComponents = baseVersion.split(
            separator: ".",
            omittingEmptySubsequences: false
        ).compactMap { Int($0) }
        guard versionComponents.count == 3 else {
            throw NSError(
                domain: "ReleaseProvenanceFixture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "base release version is not numeric SemVer"]
            )
        }
        let (nextPatch, versionOverflow) = versionComponents[2].addingReportingOverflow(1)
        let baseBuild = try XCTUnwrap(base["build"] as? Int)
        let (candidateBuild, buildOverflow) = baseBuild.addingReportingOverflow(1)
        guard !versionOverflow, !buildOverflow else {
            throw NSError(
                domain: "ReleaseProvenanceFixture",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "base release identity cannot be incremented"]
            )
        }
        let candidateVersion = "\(versionComponents[0]).\(versionComponents[1]).\(nextPatch)"
        let candidateTag = "v\(candidateVersion)"
        manifest["candidate"] = [
            "version": candidateVersion,
            "build": candidateBuild,
            "tag": candidateTag,
            "artifact": "Vifty-\(candidateTag).zip",
            "checksumAsset": "Vifty-\(candidateTag).zip.sha256",
            "artifactSummary": "Vifty-\(candidateTag)-artifact-summary.json",
            "releaseChecklist": "Vifty-\(candidateTag)-release-checklist.md",
            "sha256": NSNull(),
            "artifactTrust": "pending",
            "signingTrust": "pending",
            "tagTrust": "signed-required",
            "installedReleaseReview": "pending",
            "manualCompatibility": "pending",
            "manualCompatibilityScope": NSNull()
        ]
        try writeJSON(manifest, to: url)
        return (candidateVersion, candidateBuild, candidateTag)
    }

    private static func writeGovernanceEvidence(
        at url: URL,
        rootURL: URL,
        commitSHA: String,
        tag: String
    ) throws {
        let toolSHA = try capture(
            executable: "/usr/bin/shasum",
            arguments: ["-a", "256", rootURL.appendingPathComponent("scripts/check-release-governance.sh").path],
            currentDirectory: rootURL
        ).split(separator: " ").first.map(String.init) ?? ""
        let environmentToolSHA = try capture(
            executable: "/usr/bin/shasum",
            arguments: ["-a", "256", rootURL.appendingPathComponent("scripts/check-release-environment.sh").path],
            currentDirectory: rootURL
        ).split(separator: " ").first.map(String.init) ?? ""
        let secretsToolSHA = try capture(
            executable: "/usr/bin/shasum",
            arguments: ["-a", "256", rootURL.appendingPathComponent("scripts/check-release-secrets.sh").path],
            currentDirectory: rootURL
        ).split(separator: " ").first.map(String.init) ?? ""
        let ghVerifierSHA = try capture(
            executable: "/usr/bin/shasum",
            arguments: ["-a", "256", rootURL.appendingPathComponent("scripts/verify-release-gh-toolchain.rb").path],
            currentDirectory: rootURL
        ).split(separator: " ").first.map(String.init) ?? ""
        let ghPolicySHA = try capture(
            executable: "/usr/bin/shasum",
            arguments: ["-a", "256", rootURL.appendingPathComponent(".github/release-gh-toolchain.json").path],
            currentDirectory: rootURL
        ).split(separator: " ").first.map(String.init) ?? ""
        let observedAt = try capture(
            executable: "/bin/date",
            arguments: ["-u", "+%Y-%m-%dT%H:%M:%SZ"],
            currentDirectory: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence: [String: Any] = [
            "schemaVersion": 1,
            "status": "passed",
            "releaseAuthorized": true,
            "evidenceScope": "administrator-pretag",
            "apiHost": "github.com",
            "dataSource": "github-api-live",
            "liveAuthenticatedGitHubReadback": true,
            "repository": "Reedtrullz/Vifty",
            "releaseTag": tag,
            "expectedMainSHA": commitSHA,
            "observationStartedAt": observedAt,
            "observedAt": observedAt,
            "repositoryAdminVerified": true,
            "authenticatedActor": ["id": 12345, "login": "Reedtrullz"],
            "tagAbsentVerified": true,
            "existingTagVerified": false,
            "existingTagObjectSHA": NSNull(),
            "governanceTool": [
                "path": "scripts/check-release-governance.sh",
                "sha256": toolSHA
            ],
            "governanceDependencies": [
                [
                    "path": "scripts/check-release-environment.sh",
                    "sha256": environmentToolSHA
                ],
                [
                    "path": "scripts/check-release-secrets.sh",
                    "sha256": secretsToolSHA
                ],
                [
                    "path": "scripts/verify-release-gh-toolchain.rb",
                    "sha256": ghVerifierSHA
                ],
                [
                    "path": ".github/release-gh-toolchain.json",
                    "sha256": ghPolicySHA
                ]
            ],
            "releaseEnvironmentEvidence": [
                "schemaVersion": 5,
                "status": "passed",
                "releaseAuthorized": true,
                "dataSource": "github-api-live",
                "evidenceScope": "administrator-full",
                "privilegedSettingsVerified": true,
                "environment": "release",
                "releaseGovernanceMode": "solo-maintainer",
                "requiredReviewerGate": false,
                "requiredReviewers": [],
                "preventSelfReview": false,
                "administratorsCanBypass": false,
                "deploymentBranchPolicy": [
                    "protected_branches": false,
                    "custom_branch_policies": true
                ],
                "releaseTagDeploymentPolicy": [
                    "policyCount": 1,
                    "branchPolicyCount": 0,
                    "tagPolicyCount": 1,
                    "requiredTagPattern": "v*",
                    "policies": [
                        ["type": "tag", "name": "v*"]
                    ]
                ],
                "requiredBranch": "main",
                "requiredBranchCommitSHA": commitSHA,
                "requiredBranchProtected": true,
                "requiredBranchProtection": [
                    "strictStatusChecks": true,
                    "requiredStatusCheck": ["context": "SwiftPM checks", "appID": 15_368],
                    "enforceAdministrators": true,
                    "pullRequestRequired": true,
                    "peerApprovalRequired": false,
                    "requiredApprovingReviewCount": 0,
                    "codeOwnerReviewRequired": false,
                    "lastPushApprovalRequired": false,
                    "pullRequestBypassActors": [],
                    "requireConversationResolution": true,
                    "allowForcePushes": false,
                    "allowDeletions": false
                ],
                "readOnly": true
            ],
            "tagRulesetEvidence": [
                "schemaVersion": 1,
                "repository": "Reedtrullz/Vifty",
                "releaseTag": tag,
                "releaseRef": "refs/tags/\(tag)",
                "rulesetID": 18_940_029,
                "rulesetName": "Immutable Vifty release tags",
                "rulesetUpdatedAt": "2026-01-01T00:00:00Z",
                "currentUserCanBypass": "never",
                "target": "tag",
                "enforcement": "active",
                "matchedIncludePatterns": ["refs/tags/v*"],
                "excludePatternsVerified": true,
                "matchedExcludePatterns": [],
                "ruleTypes": ["deletion", "update"],
                "bypassActorsVerified": true,
                "bypassActors": [],
                "preventsUpdate": true,
                "preventsDeletion": true,
                "readOnly": true
            ],
            "releaseSecrets": [
                "storageScope": "repository",
                "requiredNamesVerified": true,
                "environmentShadowNames": [],
                "valuesRead": false
            ],
            "readOnly": true
        ]
        try writeJSON(evidence, to: url)
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
