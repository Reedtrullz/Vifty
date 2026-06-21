import Foundation
import CryptoKit
import XCTest

final class ValidationEvidenceReviewScriptTests: XCTestCase {
    private func smokeSummarySource(_ url: URL) -> String {
        "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    func testReviewAcceptsSupportedHardwareEvidenceBundle() throws {
        let harness = try ValidationEvidenceReviewHarness()

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode supported-hardware"))
        XCTAssertTrue(result.stderr.contains("manual fan-write smoke-test result is not recorded"))
    }

    func testReviewRejectsSupportedHardwareWhenDaemonControlPathIsNotReady() throws {
        let harness = try ValidationEvidenceReviewHarness(daemonControlPathReady: false)

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("supported hardware reports must have daemonControlPathReady=true"))
    }

    func testReviewRejectsSupportedHardwareWhenManualControlIsActive() throws {
        let harness = try ValidationEvidenceReviewHarness(manualControlActive: true)

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("supported hardware reports must have manualControlActive=false"))
    }

    func testReviewRejectsDiagnoseWithoutRecommendedRecoveryAction() throws {
        let harness = try ValidationEvidenceReviewHarness(includeRecommendedRecoveryAction: false)

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("viftyctl-diagnose.json recommendedRecoveryAction must be one of"))
    }

    func testReviewRejectsCapabilitiesUnavailableForHardwareValidationEvidence() throws {
        let harness = try ValidationEvidenceReviewHarness(capabilitiesStatus: "69")

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("viftyctl-capabilities status \"69\" was not one of 0"))
    }

    func testReviewRejectsSourceEvidenceWithoutImmutableSourceSHA() throws {
        for installSource in ["source-build-tag", "source-first-unsigned-dev-zip", "local-ad-hoc-build"] {
            let harness = try ValidationEvidenceReviewHarness(
                installSource: installSource,
                sourceRef: installSource == "local-ad-hoc-build" ? "" : "v1.2.3",
                sourceSHA: ""
            )

            let result = try harness.runReview(mode: "supported-hardware")

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(
                result.stderr.contains("\(installSource) evidence requires install-provenance.tsv sourceSHA"),
                installSource
            )
        }
    }

    func testReviewRejectsSourceBuildEvidenceWithoutVersionTagRef() throws {
        for installSource in ["source-build-tag", "source-first-unsigned-dev-zip"] {
            let harness = try ValidationEvidenceReviewHarness(
                installSource: installSource,
                sourceRef: "main",
                sourceSHA: String(repeating: "c", count: 40)
            )

            let result = try harness.runReview(mode: "supported-hardware")

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(
                result.stderr.contains("\(installSource) evidence requires install-provenance.tsv sourceRef"),
                installSource
            )
        }
    }

    func testReviewRejectsSchemaResourceDriftEvenWhenSummaryStatusPasses() throws {
        let harness = try ValidationEvidenceReviewHarness(
            schemaResourcesText: ValidationEvidenceReviewHarness.defaultSchemaResourcesTSV
                .replacingOccurrences(
                    of: "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
                    with: "Contents/Resources/schemas/stale-capabilities.schema.json"
                )
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("viftyctl-capabilities.schema.json bundlePath"))
    }

    func testReviewRejectsAdvertisedCapabilitiesSchemaResourceDriftEvenWhenSummaryStatusPasses() throws {
        let harness = try ValidationEvidenceReviewHarness(
            capabilitiesSchemaResourcesText: ValidationEvidenceReviewHarness.defaultCapabilitiesSchemaResourcesTSV
                .replacingOccurrences(
                    of: "status\tContents/Resources/schemas/viftyctl-status.schema.json\tContents/Resources/schemas/viftyctl-status.schema.json",
                    with: "status\tContents/Resources/schemas/stale-status.schema.json\tContents/Resources/schemas/viftyctl-status.schema.json"
                )
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("capabilities-schema-resources.tsv status advertisedResource"))
    }

    func testReviewRejectsCapabilitiesContractDriftEvenWhenSummaryStatusPasses() throws {
        let harness = try ValidationEvidenceReviewHarness(
            capabilitiesContractText: ValidationEvidenceReviewHarness.defaultCapabilitiesContractTSV
                .replacingOccurrences(
                    of: "runLifecycle.autoRestoreAfterChildExit\ttrue\ttrue",
                    with: "runLifecycle.autoRestoreAfterChildExit\tfalse\ttrue"
                )
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("capabilities-contract.tsv runLifecycle.autoRestoreAfterChildExit actual"))
    }

    func testReviewRejectsCapabilitiesPolicyStatusDriftEvenWhenSummaryStatusPasses() throws {
        let harness = try ValidationEvidenceReviewHarness(
            capabilitiesContractText: ValidationEvidenceReviewHarness.defaultCapabilitiesContractTSV
                .replacingOccurrences(
                    of: "policyStatusAvailable\ttrue\ttrue",
                    with: "policyStatusAvailable\tfalse\ttrue"
                )
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("capabilities-contract.tsv policyStatusAvailable actual"))
    }

    func testReviewRejectsCapabilitiesPolicyEnabledDriftEvenWhenSummaryStatusPasses() throws {
        let harness = try ValidationEvidenceReviewHarness(
            capabilitiesContractText: ValidationEvidenceReviewHarness.defaultCapabilitiesContractTSV
                .replacingOccurrences(
                    of: "policy.enabled\ttrue\ttrue",
                    with: "policy.enabled\tfalse\ttrue"
                )
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("capabilities-contract.tsv policy.enabled actual"))
    }

    func testReviewRejectsReviewSummaryTSVStatusDrift() throws {
        let harness = try ValidationEvidenceReviewHarness(
            reviewSummaryTSVStatusOverrides: ["capabilities-contract": "1"]
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("review-summary.tsv capabilities-contract status \"1\" did not match review-summary.json \"0\""))
    }

    func testReviewRejectsManifestStatusDriftFromReviewSummary() throws {
        let harness = try ValidationEvidenceReviewHarness(
            manifestStatusOverrides: ["capabilities-contract": "1"]
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("manifest.tsv capabilities-contract status \"1\" did not match review-summary.json \"0\""))
    }

    func testReviewRejectsManifestMissingOutputFile() throws {
        let harness = try ValidationEvidenceReviewHarness(
            manifestStdoutOverrides: ["capabilities-contract": "missing.tsv"]
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("manifest.tsv capabilities-contract stdout references missing file missing.tsv"))
    }

    func testReviewRejectsChecksumDriftForCapturedEvidenceFiles() throws {
        let harness = try ValidationEvidenceReviewHarness()
        try "readOnly=true\ncoolingCommandsRun=false\ntampered=true\n".write(
            to: harness.bundleURL.appendingPathComponent("metadata.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("checksums.tsv metadata.txt sha256"))
    }

    func testReviewRejectsMissingChecksumEntryForCapturedEvidenceFile() throws {
        let harness = try ValidationEvidenceReviewHarness()
        try harness.removeChecksumEntry(for: "metadata.txt")

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("checksums.tsv is missing file metadata.txt"))
    }

    func testReviewAllowsExistingReviewerSummaryWithoutChecksumEntry() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.bundleURL.appendingPathComponent("review-result.json")
        try "{\"status\":\"old\"}\n".write(to: summaryURL, atomically: true, encoding: .utf8)

        let result = try harness.runReview(mode: "supported-hardware", summaryURL: summaryURL)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode supported-hardware"))
    }

    func testReviewRejectsSupportedHardwareEvidenceWithoutProbeLocal() throws {
        let harness = try ValidationEvidenceReviewHarness(
            probeLocalStatus: "skipped",
            probeLocalText: "Skipped. Re-run with --include-probe-local."
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("viftyhelper-probeLocal status \"skipped\""))
        XCTAssertTrue(result.stderr.contains("viftyhelper-probeLocal.txt is missing fan["))
    }

    func testReviewRejectsEvidenceBundleWithPrivacyFindings() throws {
        let harness = try ValidationEvidenceReviewHarness(
            privacyReviewStatus: "1",
            privacyReviewText: """
            finding\tfile\tline\tkind
            redaction-needed\tviftyctl-status.json\t1\tserial-number-label
            """
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("privacy-review status \"1\" was not one of 0"))
    }

    func testReviewAcceptsUnsupportedHardwareSafeBlockBundle() throws {
        let harness = try ValidationEvidenceReviewHarness(
            diagnoseStatus: "75",
            diagnose: .unsupportedBlocked
        )

        let result = try harness.runReview(mode: "unsupported-hardware")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode unsupported-hardware"))
    }

    func testReviewRejectsUnsupportedHardwareWhenDaemonControlPathIsNotReady() throws {
        let harness = try ValidationEvidenceReviewHarness(
            diagnoseStatus: "75",
            diagnose: .unsupportedBlocked,
            daemonControlPathReady: false
        )

        let result = try harness.runReview(mode: "unsupported-hardware")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("unsupported hardware reports must have daemonControlPathReady=true"))
    }

    func testReviewAcceptsInstalledReleaseTrustEvidenceBundle() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode release"))
    }

    func testReviewRejectsSourceFirstUnsignedZipAsReleaseTrustEvidence() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            installSource: "source-first-unsigned-dev-zip",
            sourceRef: "v1.1.0",
            sourceSHA: String(repeating: "c", count: 40),
            sourceArtifactName: "Vifty-v1.1.0-unsigned-dev.zip",
            sourceArtifactSHA256: String(repeating: "d", count: 64)
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release mode requires installSource notarized-github-release, homebrew-cask, or local-developer-id-build"))
    }

    func testReviewWarnsWhenSourceFirstUnsignedZipOmitsArtifactChecksum() throws {
        let harness = try ValidationEvidenceReviewHarness(
            installSource: "source-first-unsigned-dev-zip",
            sourceRef: "v1.1.0",
            sourceSHA: String(repeating: "c", count: 40),
            sourceArtifactName: "",
            sourceArtifactSHA256: "",
            sourceArtifactBytes: ""
        )

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("source-first unsigned-dev zip evidence should include sourceArtifactSHA256"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseSummaryCheckWasSkipped() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            releaseSummaryCheckStatus: "skipped"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release-artifact-summary.json check codesign-teamid status \"skipped\" must be passed"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseSummaryChecksumMismatches() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            releaseSummaryActualSHA: String(repeating: "b", count: 64)
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release-artifact-summary.json expectedSHA must match actualSHA"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseSummaryArtifactNameDrifts() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            releaseSummaryExpectedArtifactName: "Vifty-v9.9.9.zip"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release-artifact-summary.json expectedArtifactName must be Vifty-v1.2.3.zip"))
    }

    func testReviewRejectsReleaseEvidenceWhenNotarizationWasSkipped() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            notarizationChecksSkipped: true
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release evidence must not skip notarization checks"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseSummarySchemaIDDrifts() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            releaseSummarySchemaID: "https://vifty.local/schemas/old-release-summary.schema.json"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release-artifact-summary.json schemaID must be https://vifty.local/schemas/release-artifact-summary.schema.json"))
    }

    func testReviewRejectsReleaseEvidenceWithoutReleaseChecklist() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: false,
            releaseArtifactStatus: "0"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("missing required file for release mode: release-checklist.md"))
        XCTAssertTrue(result.stderr.contains("release mode requires review-summary.json releaseChecklistPath"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseChecklistVersionDrifts() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            includeReleaseChecklist: true,
            releaseArtifactStatus: "0",
            releaseChecklistVersion: "9.9.9"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release checklist titleVersion must match release caskVersion"))
        XCTAssertTrue(result.stderr.contains("release checklist installedAppBundleVersion must match release bundleVersion"))
    }

    func testReviewWritesPassingMachineReadableSummary() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/supported-review.json")

        let result = try harness.runReview(mode: "supported-hardware", summaryURL: summaryURL)

        XCTAssertEqual(result.exitCode, 0)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/validation-review-result.schema.json"
        )
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["mode"] as? String, "supported-hardware")
        let summaryBundlePath = try XCTUnwrap(summary["bundlePath"] as? String)
        XCTAssertEqual(summaryBundlePath, harness.bundleURL.lastPathComponent)
        XCTAssertFalse(summaryBundlePath.contains(harness.rootURL.path))
        XCTAssertFalse(summaryBundlePath.hasPrefix("/"))
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["installSource"] as? String, "local-developer-id-build")
        XCTAssertEqual(summary["sourceRef"] as? String, "v1.2.3")
        XCTAssertEqual(summary["sourceSHA"] as? String, String(repeating: "a", count: 40))
        XCTAssertEqual(summary["sourceArtifactName"] as? String, "Vifty-v1.2.3.zip")
        XCTAssertEqual(summary["sourceArtifactSHA256"] as? String, String(repeating: "b", count: 64))
        XCTAssertEqual(summary["sourceArtifactBytes"] as? String, "12345")
        XCTAssertEqual(summary["diagnoseState"] as? String, "ready")
        XCTAssertEqual(summary["recommendedAgentAction"] as? String, "requestCooling")
        XCTAssertEqual(summary["recommendedRecoveryAction"] as? String, "none")
        XCTAssertEqual(summary["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(summary["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(summary["manualControlActive"] as? Bool, false)
        XCTAssertEqual(summary["failedCheckIDs"] as? [String], [])
        XCTAssertEqual(summary["coolingBlockerIDs"] as? [String], [])
        XCTAssertEqual(summary["modelIdentifier"] as? String, "MacBookPro18,3")
        XCTAssertEqual(summary["modelFamily"] as? String, "MacBookPro18")
        XCTAssertEqual(summary["isAppleSilicon"] as? Bool, true)
        XCTAssertEqual(summary["isMacBookPro"] as? Bool, true)
        XCTAssertEqual(summary["fanCount"] as? Int, 2)
        XCTAssertEqual(summary["controllableFanCount"] as? Int, 2)
        XCTAssertEqual(summary["temperatureSensorCount"] as? Int, 2)
        XCTAssertEqual(summary["thermalPressure"] as? String, "nominal")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "not-recorded")
        XCTAssertEqual(summary["manualSmokeTestSource"] as? String, "")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "not-recorded")
        XCTAssertEqual(summary["agentRunSmokeSource"] as? String, "")
        XCTAssertTrue((summary["failures"] as? [String])?.isEmpty == true)
        XCTAssertTrue((summary["warnings"] as? [String])?.contains {
            $0.contains("manual fan-write smoke-test result")
        } == true)
    }

    func testReviewRejectsContradictoryDiagnoseCoolingBlockerIDs() throws {
        let harness = try ValidationEvidenceReviewHarness(
            failedCheckIDs: ["thermalPressureSafe"],
            coolingBlockerIDs: ["manualControlClear"]
        )
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/blocker-id-review.json")

        let result = try harness.runReview(mode: "supported-hardware", summaryURL: summaryURL)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("coolingBlockerIDs must be empty when safeToRequestCooling=true"), result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["failedCheckIDs"] as? [String], ["thermalPressureSafe"])
        XCTAssertEqual(summary["coolingBlockerIDs"] as? [String], ["manualControlClear"])
    }

    func testReviewWritesValidatedManualSmokeSummary() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/validated-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42"
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stderr.contains("manual fan-write smoke-test result is not recorded"))
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["manualSmokeTestSource"] as? String, "https://github.com/reidar/vifty/issues/42")
        XCTAssertTrue((summary["warnings"] as? [String])?.isEmpty == true)
    }

    func testReviewRejectsValidatedManualSmokeWithoutSource() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/source-less-manual-smoke-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("manual smoke result passed-auto-restored requires --manual-smoke-source"))
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["manualSmokeTestSource"] as? String, "")
    }

    func testReviewRejectsLocalAdHocManualSmokeWithoutReadinessSummary() throws {
        let harness = try ValidationEvidenceReviewHarness(
            installSource: "local-ad-hoc-build",
            sourceRef: "main",
            sourceSHA: String(repeating: "1", count: 40)
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed local-ad-hoc manual smoke requires --manual-smoke-readiness-summary"),
            result.stderr
        )
    }

    func testReviewWritesValidatedLocalAdHocManualSmokeReadinessSummary() throws {
        let harness = try ValidationEvidenceReviewHarness(
            installSource: "local-ad-hoc-build",
            sourceRef: "main",
            sourceSHA: String(repeating: "1", count: 40)
        )
        let readinessSummaryURL = try harness.writeManualSmokeReadinessSummary()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/local-ad-hoc-manual-smoke-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            manualSmokeReadinessSummaryURL: readinessSummaryURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["manualSmokeReadinessSource"] as? String, smokeSummarySource(readinessSummaryURL))
        XCTAssertTrue((summary["warnings"] as? [String])?.isEmpty == true)
    }

    func testReviewRejectsLocalAdHocManualSmokeWhenReadinessDaemonDoesNotMatchBuild() throws {
        let harness = try ValidationEvidenceReviewHarness(
            installSource: "local-ad-hoc-build",
            sourceRef: "main",
            sourceSHA: String(repeating: "1", count: 40)
        )
        let readinessSummaryURL = try harness.writeManualSmokeReadinessSummary(daemonRuntimeMatchesExpected: false)

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            manualSmokeReadinessSummaryURL: readinessSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed local-ad-hoc manual smoke readiness summary must match the installed daemon to the expected build daemon"),
            result.stderr
        )
    }

    func testReviewWritesValidatedAgentRunSmokeSummary() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/agent-run-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeResult: "passed-auto-restored",
            agentRunSmokeSource: "https://github.com/reidar/vifty/issues/42#agent-run-smoke"
        )

        XCTAssertEqual(result.exitCode, 0)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["agentRunSmokeSource"] as? String, "https://github.com/reidar/vifty/issues/42#agent-run-smoke")
        XCTAssertTrue((summary["warnings"] as? [String])?.isEmpty == true)
    }

    func testReviewDerivesValidatedAgentRunSmokeFromCapturedSummary() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            startupMode: "Auto",
            startupModeSource: "persisted"
        )
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/captured-agent-run-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["agentRunSmokeSource"] as? String, smokeSummarySource(smokeSummaryURL))
        XCTAssertEqual(summary["agentRunSmokeStartupMode"] as? String, "Auto")
        XCTAssertEqual(summary["agentRunSmokeStartupModeSource"] as? String, "persisted")
        XCTAssertEqual(summary["agentRunSmokeStartupModeReadError"] as? String, "")
        XCTAssertTrue((summary["warnings"] as? [String])?.isEmpty == true)
    }

    func testReviewDerivesValidatedAgentRunSmokeFromCapturedSummaryWithStructuredRateLimitRetry() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            rateLimitRetryAttempted: true,
            rateLimitRetryAfterSeconds: 2
        )
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/captured-agent-run-retry-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "passed-auto-restored")
        XCTAssertEqual(summary["agentRunSmokeSource"] as? String, smokeSummarySource(smokeSummaryURL))
        XCTAssertTrue((summary["warnings"] as? [String])?.isEmpty == true)
    }

    func testReviewRejectsAgentRunSmokeRateLimitRetryWithoutStructuredCooldownJSON() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            rateLimitRetryAttempted: true,
            rateLimitInitialStdoutContents: #"{"coolingLeasePrepared":false,"autoRestoreAttempted":false,"retryAfterSeconds":2}"#
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke initial viftyctl-run JSON must be PREPARE_RATE_LIMITED cooldown evidence matching rateLimitRetry"),
            result.stderr
        )
    }

    func testReviewRejectsAgentRunSmokeRateLimitRetryWhenRunDoesNotReferenceRetryCommand() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            rateLimitRetryAttempted: true,
            runStdoutOverride: "viftyctl-run.json",
            runStderrOverride: "viftyctl-run.stderr"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke summary run.stdout must reference viftyctl-run-retry stdout after rate-limit retry"),
            result.stderr
        )
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke summary run.stderr must reference viftyctl-run-retry stderr after rate-limit retry"),
            result.stderr
        )
    }

    func testReviewRejectsAgentRunSmokeRateLimitRetryWhenInitialStatusMismatchesCommand() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            rateLimitRetryAttempted: true,
            rateLimitInitialExitStatus: 75,
            rateLimitInitialMetadataExitStatus: 1
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke summary rateLimitRetry.initialExitStatus must match viftyctl-run command status"),
            result.stderr
        )
    }

    func testReviewRejectsAgentRunSmokeSummaryWhenBundleChecksumDrifts() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(status: "passed")
        try harness.overwriteAgentRunSmokeBundleFile(
            summaryURL: smokeSummaryURL,
            filename: "viftyctl-run.json",
            contents: #"{"coolingLeasePrepared":false}"#
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke checksums.tsv viftyctl-run.json sha256"),
            result.stderr
        )
    }

    func testReviewRejectsAgentRunSmokeSummarySchemaDrift() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            schemaID: "https://example.invalid/agent-run-smoke.schema.json"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("agent-run-smoke summary schemaID must be https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json"))
    }

    func testReviewRejectsAgentRunSmokeLocalAdHocProvenanceWithoutSourceSHA() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            installSource: "local-ad-hoc-build",
            sourceRef: "main",
            sourceSHA: ""
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke summary local-ad-hoc-build evidence requires sourceSHA"),
            result.stderr
        )
    }

    func testReviewRejectsFailedCapturedAgentRunSmokeForSupportedHardware() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(status: "failed", runExitStatus: 70)
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/failed-captured-agent-run-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("supported hardware validation cannot pass with a failed supervised viftyctl run smoke test"))
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "failed")
        XCTAssertEqual(summary["agentRunSmokeSource"] as? String, smokeSummarySource(smokeSummaryURL))
    }

    func testReviewRejectsPassedAgentRunSmokeWithoutSuccessfulAutoRestoreEvidence() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            autoRestoreSucceeded: false
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must report autoRestoreSucceeded=true"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithoutResolvedChildExecutableEvidence() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            resolvedChildExecutable: nil
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must report absolute resolvedChildExecutable when capabilities advertise resolvedChildExecutableReported"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWhenExecutableDigestDiffersFromFinalRunJSON() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            resolvedChildExecutableSHA256: String(repeating: "a", count: 64),
            finalRunResolvedChildExecutableSHA256: String(repeating: "b", count: 64)
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke final run JSON resolvedChildExecutableSHA256 must match summary run.resolvedChildExecutableSHA256"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWhenExecutableDigestStatusDiffersFromFinalRunJSON() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            resolvedChildExecutableSHA256: nil,
            resolvedChildExecutableSHA256Status: "unavailable",
            finalRunResolvedChildExecutableSHA256Status: "computed"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke final run JSON resolvedChildExecutableSHA256Status must match summary run.resolvedChildExecutableSHA256Status"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWhenDigestStatusComputedWithoutDigest() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeBundleSummary(
            status: "passed",
            resolvedChildExecutableSHA256: nil,
            resolvedChildExecutableSHA256Status: "computed"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary resolvedChildExecutableSHA256Status computed requires resolvedChildExecutableSHA256"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithoutDaemonBackedCapabilities() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            daemonStatusAvailable: false,
            policySource: "fallbackUnavailable",
            policyStatusAvailable: true
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have daemon-backed capabilities policy status"),
            result.stderr
        )
    }

    func testReviewRejectsPassedLocalAdHocAgentRunSmokeWhenInstalledDaemonDoesNotMatchBuild() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            installSource: "local-ad-hoc-build",
            sourceRef: "main",
            sourceSHA: String(repeating: "1", count: 40),
            daemonRuntimeMatchesExpected: false,
            daemonRuntimeMatchRequired: true
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed local-ad-hoc agent-run-smoke summary must match the installed daemon to the expected build daemon"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithManualControlActive() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            manualControlActive: true
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have manualControlActive=false"),
            result.stderr
        )
    }

    func testReviewRejectsAgentRunSmokeSummaryWhenAppPreferencesDriftFromPreDiagnose() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(status: "passed")
        var summary = try harness.readJSON(smokeSummaryURL)
        var preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        preflight["appPreferences"] = [
            "startupMode": "Curve",
            "startupModeSource": "persisted",
            "readError": NSNull()
        ]
        summary["preflight"] = preflight
        try harness.overwriteAgentRunSmokeBundleJSON(
            summaryURL: smokeSummaryURL,
            filename: "agent-run-smoke-evidence-summary.json",
            value: summary,
            refreshChecksums: false
        )
        try harness.overwriteAgentRunSmokeBundleJSON(
            summaryURL: smokeSummaryURL,
            filename: "pre-diagnose.json",
            value: [
                "state": "ready",
                "safeToRequestCooling": true,
                "daemonControlPathReady": true,
                "appPreferences": [
                    "startupMode": "Auto",
                    "startupModeSource": "defaultMissingFile",
                    "readError": NSNull()
                ]
            ],
            refreshChecksums: true
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("agent-run-smoke summary preflight.appPreferences must match pre-diagnose appPreferences"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithDisabledPolicy() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            policyEnabled: false
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have policyEnabled=true"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithCapabilitiesSchemaDrift() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            capabilitiesSchemaVersion: 2,
            capabilitiesSchemaID: "https://example.invalid/viftyctl-capabilities.schema.json"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have capabilitiesSchemaVersion=1"),
            result.stderr
        )
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have capabilitiesSchemaID=https://vifty.local/schemas/viftyctl-capabilities.schema.json"),
            result.stderr
        )
    }

    func testReviewRejectsPassedAgentRunSmokeWithDiagnoseOrCommandErrorSchemaDrift() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let smokeSummaryURL = try harness.writeAgentRunSmokeSummary(
            status: "passed",
            diagnoseSchemaID: "https://example.invalid/viftyctl-diagnose.schema.json",
            commandErrorSchemaID: "https://example.invalid/viftyctl-command-error.schema.json"
        )

        let result = try harness.runReview(
            mode: "supported-hardware",
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeSummaryURL: smokeSummaryURL
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have diagnoseSchemaID=https://vifty.local/schemas/viftyctl-diagnose.schema.json"),
            result.stderr
        )
        XCTAssertTrue(
            result.stderr.contains("passed agent-run-smoke summary must have commandErrorSchemaID=https://vifty.local/schemas/viftyctl-command-error.schema.json"),
            result.stderr
        )
    }

    func testReviewRejectsFailedManualSmokeForSupportedHardware() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("failed-smoke-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "failed"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("supported hardware validation requires manual smoke result passed-auto-restored"))
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "failed")
    }

    func testReviewRejectsFailedAgentRunSmokeForSupportedHardware() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("failed-agent-run-review.json")

        let result = try harness.runReview(
            mode: "supported-hardware",
            summaryURL: summaryURL,
            manualSmokeResult: "passed-auto-restored",
            manualSmokeSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeResult: "failed"
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("supported hardware validation cannot pass with a failed supervised viftyctl run smoke test"))
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["agentRunSmokeResult"] as? String, "failed")
    }

    func testReviewWritesFailedMachineReadableSummary() throws {
        let harness = try ValidationEvidenceReviewHarness(
            probeLocalStatus: "skipped",
            probeLocalText: "Skipped. Re-run with --include-probe-local."
        )
        let summaryURL = harness.rootURL.appendingPathComponent("failed-review.json")

        let result = try harness.runReview(mode: "supported-hardware", summaryURL: summaryURL)

        XCTAssertEqual(result.exitCode, 65)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["status"] as? String, "failed")
        XCTAssertEqual(summary["mode"] as? String, "supported-hardware")
        let failures = try XCTUnwrap(summary["failures"] as? [String])
        XCTAssertTrue(failures.contains { $0.contains("viftyhelper-probeLocal status") })
        XCTAssertTrue(failures.contains { $0.contains("viftyhelper-probeLocal.txt is missing fan[") })
    }
}

private struct ValidationEvidenceReviewProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private enum ValidationEvidenceDiagnoseFixture {
    case supportedReady
    case unsupportedBlocked

    var status: String {
        switch self {
        case .supportedReady:
            "ready"
        case .unsupportedBlocked:
            "blocked"
        }
    }

    var recommendedAgentAction: String {
        switch self {
        case .supportedReady:
            "requestCooling"
        case .unsupportedBlocked:
            "doNotRequestCooling"
        }
    }

    var recommendedRecoveryAction: String {
        switch self {
        case .supportedReady:
            "none"
        case .unsupportedBlocked:
            "collectHardwareEvidence"
        }
    }

    var safeToRequestCooling: Bool {
        switch self {
        case .supportedReady:
            true
        case .unsupportedBlocked:
            false
        }
    }

    var daemonControlPathReady: Bool {
        true
    }

    var isAppleSilicon: Bool {
        switch self {
        case .supportedReady:
            true
        case .unsupportedBlocked:
            false
        }
    }

    var isMacBookPro: Bool {
        switch self {
        case .supportedReady:
            true
        case .unsupportedBlocked:
            false
        }
    }

    var supportedHardwareCheckPasses: Bool {
        switch self {
        case .supportedReady:
            true
        case .unsupportedBlocked:
            false
        }
    }
}

