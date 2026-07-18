import Foundation
import XCTest

final class ReleasePushDispatchScriptTests: XCTestCase {
    func testPrePushGovernanceDriftFailsWithoutRemoteMutation() throws {
        let fixture = try ReleasePushDispatchFixture()
        try Data().write(to: fixture.governanceDriftURL)

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(
            result.stderr.contains("fresh administrator governance differs"),
            result.stderr
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.tagPushedURL.path))
        XCTAssertNil(try fixture.remoteTagObject())
        XCTAssertEqual(try fixture.localTagObject(), fixture.tagObjectSHA)
    }

    func testPushUsesAbsentLeaseExactRefspecAndObservesOnlyTagPushRun() throws {
        let fixture = try ReleasePushDispatchFixture()

        let result = try fixture.runHelper()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let gitLog = try String(contentsOf: fixture.gitLogURL, encoding: .utf8)
        XCTAssertTrue(
            gitLog.contains("https://github.com/Reedtrullz/Vifty.git"),
            gitLog
        )
        XCTAssertTrue(
            gitLog.contains("--force-with-lease=refs/tags/\(fixture.tag):"),
            gitLog
        )
        XCTAssertTrue(
            gitLog.contains("\(fixture.tagObjectSHA):refs/tags/\(fixture.tag)"),
            gitLog
        )

        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
        XCTAssertTrue(
            ghLog.contains("run list --repo github.com/Reedtrullz/Vifty --workflow 77 --event push --all"),
            ghLog
        )

        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "completed")
        XCTAssertEqual(receipt["schemaVersion"] as? Int, 2)
        XCTAssertEqual(receipt["tagPushed"] as? Bool, true)
        XCTAssertEqual(receipt["workflowTrigger"] as? String, "push")
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, true)
        XCTAssertEqual(receipt["workflowRunVerified"] as? Bool, true)
        XCTAssertEqual(receipt["receiptAuthorizesRetry"] as? Bool, false)
        XCTAssertEqual(receipt["pushExitCode"] as? Int, 0)
        XCTAssertEqual(receipt["remoteTagState"] as? String, "exact")
        XCTAssertEqual(receipt["triggerState"] as? String, "confirmed")
        XCTAssertEqual(receipt["commitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(receipt["tagObjectSHA"] as? String, fixture.tagObjectSHA)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.receiptURL.path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try fixture.remoteTagObject(), fixture.tagObjectSHA)
        XCTAssertEqual(try fixture.localTagObject(), fixture.tagObjectSHA)
    }

    func testRemoteAnnotatedTagReadbackMismatchFailsWithDurablePushedReceipt() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "tag-readback-mismatch".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("tag readback"), result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.tagPushedURL.path))
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "push-result-remote-mismatched")
        XCTAssertNil(receipt["tagPushed"] as? Bool)
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, false)
        XCTAssertEqual(receipt["receiptAuthorizesRetry"] as? Bool, false)
        XCTAssertEqual(receipt["stage"] as? String, "push-response-readback")
        XCTAssertEqual(receipt["remoteTagState"] as? String, "mismatched")
        XCTAssertEqual(try fixture.remoteTagObject(), fixture.tagObjectSHA)
        XCTAssertEqual(try fixture.localTagObject(), fixture.tagObjectSHA)
    }

    func testLostPushResponseRetiresTagAndSecondInvocationCannotPushOrObserveAgain() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "push-response-lost".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let first = try fixture.runHelper()

        XCTAssertEqual(first.exitCode, 75, first.stderr)
        XCTAssertEqual(try fixture.remoteTagObject(), fixture.tagObjectSHA)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "push-response-ambiguous-remote-exact")
        XCTAssertEqual(receipt["receiptAuthorizesRetry"] as? Bool, false)
        XCTAssertEqual(receipt["tagPushConfirmed"] as? Bool, true)

        let second = try fixture.runHelper()

        XCTAssertNotEqual(second.exitCode, 0, second.stdout)
        XCTAssertTrue(second.stderr.contains("durable retired-tag marker blocks"), second.stderr)
        let gitLog = try String(contentsOf: fixture.gitLogURL, encoding: .utf8)
        XCTAssertEqual(
            gitLog.split(separator: "\n").filter { $0.contains(" push --porcelain ") }.count,
            1,
            gitLog
        )
        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
        let unchangedReceipt = try fixture.receipt()
        XCTAssertEqual(
            unchangedReceipt["status"] as? String,
            "push-response-ambiguous-remote-exact"
        )
        XCTAssertEqual(unchangedReceipt["receiptAuthorizesRetry"] as? Bool, false)
    }

    func testRetiredReceiptStillBlocksAfterRemoteTagIsDeleted() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "push-response-lost".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let first = try fixture.runHelper()
        XCTAssertEqual(first.exitCode, 75, first.stderr)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.retirementMarkerURL.path)
        )
        try fixture.simulateDeletedRemoteTransactionState()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receiptURL.path))

        let second = try fixture.runHelper()

        XCTAssertEqual(second.exitCode, 75, second.stderr)
        XCTAssertTrue(second.stderr.contains("durable retired-tag marker blocks"), second.stderr)
        XCTAssertNil(try fixture.remoteTagObject())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.receiptURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.retirementMarkerURL.path)
        )
        let gitLog = try String(contentsOf: fixture.gitLogURL, encoding: .utf8)
        XCTAssertEqual(
            gitLog.split(separator: "\n").filter { $0.contains(" push --porcelain ") }.count,
            1,
            gitLog
        )
    }

    func testAlternateCallerHomeCannotBypassRetirementAfterRemoteTagIsDeleted() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "push-response-lost".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let first = try fixture.runHelper()
        XCTAssertEqual(first.exitCode, 75, first.stderr)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.retirementMarkerURL.path)
        )
        try fixture.simulateDeletedRemoteTransactionState()

        let alternateHome = fixture.rootURL.appendingPathComponent(
            "alternate-home",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: alternateHome,
            withIntermediateDirectories: true
        )
        let second = try fixture.runHelper(environment: ["HOME": alternateHome.path])

        XCTAssertEqual(second.exitCode, 75, second.stderr)
        XCTAssertTrue(second.stderr.contains("durable retired-tag marker blocks"), second.stderr)
        XCTAssertNil(try fixture.remoteTagObject())
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.retirementMarkerURL.path)
        )
        let alternateMarker = alternateHome.appendingPathComponent(
            "Library/Application Support/Vifty/ReleaseTransactions/" +
                "Reedtrullz-Vifty/\(fixture.tag)/retired.json"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: alternateMarker.path))
        let gitLog = try String(contentsOf: fixture.gitLogURL, encoding: .utf8)
        XCTAssertEqual(
            gitLog.split(separator: "\n").filter { $0.contains(" push --porcelain ") }.count,
            1,
            gitLog
        )
    }

    func testSameNamedRemoteBranchBlocksBeforeTagPush() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "branch-collision".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("same-named remote branch"), result.stderr)
        XCTAssertNil(try fixture.remoteTagObject())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.tagPushedURL.path))
    }

    func testPreExistingDraftReleaseBlocksBeforeTagPush() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "draft-release-collision".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("draft or published"), result.stderr)
        XCTAssertNil(try fixture.remoteTagObject())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.tagPushedURL.path))
    }

    func testTagPushRunObservationDoesNotInvokeManualWorkflowDispatch() throws {
        let fixture = try ReleasePushDispatchFixture()

        let result = try fixture.runHelper()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "completed")
        XCTAssertEqual(receipt["workflowTrigger"] as? String, "push")
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, true)
        XCTAssertEqual(receipt["workflowRunVerified"] as? Bool, true)
        XCTAssertNil(receipt["dispatchNonce"])
    }

    func testMissingTagPushRunRetainsUnobservedRetiredOutcome() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "tag-push-no-run".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "tag-push-run-unobserved")
        XCTAssertEqual(receipt["tagPushed"] as? Bool, true)
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, false)
        XCTAssertEqual(receipt["workflowRunVerified"] as? Bool, false)
        XCTAssertEqual(receipt["triggerState"] as? String, "unobserved")
        XCTAssertEqual(receipt["triggerCorrelation"] as? String, "unconfirmed")
    }

    func testDuplicateTagPushRunsFailAsAmbiguousWithoutManualDispatch() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "duplicate-runs".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "tag-push-run-ambiguous")
        XCTAssertEqual(receipt["triggerState"] as? String, "ambiguous")
        XCTAssertEqual(receipt["triggerCorrelation"] as? String, "ambiguous")
        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
    }

    func testPoisonedGlobalGitTemplateCannotInstallPushHook() throws {
        let fixture = try ReleasePushDispatchFixture()
        let poisonedHome = fixture.rootURL.appendingPathComponent("poison-home", isDirectory: true)
        let poisonedTemplate = fixture.rootURL.appendingPathComponent(
            "poison-template",
            isDirectory: true
        )
        let hookURL = poisonedTemplate.appendingPathComponent("hooks/pre-push")
        let markerURL = fixture.stateURL.appendingPathComponent("poison-hook-ran")
        try FileManager.default.createDirectory(
            at: hookURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/bash\n: > \"\(markerURL.path)\"\n".write(
            to: hookURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hookURL.path
        )
        try FileManager.default.createDirectory(at: poisonedHome, withIntermediateDirectories: true)
        let poisonedGitConfig = "[init]\n\ttemplateDir = \(poisonedTemplate.path)\n"
        try poisonedGitConfig.write(
            to: poisonedHome.appendingPathComponent(".gitconfig"),
            atomically: true,
            encoding: .utf8
        )
        try poisonedGitConfig.write(
            to: fixture.homeURL.appendingPathComponent(".gitconfig"),
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper(environment: ["HOME": poisonedHome.path])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.retirementMarkerURL.path)
        )
        let poisonedRetirementMarker = poisonedHome.appendingPathComponent(
            "Library/Application Support/Vifty/ReleaseTransactions/" +
                "Reedtrullz-Vifty/\(fixture.tag)/retired.json"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: poisonedRetirementMarker.path)
        )
    }

    func testMismatchedTagPushRunFailsWithoutManualDispatch() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "run-mismatch".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("workflow run does not bind"), result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.tagPushedURL.path))
        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "tag-push-run-mismatched")
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, true)
        XCTAssertEqual(receipt["workflowRunVerified"] as? Bool, false)
        XCTAssertEqual(receipt["triggerState"] as? String, "observed-unverified")
        XCTAssertEqual(receipt["triggerCorrelation"] as? String, "observed-unverified")
    }

    func testSecondAttemptWorkflowRunIsRejectedWithoutRerun() throws {
        let fixture = try ReleasePushDispatchFixture()
        try "run-attempt-two".write(
            to: fixture.modeURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try fixture.runHelper()

        XCTAssertNotEqual(result.exitCode, 0, result.stdout)
        XCTAssertTrue(result.stderr.contains("workflow run does not bind"), result.stderr)
        let ghLog = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertFalse(ghLog.contains("workflow run"), ghLog)
        let receipt = try fixture.receipt()
        XCTAssertEqual(receipt["status"] as? String, "tag-push-run-mismatched")
        XCTAssertEqual(receipt["workflowRunObserved"] as? Bool, true)
        XCTAssertEqual(receipt["workflowRunVerified"] as? Bool, false)
    }
}

