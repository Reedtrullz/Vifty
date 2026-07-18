import Foundation
import XCTest

final class ReleaseGovernanceScriptTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    func testAdministratorPreTagGateAcceptsFullAdminVisibleEvidence() throws {
        let fixture = try ReleaseGovernanceFixture()

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(summary["status"] as? String, "test-fixture")
        XCTAssertEqual(summary["evidenceScope"] as? String, "administrator-pretag")
        XCTAssertEqual(summary["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(summary["liveAuthenticatedGitHubReadback"] as? Bool, false)
        XCTAssertEqual(summary["releaseAuthorized"] as? Bool, false)
        XCTAssertEqual(summary["repositoryAdminVerified"] as? Bool, false)
        XCTAssertEqual(summary["tagAbsentVerified"] as? Bool, false)
        let environment = try XCTUnwrap(summary["releaseEnvironmentEvidence"] as? [String: Any])
        XCTAssertEqual(environment["schemaVersion"] as? Int, 5)
        XCTAssertEqual(environment["status"] as? String, "test-fixture")
        XCTAssertEqual(environment["releaseAuthorized"] as? Bool, false)
        XCTAssertEqual(environment["dataSource"] as? String, "test-fixture")
        XCTAssertEqual(environment["requiredBranchCommitSHA"] as? String, fixture.mainSHA)
        let deploymentMode = try XCTUnwrap(environment["deploymentBranchPolicy"] as? [String: Any])
        XCTAssertEqual(deploymentMode["protected_branches"] as? Bool, false)
        XCTAssertEqual(deploymentMode["custom_branch_policies"] as? Bool, true)
        let tagPolicy = try XCTUnwrap(environment["releaseTagDeploymentPolicy"] as? [String: Any])
        XCTAssertEqual(tagPolicy["policyCount"] as? Int, 1)
        XCTAssertEqual(tagPolicy["branchPolicyCount"] as? Int, 0)
        XCTAssertEqual(tagPolicy["tagPolicyCount"] as? Int, 1)
        XCTAssertEqual(tagPolicy["requiredTagPattern"] as? String, "v*")
        let ruleset = try XCTUnwrap(summary["tagRulesetEvidence"] as? [String: Any])
        XCTAssertEqual(ruleset["excludePatternsVerified"] as? Bool, true)
        XCTAssertEqual(ruleset["bypassActorsVerified"] as? Bool, true)
        XCTAssertEqual(ruleset["rulesetUpdatedAt"] as? String, "2026-01-01T00:00:00Z")
        XCTAssertEqual(ruleset["currentUserCanBypass"] as? String, "never")
        XCTAssertTrue(try XCTUnwrap(ruleset["bypassActors"] as? [Any]).isEmpty)
        let secrets = try XCTUnwrap(summary["releaseSecrets"] as? [String: Any])
        XCTAssertEqual(secrets["storageScope"] as? String, "repository")
        XCTAssertTrue(try XCTUnwrap(secrets["environmentShadowNames"] as? [Any]).isEmpty)
    }

    func testAdministratorPreTagGateRejectsRulesetWithoutVisibleBypassEvidence() throws {
        let fixture = try ReleaseGovernanceFixture(includeBypassActors: false)

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("malformed or incomplete"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsRulesetBypassActor() throws {
        let fixture = try ReleaseGovernanceFixture(bypassActors: [[
            "actor_id": 5,
            "actor_type": "RepositoryRole",
            "bypass_mode": "always"
        ]])

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("sole matching tag ruleset"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsMissingRulesetRevisionOrActorBypassVisibility() throws {
        for fixture in [
            try ReleaseGovernanceFixture(rulesetUpdatedAt: nil),
            try ReleaseGovernanceFixture(currentUserCanBypass: nil)
        ] {
            let result = try runChecker(fixture)
            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(result.stderr.contains("malformed or incomplete"), result.stderr)
        }
    }

    func testAdministratorPreTagGateRejectsCurrentActorBypass() throws {
        let fixture = try ReleaseGovernanceFixture(currentUserCanBypass: "always")

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("sole matching tag ruleset"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsUnsupportedBraceRulesetPattern() throws {
        let fixture = try ReleaseGovernanceFixture(
            includePatterns: ["refs/tags/{v*,release-*}"]
        )

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("expected exactly one active tag ruleset"), result.stderr)
        XCTAssertTrue(result.stderr.contains("found 0"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsMalformedActiveNonmatchingRuleset() throws {
        let fixture = try ReleaseGovernanceFixture()
        try fixture.appendRuleset([
            "id": 18_940_031,
            "name": "Malformed nonmatching tag ruleset",
            "target": "tag",
            "enforcement": "active",
            "conditions": ["ref_name": ["include": ["refs/tags/not-vifty-*"], "exclude": []]],
            "bypass_actors": [],
            "rules": [["type": "update"], ["type": "deletion"]]
        ])

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("malformed or incomplete"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsRulesetWithoutVisibleExclusionEvidence() throws {
        let fixture = try ReleaseGovernanceFixture(includeExcludes: false)

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("malformed or incomplete"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsAmbiguousMatchingRulesetsEvenWhenOnlyOneIsCompliant() throws {
        let fixture = try ReleaseGovernanceFixture(additionalMatchingBypassActors: [[[
            "actor_id": 5,
            "actor_type": "RepositoryRole",
            "bypass_mode": "always"
        ]]])

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("expected exactly one active tag ruleset"), result.stderr)
        XCTAssertTrue(result.stderr.contains("found 2"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsExpectedMainDrift() throws {
        let fixture = try ReleaseGovernanceFixture()

        let result = try runChecker(fixture, expectedMain: String(repeating: "b", count: 40))

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("administrator governance identity/main check failed"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsMissingUpdateOrDeletionRule() throws {
        for ruleTypes in [["update"], ["deletion"]] {
            let fixture = try ReleaseGovernanceFixture(ruleTypes: ruleTypes)
            let result = try runChecker(fixture)
            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(result.stderr.contains("sole matching tag ruleset"), result.stderr)
        }
    }

    func testAdministratorPreTagGateRejectsExistingRemoteTag() throws {
        let fixture = try ReleaseGovernanceFixture(
            remoteTagRefs: "deadbeef\trefs/tags/v1.4.0\n"
        )

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("already exists on Reedtrullz/Vifty"), result.stderr)
    }

    func testFailedRerunRemovesEarlierPassedOutput() throws {
        let fixture = try ReleaseGovernanceFixture()
        let outputURL = fixture.rootURL.appendingPathComponent("governance-output.json")
        XCTAssertEqual(try runChecker(fixture, outputURL: outputURL).exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let failed = try runChecker(
            fixture,
            expectedMain: String(repeating: "b", count: 40),
            outputURL: outputURL
        )

        XCTAssertEqual(failed.exitCode, 65)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testAdministratorPreTagGateRejectsProtectedOutputPathsWithoutMutation() throws {
        let fixture = try ReleaseGovernanceFixture()
        let originalFixtureBytes = try Data(contentsOf: fixture.repoURL)

        var result = try runChecker(fixture, outputURL: fixture.repoURL)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not replace a checker input"), result.stderr)
        XCTAssertEqual(try Data(contentsOf: fixture.repoURL), originalFixtureBytes)

        let gitMetadataOutput = repositoryRoot
            .appendingPathComponent(".git/refs/tags")
            .appendingPathComponent("vifty-governance-output-\(UUID().uuidString)")
        result = try runChecker(fixture, outputURL: gitMetadataOutput)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not be inside Git metadata"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gitMetadataOutput.path))
    }

    func testAdministratorPreTagGateRejectsNonAdministratorEvidence() throws {
        let fixture = try ReleaseGovernanceFixture(repositoryAdmin: false)

        let result = try runChecker(fixture)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("administrator governance identity/main check failed"), result.stderr)
    }

    func testAdministratorPreTagGateRejectsEnvironmentWithoutExactVStarTagPolicy() throws {
        for policy in [
            ["id": 1, "name": "v*", "type": "branch"],
            ["id": 1, "name": "release/*", "type": "tag"]
        ] {
            let fixture = try ReleaseGovernanceFixture(
                environmentDeploymentPolicies: [
                    "total_count": 1,
                    "branch_policies": [policy]
                ]
            )

            let result = try runChecker(fixture)

            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertTrue(result.stderr.contains("must be tag-only with pattern v*"), result.stderr)
        }
    }

    private func runChecker(
        _ fixture: ReleaseGovernanceFixture,
        expectedMain: String? = nil,
        outputURL: URL? = nil
    ) throws -> GovernanceProcessResult {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/check-release-governance.sh")
        process.arguments = [
            "--tag", "v1.4.0",
            "--expected-main", expectedMain ?? fixture.mainSHA,
            "--repo-json-file", fixture.repoURL.path,
            "--branch-json-file", fixture.branchURL.path,
            "--environment-json-file", fixture.environmentURL.path,
            "--branch-protection-json-file", fixture.branchProtectionURL.path,
            "--repository-secret-list-file", fixture.repositorySecretsURL.path,
            "--environment-secret-list-file", fixture.environmentSecretsURL.path,
            "--ruleset-json-file", fixture.rulesetURL.path,
            "--remote-tag-refs-file", fixture.remoteTagRefsURL.path
        ] + (outputURL.map { ["--output", $0.path] } ?? [])

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return GovernanceProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

private struct GovernanceProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ReleaseGovernanceFixture {
    let mainSHA = String(repeating: "a", count: 40)
    let rootURL: URL
    let repoURL: URL
    let branchURL: URL
    let environmentURL: URL
    let branchProtectionURL: URL
    let repositorySecretsURL: URL
    let environmentSecretsURL: URL
    let rulesetURL: URL
    let remoteTagRefsURL: URL

    init(
        repositoryAdmin: Bool = true,
        includeBypassActors: Bool = true,
        bypassActors: [[String: Any]] = [],
        includeExcludes: Bool = true,
        rulesetUpdatedAt: String? = "2026-01-01T00:00:00Z",
        currentUserCanBypass: String? = "never",
        includePatterns: [String] = ["refs/tags/v*"],
        ruleTypes: [String] = ["update", "deletion"],
        additionalMatchingBypassActors: [[[String: Any]]] = [],
        remoteTagRefs: String = "",
        environmentDeploymentBranchPolicy: [String: Any] = [
            "protected_branches": false,
            "custom_branch_policies": true
        ],
        environmentDeploymentPolicies: [String: Any] = [
            "total_count": 1,
            "branch_policies": [[
                "id": 1,
                "name": "v*",
                "type": "tag"
            ]]
        ]
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-governance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        repoURL = rootURL.appendingPathComponent("repo.json")
        branchURL = rootURL.appendingPathComponent("branch.json")
        environmentURL = rootURL.appendingPathComponent("environment.json")
        branchProtectionURL = rootURL.appendingPathComponent("branch-protection.json")
        repositorySecretsURL = rootURL.appendingPathComponent("repository-secrets.tsv")
        environmentSecretsURL = rootURL.appendingPathComponent("environment-secrets.tsv")
        rulesetURL = rootURL.appendingPathComponent("ruleset.json")
        remoteTagRefsURL = rootURL.appendingPathComponent("remote-tag-refs.txt")

        try writeJSON([
            "full_name": "Reedtrullz/Vifty",
            "permissions": ["admin": repositoryAdmin]
        ], to: repoURL)
        try writeJSON([
            "name": "main",
            "protected": true,
            "commit": ["sha": mainSHA]
        ], to: branchURL)
        try writeJSON([
            "name": "release",
            "can_admins_bypass": false,
            "protection_rules": [["type": "branch_policy"]],
            "deployment_branch_policy": environmentDeploymentBranchPolicy,
            "deployment_branch_policies": environmentDeploymentPolicies
        ], to: environmentURL)
        try writeJSON([
            "name": "main",
            "protected": true,
            "commitSHA": mainSHA,
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

        var refName: [String: Any] = ["include": includePatterns]
        if includeExcludes {
            refName["exclude"] = []
        }
        var ruleset: [String: Any] = [
            "id": 18_940_029,
            "name": "Immutable Vifty release tags",
            "target": "tag",
            "enforcement": "active",
            "conditions": [
                "ref_name": refName
            ],
            "rules": ruleTypes.map { ["type": $0] }
        ]
        if includeBypassActors {
            ruleset["bypass_actors"] = bypassActors
        }
        if let rulesetUpdatedAt {
            ruleset["updated_at"] = rulesetUpdatedAt
        }
        if let currentUserCanBypass {
            ruleset["current_user_can_bypass"] = currentUserCanBypass
        }
        var rulesets = [ruleset]
        for (index, actors) in additionalMatchingBypassActors.enumerated() {
            var additional = ruleset
            additional["id"] = 18_940_030 + index
            additional["name"] = "Additional matching Vifty release tags \(index)"
            additional["bypass_actors"] = actors
            rulesets.append(additional)
        }
        try writeJSON(rulesets, to: rulesetURL)
        try remoteTagRefs.write(to: remoteTagRefsURL, atomically: true, encoding: .utf8)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func appendRuleset(_ ruleset: [String: Any]) throws {
        let data = try Data(contentsOf: rulesetURL)
        var rulesets = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        rulesets.append(ruleset)
        try writeJSON(rulesets, to: rulesetURL)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: url)
    }
}
