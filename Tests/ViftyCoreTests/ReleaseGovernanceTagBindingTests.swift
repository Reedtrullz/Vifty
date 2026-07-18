import Foundation
import XCTest

final class ReleaseGovernanceTagBindingTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    func testValidatorAcceptsFreshAdministratorEvidenceBoundToCommittedTool() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        let taggerTime = fixture.observedAt

        let result = try fixture.runValidator(taggerTime: taggerTime)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["releaseTag"] as? String, fixture.tag)
        XCTAssertEqual(summary["releaseCommitSHA"] as? String, fixture.commitSHA)
        XCTAssertEqual(summary["rulesetID"] as? Int, 18_940_029)
        XCTAssertEqual(summary["rulesetUpdatedAt"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(summary["currentUserCanBypass"] as? String, "never")
        XCTAssertEqual(summary["evidenceAgeSeconds"] as? Int, 0)
        XCTAssertEqual(summary["governanceToolSHA256"] as? String, fixture.governanceToolSHA256)
        XCTAssertEqual(summary["evidenceSHA256"] as? String, fixture.evidenceSHA256)
    }

    func testValidatorAcceptsCanonicalNanosecondRulesetRevisionAndRejectsOtherForms() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        var ruleset = try XCTUnwrap(fixture.evidence["tagRulesetEvidence"] as? [String: Any])
        ruleset["rulesetUpdatedAt"] = "2026-01-01T00:00:00.241000000Z"
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()

        var result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        for noncanonical in [
            "2026-01-01T00:00:00.241Z",
            "2026-01-01T02:00:00.241000000+02:00"
        ] {
            ruleset["rulesetUpdatedAt"] = noncanonical
            fixture.evidence["tagRulesetEvidence"] = ruleset
            try fixture.writeEvidence()
            result = try fixture.runValidator(taggerTime: fixture.observedAt)
            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(result.stderr.contains("rulesetUpdatedAt"), result.stderr)
        }
    }

    func testValidatorKeepsFreshnessTimestampsAtCanonicalWholeSecondPrecision() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        fixture.evidence["observationStartedAt"] = "2026-01-01T00:00:00.900000000Z"
        fixture.evidence["observedAt"] = "2026-01-01T00:00:00.100000000Z"
        try fixture.writeEvidence()

        let result = try fixture.runValidator(taggerTime: fixture.observedAt)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("observationStartedAt"), result.stderr)
        XCTAssertTrue(result.stderr.contains("YYYY-MM-DDTHH:MM:SSZ"), result.stderr)
    }

    func testFixtureGovernanceProducerOutputIsMarkedAndRejectedByProductionValidator() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)

        let producer = try fixture.runGovernanceProducer()

        XCTAssertEqual(producer.exitCode, 0, producer.stderr)
        let producedEvidence = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.evidenceURL)) as? [String: Any]
        )
        let producedObservedAt = try XCTUnwrap(producedEvidence["observedAt"] as? String)
        XCTAssertEqual(producedEvidence["status"] as? String, "test-fixture")
        XCTAssertEqual(producedEvidence["releaseAuthorized"] as? Bool, false)
        XCTAssertEqual(producedEvidence["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(producedEvidence["liveAuthenticatedGitHubReadback"] as? Bool, false)
        let environment = try XCTUnwrap(
            producedEvidence["releaseEnvironmentEvidence"] as? [String: Any]
        )
        XCTAssertEqual(environment["requiredBranchCommitSHA"] as? String, fixture.commitSHA)
        let ruleset = try XCTUnwrap(producedEvidence["tagRulesetEvidence"] as? [String: Any])
        XCTAssertEqual(ruleset["excludePatternsVerified"] as? Bool, true)

        let validation = try fixture.runValidator(taggerTime: producedObservedAt)
        XCTAssertEqual(validation.exitCode, 65)
        XCTAssertTrue(validation.stderr.contains("status must be \"passed\""), validation.stderr)
    }

    func testValidatorRejectsEvidenceOutsideExactFreshnessWindow() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        let taggerDate = try XCTUnwrap(Self.utcFormatter.date(from: fixture.observedAt))

        let staleTime = Self.utcFormatter.string(from: taggerDate.addingTimeInterval(-901))
        fixture.evidence["observationStartedAt"] = staleTime
        fixture.evidence["observedAt"] = staleTime
        try fixture.writeEvidence()
        var result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("maximum is 900 seconds"), result.stderr)

        let futureTime = Self.utcFormatter.string(from: taggerDate.addingTimeInterval(1))
        fixture.evidence["observationStartedAt"] = futureTime
        fixture.evidence["observedAt"] = futureTime
        try fixture.writeEvidence()
        result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be later than the tagger time"), result.stderr)
    }

    func testValidatorRecordsAndEnforcesOptionalCurrentFreshness() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        let taggerDate = try XCTUnwrap(Self.utcFormatter.date(from: fixture.observedAt))

        var result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: fixture.observedAt
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(summary["currentFreshnessVerified"] as? Bool, true)
        XCTAssertEqual(summary["currentEvidenceAgeSeconds"] as? Int, 0)
        XCTAssertEqual(summary["validatedAt"] as? String, fixture.observedAt)

        let staleCurrent = Self.utcFormatter.string(from: taggerDate.addingTimeInterval(901))
        result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: staleCurrent
        )
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("old at current time"), result.stderr)
    }

    func testValidatorRequiresExplicitPretagOrExactObjectPosttagStateTuple() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        let tagObjectSHA = String(repeating: "a", count: 40)
        fixture.evidence["evidenceScope"] = "administrator-posttag"
        fixture.evidence["tagAbsentVerified"] = false
        fixture.evidence["existingTagVerified"] = true
        fixture.evidence["existingTagObjectSHA"] = tagObjectSHA
        try fixture.writeEvidence()

        var result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: fixture.observedAt,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(summary["evidenceScope"] as? String, "administrator-posttag")
        XCTAssertEqual(summary["tagAbsentVerified"] as? Bool, false)
        XCTAssertEqual(summary["existingTagVerified"] as? Bool, true)
        XCTAssertEqual(summary["existingTagObjectSHA"] as? String, tagObjectSHA)

        result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("evidenceScope"), result.stderr)

        fixture.evidence["evidenceScope"] = "administrator-pretag"
        fixture.evidence["tagAbsentVerified"] = true
        fixture.evidence["existingTagVerified"] = false
        fixture.evidence["existingTagObjectSHA"] = NSNull()
        try fixture.writeEvidence()
        result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: fixture.observedAt,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("evidenceScope"), result.stderr)
    }

    func testPosttagValidatorEnforcesActualTaggerChronologyAndFreshCurrentTime() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        let tagObjectSHA = String(repeating: "a", count: 40)
        let taggerDate = try XCTUnwrap(Self.utcFormatter.date(from: fixture.observedAt))
        let observedAfterTag = Self.utcFormatter.string(
            from: taggerDate.addingTimeInterval(1)
        )
        let currentAfterObservation = Self.utcFormatter.string(
            from: taggerDate.addingTimeInterval(2)
        )
        fixture.evidence["evidenceScope"] = "administrator-posttag"
        fixture.evidence["tagAbsentVerified"] = false
        fixture.evidence["existingTagVerified"] = true
        fixture.evidence["existingTagObjectSHA"] = tagObjectSHA
        fixture.evidence["observationStartedAt"] = observedAfterTag
        fixture.evidence["observedAt"] = observedAfterTag
        try fixture.writeEvidence()

        var result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: currentAfterObservation,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("--current-time is required"), result.stderr)

        let beforeTag = Self.utcFormatter.string(from: taggerDate.addingTimeInterval(-1))
        fixture.evidence["observationStartedAt"] = beforeTag
        fixture.evidence["observedAt"] = beforeTag
        try fixture.writeEvidence()
        result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: currentAfterObservation,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be earlier than the tagger time"), result.stderr)

        fixture.evidence["observationStartedAt"] = observedAfterTag
        fixture.evidence["observedAt"] = observedAfterTag
        try fixture.writeEvidence()
        let staleCurrent = Self.utcFormatter.string(
            from: taggerDate.addingTimeInterval(902)
        )
        result = try fixture.runValidator(
            taggerTime: fixture.observedAt,
            currentTime: staleCurrent,
            expectedExistingTagObject: tagObjectSHA
        )
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("old at current time"), result.stderr)
    }

    func testValidatorRejectsToolOrNestedProtectedMainDrift() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        fixture.evidence["governanceTool"] = [
            "path": "scripts/check-release-governance.sh",
            "sha256": String(repeating: "f", count: 64)
        ]
        try fixture.writeEvidence()

        var result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("governanceTool.sha256"), result.stderr)

        fixture.evidence["governanceTool"] = [
            "path": "scripts/check-release-governance.sh",
            "sha256": fixture.governanceToolSHA256
        ]
        var environment = try XCTUnwrap(
            fixture.evidence["releaseEnvironmentEvidence"] as? [String: Any]
        )
        environment["requiredBranchCommitSHA"] = String(repeating: "b", count: 40)
        fixture.evidence["releaseEnvironmentEvidence"] = environment
        try fixture.writeEvidence()

        result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("requiredBranchCommitSHA"), result.stderr)
    }

    func testValidatorRejectsNonExplicitBypassEvidence() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        var ruleset = try XCTUnwrap(fixture.evidence["tagRulesetEvidence"] as? [String: Any])
        ruleset.removeValue(forKey: "bypassActors")
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()

        let result = try fixture.runValidator(taggerTime: fixture.observedAt)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("explicitly present empty array"), result.stderr)
    }

    func testValidatorRejectsUnverifiedRulesetExclusions() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        var ruleset = try XCTUnwrap(fixture.evidence["tagRulesetEvidence"] as? [String: Any])
        ruleset["excludePatternsVerified"] = false
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()

        let result = try fixture.runValidator(taggerTime: fixture.observedAt)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("excludePatternsVerified"), result.stderr)
    }

    func testValidatorRejectsUnsupportedRulesetPatternEvidence() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        var ruleset = try XCTUnwrap(fixture.evidence["tagRulesetEvidence"] as? [String: Any])
        ruleset["matchedIncludePatterns"] = ["refs/tags/{v*,release-*}"]
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()

        let result = try fixture.runValidator(taggerTime: fixture.observedAt)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("matchedIncludePatterns"), result.stderr)
    }

    func testValidatorRejectsMalformedAuthenticatedActorIdentity() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        fixture.evidence["authenticatedActor"] = ["id": 0, "login": ""]
        try fixture.writeEvidence()

        let result = try fixture.runValidator(taggerTime: fixture.observedAt)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("authenticatedActor"), result.stderr)
    }

    func testValidatorRejectsRulesetRevisionOrCurrentActorBypassDrift() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        var ruleset = try XCTUnwrap(fixture.evidence["tagRulesetEvidence"] as? [String: Any])
        ruleset["currentUserCanBypass"] = "always"
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()

        var result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("currentUserCanBypass"), result.stderr)

        ruleset["currentUserCanBypass"] = "never"
        ruleset["rulesetUpdatedAt"] = "not-a-timestamp"
        fixture.evidence["tagRulesetEvidence"] = ruleset
        try fixture.writeEvidence()
        result = try fixture.runValidator(taggerTime: fixture.observedAt)
        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("rulesetUpdatedAt"), result.stderr)
    }

    func testTagCreatorRejectsCallerSuppliedGovernanceEvidence() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)

        let result = try fixture.runTagCreatorWithCallerEvidence()

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("unknown argument: --evidence"), result.stderr)
        let localTag = try fixture.git("show-ref", "--verify", "refs/tags/\(fixture.tag)")
        XCTAssertNotEqual(localTag.exitCode, 0)
    }

    func testReleasePrepDiffAcceptsExactlyFourRegularFileModifications() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(
            result.stdout.contains(
                "Release prep diff OK: .github/release-manifest.json, CHANGELOG.md, Resources/Info.plist, docs/release-status.md"
            ),
            result.stdout
        )
        let rawDiff = try fixture.releasePrepRawDiff()
        let expectedPaths = [
            ".github/release-manifest.json",
            "CHANGELOG.md",
            "Resources/Info.plist",
            "docs/release-status.md"
        ]
        XCTAssertEqual(rawDiff.count, expectedPaths.count, rawDiff.joined(separator: "\n"))
        for path in expectedPaths {
            XCTAssertTrue(
                rawDiff.contains { $0.hasPrefix(":100644 100644 ") && $0.hasSuffix(" M\t\(path)") },
                "expected a regular-file modification for \(path):\n\(rawDiff.joined(separator: "\n"))"
            )
        }
    }

    func testReleasePrepDiffRejectsAddedPath() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithAddedPath()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("path must be a modification"), result.stderr)
        XCTAssertTrue(result.stderr.contains("unexpected-release-input.txt"), result.stderr)
    }

    func testReleasePrepDiffRejectsForbiddenTrackedModification() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithForbiddenTrackedModification()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("changes forbidden paths: Package.swift"), result.stderr)
    }

    func testReleasePrepDiffRejectsAllowedPathChangedToSymlink() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithSymlinkedReleaseStatus()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("docs/release-status.md"), result.stderr)
        XCTAssertTrue(
            result.stderr.contains("path must be a modification") ||
                result.stderr.contains("path mode/type changed"),
            result.stderr
        )
    }

    func testReleasePrepDiffRejectsMissingRequiredPath() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithoutReleaseStatus()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains("release-prep commit must change: docs/release-status.md"),
            result.stderr
        )
    }

    func testReleasePrepDiffRejectsUnrelatedInfoPlistMutation() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithUnrelatedInfoPlistMutation()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains(
                "Resources/Info.plist may change only CFBundleShortVersionString and CFBundleVersion"
            ),
            result.stderr
        )
    }

    func testReleasePrepDiffRejectsUnchangedInfoPlistBuild() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithUnchangedBundleBuild()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains("Resources/Info.plist CFBundleVersion must change"),
            result.stderr
        )
    }

    func testReleasePrepDiffRejectsMissingInfoPlistVersionKey() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithMissingBundleShortVersion()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(
            result.stderr.contains(
                "Resources/Info.plist CFBundleShortVersionString values must both be strings"
            ),
            result.stderr
        )
    }

    func testReleasePrepDiffRejectsMalformedInfoPlist() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot)
        try fixture.amendCandidateWithMalformedInfoPlist()

        let result = try fixture.runReleasePrepDiffCheck()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("release-prep Resources/Info.plist is malformed"),
            result.stderr
        )
    }

    func testTagCreatorRejectsTamperedPinnedGitHubCLIBeforeTokenUse() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)
        try fixture.tamperHermeticGitHubCLI()

        let result = try fixture.runTagCreator()

        XCTAssertEqual(result.exitCode, 65, result.stdout)
        XCTAssertTrue(result.stderr.contains("SHA-256 does not match"), result.stderr)
        XCTAssertFalse(try fixture.localTagExists())
    }

    func testTagCreatorRejectsReleaseToolChangedFromExactFirstParent() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)
        try fixture.commitProtectedReleaseToolDrift()

        let result = try fixture.runTagCreator()

        XCTAssertEqual(result.exitCode, 65, result.stdout)
        XCTAssertTrue(result.stderr.contains("protected release tooling must be byte-identical"), result.stderr)
        XCTAssertFalse(try fixture.localTagExists())
    }

    func testTagCreatorInternallyAcquiresLiveEvidenceSignsRechecksAndDoesNotPush() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)

        let result = try fixture.runTagCreator()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("The tag was not pushed."), result.stdout)
        XCTAssertEqual(
            try fixture.git("rev-parse", "\(fixture.tag)^{commit}").stdout
                .trimmingCharacters(in: .whitespacesAndNewlines),
            fixture.commitSHA
        )
        let evidence = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.evidenceURL)) as? [String: Any]
        )
        XCTAssertEqual(evidence["dataSource"] as? String, "github-api-live")
        XCTAssertEqual(evidence["liveAuthenticatedGitHubReadback"] as? Bool, true)
        XCTAssertEqual(evidence["apiHost"] as? String, "github.com")
        let remoteTags = try fixture.git("ls-remote", "--tags", "origin", "refs/tags/\(fixture.tag)")
        XCTAssertEqual(remoteTags.exitCode, 0, remoteTags.stderr)
        XCTAssertTrue(remoteTags.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testTagCreatorRejectsUntrustedConfiguredSigningProgram() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)
        let hostileSigningProgram = fixture.rootURL.appendingPathComponent("hostile-ssh-sign")
        try "#!/bin/sh\nexit 0\n".write(to: hostileSigningProgram, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: hostileSigningProgram.path
        )
        let hostileConfig = try fixture.git("config", "gpg.ssh.program", hostileSigningProgram.path)
        XCTAssertEqual(hostileConfig.exitCode, 0, hostileConfig.stderr)

        let result = try fixture.runTagCreator()

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("unsupported SSH signing program"), result.stderr)
        let localTag = try fixture.git("show-ref", "--verify", "refs/tags/\(fixture.tag)")
        XCTAssertNotEqual(localTag.exitCode, 0)
    }

    func testTagCreatorRejectsEvidenceOutputInsideGitMetadataWithoutCreatingTag() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)

        let result = try fixture.runTagCreator(
            evidenceOutput: ".git/refs/tags/\(fixture.tag)"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("evidence output must not be inside Git metadata"), result.stderr)
        let localTag = try fixture.git("show-ref", "--verify", "refs/tags/\(fixture.tag)")
        XCTAssertNotEqual(localTag.exitCode, 0)
    }

    func testTagCreatorIgnoresRepositoryGitHooksAndFSMonitorConfiguration() throws {
        let fixture = try GovernanceTagFixture(sourceRoot: repositoryRoot, withSigningRemote: true)
        let marker = fixture.rootURL.appendingPathComponent("untrusted-git-callback-ran")
        let callback = fixture.rootURL.appendingPathComponent("untrusted-git-callback")
        try """
        #!/bin/sh
        /usr/bin/touch "\(marker.path)"
        exit 1
        """.write(to: callback, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: callback.path)

        let hooks = fixture.repositoryURL.appendingPathComponent(".git/hooks", isDirectory: true)
        let referenceTransaction = hooks.appendingPathComponent("reference-transaction")
        try FileManager.default.copyItem(at: callback, to: referenceTransaction)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: referenceTransaction.path
        )
        let configured = try fixture.git("config", "core.fsmonitor", callback.path)
        XCTAssertEqual(configured.exitCode, 0, configured.stderr)

        let result = try fixture.runTagCreator()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: marker.path),
            "release tagging executed a repository-controlled Git hook or fsmonitor callback"
        )
    }

    func testProtectedEntrypointSuppressesExportedFunctionsForDirectAndExplicitPrivilegedLaunch() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let marker = scratch.appendingPathComponent("imported-function-ran")
        let script = repositoryRoot.appendingPathComponent("scripts/create-signed-release-tag.sh")
        let attackHarness = #"""
        exec() { /usr/bin/touch "${VIFTY_FUNCTION_MARKER}"; }
        builtin() { /usr/bin/touch "${VIFTY_FUNCTION_MARKER}"; }
        dirname() { /usr/bin/touch "${VIFTY_FUNCTION_MARKER}"; }
        export -f exec builtin dirname
        case "$1" in
          direct) "$2" --help >/dev/null 2>&1 ;;
          privileged) /bin/bash -p "$2" --help >/dev/null 2>&1 ;;
          *) exit 64 ;;
        esac
        """#

        for mode in ["direct", "privileged"] {
            if FileManager.default.fileExists(atPath: marker.path) {
                try FileManager.default.removeItem(at: marker)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", attackHarness, "vifty-release-launch-test", mode, script.path]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["VIFTY_FUNCTION_MARKER": marker.path],
                uniquingKeysWith: { _, new in new }
            )
            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(process.terminationStatus, 0, "\(mode) protected launch failed")
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: marker.path),
                "\(mode) launch imported and executed an exported shell function"
            )
        }
    }

    fileprivate static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()
}

private struct GovernanceTagProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class GovernanceTagFixture {
    let tag = "v9.8.7"
    let rootURL: URL
    let repositoryURL: URL
    let evidenceURL: URL
    let allowedSignersURL: URL
    private(set) var commitSHA = ""
    private(set) var governanceToolSHA256 = ""
    private(set) var environmentToolSHA256 = ""
    private(set) var secretsToolSHA256 = ""
    private(set) var ghVerifierSHA256 = ""
    private(set) var ghPolicySHA256 = ""
    let observedAt: String
    var evidence: [String: Any]

    private let sourceRoot: URL
    private let privateKeyURL: URL
    private var hermeticGHURL: URL?

    init(sourceRoot: URL, withSigningRemote: Bool = false) throws {
        self.sourceRoot = sourceRoot
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-governance-tag-\(UUID().uuidString)", isDirectory: true)
        repositoryURL = rootURL.appendingPathComponent("repository", isDirectory: true)
        evidenceURL = rootURL.appendingPathComponent("governance-evidence.json")
        privateKeyURL = rootURL.appendingPathComponent("signing-key")
        allowedSignersURL = repositoryURL.appendingPathComponent(".github/release-signers.allowed")
        observedAt = ReleaseGovernanceTagBindingTests.utcFormatter.string(from: Date())
        evidence = [:]

        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try copyReleaseTagTools()
        if withSigningRemote {
            try installHermeticGitHubCLI()
        }

        let keygen = try Self.run(
            "/usr/bin/ssh-keygen",
            ["-q", "-t", "ed25519", "-N", "", "-f", privateKeyURL.path],
            currentDirectory: rootURL
        )
        try Self.requireSuccess(keygen, "generate fixture SSH signing key")
        let publicKey = try String(contentsOf: privateKeyURL.appendingPathExtension("pub"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try "release@example.com \(publicKey)\n".write(
            to: allowedSignersURL,
            atomically: true,
            encoding: .utf8
        )

        try Self.requireSuccess(try git("init", "--initial-branch=main"), "initialize fixture repository")
        try Self.requireSuccess(try git("config", "user.name", "Vifty Release Test"), "configure git user")
        try Self.requireSuccess(try git("config", "user.email", "release@example.com"), "configure git email")
        try Self.requireSuccess(try git("config", "gpg.format", "ssh"), "configure SSH signing")
        try Self.requireSuccess(
            try git("config", "gpg.ssh.program", "/usr/bin/ssh-keygen"),
            "configure fixture SSH signing program"
        )
        try Self.requireSuccess(try git("config", "commit.gpgsign", "false"), "disable fixture commit signing")
        try Self.requireSuccess(try git("config", "user.signingkey", privateKeyURL.path), "configure signing key")
        try Self.requireSuccess(
            try git("config", "gpg.ssh.allowedSignersFile", allowedSignersURL.path),
            "configure allowed signers"
        )
        try Self.requireSuccess(try git("add", "."), "stage fixture files")
        try Self.requireSuccess(
            try git("commit", "-m", "Fixture trusted release base"),
            "commit trusted fixture base"
        )
        try prepareReleaseCandidate()
        try Self.requireSuccess(
            try git(
                "add",
                ".github/release-manifest.json",
                "CHANGELOG.md",
                "Resources/Info.plist",
                "docs/release-status.md"
            ),
            "stage fixture release candidate"
        )
        try Self.requireSuccess(
            try git("commit", "-m", "Fixture release candidate"),
            "commit fixture release candidate"
        )
        commitSHA = try git("rev-parse", "HEAD").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        governanceToolSHA256 = try Self.sha256(
            repositoryURL.appendingPathComponent("scripts/check-release-governance.sh")
        )
        environmentToolSHA256 = try Self.sha256(
            repositoryURL.appendingPathComponent("scripts/check-release-environment.sh")
        )
        secretsToolSHA256 = try Self.sha256(
            repositoryURL.appendingPathComponent("scripts/check-release-secrets.sh")
        )
        ghVerifierSHA256 = try Self.sha256(
            repositoryURL.appendingPathComponent("scripts/verify-release-gh-toolchain.rb")
        )
        ghPolicySHA256 = try Self.sha256(
            repositoryURL.appendingPathComponent(".github/release-gh-toolchain.json")
        )

        if withSigningRemote {
            let remoteURL = rootURL.appendingPathComponent("remote.git", isDirectory: true)
            try Self.requireSuccess(
                try Self.run("/usr/bin/git", ["init", "--bare", remoteURL.path], currentDirectory: rootURL),
                "initialize fixture remote"
            )
            let canonicalRemote = "https://github.com/Reedtrullz/Vifty.git"
            try Self.requireSuccess(try git("remote", "add", "origin", canonicalRemote), "add fixture remote")
            try Self.requireSuccess(
                try git("config", "url.\(remoteURL.absoluteString).insteadOf", canonicalRemote),
                "redirect fixture canonical remote"
            )
            try Self.requireSuccess(try git("push", "--set-upstream", "origin", "main"), "push fixture main")
        }

        evidence = Self.makeEvidence(
            tag: tag,
            commitSHA: commitSHA,
            observedAt: observedAt,
            governanceToolSHA256: governanceToolSHA256,
            environmentToolSHA256: environmentToolSHA256,
            secretsToolSHA256: secretsToolSHA256,
            ghVerifierSHA256: ghVerifierSHA256,
            ghPolicySHA256: ghPolicySHA256
        )
        try writeEvidence()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    var evidenceSHA256: String {
        (try? Self.sha256(evidenceURL)) ?? ""
    }

    func writeEvidence() throws {
        var data = try JSONSerialization.data(
            withJSONObject: evidence,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(Data("\n".utf8))
        try data.write(to: evidenceURL)
    }

    func runValidator(
        taggerTime: String,
        currentTime: String? = nil,
        expectedExistingTagObject: String? = nil
    ) throws -> GovernanceTagProcessResult {
        var arguments = [
            "--root", repositoryURL.path,
            "--evidence", evidenceURL.path,
            "--repository", "Reedtrullz/Vifty",
            "--tag", tag,
            "--commit", commitSHA,
            "--tagger-time", taggerTime
        ]
        if let currentTime {
            arguments += ["--current-time", currentTime]
        }
        if let expectedExistingTagObject {
            arguments += ["--expected-existing-tag-object", expectedExistingTagObject]
        }
        return try Self.run(
            "/usr/bin/ruby",
            [sourceRoot.appendingPathComponent("scripts/validate-release-governance-evidence.rb").path] + arguments,
            currentDirectory: repositoryURL
        )
    }

    func runTagCreator(evidenceOutput: String? = nil) throws -> GovernanceTagProcessResult {
        let script = repositoryURL.appendingPathComponent("scripts/create-signed-release-tag.sh")
        return try Self.run(
            script.path,
            [
                "--tag", tag,
                "--commit", commitSHA,
                "--evidence-output", evidenceOutput ?? evidenceURL.path
            ],
            currentDirectory: repositoryURL,
            environment: [
                "VIFTY_RELEASE_TAG_ROOT": repositoryURL.path,
                "GH_TOKEN": "fixture-token"
            ]
        )
    }

    func runTagCreatorWithCallerEvidence() throws -> GovernanceTagProcessResult {
        let script = repositoryURL.appendingPathComponent("scripts/create-signed-release-tag.sh")
        return try Self.run(
            script.path,
            ["--tag", tag, "--commit", commitSHA, "--evidence", evidenceURL.path],
            currentDirectory: repositoryURL,
            environment: [
                "VIFTY_RELEASE_TAG_ROOT": repositoryURL.path,
                "GH_TOKEN": "fixture-token"
            ]
        )
    }

    func runReleasePrepDiffCheck() throws -> GovernanceTagProcessResult {
        try Self.run(
            repositoryURL.appendingPathComponent("scripts/check-release-prep-diff.sh").path,
            ["--root", repositoryURL.path, "--commit", commitSHA],
            currentDirectory: repositoryURL
        )
    }

    func releasePrepRawDiff() throws -> [String] {
        let result = try git(
            "diff-tree",
            "--raw",
            "--no-commit-id",
            "--no-renames",
            "-r",
            "\(commitSHA)^1",
            commitSHA,
            "--"
        )
        try Self.requireSuccess(result, "read release-prep raw diff")
        return result.stdout.split(separator: "\n").map(String.init)
    }

    func amendCandidateWithAddedPath() throws {
        let addedURL = repositoryURL.appendingPathComponent("unexpected-release-input.txt")
        try "unexpected release input\n".write(to: addedURL, atomically: true, encoding: .utf8)
        try amendCandidate(staging: ["unexpected-release-input.txt"])
    }

    func amendCandidateWithForbiddenTrackedModification() throws {
        let packageURL = repositoryURL.appendingPathComponent("Package.swift")
        try Self.append("\n// forbidden release-prep drift\n", to: packageURL)
        try amendCandidate(staging: ["Package.swift"])
    }

    func amendCandidateWithSymlinkedReleaseStatus() throws {
        let releaseStatusURL = repositoryURL.appendingPathComponent("docs/release-status.md")
        try FileManager.default.removeItem(at: releaseStatusURL)
        try FileManager.default.createSymbolicLink(
            atPath: releaseStatusURL.path,
            withDestinationPath: "../CHANGELOG.md"
        )
        try amendCandidate(staging: ["docs/release-status.md"])
    }

    func amendCandidateWithoutReleaseStatus() throws {
        try Self.requireSuccess(
            try git("restore", "--source=HEAD^", "--", "docs/release-status.md"),
            "restore required release-status path from first parent"
        )
        try amendCandidate(staging: ["docs/release-status.md"])
    }

    func amendCandidateWithUnrelatedInfoPlistMutation() throws {
        try editInfoPlist("Set :CFBundleName Vifty Fixture Tampered")
        try amendCandidate(staging: ["Resources/Info.plist"])
    }

    func amendCandidateWithUnchangedBundleBuild() throws {
        let parentPlist = try git("show", "HEAD^:Resources/Info.plist")
        try Self.requireSuccess(parentPlist, "read first-parent fixture Info.plist")
        let parentProperties = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(parentPlist.stdout.utf8),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let parentBuild = try XCTUnwrap(parentProperties["CFBundleVersion"] as? String)
        try editInfoPlist("Set :CFBundleVersion \(parentBuild)")
        try amendCandidate(staging: ["Resources/Info.plist"])
    }

    func amendCandidateWithMissingBundleShortVersion() throws {
        try editInfoPlist("Delete :CFBundleShortVersionString")
        try amendCandidate(staging: ["Resources/Info.plist"])
    }

    func amendCandidateWithMalformedInfoPlist() throws {
        let infoPlistURL = repositoryURL.appendingPathComponent("Resources/Info.plist")
        try "<plist><dict><key>CFBundleVersion</key>\n".write(
            to: infoPlistURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: infoPlistURL.path
        )
        try amendCandidate(staging: ["Resources/Info.plist"])
    }

    func tamperHermeticGitHubCLI() throws {
        let url = try XCTUnwrap(hermeticGHURL)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n# tampered\n".utf8))
    }

    func commitProtectedReleaseToolDrift() throws {
        let toolURL = repositoryURL.appendingPathComponent("scripts/check-workflow-contract.rb")
        let handle = try FileHandle(forWritingTo: toolURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n# release-prep drift\n".utf8))
        try Self.requireSuccess(try git("add", "scripts/check-workflow-contract.rb"), "stage protected drift")
        try Self.requireSuccess(try git("commit", "-m", "mutate protected release tool"), "commit protected drift")
        commitSHA = try git("rev-parse", "HEAD").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.requireSuccess(try git("push", "origin", "main"), "push protected drift fixture")
    }

    func localTagExists() throws -> Bool {
        try git("rev-parse", "--verify", "refs/tags/\(tag)^{tag}").exitCode == 0
    }

    func runGovernanceProducer() throws -> GovernanceTagProcessResult {
        let fixtureRoot = rootURL.appendingPathComponent("producer-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let repoURL = fixtureRoot.appendingPathComponent("repo.json")
        let branchURL = fixtureRoot.appendingPathComponent("branch.json")
        let environmentURL = fixtureRoot.appendingPathComponent("environment.json")
        let branchProtectionURL = fixtureRoot.appendingPathComponent("branch-protection.json")
        let repositorySecretsURL = fixtureRoot.appendingPathComponent("repository-secrets.tsv")
        let environmentSecretsURL = fixtureRoot.appendingPathComponent("environment-secrets.tsv")
        let rulesetURL = fixtureRoot.appendingPathComponent("ruleset.json")
        let remoteTagsURL = fixtureRoot.appendingPathComponent("remote-tags.txt")

        try Self.writeJSON([
            "full_name": "Reedtrullz/Vifty",
            "permissions": ["admin": true]
        ], to: repoURL)
        try Self.writeJSON([
            "name": "main",
            "protected": true,
            "commit": ["sha": commitSHA]
        ], to: branchURL)
        try Self.writeJSON([
            "name": "release",
            "can_admins_bypass": false,
            "protection_rules": [["type": "branch_policy"]],
            "deployment_branch_policy": [
                "protected_branches": false,
                "custom_branch_policies": true
            ],
            "deployment_branch_policies": [
                "total_count": 1,
                "branch_policies": [
                    ["type": "tag", "name": "v*"]
                ]
            ]
        ], to: environmentURL)
        try Self.writeJSON([
            "name": "main",
            "protected": true,
            "commitSHA": commitSHA,
            "protection": [
                "required_status_checks": [
                    "strict": true,
                    "contexts": ["SwiftPM checks"],
                    "checks": [["context": "SwiftPM checks", "app_id": 15_368]]
                ],
                "enforce_admins": ["enabled": true],
                "required_pull_request_reviews": [
                    "dismiss_stale_reviews": false,
                    "require_code_owner_reviews": false,
                    "required_approving_review_count": 0,
                    "require_last_push_approval": false
                ],
                "required_conversation_resolution": ["enabled": true],
                "allow_force_pushes": ["enabled": false],
                "allow_deletions": ["enabled": false]
            ]
        ], to: branchProtectionURL)
        try """
        APPLE_TEAM_ID\t2026-07-17T10:00:00Z
        APPLE_ID\t2026-07-17T10:00:00Z
        APPLE_APP_SPECIFIC_PASSWORD\t2026-07-17T10:00:00Z
        DEVELOPER_ID_APPLICATION_IDENTITY\t2026-07-17T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64\t2026-07-17T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD\t2026-07-17T10:00:00Z
        """.write(to: repositorySecretsURL, atomically: true, encoding: .utf8)
        try "".write(to: environmentSecretsURL, atomically: true, encoding: .utf8)
        try Self.writeJSON([[
            "id": 18_940_029,
            "name": "Immutable Vifty release tags",
            "target": "tag",
            "enforcement": "active",
            "conditions": [
                "ref_name": [
                    "include": ["refs/tags/v*"],
                    "exclude": []
                ]
            ],
            "bypass_actors": [],
            "updated_at": "2026-01-01T00:00:00Z",
            "current_user_can_bypass": "never",
            "rules": [["type": "update"], ["type": "deletion"]]
        ]], to: rulesetURL)
        try "".write(to: remoteTagsURL, atomically: true, encoding: .utf8)

        return try Self.run(
            sourceRoot.appendingPathComponent("scripts/check-release-governance.sh").path,
            [
                "--tag", tag,
                "--expected-main", commitSHA,
                "--output", evidenceURL.path,
                "--repo-json-file", repoURL.path,
                "--branch-json-file", branchURL.path,
                "--environment-json-file", environmentURL.path,
                "--branch-protection-json-file", branchProtectionURL.path,
                "--repository-secret-list-file", repositorySecretsURL.path,
                "--environment-secret-list-file", environmentSecretsURL.path,
                "--ruleset-json-file", rulesetURL.path,
                "--remote-tag-refs-file", remoteTagsURL.path
            ],
            currentDirectory: repositoryURL
        )
    }

    func git(_ arguments: String...) throws -> GovernanceTagProcessResult {
        try Self.run("/usr/bin/git", arguments, currentDirectory: repositoryURL)
    }

    private func copyReleaseTagTools() throws {
        let executablePaths = [
            "scripts/check-release-governance.sh",
            "scripts/check-release-environment.sh",
            "scripts/check-release-secrets.sh",
            "scripts/validate-release-governance-evidence.rb",
            "scripts/create-signed-release-tag.sh",
            "scripts/push-and-dispatch-signed-release-tag.sh",
            "scripts/check-release-manifest.sh",
            "scripts/check-release-manifest-history-from-git.sh",
            "scripts/check-release-manifest-history.rb",
            "scripts/check-release-prep-diff.sh",
            "scripts/check-workflow-contract.rb",
            "scripts/run-actionlint.sh",
            "scripts/release-candidate-inventory.rb",
            "scripts/check-release-provenance.sh",
            "scripts/verify-release-gh-toolchain.rb",
            "scripts/lib/release_artifact_contract.rb",
            "scripts/render-release-facts.sh",
            "scripts/sign-release-candidate.sh",
            "scripts/validate-release-metadata.sh",
            "scripts/verify-release-artifact.sh",
            "scripts/write-release-checklist.sh"
        ]
        let regularPaths = [
            ".github/release-manifest.json",
            ".github/release-gh-toolchain.json",
            ".github/workflows/ci.yml",
            ".github/workflows/release.yml",
            "CHANGELOG.md",
            "docs/schemas/release-manifest.schema.json",
            "docs/release-status.md",
            "Resources/Info.plist",
            "Resources/tech.reidar.vifty.daemon.plist",
            "Casks/vifty.rb",
            "Package.swift"
        ]
        for relativePath in executablePaths + regularPaths {
            let source = sourceRoot.appendingPathComponent(relativePath)
            let destination = repositoryURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
            if executablePaths.contains(relativePath) {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: destination.path
                )
            } else {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: destination.path
                )
            }
        }
        try FileManager.default.createDirectory(
            at: allowedSignersURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func prepareReleaseCandidate() throws {
        let manifestURL = repositoryURL.appendingPathComponent(".github/release-manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
        let publishedBuild = try XCTUnwrap(published["build"] as? Int)
        let baseInfoPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: repositoryURL.appendingPathComponent("Resources/Info.plist")),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let baseBuildString = try XCTUnwrap(baseInfoPlist["CFBundleVersion"] as? String)
        let baseBuild = try XCTUnwrap(Int(baseBuildString))
        let candidateBuild = max(publishedBuild, baseBuild) + 1
        manifest["candidate"] = [
            "version": String(tag.dropFirst()),
            "build": candidateBuild,
            "tag": tag,
            "artifact": "Vifty-\(tag).zip",
            "checksumAsset": "Vifty-\(tag).zip.sha256",
            "artifactSummary": "Vifty-\(tag)-artifact-summary.json",
            "releaseChecklist": "Vifty-\(tag)-release-checklist.md",
            "sha256": NSNull(),
            "artifactTrust": "pending",
            "signingTrust": "pending",
            "tagTrust": "signed-required",
            "installedReleaseReview": "pending",
            "manualCompatibility": "pending",
            "manualCompatibilityScope": NSNull()
        ]
        var manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        manifestData.append(Data("\n".utf8))
        try manifestData.write(to: manifestURL)

        let infoPlistURL = repositoryURL.appendingPathComponent("Resources/Info.plist")
        try Self.requireSuccess(
            try Self.run(
                "/usr/libexec/PlistBuddy",
                ["-c", "Set :CFBundleShortVersionString \(tag.dropFirst())", infoPlistURL.path],
                currentDirectory: repositoryURL
            ),
            "set fixture candidate version"
        )
        try Self.requireSuccess(
            try Self.run(
                "/usr/libexec/PlistBuddy",
                ["-c", "Set :CFBundleVersion \(candidateBuild)", infoPlistURL.path],
                currentDirectory: repositoryURL
            ),
            "set fixture candidate build"
        )

        try Self.append(
            "\n## \(tag) fixture release prep\n\n- Exercise the signed release-prep boundary.\n",
            to: repositoryURL.appendingPathComponent("CHANGELOG.md")
        )
        try Self.append(
            "\nFixture candidate \(tag) remains pending until the trusted release workflow completes.\n",
            to: repositoryURL.appendingPathComponent("docs/release-status.md")
        )
    }

    private func amendCandidate(staging paths: [String]) throws {
        try Self.requireSuccess(
            try Self.run(
                "/usr/bin/git",
                ["add", "--"] + paths,
                currentDirectory: repositoryURL
            ),
            "stage amended release candidate"
        )
        try Self.requireSuccess(
            try git("commit", "--amend", "--no-edit"),
            "amend fixture release candidate"
        )
        commitSHA = try git("rev-parse", "HEAD").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func editInfoPlist(_ command: String) throws {
        try Self.requireSuccess(
            try Self.run(
                "/usr/libexec/PlistBuddy",
                [
                    "-c",
                    command,
                    repositoryURL.appendingPathComponent("Resources/Info.plist").path
                ],
                currentDirectory: repositoryURL
            ),
            "edit fixture Info.plist"
        )
    }

    private func installHermeticGitHubCLI() throws {
        let fakeBinURL = rootURL.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBinURL, withIntermediateDirectories: true)
        let fakeGHURL = fakeBinURL.appendingPathComponent("gh")
        hermeticGHURL = fakeGHURL
        let fakeGH = #"""
        #!/bin/bash
        set -euo pipefail
        args=" $* "
        if [[ "${args}" == *" version "* ]]; then
          printf '%s\n' 'gh version 2.93.0 (fixture)'
          exit 0
        fi
        sha="$(/usr/bin/git -C "${VIFTY_RELEASE_TAG_ROOT}" rev-parse HEAD)"
        case "${args}" in
          *" config get http_unix_socket "*) exit 0 ;;
          *" auth token "*) printf '%s\n' fixture-token ;;
          *" run list "*)
            printf '[{"databaseId":987654321,"headBranch":"main","headSha":"%s","status":"completed","conclusion":"success","event":"push","url":"https://github.com/Reedtrullz/Vifty/actions/runs/987654321"}]\n' "${sha}"
            ;;
          *"secret list --env "*) exit 0 ;;
          *"secret list "*)
            printf '%s\n' APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD \
              DEVELOPER_ID_APPLICATION_IDENTITY \
              DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64 \
              DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
            ;;
          *" repos/Reedtrullz/Vifty/environments/release/deployment-branch-policies?per_page=100 "*)
            printf '%s\n' '{"total_count":1,"branch_policies":[{"type":"tag","name":"v*"}]}'
            ;;
          *" repos/Reedtrullz/Vifty/environments/release "*)
            printf '%s\n' '{"name":"release","can_admins_bypass":false,"protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
            ;;
          *" repos/Reedtrullz/Vifty/branches/main/protection "*)
            printf '%s\n' '{"required_status_checks":{"strict":true,"contexts":["SwiftPM checks"],"checks":[{"context":"SwiftPM checks","app_id":15368}]},"enforce_admins":{"enabled":true},"required_pull_request_reviews":{"dismiss_stale_reviews":false,"require_code_owner_reviews":false,"required_approving_review_count":0,"require_last_push_approval":false},"required_conversation_resolution":{"enabled":true},"allow_force_pushes":{"enabled":false},"allow_deletions":{"enabled":false}}'
            ;;
          *" repos/Reedtrullz/Vifty/branches/main "*)
            printf '{"name":"main","protected":true,"commit":{"sha":"%s"}}\n' "${sha}"
            ;;
          *" repos/Reedtrullz/Vifty/rulesets?"*)
            printf '%s\n' '[[{"id":18940029,"target":"tag","enforcement":"active"}]]'
            ;;
          *" repos/Reedtrullz/Vifty/rulesets/18940029 "*)
            printf '%s\n' '{"id":18940029,"name":"Immutable Vifty release tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"bypass_actors":[],"updated_at":"2026-01-01T00:00:00Z","current_user_can_bypass":"never","rules":[{"type":"update"},{"type":"deletion"}]}'
            ;;
          *" repos/Reedtrullz/Vifty/git/ref/tags/"*)
            printf '%s\n\n%s\n' 'HTTP/2.0 404 Not Found' '{}'
            exit 1
            ;;
          *" user "*)
            printf '%s\n' '{"id":12345,"login":"Reedtrullz"}'
            ;;
          *" repos/Reedtrullz/Vifty "*)
            printf '%s\n' '{"full_name":"Reedtrullz/Vifty","permissions":{"admin":true}}'
            ;;
          *) printf 'unexpected fake gh invocation: %s\n' "$*" >&2; exit 90 ;;
        esac
        """#
        try fakeGH.write(to: fakeGHURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGHURL.path)

        let policyURL = repositoryURL.appendingPathComponent(".github/release-gh-toolchain.json")
        var policy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: policyURL)) as? [String: Any]
        )
        let fakeGHSHA = try Self.sha256(fakeGHURL)
        policy["sha256"] = fakeGHSHA
        var policyData = try JSONSerialization.data(
            withJSONObject: policy,
            options: [.prettyPrinted, .sortedKeys]
        )
        policyData.append(Data("\n".utf8))
        try policyData.write(to: policyURL)

        let contractURL = repositoryURL.appendingPathComponent("scripts/check-workflow-contract.rb")
        var contract = try String(contentsOf: contractURL, encoding: .utf8)
        let productionGHSHA = "282ec2bb5c6abb6cee50cbfa5f8c04ac2fd6b8523693970a5cab331b121f5430"
        guard contract.contains(productionGHSHA) else {
            throw NSError(
                domain: "GovernanceTagFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "workflow contract gh policy pin changed"]
            )
        }
        contract = contract.replacingOccurrences(of: productionGHSHA, with: fakeGHSHA)
        try contract.write(to: contractURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contractURL.path)

        let ghDiscovery = """
        GH_BIN=""
        for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
          if [[ -x "${gh_candidate}" ]]; then
            GH_BIN="${gh_candidate}"
            break
          fi
        done
        """
        for relativePath in [
            "scripts/check-release-governance.sh",
            "scripts/check-release-environment.sh",
            "scripts/check-release-secrets.sh",
            "scripts/create-signed-release-tag.sh"
        ] {
            let url = repositoryURL.appendingPathComponent(relativePath)
            var contents = try String(contentsOf: url, encoding: .utf8)
            guard contents.contains(ghDiscovery) else {
                throw NSError(
                    domain: "GovernanceTagFixture",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "\(relativePath) no longer contains the expected pinned gh discovery block"
                    ]
                )
            }
            contents = contents.replacingOccurrences(
                of: ghDiscovery,
                with: "GH_BIN=\"\(fakeGHURL.path)\"\n"
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private static func makeEvidence(
        tag: String,
        commitSHA: String,
        observedAt: String,
        governanceToolSHA256: String,
        environmentToolSHA256: String,
        secretsToolSHA256: String,
        ghVerifierSHA256: String,
        ghPolicySHA256: String
    ) -> [String: Any] {
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
                "sha256": governanceToolSHA256
            ],
            "governanceDependencies": [
                [
                    "path": "scripts/check-release-environment.sh",
                    "sha256": environmentToolSHA256
                ],
                [
                    "path": "scripts/check-release-secrets.sh",
                    "sha256": secretsToolSHA256
                ],
                [
                    "path": "scripts/verify-release-gh-toolchain.rb",
                    "sha256": ghVerifierSHA256
                ],
                [
                    "path": ".github/release-gh-toolchain.json",
                    "sha256": ghPolicySHA256
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
                    "requiredStatusCheck": [
                        "context": "SwiftPM checks",
                        "appID": 15_368
                    ],
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

    private static func sha256(_ url: URL) throws -> String {
        let result = try run(
            "/usr/bin/shasum",
            ["-a", "256", url.path],
            currentDirectory: url.deletingLastPathComponent()
        )
        try requireSuccess(result, "hash \(url.lastPathComponent)")
        return try XCTUnwrap(result.stdout.split(separator: " ").first.map(String.init))
    }

    private static func writeJSON(_ value: Any, to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        data.append(Data("\n".utf8))
        try data.write(to: url)
    }

    private static func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL,
        environment: [String: String] = [:]
    ) throws -> GovernanceTagProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return GovernanceTagProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private static func requireSuccess(_ result: GovernanceTagProcessResult, _ operation: String) throws {
        if result.exitCode != 0 {
            throw NSError(
                domain: "GovernanceTagFixture",
                code: Int(result.exitCode),
                userInfo: [
                    NSLocalizedDescriptionKey: "\(operation) failed: \(result.stderr)\(result.stdout)"
                ]
            )
        }
    }
}