private struct ReleasePushDispatchProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class ReleasePushDispatchFixture {
    let tag = "v9.8.7"
    let rootURL: URL
    let homeURL: URL
    let repositoryURL: URL
    let remoteURL: URL
    let stateURL: URL
    let governanceDriftURL: URL
    let modeURL: URL
    let tagPushedURL: URL
    let gitLogURL: URL
    let ghLogURL: URL
    let receiptURL: URL
    let retirementMarkerURL: URL
    private(set) var commitSHA = ""
    private(set) var tagObjectSHA = ""

    private let sourceRoot: URL
    private let privateKeyURL: URL
    private let evidenceTemplateURL: URL
    private let fakeGitURL: URL
    private let fakeGHURL: URL

    init() throws {
        sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-push-\(UUID().uuidString)", isDirectory: true)
        repositoryURL = rootURL.appendingPathComponent("repository", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        remoteURL = rootURL.appendingPathComponent("remote.git", isDirectory: true)
        stateURL = rootURL.appendingPathComponent("state", isDirectory: true)
        governanceDriftURL = stateURL.appendingPathComponent("governance-drift")
        modeURL = stateURL.appendingPathComponent("mode")
        tagPushedURL = stateURL.appendingPathComponent("tag-pushed")
        gitLogURL = stateURL.appendingPathComponent("git-args.log")
        ghLogURL = stateURL.appendingPathComponent("gh-args.log")
        receiptURL = homeURL
            .appendingPathComponent(
                "Library/Application Support/Vifty/ReleaseTransactions/Reedtrullz-Vifty/\(tag)/receipt.json"
            )
        retirementMarkerURL = receiptURL.deletingLastPathComponent()
            .appendingPathComponent("retired.json")
        privateKeyURL = rootURL.appendingPathComponent("signing-key")
        evidenceTemplateURL = rootURL.appendingPathComponent("evidence-template.json")
        let fakeBinURL = rootURL.appendingPathComponent("fake-bin", isDirectory: true)
        fakeGitURL = fakeBinURL.appendingPathComponent("git")
        fakeGHURL = fakeBinURL.appendingPathComponent("gh")

        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBinURL, withIntermediateDirectories: true)
        try Self.requireSuccess(
            try Self.run(
                "/usr/bin/git",
                ["init", "--bare", remoteURL.path],
                currentDirectory: rootURL
            ),
            "initialize isolated fake GitHub remote"
        )
        try installFakeGit()
        try installRepositoryFiles()
        try initializeSignedTag()
        try installFakeGitHubCLI()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runHelper(
        environment extraEnvironment: [String: String] = [:]
    ) throws -> ReleasePushDispatchProcessResult {
        return try Self.run(
            repositoryURL.appendingPathComponent(
                "scripts/push-and-dispatch-signed-release-tag.sh"
            ).path,
            ["--tag", tag, "--commit", commitSHA],
            currentDirectory: repositoryURL,
            environment: [
                "GH_TOKEN": "fixture-token",
                "HOME": homeURL.path
            ].merging(extraEnvironment) { _, replacement in replacement }
        )
    }

    func localTagObject() throws -> String {
        let result = try git("rev-parse", "--verify", "refs/tags/\(tag)^{tag}")
        try Self.requireSuccess(result, "read local tag object")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remoteTagObject() throws -> String? {
        let result = try Self.run(
            "/usr/bin/git",
            ["--git-dir", remoteURL.path, "rev-parse", "--verify", "refs/tags/\(tag)^{tag}"],
            currentDirectory: rootURL
        )
        guard result.exitCode == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func receipt() throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any]
        )
    }

