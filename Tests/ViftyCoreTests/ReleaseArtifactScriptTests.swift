import Foundation
import XCTest

final class ReleaseArtifactScriptTests: XCTestCase {
    private static let immutableV132SourceCommit = "6a771c2ea10386bf7a0a8369a759930f01d56062"

    func testVerifierPinsPublishedInventoryAndEntitlementsToImmutableSourceCommit() throws {
        let historicalSource = try HistoricalReleaseSourceFixture()
        let harness = try ReleaseArtifactHarness(
            publishedSourceCommit: historicalSource.commit,
            schemaSourceCommit: historicalSource.commit,
            sourceRepositoryURL: historicalSource.rootURL,
            supportScripts: ["historical-support.sh"],
            workloadWrappers: ["historical-wrapper.sh"]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.2.3"), result.stdout)
    }

    func testVerifierRejectsPublishedSourceUnavailableFromLocalHistory() throws {
        let unavailableSource = try HistoricalReleaseSourceFixture()
        let unavailableCommit = String(repeating: "a", count: 40)
        let harness = try ReleaseArtifactHarness(
            publishedSourceCommit: unavailableCommit,
            schemaSourceCommit: unavailableSource.commit,
            sourceRepositoryURL: unavailableSource.rootURL,
            supportScripts: ["historical-support.sh"],
            workloadWrappers: ["historical-wrapper.sh"]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("immutable source commit \(unavailableCommit) is unavailable"), result.stderr)
    }

    func testVerifierRejectsPublishedTagThatPeelsToDifferentValidCommit() throws {
        let harness = try ReleaseArtifactHarness(publishedTagCommit: "HEAD")

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release tag v1.2.3 resolves to"), result.stderr)
        XCTAssertTrue(
            result.stderr.contains("not manifest sourceCommit \(Self.immutableV132SourceCommit)"),
            result.stderr
        )
    }

    func testVerifierSelectsHistoricalReleaseWhileCaskRemainsCurrentAndCandidateExists() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.3.3",
            bundleVersion: "1.3.2",
            bundleBuild: 7,
            manifestBuild: 8,
            publishedBuild: 8
        )
        try harness.createSourceTag("v1.3.2", commit: Self.immutableV132SourceCommit)
        try harness.mutateReleaseManifest { manifest in
            var policy = try XCTUnwrap(manifest["releasePolicy"] as? [String: Any])
            policy["signedTagsRequiredFromVersion"] = "1.3.3"
            manifest["releasePolicy"] = policy

            var current = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            current["tagTrust"] = "signed-verified"
            manifest["publishedRelease"] = current

            var historical = current
            historical["version"] = "1.3.2"
            historical["build"] = 7
            historical["tag"] = "v1.3.2"
            historical["artifact"] = "Vifty-v1.3.2.zip"
            historical["checksumAsset"] = "Vifty-v1.3.2.zip.sha256"
            historical["artifactSummary"] = "Vifty-v1.3.2-artifact-summary.json"
            historical["releaseChecklist"] = "Vifty-v1.3.2-release-checklist.md"
            historical["tagTrust"] = "historical-unsigned"
            manifest["historicalReleases"] = [historical]
            manifest["candidate"] = [
                "version": "1.3.4",
                "build": 9,
                "tag": "v1.3.4",
                "artifact": "Vifty-v1.3.4.zip",
                "checksumAsset": "Vifty-v1.3.4.zip.sha256",
                "artifactSummary": "Vifty-v1.3.4-artifact-summary.json",
                "releaseChecklist": "Vifty-v1.3.4-release-checklist.md",
                "sha256": NSNull(),
                "artifactTrust": "pending",
                "signingTrust": "pending",
                "tagTrust": "signed-required",
                "installedReleaseReview": "pending",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ]
        }
        let summaryURL = harness.rootURL.appendingPathComponent("summary/historical-release.json")

        let result = try harness.runVerifier([
            "--release-version", "1.3.2",
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["caskVersion"] as? String, "1.3.3")
        XCTAssertEqual(summary["releaseVersion"] as? String, "1.3.2")
        XCTAssertEqual(summary["releaseTag"] as? String, "v1.3.2")
        XCTAssertEqual(summary["releaseSourceCommit"] as? String, Self.immutableV132SourceCommit)
        XCTAssertEqual(summary["releaseManifestEntryKind"] as? String, "historical")
        XCTAssertEqual(summary["expectedSHASource"] as? String, "manifest sha256")
    }

    func testVerifierRejectsPublishedSourceWithoutHistoricalEntitlements() throws {
        let invalidSource = try HistoricalReleaseSourceFixture(includeEntitlements: false)
        let harness = try ReleaseArtifactHarness(
            publishedSourceCommit: invalidSource.commit,
            schemaSourceCommit: invalidSource.commit,
            sourceRepositoryURL: invalidSource.rootURL,
            supportScripts: ["historical-support.sh"],
            workloadWrappers: ["historical-wrapper.sh"]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("immutable source commit \(invalidSource.commit) is missing Resources/Vifty.entitlements"),
            result.stderr
        )
    }