private final class ValidationEvidenceReviewHarness {
    let rootURL: URL
    let bundleURL: URL

    init(
        diagnoseStatus: String = "0",
        diagnose: ValidationEvidenceDiagnoseFixture = .supportedReady,
        probeLocalStatus: String = "0",
        probeLocalText: String = "fan[0] id=0 name=\"Left Fan\" currentRPM=2200 minimumRPM=1400 maximumRPM=6800 hardwareMode=Auto hardwareModeRawValue=0 hardwareModeKey=F0Md targetRPM=nil",
        privacyReviewStatus: String = "0",
        privacyReviewText: String = "finding\tfile\tline\tkind\nnone\t-\t-\tpassed\n",
        capabilitiesStatus: String = "0",
        reviewSummaryTSVStatusOverrides: [String: String] = [:],
        manifestStatusOverrides: [String: String] = [:],
        manifestStdoutOverrides: [String: String] = [:],
        manifestStderrOverrides: [String: String] = [:],
        schemaResourcesText: String? = nil,
        capabilitiesSchemaResourcesText: String? = nil,
        capabilitiesContractText: String? = nil,
        daemonControlPathReady: Bool? = nil,
        manualControlActive: Bool = false,
        failedCheckIDs: [String] = [],
        coolingBlockerIDs: [String] = [],
        includeRecommendedRecoveryAction: Bool = true,
        includeReleaseSummary: Bool = false,
        includeReleaseChecklist: Bool = false,
        releaseArtifactStatus: String = "skipped",
        signatureChecksSkipped: Bool = false,
        notarizationChecksSkipped: Bool = false,
        releaseSummarySchemaID: String = "https://vifty.local/schemas/release-artifact-summary.schema.json",
        releaseSummaryExpectedArtifactName: String = "Vifty-v1.2.3.zip",
        releaseSummaryExpectedSHA: String = String(repeating: "a", count: 64),
        releaseSummaryActualSHA: String = String(repeating: "a", count: 64),
        releaseSummaryCheckStatus: String = "passed",
        releaseChecklistVersion: String = "1.2.3",
        launchDaemonTeamID: String = "TEAMID1234",
        installSource: String = "local-developer-id-build",
        sourceRef: String = "v1.2.3",
        sourceSHA: String = String(repeating: "a", count: 40),
        sourceArtifactName: String = "Vifty-v1.2.3.zip",
        sourceArtifactSHA256: String = String(repeating: "b", count: 64),
        sourceArtifactBytes: String = "12345"
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-validation-review-\(UUID().uuidString)", isDirectory: true)
        bundleURL = rootURL.appendingPathComponent("evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var statuses: [String: String] = [
            "app-info-plist": "0",
            "install-provenance": "0",
            "bundle-executables": "0",
            "privacy-review": privacyReviewStatus,
            "schema-resources": "0",
            "capabilities-schema-resources": "0",
            "capabilities-contract": "0",
            "launchdaemon-lint": "0",
            "viftyctl-capabilities": capabilitiesStatus,
            "viftyctl-status": "0",
            "viftyctl-diagnose": diagnoseStatus,
            "viftyctl-audit": "0",
            "viftyhelper-probeLocal": probeLocalStatus,
            "release-artifact-summary": releaseArtifactStatus,
            "release-checklist": includeReleaseChecklist ? "0" : "skipped",
            "launchdaemon-teamid": "0",
            "launchctl-print-daemon": "0",
            "codesign-verify-app": "0",
            "codesign-verify-viftyctl": "0",
            "codesign-verify-viftyhelper": "0",
            "codesign-verify-viftydaemon": "0",
            "spctl-assess-app": "0",
            "stapler-validate-app": "0"
        ]
        if includeReleaseSummary {
            statuses["release-artifact-summary"] = releaseArtifactStatus
        }

        let reviewSummaryTSVStatuses = statuses.merging(reviewSummaryTSVStatusOverrides) { _, new in new }
        try writeReviewSummary(
            statuses: statuses,
            releaseArtifactSummaryPath: includeReleaseSummary ? "/tmp/Vifty-v1.2.3-artifact-summary.json" : "",
            releaseChecklistPath: includeReleaseChecklist ? "/tmp/Vifty-v\(releaseChecklistVersion)-release-checklist.md" : ""
        )
        try writeText("review-summary.tsv", contents: tsvSummary(reviewSummaryTSVStatuses))
        try writeText("metadata.txt", contents: "readOnly=true\ncoolingCommandsRun=false\n")
        try writeInstallProvenance(
            installSource: installSource,
            sourceRef: sourceRef,
            sourceSHA: sourceSHA,
            sourceArtifactName: sourceArtifactName,
            sourceArtifactSHA256: sourceArtifactSHA256,
            sourceArtifactBytes: sourceArtifactBytes
        )
        try writeText("bundle-executables.tsv", contents: bundleExecutablesTSV)
        try writeText("privacy-review.tsv", contents: privacyReviewText)
        try writeText("schema-resources.tsv", contents: schemaResourcesText ?? Self.defaultSchemaResourcesTSV)
        try writeText(
            "capabilities-schema-resources.tsv",
            contents: capabilitiesSchemaResourcesText ?? Self.defaultCapabilitiesSchemaResourcesTSV
        )
        try writeText("capabilities-contract.tsv", contents: capabilitiesContractText ?? Self.defaultCapabilitiesContractTSV)
        try writeDiagnose(
            diagnose,
            daemonControlPathReady: daemonControlPathReady ?? diagnose.daemonControlPathReady,
            manualControlActive: manualControlActive,
            failedCheckIDs: failedCheckIDs,
            coolingBlockerIDs: coolingBlockerIDs,
            includeRecommendedRecoveryAction: includeRecommendedRecoveryAction
        )
        try writeJSON(
            "viftyctl-audit.json",
            [
                "schemaVersion": 1,
                "generatedAt": 700000000,
                "readOnly": true,
                "coolingCommandsRun": false,
                "limit": 20,
                "eventCount": 0,
                "events": []
            ]
        )
        try writeText("viftyhelper-probeLocal.txt", contents: probeLocalText)
        try writeText("launchdaemon-teamid.txt", contents: "\(launchDaemonTeamID)\n")

        if includeReleaseSummary {
            try writeReleaseArtifactSummary(
                signatureChecksSkipped: signatureChecksSkipped,
                notarizationChecksSkipped: notarizationChecksSkipped,
                schemaID: releaseSummarySchemaID,
                expectedArtifactName: releaseSummaryExpectedArtifactName,
                expectedSHA: releaseSummaryExpectedSHA,
                actualSHA: releaseSummaryActualSHA,
                checkStatus: releaseSummaryCheckStatus
            )
        }
        if includeReleaseChecklist {
            try writeReleaseChecklist(version: releaseChecklistVersion)
        }
        try writeManifest(
            statuses: statuses,
            statusOverrides: manifestStatusOverrides,
            stdoutOverrides: manifestStdoutOverrides,
            stderrOverrides: manifestStderrOverrides
        )
        try writeChecksums()
    }

