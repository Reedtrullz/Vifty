import Foundation
import XCTest

final class ReleaseEnvironmentScriptTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    func testCheckerAcceptsSoloMaintainerEnvironmentWithoutReviewerGate() throws {
        let fixture = try ReleaseEnvironmentFixture()

        let result = try runChecker(fixture: fixture, output: fixture.outputURL)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try readJSON(fixture.outputURL)
        XCTAssertEqual(summary["status"] as? String, "test-fixture")
        XCTAssertEqual(summary["releaseAuthorized"] as? Bool, false)
        XCTAssertEqual(summary["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 5)
        XCTAssertEqual(summary["evidenceScope"] as? String, "administrator-full")
        XCTAssertEqual(summary["privilegedSettingsVerified"] as? Bool, true)
        XCTAssertEqual(summary["environment"] as? String, "release")
        XCTAssertEqual(summary["releaseGovernanceMode"] as? String, "solo-maintainer")
        XCTAssertEqual(summary["requiredReviewerGate"] as? Bool, false)
        XCTAssertEqual(summary["preventSelfReview"] as? Bool, false)
        XCTAssertEqual(summary["administratorsCanBypass"] as? Bool, false)
        let deploymentMode = try XCTUnwrap(summary["deploymentBranchPolicy"] as? [String: Any])
        XCTAssertEqual(deploymentMode["protected_branches"] as? Bool, false)
        XCTAssertEqual(deploymentMode["custom_branch_policies"] as? Bool, true)
        let tagPolicy = try XCTUnwrap(summary["releaseTagDeploymentPolicy"] as? [String: Any])
        XCTAssertEqual(tagPolicy["policyCount"] as? Int, 1)
        XCTAssertEqual(tagPolicy["branchPolicyCount"] as? Int, 0)
        XCTAssertEqual(tagPolicy["tagPolicyCount"] as? Int, 1)
        XCTAssertEqual(tagPolicy["requiredTagPattern"] as? String, "v*")
        XCTAssertEqual(
            tagPolicy["policies"] as? [[String: String]],
            [["type": "tag", "name": "v*"]]
        )
        XCTAssertEqual(summary["requiredBranch"] as? String, "main")
        XCTAssertEqual(summary["requiredBranchProtected"] as? Bool, true)
        let reviewers = try XCTUnwrap(summary["requiredReviewers"] as? [[String: Any]])
        XCTAssertTrue(reviewers.isEmpty)
        let branchProtection = try XCTUnwrap(summary["requiredBranchProtection"] as? [String: Any])
        XCTAssertEqual(branchProtection["enforceAdministrators"] as? Bool, true)
        XCTAssertEqual(branchProtection["pullRequestRequired"] as? Bool, true)
        XCTAssertEqual(branchProtection["peerApprovalRequired"] as? Bool, false)
        XCTAssertEqual(branchProtection["requiredApprovingReviewCount"] as? Int, 0)
        XCTAssertEqual(branchProtection["codeOwnerReviewRequired"] as? Bool, false)
        XCTAssertEqual(branchProtection["lastPushApprovalRequired"] as? Bool, false)
        XCTAssertEqual(try XCTUnwrap(branchProtection["pullRequestBypassActors"] as? [Any]).count, 0)
        XCTAssertEqual(branchProtection["requireConversationResolution"] as? Bool, true)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
    }

    func testCheckerAtomicallyReplacesOutputWithoutLeavingTemporaryFiles() throws {
        let fixture = try ReleaseEnvironmentFixture()
        try Data("stale evidence\n".utf8).write(to: fixture.outputURL)

        let result = try runChecker(fixture: fixture, output: fixture.outputURL)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(try readJSON(fixture.outputURL)["status"] as? String, "test-fixture")
        let siblingNames = try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
        XCTAssertFalse(
            siblingNames.contains { $0.hasPrefix(".normalized.json.tmp.") },
            "successful atomic replacement must not leave a sibling temporary file"
        )
    }

    func testFailedRerunRemovesPreviouslyPassedOutput() throws {
        let passingFixture = try ReleaseEnvironmentFixture()
        let passingResult = try runChecker(fixture: passingFixture, output: passingFixture.outputURL)
        XCTAssertEqual(passingResult.exitCode, 0, passingResult.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: passingFixture.outputURL.path))

        let failingFixture = try ReleaseEnvironmentFixture(canAdminsBypass: true)
        let failingResult = try runChecker(fixture: failingFixture, output: passingFixture.outputURL)

        XCTAssertEqual(failingResult.exitCode, 65)
        XCTAssertTrue(failingResult.stderr.contains("must not be allowed to bypass"), failingResult.stderr)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: passingFixture.outputURL.path),
            "a failed rerun must not leave previously passed evidence at --output"
        )
    }

    func testCheckerRejectsOutputThatWouldReplaceFixtureInput() throws {
        let fixture = try ReleaseEnvironmentFixture()
        let environmentBefore = try Data(contentsOf: fixture.inputURL)
        let branchBefore = try Data(contentsOf: fixture.branchProtectionURL)

        let environmentResult = try runChecker(fixture: fixture, output: fixture.inputURL)
        XCTAssertEqual(environmentResult.exitCode, 65)
        XCTAssertTrue(environmentResult.stderr.contains("must not replace an input fixture"))
        XCTAssertEqual(try Data(contentsOf: fixture.inputURL), environmentBefore)

        let branchResult = try runChecker(fixture: fixture, output: fixture.branchProtectionURL)
        XCTAssertEqual(branchResult.exitCode, 65)
        XCTAssertTrue(branchResult.stderr.contains("must not replace an input fixture"))
        XCTAssertEqual(try Data(contentsOf: fixture.branchProtectionURL), branchBefore)
    }

    func testCheckerRejectsTrackedOrGitMetadataOutputWithoutChangingIt() throws {
        let fixture = try ReleaseEnvironmentFixture()
        let trackedURL = repositoryRoot.appendingPathComponent("Package.swift")
        let trackedBefore = try Data(contentsOf: trackedURL)

        let trackedResult = try runChecker(fixture: fixture, output: trackedURL)
        XCTAssertEqual(trackedResult.exitCode, 65)
        XCTAssertTrue(trackedResult.stderr.contains("must not replace a tracked worktree path"))
        XCTAssertEqual(try Data(contentsOf: trackedURL), trackedBefore)

        let refURL = repositoryRoot
            .appendingPathComponent(".git/refs/tags/vifty-environment-output-\(UUID().uuidString)")
        let metadataResult = try runChecker(fixture: fixture, output: refURL)
        XCTAssertEqual(metadataResult.exitCode, 65)
        XCTAssertTrue(metadataResult.stderr.contains("must not be inside Git metadata"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: refURL.path))
    }

    func testCheckerRejectsSymlinkDirectoryAndMissingParentOutputs() throws {
        let fixture = try ReleaseEnvironmentFixture()
        let targetURL = fixture.rootURL.appendingPathComponent("protected-target.json")
        let symlinkURL = fixture.rootURL.appendingPathComponent("evidence-link.json")
        try Data("protected\n".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        let symlinkResult = try runChecker(fixture: fixture, output: symlinkURL)
        XCTAssertEqual(symlinkResult.exitCode, 65)
        XCTAssertTrue(symlinkResult.stderr.contains("regular non-symlink file"))
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "protected\n")

        let directoryResult = try runChecker(fixture: fixture, output: fixture.rootURL)
        XCTAssertEqual(directoryResult.exitCode, 65)
        XCTAssertTrue(directoryResult.stderr.contains("regular non-symlink file"))

        let missingParentURL = fixture.rootURL
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("evidence.json")
        let missingParentResult = try runChecker(fixture: fixture, output: missingParentURL)
        XCTAssertEqual(missingParentResult.exitCode, 66)
        XCTAssertTrue(missingParentResult.stderr.contains("parent must already be a real directory"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingParentURL.path))
    }

    func testCheckerRejectsEnvironmentWithReviewerGateInSoloMaintainerMode() throws {
        let fixture = try ReleaseEnvironmentFixture(protectionRules: Self.reviewerRule)

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not configure required reviewers"), result.stderr)
    }

    func testCheckerRejectsEnvironmentThatAllowsAdministratorBypass() throws {
        let fixture = try ReleaseEnvironmentFixture(canAdminsBypass: true)

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be allowed to bypass"), result.stderr)
    }

    func testCheckerRejectsEnvironmentWithoutAdministratorBypassReadback() throws {
        let fixture = try ReleaseEnvironmentFixture(canAdminsBypass: nil)

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be allowed to bypass"), result.stderr)
    }

    func testCheckerRejectsEnvironmentThatAdmitsProtectedBranches() throws {
        let fixture = try ReleaseEnvironmentFixture(
            deploymentBranchPolicy: ["protected_branches": true, "custom_branch_policies": false]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("must disable protected-branch admission and require custom policies"),
            result.stderr
        )
    }

    func testCheckerRejectsEnvironmentWithoutRequiredPolicyFixture() throws {
        let fixture = try ReleaseEnvironmentFixture(deploymentPolicies: nil)

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("deployment branch policy listing"), result.stderr)
    }

    func testCheckerRejectsMissingOrAdditionalDeploymentPolicies() throws {
        for policies in [
            Self.deploymentPolicies([]),
            Self.deploymentPolicies([
                ["id": 1, "name": "v*", "type": "tag"],
                ["id": 2, "name": "release/*", "type": "branch"]
            ])
        ] {
            let fixture = try ReleaseEnvironmentFixture(deploymentPolicies: policies)

            let result = try runChecker(fixture: fixture)

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(result.stderr.contains("exactly one deployment policy"), result.stderr)
        }
    }

    func testCheckerRejectsIncompleteDeploymentPolicyListing() throws {
        let fixture = try ReleaseEnvironmentFixture(deploymentPolicies: [
            "total_count": 2,
            "branch_policies": [["id": 1, "name": "v*", "type": "tag"]]
        ])

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("complete policy count and array"), result.stderr)
    }

    func testCheckerRejectsBranchPolicyOrWrongTagPattern() throws {
        for policy in [
            ["id": 1, "name": "v*", "type": "branch"],
            ["id": 1, "name": "release/*", "type": "tag"]
        ] {
            let fixture = try ReleaseEnvironmentFixture(
                deploymentPolicies: Self.deploymentPolicies([policy])
            )

            let result = try runChecker(fixture: fixture)

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(result.stderr.contains("must be tag-only with pattern v*"), result.stderr)
        }
    }

    func testCheckerRejectsUnprotectedRequiredBranch() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchSummary: ["name": "main", "protected": false]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("required release branch main is not protected"), result.stderr)
    }

    func testCheckerRejectsWrongRequiredBranchReadback() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchSummary: ["name": "release", "protected": true]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("required release branch name does not match main"), result.stderr)
    }

    func testCheckerRejectsBranchProtectionThatAdminsCanBypass() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "enforce_admins": ["enabled": false]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must enforce protection for administrators"), result.stderr)
    }

    func testCheckerRejectsBranchWithoutPullRequestGate() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "required_pull_request_reviews": NSNull()
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require a pull request"), result.stderr)
    }

    func testCheckerRejectsBranchThatRequiresPeerApproval() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "required_pull_request_reviews": Self.pullRequestRule(requiredApprovals: 1)
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not require peer approval"), result.stderr)
    }

    func testCheckerRejectsPullRequestBypassActor() throws {
        var rule = Self.pullRequestRule(requiredApprovals: 0)
        rule["bypass_pull_request_allowances"] = [
            "users": [["login": "release-owner"]],
            "teams": [],
            "apps": []
        ]
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "required_pull_request_reviews": rule
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not allow pull-request bypass actors"), result.stderr)
    }

    func testCheckerRejectsMissingEnvironmentProtectionRulesEvidence() throws {
        let fixture = try ReleaseEnvironmentFixture(protectionRules: nil)

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("protection_rules evidence must be an array"), result.stderr)
    }

    func testCheckerRejectsStatusCheckNotBoundToGitHubActions() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "required_status_checks": [
                    "strict": true,
                    "contexts": ["SwiftPM checks"],
                    "checks": [["context": "SwiftPM checks", "app_id": NSNull()]]
                ]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("GitHub Actions app"), result.stderr)
    }

    func testCheckerRejectsUnresolvedConversationPolicy() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "required_conversation_resolution": ["enabled": false]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require conversation resolution"), result.stderr)
    }

    func testCheckerRejectsForcePushAllowance() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "allow_force_pushes": ["enabled": true]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must forbid force pushes"), result.stderr)
    }

    func testCheckerRejectsDeletionAllowance() throws {
        let fixture = try ReleaseEnvironmentFixture(
            branchProtection: Self.validBranchProtection(overrides: [
                "allow_deletions": ["enabled": true]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must forbid deletion"), result.stderr)
    }

    func testWorkflowPublicCheckerAcceptsOnlyPubliclyVisibleGovernance() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(branchEvidence: Self.publicBranchEvidence(sha: sha))

        let result = try runChecker(fixture: fixture, workflowPublicSHA: sha, output: fixture.outputURL)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try readJSON(fixture.outputURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 5)
        XCTAssertEqual(summary["status"] as? String, "test-fixture")
        XCTAssertEqual(summary["releaseAuthorized"] as? Bool, false)
        XCTAssertEqual(summary["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(summary["evidenceScope"] as? String, "workflow-public")
        XCTAssertEqual(summary["privilegedSettingsVerified"] as? Bool, false)
        XCTAssertEqual(summary["requiredBranchCommitSHA"] as? String, sha)
        let tagPolicy = try XCTUnwrap(summary["releaseTagDeploymentPolicy"] as? [String: Any])
        XCTAssertEqual(tagPolicy["branchPolicyCount"] as? Int, 0)
        XCTAssertEqual(tagPolicy["tagPolicyCount"] as? Int, 1)
        XCTAssertEqual(tagPolicy["requiredTagPattern"] as? String, "v*")
        let branchProtection = try XCTUnwrap(summary["requiredBranchProtection"] as? [String: Any])
        XCTAssertEqual(branchProtection["statusCheckEnforcementLevel"] as? String, "everyone")
        XCTAssertNil(branchProtection["pullRequestRequired"])
        let operatorOnly = try XCTUnwrap(summary["operatorOnlyChecks"] as? [String])
        XCTAssertTrue(operatorOnly.contains("pull-request-required-zero-approvals-no-bypass"))
    }

    func testWorkflowPublicCheckerRejectsBranchCommitDrift() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(
            branchEvidence: Self.publicBranchEvidence(sha: String(repeating: "b", count: 40))
        )

        let result = try runChecker(fixture: fixture, workflowPublicSHA: sha)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must bind expected commit"), result.stderr)
    }

    func testWorkflowPublicCheckerRejectsStatusCheckNotEnforcedForEveryone() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(
            branchEvidence: Self.publicBranchEvidence(sha: sha, enforcementLevel: "non_admins")
        )

        let result = try runChecker(fixture: fixture, workflowPublicSHA: sha)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("enforced for everyone"), result.stderr)
    }

    func testWorkflowPublicCheckerRejectsForeignStatusCheckApp() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(
            branchEvidence: Self.publicBranchEvidence(sha: sha, appID: 9_999)
        )

        let result = try runChecker(fixture: fixture, workflowPublicSHA: sha)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("GitHub Actions app"), result.stderr)
    }

    func testWorkflowPublicLiveReadbackUsesOptionalTokenAndDisablesCaches() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(branchEvidence: Self.publicBranchEvidence(sha: sha))

        let result = try runLiveWorkflowPublicChecker(
            fixture: fixture,
            expectedSHA: sha,
            token: "fixture-token",
            output: fixture.outputURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let arguments = try String(contentsOf: fixture.curlLogURL, encoding: .utf8)
        XCTAssertFalse(arguments.contains("fixture-token"), arguments)
        XCTAssertFalse(arguments.contains("Authorization: Bearer"), arguments)
        XCTAssertEqual(arguments.components(separatedBy: "AUTH_STDIN_OK").count - 1, 3)
        XCTAssertEqual(arguments.components(separatedBy: "--header").count - 1, 3)
        XCTAssertEqual(arguments.components(separatedBy: "@-").count - 1, 3)
        XCTAssertEqual(arguments.components(separatedBy: "Cache-Control: no-cache").count - 1, 3)
        XCTAssertEqual(arguments.components(separatedBy: "Pragma: no-cache").count - 1, 3)
        XCTAssertFalse(arguments.contains("--location"))
        XCTAssertTrue(
            arguments.contains(
                "repos/Reedtrullz/Vifty/environments/release/deployment-branch-policies?per_page=100"
            ),
            arguments
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.ghLogURL.path))
        let summary = try readJSON(fixture.outputURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["releaseAuthorized"] as? Bool, true)
        XCTAssertEqual(summary["dataSource"] as? String, "github-api-live")
        XCTAssertEqual(summary["evidenceScope"] as? String, "workflow-public")
        XCTAssertEqual(summary["privilegedSettingsVerified"] as? Bool, false)
    }

    func testWorkflowPublicLiveReadbackWorksWithoutToken() throws {
        let sha = String(repeating: "a", count: 40)
        let fixture = try ReleaseEnvironmentFixture(branchEvidence: Self.publicBranchEvidence(sha: sha))

        let result = try runLiveWorkflowPublicChecker(
            fixture: fixture,
            expectedSHA: sha,
            token: nil
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let arguments = try String(contentsOf: fixture.curlLogURL, encoding: .utf8)
        XCTAssertFalse(arguments.contains("Authorization:"))
        XCTAssertFalse(arguments.contains("AUTH_STDIN_OK"))
        XCTAssertFalse(arguments.contains("@-"))
        XCTAssertEqual(arguments.components(separatedBy: "Cache-Control: no-cache").count - 1, 3)
        XCTAssertEqual(arguments.components(separatedBy: "Pragma: no-cache").count - 1, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.ghLogURL.path))
    }

    func testAdministratorLiveReadbackUsesSafeGitHubCLIForEnvironmentPolicies() throws {
        let fixture = try ReleaseEnvironmentFixture()

        let result = try runLiveAdministratorChecker(
            fixture: fixture,
            token: "fixture-token",
            output: fixture.outputURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let ghCalls = try String(contentsOf: fixture.ghLogURL, encoding: .utf8)
        XCTAssertTrue(ghCalls.contains("GH_CONFIG_DIR=/var/empty"), ghCalls)
        XCTAssertTrue(ghCalls.contains("GH_HOST=github.com"), ghCalls)
        XCTAssertTrue(ghCalls.contains("repos/Reedtrullz/Vifty/environments/release"), ghCalls)
        XCTAssertTrue(ghCalls.contains("repos/Reedtrullz/Vifty/branches/main"), ghCalls)
        XCTAssertTrue(ghCalls.contains("repos/Reedtrullz/Vifty/branches/main/protection"), ghCalls)
        XCTAssertTrue(
            ghCalls.contains(
                "repos/Reedtrullz/Vifty/environments/release/deployment-branch-policies?per_page=100"
            ),
            ghCalls
        )
        XCTAssertFalse(ghCalls.contains("api.github.example"))
        let summary = try readJSON(fixture.outputURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 5)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["releaseAuthorized"] as? Bool, true)
        XCTAssertEqual(summary["dataSource"] as? String, "github-api-live")
        XCTAssertEqual(summary["evidenceScope"] as? String, "administrator-full")
        XCTAssertEqual(summary["privilegedSettingsVerified"] as? Bool, true)
    }

    func testWorkflowRetainsAndRevalidatesNormalizedEnvironmentEvidence() throws {
        let workflow = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(
            workflow.contains(
                "run-name: Release ${{ github.ref_name }}"
            )
        )
        XCTAssertTrue(workflow.contains("vifty-release-environment-readback.json"))
        XCTAssertTrue(workflow.contains("--workflow-public"))
        XCTAssertTrue(workflow.contains("--expected-branch-sha \"${GITHUB_SHA}\""))
        XCTAssertTrue(workflow.contains("cd \"${TRUSTED_ROOT}\""))
        XCTAssertTrue(workflow.contains("\"${TRUSTED_ROOT}/scripts/check-release-environment.sh\""))
        XCTAssertTrue(workflow.contains("releaseEnvironmentEvidence"))
        XCTAssertTrue(workflow.contains(#"environment_evidence["evidenceScope"] == "workflow-public""#))
        XCTAssertTrue(workflow.contains(#"environment_evidence["privilegedSettingsVerified"] == false"#))
        XCTAssertTrue(workflow.contains(#"environment_evidence["releaseGovernanceMode"] == "solo-maintainer""#))
        XCTAssertTrue(workflow.contains("environment evidence SHA-256 mismatch"))
        XCTAssertTrue(workflow.contains("retention-days: 90"))
    }

    private static var reviewerRule: [[String: Any]] {
        [[
            "type": "required_reviewers",
            "prevent_self_review": true,
            "reviewers": [[
                "type": "User",
                "reviewer": ["login": "release-reviewer", "id": 123]
            ]]
        ]]
    }

    private static func pullRequestRule(requiredApprovals: Int) -> [String: Any] {
        [
            "dismiss_stale_reviews": false,
            "require_code_owner_reviews": false,
            "required_approving_review_count": requiredApprovals,
            "require_last_push_approval": false,
            "bypass_pull_request_allowances": [
                "users": [],
                "teams": [],
                "apps": []
            ]
        ]
    }

    fileprivate static func deploymentPolicies(_ policies: [[String: Any]]) -> [String: Any] {
        [
            "total_count": policies.count,
            "branch_policies": policies
        ]
    }

    fileprivate static func validBranchProtection(overrides: [String: Any] = [:]) -> [String: Any] {
        var protection: [String: Any] = [
            "required_status_checks": [
                "strict": true,
                "contexts": ["SwiftPM checks"],
                "checks": [["context": "SwiftPM checks", "app_id": 15_368]]
            ],
            "enforce_admins": ["enabled": true],
            "required_pull_request_reviews": pullRequestRule(requiredApprovals: 0),
            "required_conversation_resolution": ["enabled": true],
            "allow_force_pushes": ["enabled": false],
            "allow_deletions": ["enabled": false]
        ]
        for (key, value) in overrides {
            protection[key] = value
        }
        return protection
    }

    private static func publicBranchEvidence(
        sha: String,
        enforcementLevel: String = "everyone",
        appID: Int = 15_368
    ) -> [String: Any] {
        [
            "name": "main",
            "protected": true,
            "commit": ["sha": sha],
            "protection": [
                "enabled": true,
                "required_status_checks": [
                    "enforcement_level": enforcementLevel,
                    "contexts": ["SwiftPM checks"],
                    "checks": [["context": "SwiftPM checks", "app_id": appID]]
                ]
            ]
        ]
    }

    private func runChecker(
        fixture: ReleaseEnvironmentFixture,
        workflowPublicSHA: String? = nil,
        output: URL? = nil
    ) throws -> ReleaseEnvironmentProcessResult {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/check-release-environment.sh")
        process.arguments = [
            "--json-file", fixture.inputURL.path,
            "--branch-protection-json-file", fixture.branchProtectionURL.path
        ]
            + (workflowPublicSHA.map { ["--workflow-public", "--expected-branch-sha", $0] } ?? [])
            + (output.map { ["--output", $0.path] } ?? [])

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ReleaseEnvironmentProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func runLiveWorkflowPublicChecker(
        fixture: ReleaseEnvironmentFixture,
        expectedSHA: String,
        token: String?,
        output: URL? = nil
    ) throws -> ReleaseEnvironmentProcessResult {
        let process = Process()
        process.executableURL = fixture.patchedCheckerURL
        process.arguments = [
            "--workflow-public",
            "--expected-branch-sha", expectedSHA
        ] + (output.map { ["--output", $0.path] } ?? [])

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "BASH_ENV")
        environment.removeValue(forKey: "ENV")
        environment.removeValue(forKey: "RUBYOPT")
        environment.removeValue(forKey: "RUBYLIB")
        if let token {
            environment["GH_TOKEN"] = token
        } else {
            environment.removeValue(forKey: "GH_TOKEN")
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ReleaseEnvironmentProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func runLiveAdministratorChecker(
        fixture: ReleaseEnvironmentFixture,
        token: String,
        output: URL? = nil
    ) throws -> ReleaseEnvironmentProcessResult {
        let process = Process()
        process.executableURL = fixture.patchedCheckerURL
        process.arguments = output.map { ["--output", $0.path] } ?? []

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "BASH_ENV")
        environment.removeValue(forKey: "ENV")
        environment.removeValue(forKey: "RUBYOPT")
        environment.removeValue(forKey: "RUBYLIB")
        environment["GH_TOKEN"] = token
        environment["GH_HOST"] = "github.com"
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ReleaseEnvironmentProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

private struct ReleaseEnvironmentProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ReleaseEnvironmentFixture {
    let rootURL: URL
    let inputURL: URL
    let branchProtectionURL: URL
    let deploymentPoliciesURL: URL
    let liveBranchSummaryURL: URL
    let liveBranchProtectionURL: URL
    let outputURL: URL
    let patchedCheckerURL: URL
    let fakeCurlURL: URL
    let fakeGHURL: URL
    let curlLogURL: URL
    let ghLogURL: URL

    init(
        protectionRules: [[String: Any]]? = [],
        canAdminsBypass: Bool? = false,
        deploymentBranchPolicy: [String: Any] = [
            "protected_branches": false,
            "custom_branch_policies": true
        ],
        deploymentPolicies: [String: Any]? = ReleaseEnvironmentScriptTests.deploymentPolicies([
            ["id": 1, "name": "v*", "type": "tag"]
        ]),
        branchSummary: [String: Any] = ["name": "main", "protected": true],
        branchProtection: [String: Any] = ReleaseEnvironmentScriptTests.validBranchProtection(),
        branchEvidence: [String: Any]? = nil
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-environment-\(UUID().uuidString)", isDirectory: true)
        inputURL = rootURL.appendingPathComponent("environment.json")
        branchProtectionURL = rootURL.appendingPathComponent("branch-protection.json")
        deploymentPoliciesURL = rootURL.appendingPathComponent("deployment-policies.json")
        liveBranchSummaryURL = rootURL.appendingPathComponent("live-branch-summary.json")
        liveBranchProtectionURL = rootURL.appendingPathComponent("live-branch-protection.json")
        outputURL = rootURL.appendingPathComponent("normalized.json")
        patchedCheckerURL = rootURL.appendingPathComponent("check-release-environment.sh")
        fakeCurlURL = rootURL.appendingPathComponent("curl")
        fakeGHURL = rootURL.appendingPathComponent("gh")
        curlLogURL = rootURL.appendingPathComponent("curl-arguments.log")
        ghLogURL = rootURL.appendingPathComponent("gh-arguments.log")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var payload: [String: Any] = [
            "name": "release",
            "deployment_branch_policy": deploymentBranchPolicy
        ]
        if let deploymentPolicies {
            payload["deployment_branch_policies"] = deploymentPolicies
        }
        if let protectionRules {
            payload["protection_rules"] = protectionRules
        }
        if let canAdminsBypass {
            payload["can_admins_bypass"] = canAdminsBypass
        }
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: inputURL)
        let resolvedBranchEvidence: [String: Any] = branchEvidence ?? [
            "name": branchSummary["name"] ?? NSNull(),
            "protected": branchSummary["protected"] ?? NSNull(),
            "commitSHA": branchSummary["commitSHA"] ?? String(repeating: "a", count: 40),
            "protection": branchProtection
        ]
        try JSONSerialization.data(
            withJSONObject: resolvedBranchEvidence,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: branchProtectionURL)
        try JSONSerialization.data(
            withJSONObject: deploymentPolicies ?? [:],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: deploymentPoliciesURL)
        try JSONSerialization.data(
            withJSONObject: [
                "name": branchSummary["name"] ?? NSNull(),
                "protected": branchSummary["protected"] ?? NSNull(),
                "commit": [
                    "sha": branchSummary["commitSHA"] ?? String(repeating: "a", count: 40)
                ]
            ],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: liveBranchSummaryURL)
        try JSONSerialization.data(
            withJSONObject: branchProtection,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: liveBranchProtectionURL)

        let fakeCurlScript = #"""
        #!/bin/bash
        set -euo pipefail
        printf '%s\n' "$@" >> "\#(curlLogURL.path)"
        url=""
        expects_stdin_header=0
        previous=""
        for argument in "$@"; do
          if [[ "${previous}" == "--header" && "${argument}" == "@-" ]]; then
            expects_stdin_header=1
          fi
          if [[ "${argument}" == *"fixture-token"* || "${argument}" == *"Authorization: Bearer"* ]]; then
            printf 'authorization secret appeared in curl argv\n' >&2
            exit 64
          fi
          previous="${argument}"
          url="${argument}"
        done
        if [[ "${expects_stdin_header}" -eq 1 ]]; then
          IFS= read -r authorization_header
          if [[ "${authorization_header}" != "Authorization: Bearer fixture-token" ]]; then
            printf 'unexpected authorization header on stdin\n' >&2
            exit 64
          fi
          printf 'AUTH_STDIN_OK\n' >> "\#(curlLogURL.path)"
        fi
        case "${url}" in
          */environments/release)
            /bin/cat "\#(inputURL.path)"
            ;;
          */branches/main)
            /bin/cat "\#(branchProtectionURL.path)"
            ;;
          */environments/release/deployment-branch-policies\?per_page=100)
            /bin/cat "\#(deploymentPoliciesURL.path)"
            ;;
          *)
            printf 'unexpected URL: %s\n' "${url}" >&2
            exit 22
            ;;
        esac
        """#
        try Data(fakeCurlScript.utf8).write(to: fakeCurlURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fakeCurlURL.path
        )

        let fakeGHScript = #"""
        #!/bin/bash
        set -euo pipefail
        printf 'GH_CONFIG_DIR=%s GH_HOST=%s GH_TOKEN=%s ARGS=' \
          "${GH_CONFIG_DIR:-}" "${GH_HOST:-}" "${GH_TOKEN:-}" >> "\#(ghLogURL.path)"
        printf '%s ' "$@" >> "\#(ghLogURL.path)"
        printf '\n' >> "\#(ghLogURL.path)"
        if [[ "${1:-}" == "config" && "${2:-}" == "get" && "${3:-}" == "http_unix_socket" ]]; then
          exit 0
        fi
        if [[ "${1:-}" == "auth" && "${2:-}" == "token" ]]; then
          printf '%s\n' "fixture-auth-token"
          exit 0
        fi
        if [[ "${1:-}" != "api" ]]; then
          printf 'unexpected gh command\n' >&2
          exit 2
        fi
        endpoint="${!#}"
        case "${endpoint}" in
          repos/Reedtrullz/Vifty/environments/release)
            /bin/cat "\#(inputURL.path)"
            ;;
          repos/Reedtrullz/Vifty/branches/main)
            /bin/cat "\#(liveBranchSummaryURL.path)"
            ;;
          repos/Reedtrullz/Vifty/branches/main/protection)
            /bin/cat "\#(liveBranchProtectionURL.path)"
            ;;
          repos/Reedtrullz/Vifty/environments/release/deployment-branch-policies\?per_page=100)
            /bin/cat "\#(deploymentPoliciesURL.path)"
            ;;
          *)
            printf 'unexpected endpoint: %s\n' "${endpoint}" >&2
            exit 2
            ;;
        esac
        """#
        try Data(fakeGHScript.utf8).write(to: fakeGHURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fakeGHURL.path
        )

        let repositoryRoot = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let checkerURL = repositoryRoot.appendingPathComponent("scripts/check-release-environment.sh")
        var checker = try String(contentsOf: checkerURL, encoding: .utf8)
        let productionCurlBinding = #"CURL_BIN="/usr/bin/curl""#
        guard checker.contains(productionCurlBinding) else {
            throw NSError(
                domain: "ReleaseEnvironmentFixture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "release environment checker curl binding changed"]
            )
        }
        checker = checker.replacingOccurrences(
            of: productionCurlBinding,
            with: #"CURL_BIN="\#(fakeCurlURL.path)""#
        )
        let productionGHBinding = #"""
        GH_BIN=""
        for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
          if [[ -x "${gh_candidate}" ]]; then
            GH_BIN="${gh_candidate}"
            break
          fi
        done
        """#
        guard checker.contains(productionGHBinding) else {
            throw NSError(
                domain: "ReleaseEnvironmentFixture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "release environment checker gh binding changed"]
            )
        }
        checker = checker.replacingOccurrences(
            of: productionGHBinding,
            with: #"GH_BIN="\#(fakeGHURL.path)""#
       )
        let productionGHPin = #"""
    unverified_gh_bin="${GH_BIN}"
    TOOLCHAIN_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-environment-gh.XXXXXX")"
    /bin/chmod 700 "${TOOLCHAIN_SCRATCH}"
    GH_BIN="${TOOLCHAIN_SCRATCH}/pinned-gh"
    /usr/bin/ruby "${GH_TOOLCHAIN_VERIFIER_PATH}" \
      --policy "${GH_TOOLCHAIN_POLICY_PATH}" \
      --source "${unverified_gh_bin}" \
      --destination "${GH_BIN}" >/dev/null
"""#
        guard checker.contains(productionGHPin) else {
            throw NSError(
                domain: "ReleaseEnvironmentFixture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "release environment gh pin block changed"]
            )
        }
        checker = checker.replacingOccurrences(
            of: productionGHPin,
            with: "    true # fixture gh is isolated by this test harness\n"
        )
        try Data(checker.utf8).write(to: patchedCheckerURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: patchedCheckerURL.path
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