    func testVerifierUsesCurrentInventoryForCandidate() throws {
        let currentSupportScripts = ReleaseArtifactHarness.currentSupportScripts
            .filter { $0 != "vifty-helper-lifecycle.sh" }
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4",
            supportScripts: currentSupportScripts
        )

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("Contents/Resources/vifty-helper-lifecycle.sh"),
            result.stderr
        )
        XCTAssertTrue(result.stderr.contains("current candidate bundle contract"), result.stderr)
    }

    func testVerifierUsesImmutablePublishedSourceSchemaContract() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.3.2",
            bundleVersion: "1.3.2",
            bundleBuild: 7,
            manifestBuild: 7,
            publishedSourceCommit: Self.immutableV132SourceCommit,
            schemaSourceCommit: Self.immutableV132SourceCommit
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.3.2"), result.stdout)
    }

    func testVerifierRejectsHistoricalSchemaDriftAgainstImmutablePublishedSource() throws {
        let currentSchemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/viftyctl-diagnose.schema.json")
        let currentSchema = try String(contentsOf: currentSchemaURL, encoding: .utf8)
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.3.2",
            bundleVersion: "1.3.2",
            bundleBuild: 7,
            manifestBuild: 7,
            publishedSourceCommit: Self.immutableV132SourceCommit,
            schemaSourceCommit: Self.immutableV132SourceCommit,
            schemaResourceOverrides: ["viftyctl-diagnose.schema.json": currentSchema]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("immutable source commit \(Self.immutableV132SourceCommit)"), result.stderr)
        XCTAssertTrue(result.stderr.contains("does not byte-match reviewed source contract"), result.stderr)
    }

    func testVerifierKeepsCurrentCandidateSchemasFailClosed() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4",
            schemaSourceCommit: Self.immutableV132SourceCommit
        )

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("current candidate schema contract"), result.stderr)
        XCTAssertTrue(result.stderr.contains("release-manifest.schema.json"), result.stderr)
    }

    func testVerifierAcceptsMatchingArtifactWhenSecurityChecksAreExplicitlySkipped() throws {
        let harness = try ReleaseArtifactHarness()

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.2.3"))
        XCTAssertTrue(result.stdout.contains(harness.sha256))
    }

    func testVerifierWritesMachineReadableSummaryWhenRequested() throws {
        let harness = try ReleaseArtifactHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summary/release-artifact-summary.json")

        let result = try harness.runVerifier([
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 2)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/release-artifact-summary.schema.json"
        )
        XCTAssertEqual(summary["caskVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["bundleVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["bundleBuild"] as? Int, 42)
        XCTAssertEqual(summary["bundleIdentifier"] as? String, "tech.reidar.vifty")
        XCTAssertEqual(summary["releaseVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["releaseTag"] as? String, "v1.2.3")
        XCTAssertEqual(summary["releaseSourceCommit"] as? String, Self.immutableV132SourceCommit)
        XCTAssertEqual(summary["releaseManifestEntryKind"] as? String, "published")
        XCTAssertEqual(summary["releaseManifestSHA256"] as? String, harness.releaseManifestSHA256)
        XCTAssertEqual(summary["releaseManifestSchemaVersion"] as? Int, 1)
        XCTAssertEqual(
            summary["runtimeIdentifiers"] as? [String: String],
            [
                "app": "tech.reidar.vifty",
                "daemon": "tech.reidar.vifty.daemon",
                "helper": "tech.reidar.vifty.helper",
                "ctl": "tech.reidar.vifty.ctl"
            ]
        )
        let architectures = try XCTUnwrap(summary["architectures"] as? [String: [String]])
        for key in ["expected", "app", "helper", "daemon", "ctl"] {
            XCTAssertEqual(architectures[key], ["arm64"])
        }
        XCTAssertEqual(summary["actualSHA"] as? String, harness.sha256)
        XCTAssertEqual(summary["expectedSHASource"] as? String, "manifest sha256")
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["signatureChecksSkipped"] as? Bool, true)
        XCTAssertEqual(summary["notarizationChecksSkipped"] as? Bool, true)
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.count, 14)
        XCTAssertEqual(Set(checks.compactMap { $0["name"] as? String }).count, 14)
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "artifact-sha"
                && check["status"] as? String == "passed"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "schema-resources"
                && check["status"] as? String == "passed"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "xpc-trust-metadata"
                && check["status"] as? String == "passed"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "support-scripts"
                && check["status"] as? String == "passed"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "codesign-teamid"
                && check["status"] as? String == "skipped"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "notarization-gatekeeper"
                && check["status"] as? String == "skipped"
        })
    }

    func testVerifierRejectsArtifactHashMismatch() throws {
        let harness = try ReleaseArtifactHarness(caskSHA: String(repeating: "0", count: 64))

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("does not match manifest sha256"))
    }

    func testVerifierAcceptsExpectedSHAOverrideBeforeCaskChecksumIsUpdated() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4",
            caskSHA: String(repeating: "0", count: 64)
        )

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.2.4"))
    }

    func testVerifierRejectsDifferingExpectedSHAOverrideForPublishedRelease() throws {
        let harness = try ReleaseArtifactHarness()

        let result = try harness.runVerifier([
            "--expected-sha", String(repeating: "0", count: 64),
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("--expected-sha conflicts with the selected release's pinned manifest sha256"),
            result.stderr
        )
    }

    func testVerifierRejectsDifferingOverrideForPinnedCandidateWithAndWithoutSummary() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        try harness.pinCandidateSHAInCurrentAndTaggedManifests(harness.sha256)
        let override = String(repeating: "0", count: 64)

        let withoutSummary = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", override,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])
        let withSummary = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", override,
            "--summary", harness.rootURL.appendingPathComponent("summary/pinned-candidate.json").path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        for result in [withoutSummary, withSummary] {
            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(
                result.stderr.contains("--expected-sha conflicts with the selected release's pinned manifest sha256"),
                result.stderr
            )
        }
    }

    func testVerifierAcceptsMatchingOverrideForPinnedCandidateWithManifestSource() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        try harness.pinCandidateSHAInCurrentAndTaggedManifests(harness.sha256)
        let summaryURL = harness.rootURL.appendingPathComponent("summary/pinned-candidate.json")

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["expectedSHASource"] as? String, "manifest sha256")
    }

    func testVerifierRejectsInvalidExpectedSHAOverride() throws {
        let harness = try ReleaseArtifactHarness()

        let result = try harness.runVerifier([
            "--expected-sha", "not-a-sha",
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("--expected-sha must be a lowercase 64-character SHA-256 checksum"))
    }

    func testVerifierRejectsBundleVersionMismatch() throws {
        let harness = try ReleaseArtifactHarness(caskVersion: "1.2.3", bundleVersion: "9.9.9")

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("bundle version 9.9.9 does not match cask version 1.2.3"))
    }

    func testVerifierRejectsBundleBuildThatDoesNotMatchManifest() throws {
        let harness = try ReleaseArtifactHarness(bundleBuild: 43, manifestBuild: 42)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("bundle build 43 does not match release manifest build 42"))
    }

    func testVerifierRejectsWrongBundleIdentifier() throws {
        let harness = try ReleaseArtifactHarness(bundleIdentifier: "tech.reidar.wrong")

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("bundle identifier tech.reidar.wrong does not match release manifest tech.reidar.vifty"))
    }

    func testVerifierRejectsWrongLaunchDaemonIdentity() throws {
        let harness = try ReleaseArtifactHarness(launchDaemonID: "tech.reidar.vifty.wrong")

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("LaunchDaemon Label tech.reidar.vifty.wrong does not match release manifest tech.reidar.vifty.daemon"))
    }

    func testVerifierRejectsAdHocDevelopmentAllowlistInPublicArtifact() throws {
        let harness = try ReleaseArtifactHarness(includeAdHocDevelopmentMetadata: true)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must not contain VIFTY_XPC_ADHOC_* development keys"), result.stderr)
    }

    func testVerifierReportsSelectedCandidateVersionWhenCaskRemainsPublished() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        let summaryURL = harness.rootURL.appendingPathComponent("summary/candidate-release-artifact-summary.json")

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.2.4"), result.stdout)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 2)
        XCTAssertEqual(summary["caskVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["releaseVersion"] as? String, "1.2.4")
        XCTAssertEqual(summary["bundleVersion"] as? String, "1.2.4")
        XCTAssertEqual(summary["expectedArtifactName"] as? String, "Vifty-v1.2.4.zip")
        XCTAssertEqual(summary["releaseTag"] as? String, "v1.2.4")
        XCTAssertEqual(summary["releaseSourceCommit"] as? String, harness.releaseTagCommit)
        XCTAssertEqual(summary["releaseManifestEntryKind"] as? String, "candidate")
        XCTAssertEqual(summary["releaseManifestSHA256"] as? String, harness.releaseManifestSHA256)
        XCTAssertEqual(summary["expectedSHASource"] as? String, "expected sha256")
    }

    func testVerifierKeepsTaggedCandidateIdentityAfterManifestPromotion() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        try harness.promoteCandidateToPublished()
        let summaryURL = harness.rootURL.appendingPathComponent("summary/promoted-release-artifact-summary.json")

        let result = try harness.runVerifier([
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["releaseManifestEntryKind"] as? String, "candidate")
        XCTAssertEqual(summary["releaseManifestSHA256"] as? String, harness.taggedReleaseManifestSHA256)
        XCTAssertEqual(summary["releaseSourceCommit"] as? String, harness.releaseTagCommit)
        XCTAssertEqual(summary["expectedSHASource"] as? String, "manifest sha256")
    }

    func testVerifierRejectsDifferingExpectedSHAOverrideAfterTaggedCandidatePromotion() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        try harness.promoteCandidateToPublished()

        let result = try harness.runVerifier([
            "--expected-sha", String(repeating: "0", count: 64),
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("--expected-sha conflicts with the selected release's pinned manifest sha256"),
            result.stderr
        )
    }

    func testVerifierRejectsPromotedSHAThatDriftsFromPinnedTaggedCandidate() throws {
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4"
        )
        try harness.pinCandidateSHAInCurrentAndTaggedManifests(String(repeating: "a", count: 64))
        try harness.promoteCandidateToPublished()

        let result = try harness.runVerifier([
            "--summary", harness.rootURL.appendingPathComponent("summary/promoted-drift.json").path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("current and tagged manifest sha256 values conflict"),
            result.stderr
        )
    }

    func testVerifierRejectsArchitectureDrift() throws {
        let harness = try ReleaseArtifactHarness(binaryArchitectures: ["arm64", "x86_64"])

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("binary architectures arm64 x86_64 do not match release manifest arm64"))
    }

    func testVerifierRejectsMissingBundledSchemas() throws {
        let harness = try ReleaseArtifactHarness(includeSchemaResources: false)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("missing bundled schema"))
        XCTAssertTrue(result.stderr.contains("Contents/Resources/schemas"))
    }

    func testVerifierRejectsMissingSupportScripts() throws {
        let harness = try ReleaseArtifactHarness(includeSupportScripts: false)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("missing executable support script"))
        XCTAssertTrue(result.stderr.contains("collect-agent-cooling-evidence.sh"))
    }

    func testVerifierRejectsMissingWorkloadWrappers() throws {
        let harness = try ReleaseArtifactHarness(includeWorkloadWrappers: false)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("missing executable workload wrapper"))
        XCTAssertTrue(result.stderr.contains("guarded-run.sh"))
    }

    func testVerifierRejectsInvalidBundledSchemaJSON() throws {
        let harness = try ReleaseArtifactHarness(
            schemaResourceOverrides: [
                "viftyctl-diagnose.schema.json": "{"
            ]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("invalid bundled schema"))
        XCTAssertTrue(result.stderr.contains("viftyctl-diagnose.schema.json"))
        XCTAssertTrue(result.stderr.contains("invalid JSON"))
    }

    func testVerifierRejectsBundledSchemaIDDrift() throws {
        let harness = try ReleaseArtifactHarness(
            schemaResourceOverrides: [
                "viftyctl-status.schema.json": """
                {
                  "$schema": "https://json-schema.org/draft/2020-12/schema",
                  "$id": "https://vifty.local/schemas/wrong.schema.json",
                  "type": "object"
                }
                """
            ]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("invalid bundled schema"))
        XCTAssertTrue(result.stderr.contains("viftyctl-status.schema.json"))
        XCTAssertTrue(result.stderr.contains("$id"))
        XCTAssertTrue(result.stderr.contains("https://vifty.local/schemas/viftyctl-status.schema.json"))
    }

    func testVerifierRejectsSchemaThatKeepsIDButDriftsFromReviewedContract() throws {
        let harness = try ReleaseArtifactHarness(
            schemaResourceOverrides: [
                "viftyctl-status.schema.json": """
                {
                  "$schema": "https://json-schema.org/draft/2020-12/schema",
                  "$id": "https://vifty.local/schemas/viftyctl-status.schema.json",
                  "type": "object"
                }
                """
            ]
        )

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("does not byte-match reviewed source contract"), result.stderr)
    }

    func testVerifierRejectsFormattingOnlySchemaDrift() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/viftyctl-status.schema.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceURL))
        let minified = String(
            decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            as: UTF8.self
        )
        let harness = try ReleaseArtifactHarness(
            caskVersion: "1.2.3",
            bundleVersion: "1.2.4",
            bundleBuild: 43,
            manifestBuild: 43,
            publishedBuild: 42,
            candidateVersion: "1.2.4",
            schemaResourceOverrides: ["viftyctl-status.schema.json": minified]
        )

        let result = try harness.runVerifier([
            "--release-version", "1.2.4",
            "--expected-sha", harness.sha256,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("does not byte-match reviewed source contract"), result.stderr)
    }

    func testVerifierWritesSchemaCompatibleSummaryForManifestFailure() throws {
        let harness = try ReleaseArtifactHarness()
        try harness.corruptReleaseManifest()
        let summaryURL = harness.rootURL.appendingPathComponent("summary/early-failure.json")

        let result = try harness.runVerifier([
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["failureCheck"] as? String, "release-manifest")
        XCTAssertEqual(summary["expectedSHASource"] as? String, "cask sha256")
        for field in [
            "schemaID", "generatedAtUTC", "caskVersion", "caskURL",
            "expectedArtifactName", "artifactPath", "appPath", "bundleVersion",
            "expectedSHA", "actualSHA", "expectedTeamID", "requiredTeamID"
        ] {
            XCTAssertNotNil(summary[field] as? String, "legacy failure summary should contain string field \(field)")
        }
        XCTAssertNotNil(summary["checks"] as? [[String: Any]])
    }

    func testVerifierWritesFailureSummaryWhenBundleVersionMismatches() throws {
        let harness = try ReleaseArtifactHarness(caskVersion: "1.2.3", bundleVersion: "9.9.9")
        let summaryURL = harness.rootURL.appendingPathComponent("summary/failed-release-artifact-summary.json")

        let result = try harness.runVerifier([
            "--summary", summaryURL.path,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/release-artifact-summary.schema.json"
        )
        XCTAssertEqual(summary["failureCheck"] as? String, "bundle-version")
        XCTAssertEqual(summary["failureMessage"] as? String, "bundle version 9.9.9 does not match cask version 1.2.3")
        XCTAssertEqual(summary["caskVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["bundleVersion"] as? String, "9.9.9")
        XCTAssertEqual(summary["actualSHA"] as? String, harness.sha256)
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "bundle-version"
                && check["status"] as? String == "failed"
        })
    }

    func testVerifierRequiresSecurityChecksByDefault() throws {
        let harness = try ReleaseArtifactHarness()

        let result = try harness.runVerifier()

        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testReleaseArtifactSummarySchemaDocumentsVerifierContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/release-artifact-summary.schema.json")
        let schema = try ReleaseArtifactHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/release-artifact-summary.schema.json")

        let variants = try XCTUnwrap(schema["oneOf"] as? [[String: Any]])
        XCTAssertEqual(variants.count, 2)
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let legacy = try XCTUnwrap(defs["legacyVersion1"] as? [String: Any])
        let current = try XCTUnwrap(defs["currentVersion2"] as? [String: Any])
        XCTAssertTrue((legacy["required"] as? [String])?.contains("schemaVersion") == true)
        let required = try XCTUnwrap(current["required"] as? [String])
        for field in [
            "bundleBuild", "bundleIdentifier", "releaseTag", "releaseSourceCommit",
            "releaseManifestEntryKind", "releaseManifestSHA256", "runtimeIdentifiers", "architectures"
        ] {
            XCTAssertTrue(required.contains(field), "version 2 schema should require \(field)")
        }
        XCTAssertFalse((current["allOf"] as? [[String: Any]] ?? []).isEmpty)
    }

    func testReleaseReadinessSchemaDocumentsPreflightContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/release-readiness.schema.json")
        let schema = try ReleaseArtifactHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/release-readiness.schema.json")
        XCTAssertTrue((schema["description"] as? String)?.contains("unsigned-dev tester zip has a `.sha256` sidecar whose SHA-256 digest matches the zip") == true)
        XCTAssertTrue((schema["description"] as? String)?.contains("does not replace future Developer ID artifact verification") == true)

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "version",
            "tag",
            "releaseMode",
            "sourceCommit",
            "status",
            "knownReadinessBlockersClear",
            "checks",
            "blockers"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let checkName = try XCTUnwrap(defs["checkName"] as? [String: Any])
        let checkNames = try XCTUnwrap(checkName["enum"] as? [String])
        XCTAssertTrue(checkNames.contains("release-source-ref"))
        XCTAssertTrue(checkNames.contains("release-mode"))
        XCTAssertTrue(checkNames.contains("source-ci"))
        XCTAssertTrue(checkNames.contains("release-workflow"))
        XCTAssertTrue(checkNames.contains("source-first-unsigned-dev-assets"))

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let releaseMode = try XCTUnwrap(properties["releaseMode"] as? [String: Any])
        let releaseModes = try XCTUnwrap(releaseMode["enum"] as? [String])
        XCTAssertTrue(releaseModes.contains("developer-id"))
        XCTAssertTrue(releaseModes.contains("source-first"))
    }
}