    func simulateDeletedRemoteTransactionState() throws {
        let result = try Self.run(
            "/usr/bin/git",
            ["--git-dir", remoteURL.path, "update-ref", "-d", "refs/tags/\(tag)"],
            currentDirectory: rootURL
        )
        try Self.requireSuccess(result, "delete isolated remote tag for tombstone regression")
        for url in [tagPushedURL, modeURL, receiptURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func installRepositoryFiles() throws {
        let helperSource = sourceRoot.appendingPathComponent(
            "scripts/push-and-dispatch-signed-release-tag.sh"
        )
        let helperDestination = repositoryURL.appendingPathComponent(
            "scripts/push-and-dispatch-signed-release-tag.sh"
        )
        let validatorSource = sourceRoot.appendingPathComponent(
            "scripts/validate-release-governance-evidence.rb"
        )
        let validatorDestination = repositoryURL.appendingPathComponent(
            "scripts/validate-release-governance-evidence.rb"
        )
        let ghVerifierSource = sourceRoot.appendingPathComponent(
            "scripts/verify-release-gh-toolchain.rb"
        )
        let ghVerifierDestination = repositoryURL.appendingPathComponent(
            "scripts/verify-release-gh-toolchain.rb"
        )
        let ghPolicySource = sourceRoot.appendingPathComponent(
            ".github/release-gh-toolchain.json"
        )
        let ghPolicyDestination = repositoryURL.appendingPathComponent(
            ".github/release-gh-toolchain.json"
        )
        try FileManager.default.createDirectory(
            at: helperDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: helperSource, to: helperDestination)
        try FileManager.default.copyItem(at: validatorSource, to: validatorDestination)
        try FileManager.default.copyItem(at: ghVerifierSource, to: ghVerifierDestination)
        try FileManager.default.createDirectory(
            at: ghPolicyDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: ghPolicySource, to: ghPolicyDestination)

        let protectedSupportPaths = [
            ".github/workflows/ci.yml",
            ".github/workflows/release.yml",
            "scripts/check-release-environment.sh",
            "scripts/check-release-governance.sh",
            "scripts/check-release-manifest-history-from-git.sh",
            "scripts/check-release-manifest-history.rb",
            "scripts/check-release-manifest.sh",
            "scripts/check-release-prep-diff.sh",
            "scripts/check-release-provenance.sh",
            "scripts/check-release-secrets.sh",
            "scripts/check-workflow-contract.rb",
            "scripts/create-signed-release-tag.sh",
            "scripts/lib/release_artifact_contract.rb",
            "scripts/release-candidate-inventory.rb",
            "scripts/render-release-facts.sh",
            "scripts/run-actionlint.sh",
            "scripts/sign-release-candidate.sh",
            "scripts/validate-release-metadata.sh",
            "scripts/verify-release-artifact.sh",
            "scripts/write-release-checklist.sh"
        ]
        for relativePath in protectedSupportPaths {
            let source = sourceRoot.appendingPathComponent(relativePath)
            let destination = repositoryURL.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }

        var helper = try String(contentsOf: helperDestination, encoding: .utf8)
        let ghDiscovery = """
        GH_BIN=""
        for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
          if [[ -x "${gh_candidate}" ]]; then
            GH_BIN="${gh_candidate}"
            break
          fi
        done
        """
        guard helper.contains(ghDiscovery), helper.contains("GIT_BIN=\"/usr/bin/git\"") else {
            throw NSError(
                domain: "ReleasePushDispatchFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "release helper binary bindings changed"]
            )
        }
        helper = helper.replacingOccurrences(
            of: ghDiscovery,
            with: "GH_BIN=\"\(fakeGHURL.path)\"\n"
        )
        helper = helper.replacingOccurrences(
            of: "GIT_BIN=\"/usr/bin/git\"",
            with: "GIT_BIN=\"\(fakeGitURL.path)\""
        )
        let canonicalHomeBlock = #"""
        CANONICAL_HOME="$("${RUBY_BIN}" -retc -e '
          begin
            passwd_home = Etc.getpwuid(Process.uid).dir
            abort("passwd home must be an absolute path") unless
              passwd_home.is_a?(String) && passwd_home.start_with?("/") && passwd_home != "/"
            resolved_home = File.realpath(passwd_home)
            abort("canonical passwd home must be a directory") unless File.directory?(resolved_home)
            print resolved_home
          rescue ArgumentError, SystemCallError => error
            abort("cannot resolve canonical passwd home: #{error.message}")
          end
        ')" || {
          echo "error: failed to resolve the current uid's canonical passwd home" >&2
          exit 65
        }
        if [[ -z "${CANONICAL_HOME}" || "${CANONICAL_HOME}" != /* ||
              ! -d "${CANONICAL_HOME}" || -L "${CANONICAL_HOME}" ]]; then
          echo "error: current uid does not have a safe canonical passwd home" >&2
          exit 65
        fi
        HOME="${CANONICAL_HOME}"
        export HOME
        """#
        guard helper.contains(canonicalHomeBlock) else {
            throw NSError(
                domain: "ReleasePushDispatchFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "release helper canonical home block changed"]
            )
        }
        helper = helper.replacingOccurrences(
            of: canonicalHomeBlock,
            with: "CANONICAL_HOME=\"\(homeURL.path)\"\nHOME=\"${CANONICAL_HOME}\"\nexport HOME"
        )
        let ghPinBlock = """
        unverified_gh_bin="${GH_BIN}"
        GH_BIN="${scratch}/pinned-gh"
        "${RUBY_BIN}" "${committed_root}/${GH_TOOLCHAIN_VERIFIER_PATH}" \\
          --policy "${committed_root}/${GH_TOOLCHAIN_POLICY_PATH}" \\
          --source "${unverified_gh_bin}" \\
          --destination "${GH_BIN}" > "${scratch}/gh-toolchain-verification.json"
        """
        guard helper.contains(ghPinBlock) else {
            throw NSError(
                domain: "ReleasePushDispatchFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "release helper gh pin block changed"]
            )
        }
        helper = helper.replacingOccurrences(
            of: ghPinBlock,
            with: "true # fixture gh is isolated by this test harness\n"
        )
        helper = helper.replacingOccurrences(of: "/bin/sleep", with: "/usr/bin/true")
        try helper.write(to: helperDestination, atomically: true, encoding: .utf8)

        try executable(
            """
            #!/bin/bash -p
            set -euo pipefail
            if [[ "${VIFTY_FIXTURE_INITIAL_GOVERNANCE:-}" != "1" ]]; then
              [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]] || {
                echo "raw GitHub token leaked to governance child environment" >&2
                exit 91
              }
              [[ "${VIFTY_GH_TOKEN_FD:-}" == "9" ]] || exit 91
              IFS= read -r inherited_token <&9 || exit 91
              exec 9<&-
              unset VIFTY_GH_TOKEN_FD
              [[ "${inherited_token}" == "fixture-token" ]] || exit 91
              unset inherited_token
            fi
            unset VIFTY_FIXTURE_INITIAL_GOVERNANCE
            output=""
            repo="Reedtrullz/Vifty"
            tag=""
            commit=""
            existing_object=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --output) output="$2"; shift 2 ;;
                --repo) repo="$2"; shift 2 ;;
                --tag) tag="$2"; shift 2 ;;
                --expected-main) commit="$2"; shift 2 ;;
                --expected-existing-tag-object) existing_object="$2"; shift 2 ;;
                --environment|--branch) shift 2 ;;
                *) echo "unexpected governance argument: $1" >&2; exit 64 ;;
              esac
            done
            if [[ -n "${existing_object}" && -f "\(modeURL.path)" ]] &&
               [[ "$(< "\(modeURL.path)")" == "postpush-governance-block" ]]; then
              exit 65
            fi
            /usr/bin/ruby -rjson -rdigest -rtime -e '
              value = JSON.parse(File.read(ARGV.fetch(0)))
              output, repo, tag, commit, existing_object, script_root, drift = ARGV.drop(1)
              now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
              value["repository"] = repo
              value["releaseTag"] = tag
              value["expectedMainSHA"] = commit
              value["observationStartedAt"] = now
              value["observedAt"] = now
              if existing_object.empty?
                value["evidenceScope"] = "administrator-pretag"
                value["tagAbsentVerified"] = true
                value["existingTagVerified"] = false
                value["existingTagObjectSHA"] = nil
              else
                value["evidenceScope"] = "administrator-posttag"
                value["tagAbsentVerified"] = false
                value["existingTagVerified"] = true
                value["existingTagObjectSHA"] = existing_object
              end
              value["governanceTool"]["sha256"] =
                Digest::SHA256.file(File.join(script_root, "check-release-governance.sh")).hexdigest
              value["governanceDependencies"][0]["sha256"] =
                Digest::SHA256.file(File.join(script_root, "check-release-environment.sh")).hexdigest
              value["governanceDependencies"][1]["sha256"] =
                Digest::SHA256.file(File.join(script_root, "check-release-secrets.sh")).hexdigest
              value["governanceDependencies"][2]["sha256"] =
                Digest::SHA256.file(File.join(script_root, "verify-release-gh-toolchain.rb")).hexdigest
              value["governanceDependencies"][3]["sha256"] =
                Digest::SHA256.file(File.join(script_root, "..", ".github", "release-gh-toolchain.json")).hexdigest
              value["releaseEnvironmentEvidence"]["requiredBranchCommitSHA"] = commit
              value["tagRulesetEvidence"]["repository"] = repo
              value["tagRulesetEvidence"]["releaseTag"] = tag
              value["tagRulesetEvidence"]["releaseRef"] = "refs/tags/#{tag}"
              if File.exist?(drift)
                value["tagRulesetEvidence"]["rulesetUpdatedAt"] = "2026-01-02T00:00:00Z"
              end
              bytes = JSON.pretty_generate(value) + "\\n"
              File.write(output, bytes)
              print bytes
            ' "\(evidenceTemplateURL.path)" "${output}" "${repo}" "${tag}" "${commit}" "${existing_object}" \
              "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" "\(governanceDriftURL.path)"
            """,
            at: repositoryURL.appendingPathComponent("scripts/check-release-governance.sh")
        )
        try executable(
            "#!/bin/bash -p\nexit 0\n",
            at: repositoryURL.appendingPathComponent("scripts/check-release-environment.sh")
        )
        try executable(
            "#!/bin/bash -p\nexit 0\n",
            at: repositoryURL.appendingPathComponent("scripts/check-release-secrets.sh")
        )
        try executable(
            "#!/bin/bash -p\nexit 0\n",
            at: repositoryURL.appendingPathComponent("scripts/check-release-manifest.sh")
        )
        try executable(
            "#!/usr/bin/ruby\nexit 0\n",
            at: repositoryURL.appendingPathComponent("scripts/check-workflow-contract.rb")
        )

        let workflowURL = repositoryURL.appendingPathComponent(".github/workflows/release.yml")
        try FileManager.default.createDirectory(
            at: workflowURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "name: Release\n".write(to: workflowURL, atomically: true, encoding: .utf8)
        try "{}\n".write(
            to: repositoryURL.appendingPathComponent(".github/release-manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try "# Changelog\n".write(
            to: repositoryURL.appendingPathComponent("CHANGELOG.md"),
            atomically: true,
            encoding: .utf8
        )
        let releaseStatusURL = repositoryURL.appendingPathComponent("docs/release-status.md")
        try FileManager.default.createDirectory(
            at: releaseStatusURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Release status\n".write(
            to: releaseStatusURL,
            atomically: true,
            encoding: .utf8
        )
        let infoPlistURL = repositoryURL.appendingPathComponent("Resources/Info.plist")
        try FileManager.default.createDirectory(
            at: infoPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleShortVersionString</key>
          <string>9.8.6</string>
          <key>CFBundleVersion</key>
          <string>7</string>
        </dict>
        </plist>
        """.write(to: infoPlistURL, atomically: true, encoding: .utf8)
        try ".build/\n".write(
            to: repositoryURL.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperDestination.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: validatorDestination.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ghVerifierDestination.path
        )

        var templateData = try JSONSerialization.data(
            withJSONObject: Self.evidenceTemplate(tag: tag),
            options: [.prettyPrinted, .sortedKeys]
        )
        templateData.append(Data("\n".utf8))
        try templateData.write(to: evidenceTemplateURL)
    }

    private func initializeSignedTag() throws {
        let keygen = try Self.run(
            "/usr/bin/ssh-keygen",
            ["-q", "-t", "ed25519", "-N", "", "-f", privateKeyURL.path],
            currentDirectory: rootURL
        )
        try Self.requireSuccess(keygen, "generate fixture SSH signing key")
        let publicKey = try String(
            contentsOf: privateKeyURL.appendingPathExtension("pub"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedURL = repositoryURL.appendingPathComponent(".github/release-signers.allowed")
        try FileManager.default.createDirectory(
            at: allowedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "release@example.com \(publicKey)\n".write(
            to: allowedURL,
            atomically: true,
            encoding: .utf8
        )

        try Self.requireSuccess(try git("init", "--initial-branch=main"), "initialize repository")
        try Self.requireSuccess(try git("config", "user.name", "Vifty Release Test"), "set user name")
        try Self.requireSuccess(
            try git("config", "user.email", "release@example.com"),
            "set user email"
        )
        try Self.requireSuccess(try git("config", "gpg.format", "ssh"), "set SSH signing")
        try Self.requireSuccess(
            try git("config", "gpg.ssh.program", "/usr/bin/ssh-keygen"),
            "set signing program"
        )
        try Self.requireSuccess(
            try git("config", "user.signingkey", privateKeyURL.path),
            "set signing key"
        )
        try Self.requireSuccess(try git("add", "."), "stage base")
        try Self.requireSuccess(try git("commit", "-m", "trusted release base"), "commit base")
        try "{\"tag\":\"\(tag)\"}\n".write(
            to: repositoryURL.appendingPathComponent(".github/release-manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        let infoPlistURL = repositoryURL.appendingPathComponent("Resources/Info.plist")
        var infoPlist = try String(contentsOf: infoPlistURL, encoding: .utf8)
        infoPlist = infoPlist.replacingOccurrences(
            of: "<string>9.8.6</string>",
            with: "<string>\(tag.dropFirst())</string>"
        )
        infoPlist = infoPlist.replacingOccurrences(
            of: "<string>7</string>",
            with: "<string>8</string>"
        )
        try infoPlist.write(to: infoPlistURL, atomically: true, encoding: .utf8)
        try "# Changelog\n\n- Release candidate.\n".write(
            to: repositoryURL.appendingPathComponent("CHANGELOG.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Release status\n\nCandidate prepared.\n".write(
            to: repositoryURL.appendingPathComponent("docs/release-status.md"),
            atomically: true,
            encoding: .utf8
        )
        try Self.requireSuccess(
            try git(
                "add",
                ".github/release-manifest.json",
                "Resources/Info.plist",
                "CHANGELOG.md",
                "docs/release-status.md"
            ),
            "stage exact release-prep candidate"
        )
        try Self.requireSuccess(try git("commit", "-m", "release candidate"), "commit candidate")
        commitSHA = try git("rev-parse", "HEAD").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let evidenceURL = rootURL.appendingPathComponent("signed-evidence.json")
        let governanceResult = try Self.run(
            repositoryURL.appendingPathComponent("scripts/check-release-governance.sh").path,
            [
                "--repo", "Reedtrullz/Vifty",
                "--environment", "release",
                "--branch", "main",
                "--tag", tag,
                "--expected-main", commitSHA,
                "--output", evidenceURL.path
            ],
            currentDirectory: repositoryURL,
            environment: ["VIFTY_FIXTURE_INITIAL_GOVERNANCE": "1"]
        )
        try Self.requireSuccess(governanceResult, "generate signed governance fixture")
        let evidenceBase64 = try Data(contentsOf: evidenceURL).base64EncodedString()
        let messageURL = rootURL.appendingPathComponent("tag-message.txt")
        try """
        Vifty release \(tag)

        Vifty-Release-Governance-Base64: \(evidenceBase64)
        """.write(to: messageURL, atomically: true, encoding: .utf8)
        let taggerTime = ISO8601DateFormatter().string(from: Date())
        let tagResult = try Self.run(
            "/usr/bin/git",
            [
                "-C", repositoryURL.path,
                "-c", "gpg.format=ssh",
                "-c", "gpg.ssh.program=/usr/bin/ssh-keygen",
                "tag", "--sign", "--annotate", "--file", messageURL.path,
                tag, commitSHA
            ],
            currentDirectory: repositoryURL,
            environment: ["GIT_COMMITTER_DATE": taggerTime]
        )
        try Self.requireSuccess(tagResult, "create signed fixture tag")
        tagObjectSHA = try localTagObject()
    }

    private func installFakeGit() throws {
        try executable(
            """
            #!/bin/bash -p
            set -euo pipefail
            printf '%s ' "$@" >> "\(gitLogURL.path)"
            printf '\\n' >> "\(gitLogURL.path)"
            is_push=0
            rewritten=()
            for argument in "$@"; do
              if [[ "${argument}" == "push" ]]; then
                is_push=1
              fi
              if [[ "${argument}" == "https://github.com/Reedtrullz/Vifty.git" ]]; then
                rewritten+=("file://\(remoteURL.path)")
              else
                rewritten+=("${argument}")
              fi
            done
            if [[ "${is_push}" == "1" ]]; then
              [[ -z "${VIFTY_GIT_TOKEN:-}" ]] || {
                /usr/bin/printf '%s\n' 'raw git token leaked through the process environment' >&2
                exit 91
              }
              token_file="${VIFTY_GIT_TOKEN_FILE:-}"
              [[ "${token_file}" == /* && -f "${token_file}" && ! -L "${token_file}" ]] || exit 91
              [[ "$(/usr/bin/stat -f %Lp "${token_file}")" == "600" ]] || exit 91
              [[ "$(< "${token_file}")" == "fixture-token" ]] || exit 91
              /usr/bin/git "${rewritten[@]}"
              : > "\(tagPushedURL.path)"
              if [[ -f "\(modeURL.path)" ]] &&
                 [[ "$(< "\(modeURL.path)")" == "push-response-lost" ]]; then
                exit 1
              fi
              exit 0
            fi
            exec /usr/bin/git "${rewritten[@]}"
            """,
            at: fakeGitURL
        )
    }

    private func installFakeGitHubCLI() throws {
        try executable(
            """
            #!/bin/bash -p
            set -euo pipefail
            printf '%s ' "$@" >> "\(ghLogURL.path)"
            printf '\\n' >> "\(ghLogURL.path)"
            command="${1:-}"
            subcommand="${2:-}"
            mode=""
            [[ ! -f "\(modeURL.path)" ]] || mode="$(< "\(modeURL.path)")"
            case "${command} ${subcommand}" in
              "config get") exit 0 ;;
              "auth token") /usr/bin/printf '%s\\n' fixture-token; exit 0 ;;
              "run list")
                args=" $* "
                if [[ "${args}" == *" .github/workflows/ci.yml "* ]]; then
                  /usr/bin/printf '%s\\n' \
                    '[{"databaseId":1001,"headBranch":"main","headSha":"\(commitSHA)","status":"completed","conclusion":"success","event":"push","url":"https://github.com/Reedtrullz/Vifty/actions/runs/1001"}]'
                  exit 0
                fi
                if [[ ! -f "\(tagPushedURL.path)" || "${mode}" == "tag-push-no-run" ]]; then
                  /usr/bin/printf '%s\\n' '[]'
                  exit 0
                fi
                created_at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
                if [[ "${mode}" == "duplicate-runs" ]]; then
                  /usr/bin/printf \
                    '[{"databaseId":555,"displayTitle":"Release \(tag)","event":"push","headBranch":"\(tag)","headSha":"\(commitSHA)","status":"queued","url":"https://github.com/Reedtrullz/Vifty/actions/runs/555","workflowDatabaseId":77,"workflowName":"Release","createdAt":"%s","attempt":1},{"databaseId":556,"displayTitle":"Release \(tag)","event":"push","headBranch":"\(tag)","headSha":"\(commitSHA)","status":"queued","url":"https://github.com/Reedtrullz/Vifty/actions/runs/556","workflowDatabaseId":77,"workflowName":"Release","createdAt":"%s","attempt":1}]\\n' \
                    "${created_at}" "${created_at}"
                  exit 0
                fi
                /usr/bin/printf \
                  '[{"databaseId":555,"displayTitle":"Release \(tag)","event":"push","headBranch":"\(tag)","headSha":"\(commitSHA)","status":"queued","url":"https://github.com/Reedtrullz/Vifty/actions/runs/555","workflowDatabaseId":77,"workflowName":"Release","createdAt":"%s","attempt":1}]\\n' \
                  "${created_at}"
                exit 0
                ;;
              "api --hostname")
                endpoint=""
                for argument in "$@"; do endpoint="${argument}"; done
                case "${endpoint}" in
                  repos/Reedtrullz/Vifty/branches/main)
                    /usr/bin/printf '%s\\n' '{"commit":{"sha":"\(commitSHA)"}}'
                    ;;
                  repos/Reedtrullz/Vifty/git/ref/tags/\(tag))
                    if [[ -f "\(tagPushedURL.path)" ]]; then
                      object_sha="\(tagObjectSHA)"
                      [[ "${mode}" != "tag-readback-mismatch" ]] || \
                        object_sha="cccccccccccccccccccccccccccccccccccccccc"
                      /usr/bin/printf \
                        'HTTP/2.0 200 OK\\n\\n{"ref":"refs/tags/\(tag)","object":{"type":"tag","sha":"%s"}}\\n' \
                        "${object_sha}"
                    else
                      /usr/bin/printf '%s\\n\\n%s\\n' 'HTTP/2.0 404 Not Found' '{}'
                      exit 1
                    fi
                    ;;
                  repos/Reedtrullz/Vifty/git/ref/heads/\(tag))
                    if [[ "${mode}" == "branch-collision" ]]; then
                      /usr/bin/printf '%s\\n\\n%s\\n' \
                        'HTTP/2.0 200 OK' \
                        '{"ref":"refs/heads/\(tag)","object":{"type":"commit","sha":"\(commitSHA)"}}'
                    else
                      /usr/bin/printf '%s\\n\\n%s\\n' 'HTTP/2.0 404 Not Found' '{}'
                      exit 1
                    fi
                    ;;
                  'repos/Reedtrullz/Vifty/releases?per_page=100')
                    if [[ "${mode}" == "draft-release-collision" ]]; then
                      /usr/bin/printf '%s\\n' '[[{"id":991,"tag_name":"\(tag)","draft":true}]]'
                    else
                      /usr/bin/printf '%s\\n' '[[]]'
                    fi
                    ;;
                  repos/Reedtrullz/Vifty/actions/workflows/release.yml)
                    /usr/bin/printf '%s\\n' \
                      '{"id":77,"path":".github/workflows/release.yml","state":"active"}'
                    ;;
                  repos/Reedtrullz/Vifty/actions/runs/555)
                    head_sha="\(commitSHA)"
                    [[ "${mode}" != "run-mismatch" ]] || \
                      head_sha="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                    run_attempt=1
                    [[ "${mode}" != "run-attempt-two" ]] || run_attempt=2
                    created_at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
                    /usr/bin/printf \
                      '{"id":555,"name":"Release","path":".github/workflows/release.yml","display_title":"Release \(tag)","event":"push","head_branch":"\(tag)","head_sha":"%s","run_attempt":%s,"workflow_id":77,"actor":{"id":12345,"login":"Reedtrullz"},"repository":{"full_name":"Reedtrullz/Vifty"},"created_at":"%s","html_url":"https://github.com/Reedtrullz/Vifty/actions/runs/555"}\\n' \
                      "${head_sha}" "${run_attempt}" "${created_at}"
                    ;;
                  repos/Reedtrullz/Vifty/git/tags/\(tagObjectSHA))
                    /usr/bin/printf '%s\\n' \
                      '{"sha":"\(tagObjectSHA)","tag":"\(tag)","object":{"type":"commit","sha":"\(commitSHA)"}}'
                    ;;
                  *)
                    /usr/bin/printf 'unexpected fake gh API: %s\\n' "${endpoint}" >&2
                    exit 90
                    ;;
                esac
                exit 0
                ;;
            esac
            /usr/bin/printf 'unexpected fake gh invocation: %s\\n' "$*" >&2
            exit 90
            """,
            at: fakeGHURL
        )
    }

    private func executable(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func git(_ arguments: String...) throws -> ReleasePushDispatchProcessResult {
        try Self.run(
            "/usr/bin/git",
            ["-C", repositoryURL.path] + arguments,
            currentDirectory: repositoryURL
        )
    }

    private static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL,
        environment: [String: String] = [:]
    ) throws -> ReleasePushDispatchProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) {
            _, replacement in replacement
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        return ReleasePushDispatchProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            stderr: String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }

    private static func requireSuccess(
        _ result: ReleasePushDispatchProcessResult,
        _ operation: String
    ) throws {
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "ReleasePushDispatchFixture",
                code: Int(result.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(operation) failed\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)"
                ]
            )
        }
    }

    private static func evidenceTemplate(tag: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "status": "passed",
            "releaseAuthorized": true,
            "evidenceScope": "administrator-pretag",
            "apiHost": "github.com",
            "dataSource": "github-api-live",
            "liveAuthenticatedGitHubReadback": true,
            "repository": "Reedtrullz/Vifty",
            "releaseTag": tag,
            "expectedMainSHA": String(repeating: "0", count: 40),
            "observationStartedAt": "2026-07-17T10:00:00Z",
            "observedAt": "2026-07-17T10:00:00Z",
            "repositoryAdminVerified": true,
            "authenticatedActor": ["id": 12345, "login": "Reedtrullz"],
            "tagAbsentVerified": true,
            "existingTagVerified": false,
            "existingTagObjectSHA": NSNull(),
            "governanceTool": [
                "path": "scripts/check-release-governance.sh",
                "sha256": String(repeating: "0", count: 64)
            ],
            "governanceDependencies": [
                [
                    "path": "scripts/check-release-environment.sh",
                    "sha256": String(repeating: "0", count: 64)
                ],
                [
                    "path": "scripts/check-release-secrets.sh",
                    "sha256": String(repeating: "0", count: 64)
                ],
                [
                    "path": "scripts/verify-release-gh-toolchain.rb",
                    "sha256": String(repeating: "0", count: 64)
                ],
                [
                    "path": ".github/release-gh-toolchain.json",
                    "sha256": String(repeating: "0", count: 64)
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
                    "policies": [["type": "tag", "name": "v*"]]
                ],
                "requiredBranch": "main",
                "requiredBranchCommitSHA": String(repeating: "0", count: 40),
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
                "matchedExcludePatterns": [],
                "excludePatternsVerified": true,
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
    }
}