    func runReview(
        mode: String,
        summaryURL: URL? = nil,
        manualSmokeResult: String? = nil,
        manualSmokeSource: String? = nil,
        manualSmokeReadinessSummaryURL: URL? = nil,
        agentRunSmokeResult: String? = nil,
        agentRunSmokeSource: String? = nil,
        agentRunSmokeSummaryURL: URL? = nil
    ) throws -> ValidationEvidenceReviewProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/review-validation-evidence.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        var arguments = [
            "--bundle", bundleURL.path,
            "--mode", mode
        ]
        if let summaryURL {
            arguments += ["--summary", summaryURL.path]
        }
        if let manualSmokeResult {
            arguments += ["--manual-smoke-result", manualSmokeResult]
        }
        if let manualSmokeSource {
            arguments += ["--manual-smoke-source", manualSmokeSource]
        }
        if let manualSmokeReadinessSummaryURL {
            arguments += ["--manual-smoke-readiness-summary", manualSmokeReadinessSummaryURL.path]
        }
        if let agentRunSmokeResult {
            arguments += ["--agent-run-smoke-result", agentRunSmokeResult]
        }
        if let agentRunSmokeSource {
            arguments += ["--agent-run-smoke-source", agentRunSmokeSource]
        }
        if let agentRunSmokeSummaryURL {
            arguments += ["--agent-run-smoke-summary", agentRunSmokeSummaryURL.path]
        }
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ValidationEvidenceReviewProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func writeManualSmokeReadinessSummary(
        status: String = "ready",
        schemaID: String = "https://vifty.local/schemas/manual-smoke-readiness.schema.json",
        manualSmokeReady: Bool = true,
        safeToRequestCooling: Bool = true,
        daemonControlPathReady: Bool = true,
        manualControlActive: Bool = false,
        daemonRuntimeMatchesExpected: Bool? = true,
        daemonRuntimeMatchRequired: Bool = true
    ) throws -> URL {
        let readinessBundleURL = rootURL.appendingPathComponent("manual-smoke-readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: readinessBundleURL, withIntermediateDirectories: true)
        let summaryURL = readinessBundleURL.appendingPathComponent("manual-smoke-readiness.json")
        let json: [String: Any] = [
            "kind": "vifty-manual-smoke-readiness",
            "schemaVersion": 1,
            "schemaID": schemaID,
            "status": status,
            "manualSmokeReady": manualSmokeReady,
            "readOnly": true,
            "coolingCommandsRun": false,
            "diagnoseExitStatus": status == "ready" ? 0 : 75,
            "diagnoseState": status == "ready" ? "ready" : "blocked",
            "modelIdentifier": "MacBookPro18,3",
            "isAppleSilicon": true,
            "isMacBookPro": true,
            "recommendedAgentAction": status == "ready" ? "requestCooling" : "doNotRequestCooling",
            "recommendedRecoveryAction": status == "ready" ? "none" : "repairHelper",
            "safeToRequestCooling": safeToRequestCooling,
            "daemonControlPathReady": daemonControlPathReady,
            "manualControlActive": manualControlActive,
            "fanCount": 2,
            "controllableFanCount": 2,
            "temperatureSensorCount": 2,
            "thermalPressure": "nominal",
            "failedCheckIDs": [],
            "coolingBlockerIDs": [],
            "appPreferences": [
                "startupMode": "Auto",
                "startupModeSource": "persisted",
                "readError": NSNull()
            ],
            "daemonRuntime": [
                "installedDaemonPath": "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
                "installedDaemonPresent": true,
                "installedDaemonSHA256": String(repeating: "a", count: 64),
                "expectedDaemonPath": "/tmp/ViftyDaemon",
                "expectedDaemonSHA256": String(repeating: daemonRuntimeMatchesExpected == false ? "b" : "a", count: 64),
                "matchesExpectedDaemon": daemonRuntimeMatchesExpected as Any? ?? NSNull(),
                "matchRequired": daemonRuntimeMatchRequired
            ],
            "blockers": [],
            "nextAction": "Capture baseline diagnose/probe evidence, run one human-supervised conservative Fixed smoke, restore Auto, then repeat with one conservative Curve smoke.",
            "parseError": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: summaryURL)
        return summaryURL
    }

    func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func writeAgentRunSmokeSummary(
        status: String,
        schemaID: String = "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json",
        runExitStatus: Int = 0,
        coolingLeasePrepared: Bool = true,
        autoRestoreAttempted: Bool = true,
        autoRestoreSucceeded: Bool = true,
        childExitCode: Int = 0,
        daemonStatusAvailable: Bool = true,
        policySource: String = "daemonStatus",
        policyStatusAvailable: Bool = true,
        policyEnabled: Bool = true,
        capabilitiesSchemaVersion: Int = 1,
        capabilitiesSchemaID: String = "https://vifty.local/schemas/viftyctl-capabilities.schema.json",
        diagnoseSchemaID: String = "https://vifty.local/schemas/viftyctl-diagnose.schema.json",
        commandErrorSchemaID: String = "https://vifty.local/schemas/viftyctl-command-error.schema.json",
        runSchemaID: String = "https://vifty.local/schemas/viftyctl-run.schema.json",
        resolvedChildExecutableReported: Bool? = true,
        resolvedChildExecutable: String? = "/bin/sleep",
        resolvedChildExecutableSHA256: String? = String(repeating: "a", count: 64),
        resolvedChildExecutableSHA256Status: String? = "computed",
        manualControlActive: Bool = false,
        startupMode: String? = nil,
        startupModeSource: String? = nil,
        startupModeReadError: String? = nil,
        installSource: String = "not-recorded",
        sourceRef: String = "",
        sourceSHA: String = "",
        sourceArtifactName: String = "",
        sourceArtifactSHA256: String = "",
        sourceArtifactBytes: String = "",
        daemonRuntimeMatchesExpected: Bool? = true,
        daemonRuntimeMatchRequired: Bool = true
    ) throws -> URL {
        try writeAgentRunSmokeBundleSummary(
            status: status,
            schemaID: schemaID,
            runExitStatus: runExitStatus,
            coolingLeasePrepared: coolingLeasePrepared,
            autoRestoreAttempted: autoRestoreAttempted,
            autoRestoreSucceeded: autoRestoreSucceeded,
            childExitCode: childExitCode,
            daemonStatusAvailable: daemonStatusAvailable,
            policySource: policySource,
            policyStatusAvailable: policyStatusAvailable,
            policyEnabled: policyEnabled,
            capabilitiesSchemaVersion: capabilitiesSchemaVersion,
            capabilitiesSchemaID: capabilitiesSchemaID,
            diagnoseSchemaID: diagnoseSchemaID,
            commandErrorSchemaID: commandErrorSchemaID,
            runSchemaID: runSchemaID,
            resolvedChildExecutableReported: resolvedChildExecutableReported,
            resolvedChildExecutable: resolvedChildExecutable,
            resolvedChildExecutableSHA256: resolvedChildExecutableSHA256,
            resolvedChildExecutableSHA256Status: resolvedChildExecutableSHA256Status,
            manualControlActive: manualControlActive,
            startupMode: startupMode,
            startupModeSource: startupModeSource,
            startupModeReadError: startupModeReadError,
            installSource: installSource,
            sourceRef: sourceRef,
            sourceSHA: sourceSHA,
            sourceArtifactName: sourceArtifactName,
            sourceArtifactSHA256: sourceArtifactSHA256,
            sourceArtifactBytes: sourceArtifactBytes,
            daemonRuntimeMatchesExpected: daemonRuntimeMatchesExpected,
            daemonRuntimeMatchRequired: daemonRuntimeMatchRequired
        )
    }

    func writeAgentRunSmokeBundleSummary(
        status: String,
        schemaID: String = "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json",
        runExitStatus: Int = 0,
        coolingLeasePrepared: Bool = true,
        autoRestoreAttempted: Bool = true,
        autoRestoreSucceeded: Bool = true,
        childExitCode: Int = 0,
        daemonStatusAvailable: Bool = true,
        policySource: String = "daemonStatus",
        policyStatusAvailable: Bool = true,
        policyEnabled: Bool = true,
        capabilitiesSchemaVersion: Int = 1,
        capabilitiesSchemaID: String = "https://vifty.local/schemas/viftyctl-capabilities.schema.json",
        diagnoseSchemaID: String = "https://vifty.local/schemas/viftyctl-diagnose.schema.json",
        commandErrorSchemaID: String = "https://vifty.local/schemas/viftyctl-command-error.schema.json",
        runSchemaID: String = "https://vifty.local/schemas/viftyctl-run.schema.json",
        resolvedChildExecutableReported: Bool? = true,
        resolvedChildExecutable: String? = "/bin/sleep",
        resolvedChildExecutableSHA256: String? = String(repeating: "a", count: 64),
        finalRunResolvedChildExecutableSHA256: String? = nil,
        resolvedChildExecutableSHA256Status: String? = "computed",
        finalRunResolvedChildExecutableSHA256Status: String? = nil,
        manualControlActive: Bool = false,
        startupMode: String? = nil,
        startupModeSource: String? = nil,
        startupModeReadError: String? = nil,
        rateLimitRetryAttempted: Bool = false,
        rateLimitRetryAfterSeconds: Int = 2,
        rateLimitInitialExitStatus: Int = 75,
        rateLimitInitialMetadataExitStatus: Int? = nil,
        rateLimitInitialStdoutContents: String? = nil,
        runStdoutOverride: String? = nil,
        runStderrOverride: String? = nil,
        includeRateLimitRetryCommand: Bool = true,
        installSource: String = "not-recorded",
        sourceRef: String = "",
        sourceSHA: String = "",
        sourceArtifactName: String = "",
        sourceArtifactSHA256: String = "",
        sourceArtifactBytes: String = "",
        daemonRuntimeMatchesExpected: Bool? = true,
        daemonRuntimeMatchRequired: Bool = true
    ) throws -> URL {
        let smokeBundleURL = rootURL.appendingPathComponent("agent-run-smoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: smokeBundleURL, withIntermediateDirectories: true)
        let summaryURL = smokeBundleURL.appendingPathComponent("agent-run-smoke-evidence-summary.json")
        let run: [String: Any]
        var commands: [[String: Any]]
        if status == "blocked" {
            run = [
                "schemaVersion": NSNull(),
                "schemaID": NSNull(),
                "command": NSNull(),
                "exitStatus": NSNull(),
                "stdout": NSNull(),
                "stderr": NSNull(),
                "skippedReason": "readiness blocked before smoke run",
                "coolingLeasePrepared": NSNull(),
                "autoRestoreAttempted": NSNull(),
                "autoRestoreSucceeded": NSNull(),
                "childExitCode": NSNull(),
                "resolvedChildExecutable": NSNull(),
                "resolvedChildExecutableSHA256": NSNull(),
                "resolvedChildExecutableSHA256Status": NSNull()
            ]
            commands = [
                ["name": "pre-capabilities", "status": 0, "stdout": "pre-capabilities.json", "stderr": "pre-capabilities.stderr", "statusFile": "pre-capabilities.status"],
                ["name": "pre-diagnose", "status": 75, "stdout": "pre-diagnose.json", "stderr": "pre-diagnose.stderr", "statusFile": "pre-diagnose.status"]
            ]
            try writeAgentRunSmokeCommandFiles(
                in: smokeBundleURL,
                name: "pre-capabilities",
                status: 0,
                stdout: "pre-capabilities.json",
                stderr: "pre-capabilities.stderr",
                stdoutContents: #"{"schemaVersion":\#(capabilitiesSchemaVersion),"schemaIDs":{"capabilities":"\#(capabilitiesSchemaID)","diagnose":"\#(diagnoseSchemaID)","commandError":"\#(commandErrorSchemaID)","run":"\#(runSchemaID)"},"daemonStatusAvailable":true,"policySource":"daemonStatus","policyStatusAvailable":true,"policy":{"enabled":\#(policyEnabled)}}"#
            )
            try writeAgentRunSmokeCommandFiles(
                in: smokeBundleURL,
                name: "pre-diagnose",
                status: 75,
                stdout: "pre-diagnose.json",
                stderr: "pre-diagnose.stderr",
                stdoutContents: agentRunSmokeDiagnoseJSON(
                    state: "blocked",
                    safeToRequestCooling: false,
                    daemonControlPathReady: false,
                    startupMode: startupMode,
                    startupModeSource: startupModeSource,
                    startupModeReadError: startupModeReadError
                )
            )
        } else {
            let finalRunStdout = rateLimitRetryAttempted ? (runStdoutOverride ?? "viftyctl-run-retry.json") : "viftyctl-run.json"
            let finalRunStderr = rateLimitRetryAttempted ? (runStderrOverride ?? "viftyctl-run-retry.stderr") : "viftyctl-run.stderr"
            run = [
                "schemaVersion": 1,
                "schemaID": runSchemaID,
                "command": "run",
                "exitStatus": runExitStatus,
                "stdout": finalRunStdout,
                "stderr": finalRunStderr,
                "skippedReason": NSNull(),
                "coolingLeasePrepared": coolingLeasePrepared,
                "autoRestoreAttempted": autoRestoreAttempted,
                "autoRestoreSucceeded": autoRestoreSucceeded,
                "childExitCode": childExitCode,
                "resolvedChildExecutable": resolvedChildExecutable as Any? ?? NSNull(),
                "resolvedChildExecutableSHA256": resolvedChildExecutableSHA256 as Any? ?? NSNull(),
                "resolvedChildExecutableSHA256Status": resolvedChildExecutableSHA256Status as Any? ?? NSNull()
            ]
            commands = [
                ["name": "pre-capabilities", "status": 0, "stdout": "pre-capabilities.json", "stderr": "pre-capabilities.stderr", "statusFile": "pre-capabilities.status"],
                ["name": "pre-diagnose", "status": 0, "stdout": "pre-diagnose.json", "stderr": "pre-diagnose.stderr", "statusFile": "pre-diagnose.status"],
                [
                    "name": "viftyctl-run",
                    "status": rateLimitRetryAttempted ? rateLimitInitialExitStatus : runExitStatus,
                    "stdout": "viftyctl-run.json",
                    "stderr": "viftyctl-run.stderr",
                    "statusFile": "viftyctl-run.status"
                ]
            ]
            if rateLimitRetryAttempted && includeRateLimitRetryCommand {
                commands.append([
                    "name": "viftyctl-run-retry",
                    "status": runExitStatus,
                    "stdout": "viftyctl-run-retry.json",
                    "stderr": "viftyctl-run-retry.stderr",
                    "statusFile": "viftyctl-run-retry.status"
                ])
            }
            try writeAgentRunSmokeCommandFiles(
                in: smokeBundleURL,
                name: "pre-capabilities",
                status: 0,
                stdout: "pre-capabilities.json",
                stderr: "pre-capabilities.stderr",
                stdoutContents: #"{"schemaVersion":\#(capabilitiesSchemaVersion),"schemaIDs":{"capabilities":"\#(capabilitiesSchemaID)","diagnose":"\#(diagnoseSchemaID)","commandError":"\#(commandErrorSchemaID)","run":"\#(runSchemaID)"},"daemonStatusAvailable":\#(daemonStatusAvailable),"policySource":"\#(policySource)","policyStatusAvailable":\#(policyStatusAvailable),"policy":{"enabled":\#(policyEnabled)}}"#
            )
            try writeAgentRunSmokeCommandFiles(
                in: smokeBundleURL,
                name: "pre-diagnose",
                status: 0,
                stdout: "pre-diagnose.json",
                stderr: "pre-diagnose.stderr",
                stdoutContents: agentRunSmokeDiagnoseJSON(
                    state: "ready",
                    safeToRequestCooling: true,
                    daemonControlPathReady: true,
                    startupMode: startupMode,
                    startupModeSource: startupModeSource,
                    startupModeReadError: startupModeReadError
                )
            )
            let initialRunStatus = rateLimitRetryAttempted ? rateLimitInitialExitStatus : runExitStatus
            let finalRunDigest = finalRunResolvedChildExecutableSHA256 ?? resolvedChildExecutableSHA256
            let finalRunDigestField = finalRunDigest.map { #","resolvedChildExecutableSHA256":"\#($0)""# } ?? ""
            let finalRunDigestStatus = finalRunResolvedChildExecutableSHA256Status ?? resolvedChildExecutableSHA256Status
            let finalRunDigestStatusField = finalRunDigestStatus.map { #","resolvedChildExecutableSHA256Status":"\#($0)""# } ?? ""
            let initialRunStdoutContents = rateLimitRetryAttempted
                ? (rateLimitInitialStdoutContents ?? #"{"schemaVersion":1,"command":"run","errorCode":"PREPARE_RATE_LIMITED","message":"Wait before retrying","safeToProceed":false,"recommendedRecoveryAction":"waitBeforeRetry","coolingLeasePrepared":false,"autoRestoreAttempted":false,"autoRestoreSucceeded":null,"retryAfterSeconds":\#(rateLimitRetryAfterSeconds)}"#)
                : #"{"schemaVersion":1,"schemaID":"\#(runSchemaID)","command":"run","coolingLeasePrepared":true,"autoRestoreAttempted":true,"autoRestoreSucceeded":true,"childExitCode":0,"resolvedChildExecutable":"\#(resolvedChildExecutable ?? "/bin/sleep")"\#(finalRunDigestField)\#(finalRunDigestStatusField),"autoRestoreError":null}"#
            try writeAgentRunSmokeCommandFiles(
                in: smokeBundleURL,
                name: "viftyctl-run",
                status: initialRunStatus,
                stdout: "viftyctl-run.json",
                stderr: "viftyctl-run.stderr",
                stdoutContents: initialRunStdoutContents
            )
            if rateLimitRetryAttempted && includeRateLimitRetryCommand {
                try writeAgentRunSmokeCommandFiles(
                    in: smokeBundleURL,
                    name: "viftyctl-run-retry",
                    status: runExitStatus,
                    stdout: "viftyctl-run-retry.json",
                    stderr: "viftyctl-run-retry.stderr",
                    stdoutContents: #"{"schemaVersion":1,"schemaID":"\#(runSchemaID)","command":"run","coolingLeasePrepared":\#(coolingLeasePrepared),"autoRestoreAttempted":\#(autoRestoreAttempted),"autoRestoreSucceeded":\#(autoRestoreSucceeded),"childExitCode":\#(childExitCode),"resolvedChildExecutable":"\#(resolvedChildExecutable ?? "/bin/sleep")"\#(finalRunDigestField)\#(finalRunDigestStatusField),"autoRestoreError":null}"#
                )
            }
        }
        var preflight: [String: Any] = [
            "exitStatus": status == "blocked" ? 75 : 0,
            "state": status == "blocked" ? "blocked" : "ready",
            "recommendedAgentAction": status == "blocked" ? "doNotRequestCooling" : "requestCooling",
            "recommendedRecoveryAction": status == "blocked" ? "repairHelper" : "none",
            "safeToRequestCooling": status != "blocked",
            "daemonControlPathReady": status != "blocked",
            "manualControlActive": manualControlActive,
            "capabilitiesExitStatus": status == "blocked" ? 75 : 0,
            "capabilitiesSchemaVersion": capabilitiesSchemaVersion,
            "capabilitiesSchemaID": capabilitiesSchemaID,
            "diagnoseSchemaID": diagnoseSchemaID,
            "commandErrorSchemaID": commandErrorSchemaID,
            "runSchemaID": runSchemaID,
            "resolvedChildExecutableReported": resolvedChildExecutableReported as Any? ?? NSNull(),
            "daemonStatusAvailable": status == "blocked" ? false : daemonStatusAvailable,
            "policySource": status == "blocked" ? "fallbackUnavailable" : policySource,
            "policyStatusAvailable": status == "blocked" ? false : policyStatusAvailable,
            "policyEnabled": policyEnabled
        ]
        if startupMode != nil || startupModeSource != nil || startupModeReadError != nil {
            preflight["appPreferences"] = [
                "startupMode": startupMode as Any? ?? NSNull(),
                "startupModeSource": startupModeSource as Any? ?? NSNull(),
                "readError": startupModeReadError as Any? ?? NSNull()
            ]
        }

        var json: [String: Any] = [
            "schemaVersion": 1,
            "schemaID": schemaID,
            "kind": "vifty-agent-run-smoke",
            "generatedAtUTC": "2026-06-13T00:00:00Z",
            "status": status,
            "readOnly": status == "blocked",
            "coolingCommandsRun": status != "blocked",
            "viftyctl": "/Applications/Vifty.app/Contents/MacOS/viftyctl",
            "installSource": installSource,
            "sourceRef": sourceRef,
            "sourceSHA": sourceSHA,
            "sourceArtifactName": sourceArtifactName,
            "sourceArtifactSHA256": sourceArtifactSHA256,
            "sourceArtifactBytes": sourceArtifactBytes,
            "daemonRuntime": [
                "installedDaemonPath": "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
                "installedDaemonPresent": true,
                "installedDaemonSHA256": String(repeating: "a", count: 64),
                "expectedDaemonPath": "/tmp/ViftyDaemon",
                "expectedDaemonSHA256": String(repeating: daemonRuntimeMatchesExpected == false ? "b" : "a", count: 64),
                "matchesExpectedDaemon": daemonRuntimeMatchesExpected as Any? ?? NSNull(),
                "matchRequired": daemonRuntimeMatchRequired
            ],
            "workload": "test",
            "duration": "2m",
            "maxRPMPercent": 55,
            "reason": "agent run smoke test",
            "auditLimit": 20,
            "childCommand": ["/bin/sleep", "5"],
            "preflight": preflight,
            "run": run,
            "commands": commands
        ]
        json["rateLimitRetry"] = rateLimitRetryAttempted
            ? [
                "attempted": true,
                "retryAfterSeconds": rateLimitRetryAfterSeconds,
                "initialExitStatus": rateLimitInitialMetadataExitStatus ?? rateLimitInitialExitStatus,
                "stdout": "viftyctl-run.json",
                "stderr": "viftyctl-run.stderr"
            ]
            : [
                "attempted": false,
                "retryAfterSeconds": NSNull(),
                "initialExitStatus": NSNull(),
                "stdout": NSNull(),
                "stderr": NSNull()
            ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: summaryURL)
        let manifestLines = ([
            "name\tstatus\tstdout\tstderr"
        ] + commands.map { command in
            "\(command["name"] ?? "")\t\(command["status"] ?? "")\t\(command["stdout"] ?? "")\t\(command["stderr"] ?? "")"
        }).joined(separator: "\n") + "\n"
        try manifestLines.write(to: smokeBundleURL.appendingPathComponent("manifest.tsv"), atomically: true, encoding: .utf8)
        try writeAgentRunSmokeChecksums(in: smokeBundleURL)
        return summaryURL
    }

    func overwriteAgentRunSmokeBundleFile(summaryURL: URL, filename: String, contents: String) throws {
        try contents.write(
            to: summaryURL.deletingLastPathComponent().appendingPathComponent(filename),
            atomically: true,
            encoding: .utf8
        )
    }

    func overwriteAgentRunSmokeBundleJSON(
        summaryURL: URL,
        filename: String,
        value: Any,
        refreshChecksums: Bool
    ) throws {
        let smokeBundleURL = summaryURL.deletingLastPathComponent()
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: smokeBundleURL.appendingPathComponent(filename))
        if refreshChecksums {
            try writeAgentRunSmokeChecksums(in: smokeBundleURL)
        }
    }

    func removeChecksumEntry(for filename: String) throws {
        let checksumURL = bundleURL.appendingPathComponent("checksums.tsv")
        let lines = try String(contentsOf: checksumURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasSuffix("\t\(filename)") }
            .map(String.init)
        try lines.joined(separator: "\n").appending("\n").write(to: checksumURL, atomically: true, encoding: .utf8)
    }

    private func writeReviewSummary(
        statuses: [String: String],
        releaseArtifactSummaryPath: String,
        releaseChecklistPath: String
    ) throws {
        let checks = statuses
            .keys
            .sorted()
            .map { name in
                [
                    "name": name,
                    "status": statuses[name] ?? "",
                    "expected": "0",
                    "scope": "test",
                    "note": "fixture"
                ]
            }
        let json: [String: Any] = [
            "schemaVersion": 1,
            "generatedAtUTC": "2026-06-11T00:00:00Z",
            "appPath": "/Applications/Vifty.app",
            "readOnly": true,
            "coolingCommandsRun": false,
            "includeProbeLocal": true,
            "releaseArtifactSummaryPath": releaseArtifactSummaryPath,
            "releaseChecklistPath": releaseChecklistPath,
            "checks": checks
        ]
        try writeJSON("review-summary.json", json)
    }

    private func tsvSummary(_ statuses: [String: String]) -> String {
        var lines = ["name\tstatus\texpected\tscope\tnote"]
        for name in statuses.keys.sorted() {
            lines.append("\(name)\t\(statuses[name] ?? "")\t0\ttest\tfixture")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func writeManifest(
        statuses: [String: String],
        statusOverrides: [String: String],
        stdoutOverrides: [String: String],
        stderrOverrides: [String: String]
    ) throws {
        let manifestStatuses = statuses.merging(statusOverrides) { _, new in new }
        var lines = ["name\tstatus\tstdout\tstderr"]

        for name in manifestStatuses.keys.sorted() {
            let status = manifestStatuses[name] ?? ""
            guard status != "skipped" else {
                continue
            }

            let stdoutName = stdoutOverrides[name] ?? defaultManifestStdoutName(for: name)
            let stderrName = stderrOverrides[name] ?? "\(name).stderr"

            if stdoutOverrides[name] == nil {
                try ensureManifestFile(stdoutName, contents: "fixture for \(name)\n")
            }
            if stderrOverrides[name] == nil {
                try ensureManifestFile(stderrName, contents: "")
            }
            try writeText("\(name).status", contents: "\(status)\n")
            lines.append("\(name)\t\(status)\t\(stdoutName)\t\(stderrName)")
        }

        try writeText("manifest.tsv", contents: lines.joined(separator: "\n") + "\n")
    }

    private func ensureManifestFile(_ filename: String, contents: String) throws {
        guard isBundleLocalManifestFilename(filename) else {
            return
        }
        let url = bundleURL.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try writeText(filename, contents: contents)
    }

    private func writeAgentRunSmokeCommandFiles(
        in directory: URL,
        name: String,
        status: Int,
        stdout: String,
        stderr: String,
        stdoutContents: String
    ) throws {
        try stdoutContents.write(to: directory.appendingPathComponent(stdout), atomically: true, encoding: .utf8)
        try "".write(to: directory.appendingPathComponent(stderr), atomically: true, encoding: .utf8)
        try "\(status)\n".write(to: directory.appendingPathComponent("\(name).status"), atomically: true, encoding: .utf8)
    }

    private func agentRunSmokeDiagnoseJSON(
        state: String,
        safeToRequestCooling: Bool,
        daemonControlPathReady: Bool,
        startupMode: String?,
        startupModeSource: String?,
        startupModeReadError: String?
    ) throws -> String {
        var json: [String: Any] = [
            "state": state,
            "safeToRequestCooling": safeToRequestCooling,
            "daemonControlPathReady": daemonControlPathReady
        ]
        if startupMode != nil || startupModeSource != nil || startupModeReadError != nil {
            json["appPreferences"] = [
                "startupMode": startupMode as Any? ?? NSNull(),
                "startupModeSource": startupModeSource as Any? ?? NSNull(),
                "readError": startupModeReadError as Any? ?? NSNull()
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func writeAgentRunSmokeChecksums(in directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var lines = ["sha256\tbytes\tfile"]
        for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard fileURL.lastPathComponent != "checksums.tsv" else {
                continue
            }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let data = try Data(contentsOf: fileURL)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            lines.append("\(digest)\t\(data.count)\t\(fileURL.lastPathComponent)")
        }
        try lines.joined(separator: "\n").appending("\n")
            .write(to: directory.appendingPathComponent("checksums.tsv"), atomically: true, encoding: .utf8)
    }

    private func isBundleLocalManifestFilename(_ filename: String) -> Bool {
        !filename.isEmpty && !filename.contains("/") && !filename.hasPrefix(".")
    }

    private func defaultManifestStdoutName(for name: String) -> String {
        switch name {
        case "bundle-executables",
            "install-provenance",
            "privacy-review",
            "schema-resources",
            "capabilities-schema-resources",
            "capabilities-contract",
            "release-artifact-summary",
            "release-checklist":
            "\(name).tsv"
        case "viftyctl-capabilities", "viftyctl-status", "viftyctl-diagnose", "viftyctl-audit":
            "\(name).json"
        default:
            "\(name).txt"
        }
    }

    private func writeInstallProvenance(
        installSource: String,
        sourceRef: String,
        sourceSHA: String,
        sourceArtifactName: String,
        sourceArtifactSHA256: String,
        sourceArtifactBytes: String
    ) throws {
        try writeText(
            "install-provenance.tsv",
            contents: """
            field\tvalue
            installSource\t\(installSource)
            sourceRef\t\(sourceRef)
            sourceSHA\t\(sourceSHA)
            sourceArtifactPath\t/tmp/\(sourceArtifactName)
            sourceArtifactName\t\(sourceArtifactName)
            sourceArtifactSHA256\t\(sourceArtifactSHA256)
            sourceArtifactBytes\t\(sourceArtifactBytes)
            installedAppBundleVersion\t1.2.3
            trustBoundary\tFixture trust boundary.
            """
        )
    }

    private func writeDiagnose(
        _ fixture: ValidationEvidenceDiagnoseFixture,
        daemonControlPathReady: Bool,
        manualControlActive: Bool,
        failedCheckIDs: [String],
        coolingBlockerIDs: [String],
        includeRecommendedRecoveryAction: Bool
    ) throws {
        let supportedPasses = fixture.supportedHardwareCheckPasses
        var json: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": 700000000,
            "state": fixture.status,
            "recommendedAgentAction": fixture.recommendedAgentAction,
            "safeToRequestCooling": fixture.safeToRequestCooling,
            "daemonControlPathReady": daemonControlPathReady,
            "manualControlActive": manualControlActive,
            "failedCheckIDs": failedCheckIDs,
            "coolingBlockerIDs": coolingBlockerIDs,
            "modelIdentifier": supportedPasses ? "MacBookPro18,3" : "Mac14,2",
            "isAppleSilicon": fixture.isAppleSilicon,
            "isMacBookPro": fixture.isMacBookPro,
            "thermalPressure": "nominal",
            "fanCount": supportedPasses ? 2 : 0,
            "controllableFanCount": supportedPasses ? 2 : 0,
            "temperatureSensorCount": supportedPasses ? 2 : 0,
            "fans": [
                [
                    "id": 0,
                    "name": "Left Fan",
                    "currentRPM": 2200,
                    "minimumRPM": 1400,
                    "maximumRPM": 6800,
                    "controllable": true,
                    "hardwareMode": "Auto",
                    "hardwareModeKey": "F0Md",
                    "hardwareModeRawValue": 0
                ]
            ],
            "temperatureSensors": [
                [
                    "id": "Tp09",
                    "name": "CPU Proximity",
                    "celsius": 58.4,
                    "source": "SMC"
                ]
            ],
            "agentControl": [
                "enabled": true,
                "policy": [
                    "enabled": true,
                    "maxDurationSeconds": 1800,
                    "maximumAllowedRPMPercent": 80,
                    "minimumAgentRPMPercent": 45,
                    "prepareCooldownSeconds": 30
                ]
            ],
            "checks": [
                [
                    "id": "daemonSnapshotAvailable",
                    "severity": "info",
                    "passed": true,
                    "message": "Daemon hardware snapshot is available."
                ],
                [
                    "id": "agentControlStatusAvailable",
                    "severity": "info",
                    "passed": true,
                    "message": "Agent control status is available."
                ],
                [
                    "id": "daemonControlPathReady",
                    "severity": "error",
                    "passed": daemonControlPathReady,
                    "message": daemonControlPathReady
                        ? "Daemon-backed control path is ready for bounded agent cooling requests."
                        : "Daemon-backed control path is unavailable; repair the helper before requesting cooling."
                ],
                [
                    "id": "supportedHardware",
                    "severity": supportedPasses ? "info" : "error",
                    "passed": supportedPasses,
                    "message": supportedPasses
                        ? "Apple Silicon MacBook Pro hardware detected."
                        : "This machine is outside Vifty's supported fan-control scope."
                ]
            ]
        ]
        if includeRecommendedRecoveryAction {
            json["recommendedRecoveryAction"] = fixture.recommendedRecoveryAction
        }
        try writeJSON("viftyctl-diagnose.json", json)
    }

    private func writeReleaseArtifactSummary(
        signatureChecksSkipped: Bool,
        notarizationChecksSkipped: Bool,
        schemaID: String,
        expectedArtifactName: String,
        expectedSHA: String,
        actualSHA: String,
        checkStatus: String
    ) throws {
        try writeJSON(
            "release-artifact-summary.json",
            [
                "schemaVersion": 1,
                "schemaID": schemaID,
                "status": "passed",
                "generatedAtUTC": "2026-06-11T00:00:00Z",
                "caskVersion": "1.2.3",
                "caskURL": "https://github.com/Reedtrullz/Vifty/releases/download/v1.2.3/Vifty-v1.2.3.zip",
                "expectedArtifactName": expectedArtifactName,
                "artifactPath": "/tmp/Vifty-v1.2.3.zip",
                "appPath": "/tmp/extract/Vifty.app",
                "bundleVersion": "1.2.3",
                "expectedSHA": expectedSHA,
                "expectedSHASource": "expected sha256",
                "actualSHA": actualSHA,
                "expectedTeamID": "TEAMID1234",
                "requiredTeamID": "TEAMID1234",
                "signatureChecksSkipped": signatureChecksSkipped,
                "notarizationChecksSkipped": notarizationChecksSkipped,
                "checks": [
                    [
                        "name": "artifact-sha",
                        "status": "passed",
                        "scope": "release-trust",
                        "note": "Artifact SHA-256 matched expected sha256."
                    ],
                    [
                        "name": "codesign-teamid",
                        "status": checkStatus,
                        "scope": "release-trust",
                        "note": "Signature and TeamID checks."
                    ],
                    [
                        "name": "notarization-gatekeeper",
                        "status": "passed",
                        "scope": "release-trust",
                        "note": "Stapler validation and Gatekeeper assessment passed."
                    ]
                ]
            ]
        )
        try writeText(
            "release-artifact-summary.tsv",
            contents: """
            field\tvalue
            installedAppBundleVersion\t1.2.3
            caskVersion\t1.2.3
            bundleVersion\t1.2.3
            """
        )
    }

    private func writeReleaseChecklist(version: String) throws {
        try writeText(
            "release-checklist.md",
            contents: """
            # Vifty \(version) Release Checklist

            ## Verified By The Release Workflow

            - [x] Release workflow checks passed.

            ## Required Post-Publication Follow-Up

            - [ ] Update `Casks/vifty.rb` with the published checksum using `scripts/update-cask-checksum.sh`.
            - [ ] Run `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"`.
            - [ ] Review evidence with `make validation-evidence-review VALIDATION_EVIDENCE_BUNDLE=<evidence-dir> VALIDATION_EVIDENCE_REVIEW_MODE=release`.
            - [ ] Keep compatibility claims gated on `manualSmokeTestResult: "passed-auto-restored"`.
            - [ ] Do not describe the Homebrew path as a fully trusted public binary install until checks pass.
            """
        )
        try writeText(
            "release-checklist.tsv",
            contents: """
            field\tvalue
            titleVersion\t\(version)
            installedAppBundleVersion\t\(version)
            hasWorkflowSection\ttrue
            hasFollowUpSection\ttrue
            hasCaskChecksumFollowUp\ttrue
            hasPublicVerifierFollowUp\ttrue
            hasEvidenceReviewFollowUp\ttrue
            hasCompatibilityGate\ttrue
            hasTrustedHomebrewWarning\ttrue
            """
        )
    }

    private func writeJSON(_ filename: String, _ value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: bundleURL.appendingPathComponent(filename))
    }

    private func writeText(_ filename: String, contents: String) throws {
        try contents.write(
            to: bundleURL.appendingPathComponent(filename),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeChecksums() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var lines = ["sha256\tbytes\tfile"]
        for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard fileURL.lastPathComponent != "checksums.tsv" else {
                continue
            }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let data = try Data(contentsOf: fileURL)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            lines.append("\(digest)\t\(data.count)\t\(fileURL.lastPathComponent)")
        }
        try writeText("checksums.tsv", contents: lines.joined(separator: "\n") + "\n")
    }

    private var bundleExecutablesTSV: String {
        """
        executable\tsha256\tbytes\tbundlePath
        Vifty\t\(String(repeating: "a", count: 64))\t2301952\tContents/MacOS/Vifty
        ViftyHelper\t\(String(repeating: "b", count: 64))\t1407120\tContents/MacOS/ViftyHelper
        ViftyDaemon\t\(String(repeating: "c", count: 64))\t1427184\tContents/MacOS/ViftyDaemon
        viftyctl\t\(String(repeating: "d", count: 64))\t1395104\tContents/MacOS/viftyctl
        """
    }

    static let defaultSchemaResourcesTSV = """
    schema\tsha256\tbytes\tbundlePath
    agent-cooling-evidence-summary.schema.json\t\(String(repeating: "1", count: 64))\t2100\tContents/Resources/schemas/agent-cooling-evidence-summary.schema.json
    agent-cooling-evidence-review.schema.json\t\(String(repeating: "2", count: 64))\t1700\tContents/Resources/schemas/agent-cooling-evidence-review.schema.json
    agent-run-smoke-readiness.schema.json\t\(String(repeating: "5", count: 64))\t2600\tContents/Resources/schemas/agent-run-smoke-readiness.schema.json
    agent-run-smoke-evidence-summary.schema.json\t\(String(repeating: "3", count: 64))\t2600\tContents/Resources/schemas/agent-run-smoke-evidence-summary.schema.json
    guarded-run-decision.schema.json\t\(String(repeating: "6", count: 64))\t3200\tContents/Resources/schemas/guarded-run-decision.schema.json
    manual-smoke-readiness.schema.json\t\(String(repeating: "4", count: 64))\t2600\tContents/Resources/schemas/manual-smoke-readiness.schema.json
    release-artifact-summary.schema.json\t\(String(repeating: "f", count: 64))\t3300\tContents/Resources/schemas/release-artifact-summary.schema.json
    release-readiness.schema.json\t\(String(repeating: "0", count: 64))\t2600\tContents/Resources/schemas/release-readiness.schema.json
    validation-report-index.schema.json\t\(String(repeating: "9", count: 64))\t3100\tContents/Resources/schemas/validation-report-index.schema.json
    validation-review-result.schema.json\t\(String(repeating: "8", count: 64))\t3700\tContents/Resources/schemas/validation-review-result.schema.json
    viftyctl-audit.schema.json\t\(String(repeating: "e", count: 64))\t1390\tContents/Resources/schemas/viftyctl-audit.schema.json
    viftyctl-capabilities.schema.json\t\(String(repeating: "a", count: 64))\t5170\tContents/Resources/schemas/viftyctl-capabilities.schema.json
    viftyctl-command-error.schema.json\t\(String(repeating: "b", count: 64))\t1461\tContents/Resources/schemas/viftyctl-command-error.schema.json
    viftyctl-diagnose.schema.json\t\(String(repeating: "c", count: 64))\t5697\tContents/Resources/schemas/viftyctl-diagnose.schema.json
    viftyctl-run.schema.json\t\(String(repeating: "7", count: 64))\t1320\tContents/Resources/schemas/viftyctl-run.schema.json
    viftyctl-status.schema.json\t\(String(repeating: "d", count: 64))\t4828\tContents/Resources/schemas/viftyctl-status.schema.json
    """

    static let defaultCapabilitiesSchemaResourcesTSV = """
    key\tadvertisedResource\texpectedResource
    audit\tContents/Resources/schemas/viftyctl-audit.schema.json\tContents/Resources/schemas/viftyctl-audit.schema.json
    capabilities\tContents/Resources/schemas/viftyctl-capabilities.schema.json\tContents/Resources/schemas/viftyctl-capabilities.schema.json
    commandError\tContents/Resources/schemas/viftyctl-command-error.schema.json\tContents/Resources/schemas/viftyctl-command-error.schema.json
    diagnose\tContents/Resources/schemas/viftyctl-diagnose.schema.json\tContents/Resources/schemas/viftyctl-diagnose.schema.json
    run\tContents/Resources/schemas/viftyctl-run.schema.json\tContents/Resources/schemas/viftyctl-run.schema.json
    status\tContents/Resources/schemas/viftyctl-status.schema.json\tContents/Resources/schemas/viftyctl-status.schema.json
    """

    static let defaultCapabilitiesContractTSV = """
    field\tactual\texpected
    policyStatusAvailable\ttrue\ttrue
    policy.enabled\ttrue\ttrue
    supportsForceRetry\ttrue\ttrue
    runLifecycle.childCommandPreflightBeforeCooling\ttrue\ttrue
    runLifecycle.autoRestoreAfterChildExit\ttrue\ttrue
    runLifecycle.structuredPreChildFailures\ttrue\ttrue
    runLifecycle.cleanupStateReportedOnLaunchFailure\ttrue\ttrue
    runLifecycle.resolvedChildExecutableReported\ttrue\ttrue
    runLifecycle.signalsForwardedToChild\tINT,TERM,HUP\tINT,TERM,HUP
    directControlLifecycle.prepareUsesIdempotencyKey\ttrue\ttrue
    directControlLifecycle.restoreAutoAcceptsIdempotencyKey\tfalse\tfalse
    directControlLifecycle.restoreAutoScopedByIdempotencyKey\tfalse\tfalse
    directControlLifecycle.preferRunForSingleChildWorkloads\ttrue\ttrue
    metadataLimits.maximumReasonLength\t512\t512
    metadataLimits.maximumIdempotencyKeyLength\t256\t256
    wrapperResources.sourceDirectory\texamples/viftyctl\texamples/viftyctl
    wrapperResources.bundleDirectory\tContents/Resources/viftyctl-wrappers\tContents/Resources/viftyctl-wrappers
    wrapperResources.guardedRunScript\tguarded-run.sh\tguarded-run.sh
    wrapperResources.workloadScripts\tcargo-build.sh,cargo-test.sh,custom-workload.sh,local-model.sh,make-build.sh,make-test.sh,make-verify.sh,npm-build.sh,npm-test.sh,pytest.sh,swift-release-build.sh,swift-test.sh,xcode-build.sh,xcode-test.sh\tcargo-build.sh,cargo-test.sh,custom-workload.sh,local-model.sh,make-build.sh,make-test.sh,make-verify.sh,npm-build.sh,npm-test.sh,pytest.sh,swift-release-build.sh,swift-test.sh,xcode-build.sh,xcode-test.sh
    """
}
