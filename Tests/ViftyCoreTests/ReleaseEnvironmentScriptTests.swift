import Foundation
import XCTest

final class ReleaseEnvironmentScriptTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    func testCheckerAcceptsRequiredReviewerWithSelfReviewPrevention() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]]
        )

        let result = try runChecker(fixture: fixture, output: fixture.outputURL)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try readJSON(fixture.outputURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 2)
        XCTAssertEqual(summary["environment"] as? String, "release")
        XCTAssertEqual(summary["preventSelfReview"] as? Bool, true)
        XCTAssertEqual(summary["administratorsCanBypass"] as? Bool, false)
        XCTAssertEqual(summary["eligibleNonOwnerReviewer"] as? Bool, true)
        XCTAssertEqual(summary["requiredBranch"] as? String, "main")
        XCTAssertEqual(summary["requiredBranchProtected"] as? Bool, true)
        XCTAssertEqual(summary["teamReviewerEligibilityAssumed"] as? Bool, false)
        let eligibleUsers = try XCTUnwrap(summary["eligibleNonOwnerUsers"] as? [[String: Any]])
        XCTAssertEqual(eligibleUsers.map { $0["login"] as? String }, ["release-reviewer"])
        let branchProtection = try XCTUnwrap(summary["requiredBranchProtection"] as? [String: Any])
        XCTAssertEqual(branchProtection["enforceAdministrators"] as? Bool, true)
        XCTAssertEqual(branchProtection["requiredApprovingReviewCount"] as? Int, 1)
        XCTAssertEqual(branchProtection["requireCodeOwnerReviews"] as? Bool, true)
        XCTAssertEqual(branchProtection["requireLastPushApproval"] as? Bool, true)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
    }

    func testCheckerRejectsEnvironmentWithoutRequiredReviewers() throws {
        let fixture = try ReleaseEnvironmentFixture(protectionRules: [])

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("required_reviewers protection rule is missing"), result.stderr)
    }

    func testCheckerRejectsEnvironmentThatAllowsSelfReview() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": false,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must prevent self review"), result.stderr)
    }

    func testCheckerRejectsOwnerAsTheOnlyRequiredReviewer() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "Reedtrullz", "id": 123]
                ]]
            ]]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("no directly verified non-owner User reviewer"), result.stderr)
    }

    func testCheckerRejectsTeamWithoutMembershipEvidence() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "Team",
                    "reviewer": [
                        "name": "release reviewers",
                        "slug": "release-reviewers",
                        "id": 456
                    ]
                ]]
            ]]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("Team membership is not present"), result.stderr)
        XCTAssertTrue(result.stderr.contains("is not eligibility proof"), result.stderr)
    }

    func testCheckerRejectsEnvironmentThatAllowsAdministratorBypass() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]],
            canAdminsBypass: true
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be allowed to bypass"), result.stderr)
    }

    func testCheckerRejectsEnvironmentWithoutAdministratorBypassReadback() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]],
            canAdminsBypass: nil
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be allowed to bypass"), result.stderr)
    }

    func testCheckerRejectsEnvironmentWithoutProtectedBranchPolicy() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]],
            deploymentBranchPolicy: ["protected_branches": false, "custom_branch_policies": false]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require protected branches only"), result.stderr)
    }

    func testCheckerRejectsUnprotectedRequiredBranch() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]],
            branchSummary: ["name": "main", "protected": false]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("required release branch main is not protected"), result.stderr)
    }

    func testCheckerRejectsWrongRequiredBranchReadback() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: [[
                "type": "required_reviewers",
                "prevent_self_review": true,
                "reviewers": [[
                    "type": "User",
                    "reviewer": ["login": "release-reviewer", "id": 123]
                ]]
            ]],
            branchSummary: ["name": "release", "protected": true]
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("required release branch name does not match main"), result.stderr)
    }

    func testCheckerRejectsBranchProtectionThatAdminsCanBypass() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: Self.validReviewerRule,
            branchProtection: Self.validBranchProtection(overrides: [
                "enforce_admins": ["enabled": false]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must enforce protection for administrators"), result.stderr)
    }

    func testCheckerRejectsBranchWithoutRequiredPullRequestReviews() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: Self.validReviewerRule,
            branchProtection: Self.validBranchProtection(overrides: [
                "required_pull_request_reviews": NSNull()
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require pull-request reviews"), result.stderr)
    }

    func testCheckerRejectsWeakPullRequestReviewSettings() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: Self.validReviewerRule,
            branchProtection: Self.validBranchProtection(overrides: [
                "required_pull_request_reviews": [
                    "dismiss_stale_reviews": false,
                    "require_code_owner_reviews": false,
                    "required_approving_review_count": 0,
                    "require_last_push_approval": false,
                    "bypass_pull_request_allowances": [
                        "users": [["login": "Reedtrullz"]],
                        "teams": [],
                        "apps": []
                    ]
                ]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require at least one approving review"), result.stderr)
    }

    func testCheckerRejectsStatusCheckNotBoundToGitHubActions() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: Self.validReviewerRule,
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
        XCTAssertTrue(result.stderr.contains("must require SwiftPM checks from the GitHub Actions app"), result.stderr)
    }

    func testCheckerRejectsForcePushDeletionOrUnresolvedConversationPolicy() throws {
        let fixture = try ReleaseEnvironmentFixture(
            protectionRules: Self.validReviewerRule,
            branchProtection: Self.validBranchProtection(overrides: [
                "required_conversation_resolution": ["enabled": false],
                "allow_force_pushes": ["enabled": true],
                "allow_deletions": ["enabled": true]
            ])
        )

        let result = try runChecker(fixture: fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must require conversation resolution"), result.stderr)
    }

    func testWorkflowRetainsAndRevalidatesNormalizedEnvironmentEvidence() throws {
        let workflow = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(workflow.contains("run-name: Release ${{ inputs.tag }}"))
        XCTAssertTrue(workflow.contains("vifty-release-environment-readback.json"))
        XCTAssertTrue(workflow.contains("releaseEnvironmentEvidence"))
        XCTAssertTrue(workflow.contains("environment evidence SHA-256 mismatch"))
        XCTAssertTrue(workflow.contains("retention-days: 90"))
    }

    private static var validReviewerRule: [[String: Any]] {
        [[
            "type": "required_reviewers",
            "prevent_self_review": true,
            "reviewers": [[
                "type": "User",
                "reviewer": ["login": "release-reviewer", "id": 123]
            ]]
        ]]
    }

    fileprivate static func validBranchProtection(overrides: [String: Any] = [:]) -> [String: Any] {
        var protection: [String: Any] = [
            "required_status_checks": [
                "strict": true,
                "contexts": ["SwiftPM checks"],
                "checks": [["context": "SwiftPM checks", "app_id": 15_368]]
            ],
            "enforce_admins": ["enabled": true],
            "required_pull_request_reviews": [
                "dismiss_stale_reviews": true,
                "require_code_owner_reviews": true,
                "required_approving_review_count": 1,
                "require_last_push_approval": true,
                "bypass_pull_request_allowances": [
                    "users": [],
                    "teams": [],
                    "apps": []
                ]
            ],
            "required_conversation_resolution": ["enabled": true],
            "allow_force_pushes": ["enabled": false],
            "allow_deletions": ["enabled": false]
        ]
        for (key, value) in overrides {
            protection[key] = value
        }
        return protection
    }

    private func runChecker(
        fixture: ReleaseEnvironmentFixture,
        output: URL? = nil
    ) throws -> ReleaseEnvironmentProcessResult {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/check-release-environment.sh")
        process.arguments = [
            "--json-file", fixture.inputURL.path,
            "--branch-protection-json-file", fixture.branchProtectionURL.path
        ]
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
    let outputURL: URL

    init(
        protectionRules: [[String: Any]],
        canAdminsBypass: Bool? = false,
        deploymentBranchPolicy: [String: Any] = [
            "protected_branches": true,
            "custom_branch_policies": false
        ],
        branchSummary: [String: Any] = ["name": "main", "protected": true],
        branchProtection: [String: Any] = ReleaseEnvironmentScriptTests.validBranchProtection()
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-environment-\(UUID().uuidString)", isDirectory: true)
        inputURL = rootURL.appendingPathComponent("environment.json")
        branchProtectionURL = rootURL.appendingPathComponent("branch-protection.json")
        outputURL = rootURL.appendingPathComponent("normalized.json")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var payload: [String: Any] = [
            "name": "release",
            "protection_rules": protectionRules,
            "deployment_branch_policy": deploymentBranchPolicy
        ]
        if let canAdminsBypass {
            payload["can_admins_bypass"] = canAdminsBypass
        }
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: inputURL)
        let branchEvidence: [String: Any] = [
            "name": branchSummary["name"] ?? NSNull(),
            "protected": branchSummary["protected"] ?? NSNull(),
            "protection": branchProtection
        ]
        try JSONSerialization.data(
            withJSONObject: branchEvidence,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: branchProtectionURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