private struct ReleaseArtifactProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class HistoricalReleaseSourceFixture {
    let rootURL: URL
    let commit: String
    let historicalEntitlements: String

    init(includeEntitlements: Bool = true) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-historical-release-source-\(UUID().uuidString)", isDirectory: true)
        historicalEntitlements = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>com.apple.security.network.client</key>
          <true/>
        </dict>
        </plist>
        """
        let fileManager = FileManager.default
        for directory in ["docs/schemas", "Resources", "scripts", "examples/viftyctl"] {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let historicalMakefile = """
        app:
        \tinstall -m 755 scripts/historical-support.sh "$(CONTENTS)/Resources/historical-support.sh"
        \tinstall -m 755 examples/viftyctl/*.sh "$(WRAPPERS)/"
        \tinstall -m 644 examples/viftyctl/README.md "$(WRAPPERS)/README.md"
        \tcodesign --entitlements Resources/Vifty.entitlements Vifty.app
        """
        try historicalMakefile.write(
            to: rootURL.appendingPathComponent("Makefile"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "$id": "https://vifty.local/schemas/historical.schema.json",
          "type": "object"
        }
        """.write(
            to: rootURL.appendingPathComponent("docs/schemas/historical.schema.json"),
            atomically: true,
            encoding: .utf8
        )
        try "historical.schema.json\n".write(
            to: rootURL.appendingPathComponent("scripts/bundled-schema-inventory.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: rootURL.appendingPathComponent("scripts/historical-support.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: rootURL.appendingPathComponent("examples/viftyctl/historical-wrapper.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "Historical wrappers\n".write(
            to: rootURL.appendingPathComponent("examples/viftyctl/README.md"),
            atomically: true,
            encoding: .utf8
        )
        if includeEntitlements {
            try historicalEntitlements.write(
                to: rootURL.appendingPathComponent("Resources/Vifty.entitlements"),
                atomically: true,
                encoding: .utf8
            )
        }
        _ = try Self.run(["init", "--quiet"], at: rootURL)
        _ = try Self.run(["add", "."], at: rootURL)
        _ = try Self.run([
            "-c", "user.name=Vifty Tests",
            "-c", "user.email=vifty-tests@example.invalid",
            "commit", "--quiet", "-m", "historical release contract"
        ], at: rootURL)
        commit = try Self.run(["rev-parse", "HEAD"], at: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try Self.run(["tag", "v1.2.3", commit], at: rootURL)

        let futureMakefile = """
        app:
        \tinstall -m 755 scripts/future-support.sh "$(CONTENTS)/Resources/future-support.sh"
        \tinstall -m 755 examples/viftyctl/*.sh "$(WRAPPERS)/"
        \tinstall -m 644 examples/viftyctl/README.md "$(WRAPPERS)/README.md"
        \tcodesign --entitlements Resources/Vifty.entitlements Vifty.app
        """
        try futureMakefile.write(
            to: rootURL.appendingPathComponent("Makefile"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: rootURL.appendingPathComponent("scripts/future-support.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/usr/bin/env bash\nexit 0\n".write(
            to: rootURL.appendingPathComponent("examples/viftyctl/future-wrapper.sh"),
            atomically: true,
            encoding: .utf8
        )
        try historicalEntitlements.replacingOccurrences(
            of: "com.apple.security.network.client",
            with: "com.apple.security.files.user-selected.read-only"
        ).write(
            to: rootURL.appendingPathComponent("Resources/Vifty.entitlements"),
            atomically: true,
            encoding: .utf8
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func run(_ arguments: [String], at rootURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootURL.path] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 {
            let error = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "HistoricalReleaseSourceFixture",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        return output
    }
}

private final class ReleaseArtifactHarness {
    let rootURL: URL
    let caskURL: URL
    let artifactURL: URL
    let sha256: String
    private let sourceRepositoryURL: URL
    private let selectedReleaseTag: String

    var releaseManifestSHA256: String {
        try! Self.sha256(of: rootURL.appendingPathComponent(".github/release-manifest.json"))
    }

    var taggedReleaseManifestSHA256: String {
        let contents = try! Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-C", sourceRepositoryURL.path,
                "show", "\(selectedReleaseTag)^{commit}:.github/release-manifest.json"
            ]
        )
        let snapshotURL = rootURL.appendingPathComponent("tagged-release-manifest.json")
        try! contents.write(to: snapshotURL, atomically: true, encoding: .utf8)
        return try! Self.sha256(of: snapshotURL)
    }

    var releaseTagCommit: String {
        try! Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", sourceRepositoryURL.path, "rev-parse", "--verify", "\(selectedReleaseTag)^{commit}"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let historicalV132SupportScripts = [
        "collect-agent-cooling-evidence.sh",
        "check-manual-smoke-readiness.sh",
        "check-agent-run-smoke-readiness.sh",
        "collect-agent-run-smoke-evidence.sh"
    ]

    static let currentSupportScripts = [
        "collect-agent-cooling-evidence.sh",
        "check-manual-smoke-readiness.sh",
        "check-agent-run-smoke-readiness.sh",
        "collect-agent-run-smoke-evidence.sh",
        "vifty-helper-lifecycle.sh",
        "repair-vifty-helper.sh",
        "uninstall-vifty.sh"
    ]

    init(
        caskVersion: String = "1.2.3",
        bundleVersion: String = "1.2.3",
        bundleBuild: Int = 42,
        manifestBuild: Int = 42,
        publishedBuild: Int? = nil,
        candidateVersion: String? = nil,
        bundleIdentifier: String = "tech.reidar.vifty",
        launchDaemonID: String = "tech.reidar.vifty.daemon",
        binaryArchitectures: [String] = ["arm64"],
        caskSHA: String? = nil,
        includeSchemaResources: Bool = true,
        includeSupportScripts: Bool = true,
        includeWorkloadWrappers: Bool = true,
        includeAdHocDevelopmentMetadata: Bool = false,
        publishedSourceCommit: String = "6a771c2ea10386bf7a0a8369a759930f01d56062",
        publishedTagCommit: String? = nil,
        schemaSourceCommit: String? = nil,
        schemaResourceOverrides: [String: String] = [:],
        sourceRepositoryURL: URL? = nil,
        supportScripts: [String]? = nil,
        workloadWrappers: [String]? = nil
    ) throws {
        selectedReleaseTag = "v\(candidateVersion ?? caskVersion)"
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-artifact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if let sourceRepositoryURL {
            self.sourceRepositoryURL = sourceRepositoryURL
        } else {
            let repositoryURL = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            let clonedRepositoryURL = rootURL.appendingPathComponent("source-repository", isDirectory: true)
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "clone", "--quiet", "--no-checkout", "--shared",
                    repositoryURL.path, clonedRepositoryURL.path
                ]
            )
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "-C", clonedRepositoryURL.path,
                    "tag", "-f", "v\(caskVersion)", publishedTagCommit ?? publishedSourceCommit
                ]
            )
            if let candidateVersion {
                try Self.run(
                    executable: URL(fileURLWithPath: "/usr/bin/git"),
                    arguments: [
                        "-C", clonedRepositoryURL.path,
                        "tag", "-f", "v\(candidateVersion)", "HEAD"
                    ]
                )
            }
            self.sourceRepositoryURL = clonedRepositoryURL
        }
        let repositoryURL = self.sourceRepositoryURL
        let payloadURL = rootURL.appendingPathComponent("payload", isDirectory: true)
        caskURL = rootURL.appendingPathComponent("Casks/vifty.rb")
        artifactURL = rootURL.appendingPathComponent("Vifty-v\(bundleVersion).zip")

        try FileManager.default.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: caskURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(".github", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("docs/schemas", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Self.copyCurrentCandidateContract(to: rootURL)
        let reviewedSchemasURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas", isDirectory: true)
        for sourceURL in try FileManager.default.contentsOfDirectory(
            at: reviewedSchemasURL,
            includingPropertiesForKeys: nil
        ) where sourceURL.lastPathComponent.hasSuffix(".schema.json") {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: rootURL.appendingPathComponent("docs/schemas/\(sourceURL.lastPathComponent)")
            )
        }
        let effectiveSchemaSourceCommit = schemaSourceCommit
            ?? (candidateVersion == nil ? publishedSourceCommit : nil)
        try Self.writeFakeApp(
            at: payloadURL.appendingPathComponent("Vifty.app", isDirectory: true),
            version: bundleVersion,
            build: bundleBuild,
            bundleIdentifier: bundleIdentifier,
            launchDaemonID: launchDaemonID,
                binaryArchitectures: binaryArchitectures,
                includeSchemaResources: includeSchemaResources,
                includeSupportScripts: includeSupportScripts,
                includeWorkloadWrappers: includeWorkloadWrappers,
                includeAdHocDevelopmentMetadata: includeAdHocDevelopmentMetadata,
                supportScripts: supportScripts
                    ?? (candidateVersion == nil ? Self.historicalV132SupportScripts : Self.currentSupportScripts),
                workloadWrappers: workloadWrappers ?? Self.workloadWrapperScripts,
                sourceRepositoryURL: effectiveSchemaSourceCommit == nil ? rootURL : repositoryURL,
                schemaSourceCommit: effectiveSchemaSourceCommit,
                schemaResourceOverrides: schemaResourceOverrides
            )
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--keepParent", "Vifty.app", artifactURL.path],
            currentDirectoryURL: payloadURL
        )
        sha256 = try Self.sha256(of: artifactURL)
        let effectiveCaskSHA = caskSHA ?? (candidateVersion == nil ? sha256 : String(repeating: "b", count: 64))
        try Self.writeCask(
            at: caskURL,
            version: caskVersion,
            sha: effectiveCaskSHA
        )
        try Self.writeReleaseManifest(
            at: rootURL.appendingPathComponent(".github/release-manifest.json"),
            version: caskVersion,
            build: publishedBuild ?? manifestBuild,
            sha: effectiveCaskSHA,
            candidateVersion: candidateVersion,
            candidateBuild: manifestBuild,
            publishedSourceCommit: publishedSourceCommit
        )
        if let candidateVersion, sourceRepositoryURL == nil {
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", repositoryURL.path, "checkout", "--quiet", "HEAD"]
            )
            let currentRepositoryURL = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            for relativePath in ["Makefile", "Resources/Vifty.entitlements", "scripts", "examples", "docs/schemas"] {
                let sourceURL = currentRepositoryURL.appendingPathComponent(relativePath)
                let destinationURL = repositoryURL.appendingPathComponent(relativePath)
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            let taggedManifestURL = repositoryURL.appendingPathComponent(".github/release-manifest.json")
            try FileManager.default.createDirectory(
                at: taggedManifestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: taggedManifestURL)
            try FileManager.default.copyItem(
                at: rootURL.appendingPathComponent(".github/release-manifest.json"),
                to: taggedManifestURL
            )
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", repositoryURL.path, "add", "--all"]
            )
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "-C", repositoryURL.path,
                    "-c", "user.name=Vifty Tests",
                    "-c", "user.email=vifty-tests@example.invalid",
                    "commit", "--quiet", "-m", "tagged candidate manifest"
                ]
            )
            try Self.run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", repositoryURL.path, "tag", "-f", "v\(candidateVersion)", "HEAD"]
            )
        }
        try Self.writeFakeLipo(at: rootURL.appendingPathComponent("fake-lipo.sh"))
    }

    func runVerifier(_ arguments: [String] = []) throws -> ReleaseArtifactProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/verify-release-artifact.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = [
            "--cask", caskURL.path,
            "--artifact", artifactURL.path
        ] + arguments
        let environment = [
                "VIFTY_RELEASE_ARTIFACT_ROOT": rootURL.path,
                "VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT": sourceRepositoryURL.path,
                "VIFTY_LIPO_PATH": rootURL.appendingPathComponent("fake-lipo.sh").path
            ]
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

        return ReleaseArtifactProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func readJSON(_ url: URL) throws -> [String: Any] {
        try Self.readJSON(url)
    }

    func corruptReleaseManifest() throws {
        try "{\n".write(
            to: rootURL.appendingPathComponent(".github/release-manifest.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    func mutateReleaseManifest(_ mutation: (inout [String: Any]) throws -> Void) throws {
        let manifestURL = rootURL.appendingPathComponent(".github/release-manifest.json")
        var manifest = try Self.readJSON(manifestURL)
        try mutation(&manifest)
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL)
    }

    func createSourceTag(_ tag: String, commit: String) throws {
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", sourceRepositoryURL.path, "tag", "-f", tag, commit]
        )
    }

    func pinCandidateSHAInCurrentAndTaggedManifests(_ pinnedSHA: String) throws {
        try mutateReleaseManifest { manifest in
            var candidate = try XCTUnwrap(manifest["candidate"] as? [String: Any])
            candidate["sha256"] = pinnedSHA
            manifest["candidate"] = candidate
        }

        let taggedManifestURL = sourceRepositoryURL.appendingPathComponent(
            ".github/release-manifest.json"
        )
        var taggedManifest = try Self.readJSON(taggedManifestURL)
        var taggedCandidate = try XCTUnwrap(taggedManifest["candidate"] as? [String: Any])
        taggedCandidate["sha256"] = pinnedSHA
        taggedManifest["candidate"] = taggedCandidate
        try JSONSerialization.data(
            withJSONObject: taggedManifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: taggedManifestURL)
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", sourceRepositoryURL.path, "add", ".github/release-manifest.json"]
        )
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-C", sourceRepositoryURL.path,
                "-c", "user.name=Vifty Tests",
                "-c", "user.email=vifty-tests@example.invalid",
                "-c", "commit.gpgsign=false",
                "commit", "--quiet", "-m", "pin candidate SHA"
            ]
        )
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-C", sourceRepositoryURL.path,
                "-c", "tag.gpgsign=false",
                "tag", "-f", selectedReleaseTag, "HEAD"
            ]
        )
    }

    func promoteCandidateToPublished() throws {
        let commit = releaseTagCommit
        try mutateReleaseManifest { manifest in
            let previous = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
            var candidate = try XCTUnwrap(manifest["candidate"] as? [String: Any])
            candidate["sourceCommit"] = commit
            candidate["sourceCIRunID"] = 3
            candidate["releaseWorkflowRunID"] = 4
            candidate["sha256"] = sha256
            candidate["artifactTrust"] = "passed"
            candidate["signingTrust"] = "developer-id-notarized"
            candidate["tagTrust"] = "signed-verified"
            var historical = manifest["historicalReleases"] as? [[String: Any]] ?? []
            historical.append(previous)
            manifest["historicalReleases"] = historical
            manifest["publishedRelease"] = candidate
            manifest["candidate"] = NSNull()
        }
        try Self.writeCask(at: caskURL, version: "1.2.4", sha: sha256)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private static func writeFakeApp(
        at appURL: URL,
        version: String,
        build: Int,
        bundleIdentifier: String,
        launchDaemonID: String,
        binaryArchitectures: [String],
        includeSchemaResources: Bool,
        includeSupportScripts: Bool,
        includeWorkloadWrappers: Bool,
        includeAdHocDevelopmentMetadata: Bool,
        supportScripts: [String],
        workloadWrappers: [String],
        sourceRepositoryURL: URL,
        schemaSourceCommit: String?,
        schemaResourceOverrides: [String: String]
    ) throws {
        let macOSURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let schemasURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("schemas", isDirectory: true)
        let wrappersURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("viftyctl-wrappers", isDirectory: true)
        let launchDaemonsURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchDaemons", isDirectory: true)

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        if includeSchemaResources {
            try FileManager.default.createDirectory(at: schemasURL, withIntermediateDirectories: true)
            try writeSchemaResources(
                at: schemasURL,
                repositoryURL: sourceRepositoryURL,
                sourceCommit: schemaSourceCommit,
                overrides: schemaResourceOverrides
            )
        }
        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        try writeInfoPlist(
            at: appURL.appendingPathComponent("Contents/Info.plist"),
            version: version,
            build: build,
            bundleIdentifier: bundleIdentifier
        )
        try writeDaemonPlist(
            at: launchDaemonsURL.appendingPathComponent("tech.reidar.vifty.daemon.plist"),
            identity: launchDaemonID,
            includeAdHocDevelopmentMetadata: includeAdHocDevelopmentMetadata
        )
        for executable in ["Vifty", "ViftyHelper", "ViftyDaemon", "viftyctl"] {
            let executableURL = macOSURL.appendingPathComponent(executable)
            try writeExecutable(executableURL)
            try binaryArchitectures.joined(separator: " ").write(
                to: URL(fileURLWithPath: "\(executableURL.path).archs"),
                atomically: true,
                encoding: .utf8
            )
        }
        if includeSupportScripts {
            for script in supportScripts {
                try writeExecutable(resourcesURL.appendingPathComponent(script))
            }
        }
        if includeWorkloadWrappers {
            try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
            for script in workloadWrappers {
                try writeExecutable(wrappersURL.appendingPathComponent(script))
            }
            try "Bundled workload wrappers\n".write(
                to: wrappersURL.appendingPathComponent("README.md"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static let workloadWrapperScripts = [
        "guarded-run.sh",
        "bun-build.sh",
        "bun-test.sh",
        "swift-test.sh",
        "swift-release-build.sh",
        "xcode-build.sh",
        "xcode-test.sh",
        "make-build.sh",
        "make-test.sh",
        "make-verify.sh",
        "npm-build.sh",
        "npm-test.sh",
        "pnpm-build.sh",
        "pnpm-test.sh",
        "go-build.sh",
        "go-test.sh",
        "cargo-build.sh",
        "cargo-test.sh",
        "pytest.sh",
        "uv-build.sh",
        "uv-test.sh",
        "local-model.sh",
        "custom-workload.sh"
    ]

    private static func writeSchemaResources(
        at schemasURL: URL,
        repositoryURL: URL,
        sourceCommit: String?,
        overrides: [String: String]
    ) throws {
        let schemaContents: [String: String]
        if let sourceCommit {
            let listing = try run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "-C", repositoryURL.path,
                    "ls-tree", "-r", "--name-only", sourceCommit, "--", "docs/schemas"
                ]
            )
            schemaContents = try Dictionary(uniqueKeysWithValues: listing
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.hasSuffix(".schema.json") }
                .map { path in
                    let filename = URL(fileURLWithPath: path).lastPathComponent
                    let contents = try run(
                        executable: URL(fileURLWithPath: "/usr/bin/git"),
                        arguments: ["-C", repositoryURL.path, "show", "\(sourceCommit):\(path)"]
                    )
                    return (filename, contents)
                })
        } else {
            let reviewedSchemasURL = repositoryURL.appendingPathComponent("docs/schemas", isDirectory: true)
            schemaContents = try Dictionary(uniqueKeysWithValues: FileManager.default
                .contentsOfDirectory(at: reviewedSchemasURL, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".schema.json") }
                .map { url in
                    (url.lastPathComponent, try String(contentsOf: url, encoding: .utf8))
                })
        }

        let inventoryNames: [String]
        if let sourceCommit {
            let inventory = try? run(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: [
                    "-C", repositoryURL.path,
                    "show", "\(sourceCommit):scripts/bundled-schema-inventory.txt"
                ]
            )
            inventoryNames = inventory?.split(separator: "\n").map(String.init).sorted()
                ?? schemaContents.keys.sorted()
        } else {
            let inventoryURL = repositoryURL.appendingPathComponent("scripts/bundled-schema-inventory.txt")
            inventoryNames = try String(contentsOf: inventoryURL, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
                .sorted()
        }

        for filename in inventoryNames {
            let reviewedContents = try XCTUnwrap(
                schemaContents[filename],
                "bundled schema inventory references missing reviewed source \(filename)"
            )
            let contents = overrides[filename] ?? reviewedContents
            try contents.write(
                to: schemasURL.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private static func writeInfoPlist(
        at url: URL,
        version: String,
        build: Int,
        bundleIdentifier: String
    ) throws {
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>\(bundleIdentifier)</string>
          <key>CFBundleShortVersionString</key>
          <string>\(version)</string>
          <key>CFBundleVersion</key>
          <string>\(build)</string>
        </dict>
        </plist>
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeDaemonPlist(
        at url: URL,
        identity: String,
        includeAdHocDevelopmentMetadata: Bool
    ) throws {
        let developmentMetadata = includeAdHocDevelopmentMetadata
            ? """
            <key>VIFTY_XPC_ADHOC_ALLOWED_UID</key>
            <string>501</string>
            <key>VIFTY_XPC_ADHOC_APP_PATH</key>
            <string>/Applications/Vifty.app/Contents/MacOS/Vifty</string>
            """
            : ""
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(identity)</string>
          <key>MachServices</key>
          <dict>
            <key>\(identity)</key>
            <true/>
          </dict>
          <key>EnvironmentVariables</key>
          <dict>
            <key>VIFTY_XPC_ALLOWED_TEAM_ID</key>
            <string>TEAM123456</string>
            \(developmentMetadata)
          </dict>
        </dict>
        </plist>
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeExecutable(_ url: URL) throws {
        try "#!/usr/bin/env bash\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private static func writeCask(at url: URL, version: String, sha: String) throws {
        let contents = """
        cask "vifty" do
          version "\(version)"
          sha256 "\(sha)"

          url "https://github.com/Reedtrullz/Vifty/releases/download/v#{version}/Vifty-v#{version}.zip"
          depends_on arch: :arm64
        end
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeReleaseManifest(
        at url: URL,
        version: String,
        build: Int,
        sha: String,
        candidateVersion: String?,
        candidateBuild: Int,
        publishedSourceCommit: String
    ) throws {
        let candidate: Any
        if let candidateVersion {
            candidate = [
                "version": candidateVersion,
                "build": candidateBuild,
                "tag": "v\(candidateVersion)",
                "artifact": "Vifty-v\(candidateVersion).zip",
                "checksumAsset": "Vifty-v\(candidateVersion).zip.sha256",
                "artifactSummary": "Vifty-v\(candidateVersion)-artifact-summary.json",
                "releaseChecklist": "Vifty-v\(candidateVersion)-release-checklist.md",
                "sha256": NSNull(),
                "artifactTrust": "pending",
                "signingTrust": "pending",
                "tagTrust": "signed-required",
                "installedReleaseReview": "pending",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ]
        } else {
            candidate = NSNull()
        }
        let manifest: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "schemaVersion": 1,
            "schemaID": "https://vifty.local/schemas/release-manifest.schema.json",
            "product": [
                "bundleID": "tech.reidar.vifty",
                "daemonID": "tech.reidar.vifty.daemon",
                "helperID": "tech.reidar.vifty.helper",
                "ctlID": "tech.reidar.vifty.ctl",
                "architectures": ["arm64"],
                "minimumMacOS": "15.0"
            ],
            "releasePolicy": [
                "developerTeamID": "TEAM123456",
                "signedTagsRequiredFromVersion": candidateVersion ?? "99.0.0"
            ],
            "historicalReleases": [],
            "publishedRelease": [
                "version": version,
                "build": build,
                "tag": "v\(version)",
                "sourceCommit": publishedSourceCommit,
                "sourceCIRunID": 1,
                "releaseWorkflowRunID": 2,
                "artifact": "Vifty-v\(version).zip",
                "checksumAsset": "Vifty-v\(version).zip.sha256",
                "artifactSummary": "Vifty-v\(version)-artifact-summary.json",
                "releaseChecklist": "Vifty-v\(version)-release-checklist.md",
                "sha256": sha,
                "artifactTrust": "passed",
                "signingTrust": "developer-id-notarized",
                "tagTrust": "historical-unsigned",
                "installedReleaseReview": "pending",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ],
            "candidate": candidate
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: url)
    }

    private static func writeFakeLipo(at url: URL) throws {
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "$1" != "-archs" || ! -f "$2.archs" ]]; then
          exit 1
        fi
        cat "$2.archs"
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func copyCurrentCandidateContract(to rootURL: URL) throws {
        let repositoryURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let fileManager = FileManager.default
        try fileManager.copyItem(
            at: repositoryURL.appendingPathComponent("Makefile"),
            to: rootURL.appendingPathComponent("Makefile")
        )
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent("Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(
            at: repositoryURL.appendingPathComponent("Resources/Vifty.entitlements"),
            to: rootURL.appendingPathComponent("Resources/Vifty.entitlements")
        )
        for directory in ["scripts", "examples"] {
            try fileManager.copyItem(
                at: repositoryURL.appendingPathComponent(directory, isDirectory: true),
                to: rootURL.appendingPathComponent(directory, isDirectory: true)
            )
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let output = try run(
            executable: URL(fileURLWithPath: "/usr/bin/shasum"),
            arguments: ["-a", "256", url.path]
        )
        return try XCTUnwrap(output.split(separator: " ").first.map(String.init))
    }

    @discardableResult
    private static func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutString = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderrString = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "ReleaseArtifactHarness",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderrString]
            )
        }
        return stdoutString
    }
}
