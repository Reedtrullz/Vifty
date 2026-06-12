import Foundation
import CryptoKit
import XCTest

private let expectedReadOnlyViftyCtlInvocations = [
    "capabilities --json",
    "status --json",
    "diagnose --json",
    "audit --limit 20 --json"
]

final class ValidationEvidenceScriptTests: XCTestCase {
    func testCollectorCapturesReadOnlyViftyCtlEvidence() throws {
        let harness = try ValidationEvidenceHarness()

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence written"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("coolingCommandsRun=false"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("viftyDaemon="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("schemaDir="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("daemonPlist="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("releaseArtifactSummaryPath="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("installSource=not-recorded"))
        XCTAssertTrue(try harness.read("README.txt").contains("review-summary.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("review-summary.json"))
        XCTAssertTrue(try harness.read("README.txt").contains("install-provenance.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("release-artifact-summary.json"))
        XCTAssertTrue(try harness.read("README.txt").contains("release-artifact-summary.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("release-checklist.md"))
        XCTAssertTrue(try harness.read("README.txt").contains("release-checklist.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("bundled executable hashes"))
        XCTAssertTrue(try harness.read("README.txt").contains("manifest.tsv records each captured command"))
        XCTAssertTrue(try harness.read("README.txt").contains("<command>.status"))
        XCTAssertTrue(try harness.read("README.txt").contains("privacy-review.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("checksums.tsv"))
        XCTAssertLessThanOrEqual(try harness.read("system-uname.txt").split(separator: " ").count, 3)
        let bundleExecutables = try harness.read("bundle-executables.tsv")
        XCTAssertTrue(bundleExecutables.contains("executable\tsha256\tbytes\tbundlePath"))
        XCTAssertTrue(bundleExecutables.contains("Vifty\t"))
        XCTAssertTrue(bundleExecutables.contains("ViftyHelper\t"))
        XCTAssertTrue(bundleExecutables.contains("ViftyDaemon\t"))
        XCTAssertTrue(bundleExecutables.contains("viftyctl\t"))
        XCTAssertTrue(bundleExecutables.contains("Contents/MacOS/viftyctl"))
        let installProvenance = try harness.read("install-provenance.tsv")
        XCTAssertTrue(installProvenance.contains("field\tvalue"))
        XCTAssertTrue(installProvenance.contains("installSource\tnot-recorded"))
        XCTAssertTrue(installProvenance.contains("installedAppBundleVersion\t1.2.3"))
        XCTAssertTrue(installProvenance.contains("trustBoundary\tInstall source was not recorded"))
        let schemaResources = try harness.read("schema-resources.tsv")
        XCTAssertTrue(schemaResources.contains("schema\tsha256\tbytes\tbundlePath"))
        XCTAssertTrue(schemaResources.contains("agent-cooling-evidence-summary.schema.json"))
        XCTAssertTrue(schemaResources.contains("release-artifact-summary.schema.json"))
        XCTAssertTrue(schemaResources.contains("release-readiness.schema.json"))
        XCTAssertTrue(schemaResources.contains("validation-report-index.schema.json"))
        XCTAssertTrue(schemaResources.contains("validation-review-result.schema.json"))
        XCTAssertTrue(schemaResources.contains("viftyctl-audit.schema.json"))
        XCTAssertTrue(schemaResources.contains("viftyctl-capabilities.schema.json"))
        XCTAssertTrue(schemaResources.contains("Contents/Resources/schemas/viftyctl-capabilities.schema.json"))
        XCTAssertTrue(schemaResources.contains("viftyctl-diagnose.schema.json"))
        let capabilitiesSchemaResources = try harness.read("capabilities-schema-resources.tsv")
        XCTAssertTrue(capabilitiesSchemaResources.contains("key\tadvertisedResource\texpectedResource"))
        XCTAssertTrue(capabilitiesSchemaResources.contains("audit\tContents/Resources/schemas/viftyctl-audit.schema.json\tContents/Resources/schemas/viftyctl-audit.schema.json"))
        XCTAssertTrue(capabilitiesSchemaResources.contains("capabilities\tContents/Resources/schemas/viftyctl-capabilities.schema.json\tContents/Resources/schemas/viftyctl-capabilities.schema.json"))
        XCTAssertTrue(capabilitiesSchemaResources.contains("commandError\tContents/Resources/schemas/viftyctl-command-error.schema.json\tContents/Resources/schemas/viftyctl-command-error.schema.json"))
        let capabilitiesContract = try harness.read("capabilities-contract.tsv")
        XCTAssertTrue(capabilitiesContract.contains("field\tactual\texpected"))
        XCTAssertTrue(capabilitiesContract.contains("supportsForceRetry\ttrue\ttrue"))
        XCTAssertTrue(capabilitiesContract.contains("runLifecycle.childCommandPreflightBeforeCooling\ttrue\ttrue"))
        XCTAssertTrue(capabilitiesContract.contains("runLifecycle.signalsForwardedToChild\tINT,TERM,HUP\tINT,TERM,HUP"))
        XCTAssertTrue(capabilitiesContract.contains("directControlLifecycle.prepareUsesIdempotencyKey\ttrue\ttrue"))
        XCTAssertTrue(capabilitiesContract.contains("directControlLifecycle.restoreAutoAcceptsIdempotencyKey\tfalse\tfalse"))
        XCTAssertTrue(capabilitiesContract.contains("directControlLifecycle.restoreAutoScopedByIdempotencyKey\tfalse\tfalse"))
        XCTAssertTrue(capabilitiesContract.contains("directControlLifecycle.preferRunForSingleChildWorkloads\ttrue\ttrue"))
        XCTAssertTrue(capabilitiesContract.contains("metadataLimits.maximumReasonLength\t512\t512"))
        XCTAssertTrue(capabilitiesContract.contains("metadataLimits.maximumIdempotencyKeyLength\t256\t256"))
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"ready\""))
        XCTAssertTrue(try harness.read("viftyctl-audit.json").contains("\"readOnly\":true"))
        XCTAssertTrue(try harness.read("viftyhelper-probeLocal.txt").contains("Skipped"))

        let manifest = try harness.read("manifest.tsv")
        XCTAssertTrue(manifest.contains("app-info-plist\t0\tapp-info-plist.txt"))
        XCTAssertTrue(manifest.contains("install-provenance\t0\tinstall-provenance.tsv"))
        XCTAssertTrue(manifest.contains("bundle-executables\t0\tbundle-executables.tsv"))
        XCTAssertTrue(manifest.contains("privacy-review\t0\tprivacy-review.tsv"))
        XCTAssertTrue(manifest.contains("schema-resources\t0\tschema-resources.tsv"))
        XCTAssertTrue(manifest.contains("capabilities-schema-resources\t0\tcapabilities-schema-resources.tsv"))
        XCTAssertTrue(manifest.contains("capabilities-contract\t0\tcapabilities-contract.tsv"))
        XCTAssertTrue(manifest.contains("launchdaemon-plist\t0\tlaunchdaemon-plist.txt"))
        XCTAssertTrue(manifest.contains("launchdaemon-lint\t0\tlaunchdaemon-lint.txt"))
        XCTAssertTrue(manifest.contains("launchdaemon-teamid\t0\tlaunchdaemon-teamid.txt"))
        XCTAssertTrue(manifest.contains("codesign-viftyctl\t"))
        XCTAssertTrue(manifest.contains("codesign-viftyhelper\t"))
        XCTAssertTrue(manifest.contains("codesign-viftydaemon\t"))
        XCTAssertTrue(manifest.contains("viftyctl-capabilities\t0\tviftyctl-capabilities.json"))
        XCTAssertTrue(manifest.contains("viftyctl-status\t0\tviftyctl-status.json"))
        XCTAssertTrue(manifest.contains("viftyctl-diagnose\t0\tviftyctl-diagnose.json"))
        XCTAssertTrue(manifest.contains("viftyctl-audit\t0\tviftyctl-audit.json"))

        let reviewSummary = try harness.read("review-summary.tsv")
        XCTAssertTrue(reviewSummary.contains("name\tstatus\texpected\tscope\tnote"))
        XCTAssertTrue(reviewSummary.contains("app-info-plist\t0\t0\trelease-and-hardware"))
        XCTAssertTrue(reviewSummary.contains("install-provenance\t0\t0\tsource-and-release-trust"))
        XCTAssertTrue(reviewSummary.contains("bundle-executables\t0\t0\trelease-and-hardware"))
        XCTAssertTrue(reviewSummary.contains("privacy-review\t0\t0\tpublic-report-privacy"))
        XCTAssertTrue(reviewSummary.contains("release-artifact-summary\tskipped\t0 or skipped\trelease-trust"))
        XCTAssertTrue(reviewSummary.contains("release-checklist\tskipped\t0 or skipped\trelease-trust"))
        XCTAssertTrue(reviewSummary.contains("schema-resources\t0\t0\tsupport-release-and-agent-contract"))
        XCTAssertTrue(reviewSummary.contains("capabilities-schema-resources\t0\t0\tagent-contract"))
        XCTAssertTrue(reviewSummary.contains("capabilities-contract\t0\t0\tagent-contract"))
        XCTAssertTrue(reviewSummary.contains("launchdaemon-teamid\t0\t0 for public release\trelease-trust"))
        XCTAssertTrue(reviewSummary.contains("spctl-assess-app\t"))
        XCTAssertTrue(reviewSummary.contains("viftyctl-capabilities\t0\t0 or 69\tagent-contract"))
        XCTAssertTrue(reviewSummary.contains("viftyctl-diagnose\t0\t0 or 75\thardware-and-agent"))
        XCTAssertTrue(reviewSummary.contains("viftyctl-audit\t0\t0\tagent-contract"))
        XCTAssertTrue(reviewSummary.contains("viftyhelper-probeLocal\tskipped\t0 or skipped\thardware-validation"))

        let reviewSummaryJSON = try harness.readJSON("review-summary.json")
        XCTAssertEqual(reviewSummaryJSON["schemaVersion"] as? Int, 1)
        XCTAssertEqual(reviewSummaryJSON["readOnly"] as? Bool, true)
        XCTAssertEqual(reviewSummaryJSON["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(reviewSummaryJSON["includeProbeLocal"] as? Bool, false)
        XCTAssertEqual(reviewSummaryJSON["releaseArtifactSummaryPath"] as? String, "")
        XCTAssertEqual(reviewSummaryJSON["releaseChecklistPath"] as? String, "")
        XCTAssertEqual(reviewSummaryJSON["installSource"] as? String, "not-recorded")
        XCTAssertEqual(reviewSummaryJSON["sourceRef"] as? String, "")
        XCTAssertEqual(reviewSummaryJSON["sourceSHA"] as? String, "")
        let checks = try XCTUnwrap(reviewSummaryJSON["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-artifact-summary"
                && check["status"] as? String == "skipped"
                && check["expected"] as? String == "0 or skipped"
                && check["scope"] as? String == "release-trust"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-checklist"
                && check["status"] as? String == "skipped"
                && check["expected"] as? String == "0 or skipped"
                && check["scope"] as? String == "release-trust"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "bundle-executables"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "release-and-hardware"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "install-provenance"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "source-and-release-trust"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "privacy-review"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "public-report-privacy"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "schema-resources"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "support-release-and-agent-contract"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "capabilities-schema-resources"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "agent-contract"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "capabilities-contract"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "agent-contract"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "viftyctl-audit"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0"
                && check["scope"] as? String == "agent-contract"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "viftyctl-diagnose"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0 or 75"
                && check["scope"] as? String == "hardware-and-agent"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "viftyhelper-probeLocal"
                && check["status"] as? String == "skipped"
        })

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("sha256\tbytes\tfile"))
        XCTAssertTrue(checksums.contains("\tapp-info-plist.txt"))
        XCTAssertTrue(checksums.contains("\tinstall-provenance.tsv"))
        XCTAssertTrue(checksums.contains("\tbundle-executables.tsv"))
        XCTAssertTrue(checksums.contains("\tprivacy-review.tsv"))
        XCTAssertTrue(checksums.contains("\tschema-resources.tsv"))
        XCTAssertTrue(checksums.contains("\tcapabilities-schema-resources.tsv"))
        XCTAssertTrue(checksums.contains("\tcapabilities-contract.tsv"))
        XCTAssertTrue(checksums.contains("\tlaunchdaemon-plist.txt"))
        XCTAssertTrue(checksums.contains("\treview-summary.tsv"))
        XCTAssertTrue(checksums.contains("\treview-summary.json"))
        XCTAssertFalse(checksums.contains("\trelease-artifact-summary.json"))
        XCTAssertFalse(checksums.contains("\trelease-artifact-summary.tsv"))
        XCTAssertFalse(checksums.contains("\trelease-checklist.md"))
        XCTAssertFalse(checksums.contains("\trelease-checklist.tsv"))
        XCTAssertTrue(checksums.contains("\tviftyctl-capabilities.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-status.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-diagnose.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-audit.json"))
        XCTAssertFalse(checksums.contains("\tchecksums.tsv"))

        let invocations = try harness.loggedViftyCtlInvocations()
        XCTAssertEqual(invocations, expectedReadOnlyViftyCtlInvocations)
        XCTAssertFalse(invocations.contains { invocation in
            ["prepare", "run", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })
    }

    func testCollectorManifestRowsReferenceCapturedStatusAndChecksumFiles() throws {
        let harness = try ValidationEvidenceHarness()

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)

        let manifestRows = try harness.readTSV("manifest.tsv")
        XCTAssertFalse(manifestRows.isEmpty)
        let checksumFiles = Set(try harness.readTSV("checksums.tsv").compactMap { $0["file"] })

        for row in manifestRows {
            let name = try XCTUnwrap(row["name"])
            let status = try XCTUnwrap(row["status"])
            let stdout = try XCTUnwrap(row["stdout"])
            let stderr = try XCTUnwrap(row["stderr"])
            let statusFile = "\(name).status"

            XCTAssertFalse(name.isEmpty)
            XCTAssertFalse(status.isEmpty)
            for filename in [stdout, stderr, statusFile] {
                XCTAssertFalse(filename.isEmpty)
                XCTAssertFalse(filename.contains("/"))
                XCTAssertFalse(filename.hasPrefix("."))
                XCTAssertTrue(FileManager.default.fileExists(atPath: harness.outputURL.appendingPathComponent(filename).path))
                XCTAssertTrue(checksumFiles.contains(filename), "\(filename) should be listed in checksums.tsv")
            }
            XCTAssertEqual(try harness.read(statusFile).trimmingCharacters(in: .whitespacesAndNewlines), status)
        }
    }

    func testCollectorRecordsSourceFirstInstallProvenanceAndArtifactChecksum() throws {
        let harness = try ValidationEvidenceHarness()
        let artifactData = Data("unsigned tester zip fixture\n".utf8)
        let artifactURL = harness.rootURL.appendingPathComponent("Vifty-v1.1.0-unsigned-dev.zip")
        try artifactData.write(to: artifactURL)
        let expectedArtifactSHA = SHA256.hash(data: artifactData)
            .map { String(format: "%02x", $0) }
            .joined()
        let sourceSHA = String(repeating: "A", count: 40)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--install-source", "source-first-unsigned-dev-zip",
            "--source-ref", "v1.1.0",
            "--source-sha", sourceSHA,
            "--source-artifact", artifactURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let provenance = try harness.read("install-provenance.tsv")
        XCTAssertTrue(provenance.contains("installSource\tsource-first-unsigned-dev-zip"))
        XCTAssertTrue(provenance.contains("sourceRef\tv1.1.0"))
        XCTAssertTrue(provenance.contains("sourceSHA\t\(sourceSHA.lowercased())"))
        XCTAssertTrue(provenance.contains("sourceArtifactName\tVifty-v1.1.0-unsigned-dev.zip"))
        XCTAssertTrue(provenance.contains("sourceArtifactSHA256\t\(expectedArtifactSHA)"))
        XCTAssertTrue(provenance.contains("sourceArtifactBytes\t\(artifactData.count)"))
        XCTAssertTrue(provenance.contains("not Developer ID signed, notarized, Homebrew-trusted, or an official trusted binary"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("install-provenance\t0\t0\tsource-and-release-trust"))

        let summary = try harness.readJSON("review-summary.json")
        XCTAssertEqual(summary["installSource"] as? String, "source-first-unsigned-dev-zip")
        XCTAssertEqual(summary["sourceRef"] as? String, "v1.1.0")
        XCTAssertEqual(summary["sourceSHA"] as? String, sourceSHA)
        XCTAssertEqual(summary["sourceArtifactPath"] as? String, artifactURL.path)
    }

    func testCollectorFlagsLikelyPrivateIdentifiersWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness(includePrivacyLeak: true)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("redaction-needed\tviftyctl-status.json"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("serial-number-label"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("user-home-path"))
        XCTAssertTrue(try harness.read("privacy-review.stderr").contains("privacy review found local identifiers"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("privacy-review\t1\tprivacy-review.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("privacy-review\t1\t0\tpublic-report-privacy"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "privacy-review"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0"
        })
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorPrivacyReviewScansGeneratedReviewSummary() throws {
        let harness = try ValidationEvidenceHarness(
            appPathComponents: ["Users", "private-user", "Vifty.app"]
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("redaction-needed\treview-summary.json"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("user-home-path"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("privacy-review\t1\t0\tpublic-report-privacy"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorOptionallyCapturesProbeLocal() throws {
        let harness = try ValidationEvidenceHarness()

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--include-probe-local"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let probeLocal = try harness.read("viftyhelper-probeLocal.txt")
        XCTAssertTrue(probeLocal.contains("fan[0]"))
        XCTAssertTrue(probeLocal.contains("hardwareMode=Forced"))
        XCTAssertTrue(probeLocal.contains("hardwareModeRawValue=1"))
        XCTAssertTrue(probeLocal.contains("hardwareModeKey=F0Md"))
        XCTAssertTrue(probeLocal.contains("targetRPM=5000"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("viftyhelper-probeLocal\t0\t0 or skipped\thardware-validation"))
        let summary = try harness.readJSON("review-summary.json")
        XCTAssertEqual(summary["includeProbeLocal"] as? Bool, true)
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "viftyhelper-probeLocal"
                && check["status"] as? String == "0"
        })
        XCTAssertEqual(try harness.loggedHelperInvocations(), ["probeLocal"])
    }

    func testCollectorRecordsMissingBundledSchemasWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness(createSchemaResources: false)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("manifest.tsv").contains("schema-resources\t1\tschema-resources.tsv"))
        XCTAssertTrue(try harness.read("schema-resources.stderr").contains("missing bundled schema"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "schema-resources"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0"
        })
        let invocations = try harness.loggedViftyCtlInvocations()
        XCTAssertEqual(invocations, expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsMissingBundledExecutableWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness(createViftyAppExecutable: false)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("manifest.tsv").contains("bundle-executables\t1\tbundle-executables.tsv"))
        XCTAssertTrue(try harness.read("bundle-executables.stderr").contains("missing or non-executable bundled executable"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "bundle-executables"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0"
        })
        let invocations = try harness.loggedViftyCtlInvocations()
        XCTAssertEqual(invocations, expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsCapabilitiesSchemaResourceDriftWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness(
            statusSchemaResourcePath: "Contents/Resources/schemas/wrong-status.schema.json"
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("manifest.tsv").contains("capabilities-schema-resources\t1\tcapabilities-schema-resources.tsv"))
        XCTAssertTrue(try harness.read("capabilities-schema-resources.stderr").contains("schemaResources.status"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "capabilities-schema-resources"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0"
        })
        let invocations = try harness.loggedViftyCtlInvocations()
        XCTAssertEqual(invocations, expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsCapabilitiesContractDriftWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness(runLifecycleAutoRestore: false)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("manifest.tsv").contains("capabilities-contract\t1\tcapabilities-contract.tsv"))
        XCTAssertTrue(try harness.read("capabilities-contract.tsv").contains("runLifecycle.autoRestoreAfterChildExit\tfalse\ttrue"))
        XCTAssertTrue(try harness.read("capabilities-contract.stderr").contains("runLifecycle.autoRestoreAfterChildExit"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "capabilities-contract"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0"
        })
        let invocations = try harness.loggedViftyCtlInvocations()
        XCTAssertEqual(invocations, expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorCopiesPassingReleaseArtifactSummary() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(status: "passed")

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("metadata.txt").contains("releaseArtifactSummaryPath=\(summaryURL.path)"))

        let copiedSummary = try harness.readJSON("release-artifact-summary.json")
        XCTAssertEqual(
            copiedSummary["schemaID"] as? String,
            "https://vifty.local/schemas/release-artifact-summary.schema.json"
        )
        XCTAssertEqual(copiedSummary["status"] as? String, "passed")
        XCTAssertEqual(copiedSummary["caskVersion"] as? String, "1.2.3")
        XCTAssertEqual(copiedSummary["bundleVersion"] as? String, "1.2.3")

        let releaseSummary = try harness.read("release-artifact-summary.tsv")
        XCTAssertTrue(releaseSummary.contains("field\tvalue"))
        XCTAssertTrue(releaseSummary.contains("sourcePath\t\(summaryURL.path)"))
        XCTAssertTrue(releaseSummary.contains("schemaID\thttps://vifty.local/schemas/release-artifact-summary.schema.json"))
        XCTAssertTrue(releaseSummary.contains("status\tpassed"))
        XCTAssertTrue(releaseSummary.contains("installedAppBundleVersion\t1.2.3"))
        XCTAssertTrue(releaseSummary.contains("caskVersion\t1.2.3"))
        XCTAssertTrue(releaseSummary.contains("actualSHA\t0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"))

        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t0\trelease-artifact-summary.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-artifact-summary\t0\t0 or skipped\trelease-trust"))
        let reviewSummaryJSON = try harness.readJSON("review-summary.json")
        XCTAssertEqual(reviewSummaryJSON["releaseArtifactSummaryPath"] as? String, summaryURL.path)
        let checks = try XCTUnwrap(reviewSummaryJSON["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-artifact-summary"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0 or skipped"
                && check["scope"] as? String == "release-trust"
        })

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("\trelease-artifact-summary.json"))
        XCTAssertTrue(checksums.contains("\trelease-artifact-summary.tsv"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorCopiesPassingReleaseChecklist() throws {
        let harness = try ValidationEvidenceHarness()
        let checklistURL = try harness.writeReleaseChecklist(version: "1.2.3")

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-checklist", checklistURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("metadata.txt").contains("releaseChecklistPath=\(checklistURL.path)"))
        XCTAssertTrue(try harness.read("release-checklist.md").contains("# Vifty 1.2.3 Release Checklist"))

        let releaseChecklist = try harness.read("release-checklist.tsv")
        XCTAssertTrue(releaseChecklist.contains("field\tvalue"))
        XCTAssertTrue(releaseChecklist.contains("sourcePath\t\(checklistURL.path)"))
        XCTAssertTrue(releaseChecklist.contains("copiedFile\trelease-checklist.md"))
        XCTAssertTrue(releaseChecklist.contains("titleVersion\t1.2.3"))
        XCTAssertTrue(releaseChecklist.contains("installedAppBundleVersion\t1.2.3"))
        XCTAssertTrue(releaseChecklist.contains("hasWorkflowSection\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasFollowUpSection\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasCaskChecksumFollowUp\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasPublicVerifierFollowUp\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasEvidenceReviewFollowUp\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasCompatibilityGate\ttrue"))
        XCTAssertTrue(releaseChecklist.contains("hasTrustedHomebrewWarning\ttrue"))

        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-checklist\t0\trelease-checklist.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-checklist\t0\t0 or skipped\trelease-trust"))
        let reviewSummaryJSON = try harness.readJSON("review-summary.json")
        XCTAssertEqual(reviewSummaryJSON["releaseChecklistPath"] as? String, checklistURL.path)
        let checks = try XCTUnwrap(reviewSummaryJSON["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-checklist"
                && check["status"] as? String == "0"
                && check["expected"] as? String == "0 or skipped"
                && check["scope"] as? String == "release-trust"
        })

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("\trelease-checklist.md"))
        XCTAssertTrue(checksums.contains("\trelease-checklist.tsv"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsReleaseChecklistVersionMismatchWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let checklistURL = try harness.writeReleaseChecklist(version: "9.9.9")

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-checklist", checklistURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("release-checklist.tsv").contains("titleVersion\t9.9.9"))
        XCTAssertTrue(try harness.read("release-checklist.stderr").contains("did not match installed app bundle version"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-checklist\t1\trelease-checklist.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-checklist\t1\t0 or skipped\trelease-trust"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsReleaseArtifactSummaryVersionMismatchWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(
            status: "passed",
            caskVersion: "9.9.9",
            bundleVersion: "9.9.9"
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("release-artifact-summary.tsv").contains("installedAppBundleVersion\t1.2.3"))
        XCTAssertTrue(try harness.read("release-artifact-summary.tsv").contains("bundleVersion\t9.9.9"))
        XCTAssertTrue(try harness.read("release-artifact-summary.stderr").contains("did not match installed app bundle version"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t1\trelease-artifact-summary.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-artifact-summary\t1\t0 or skipped\trelease-trust"))

        let reviewSummaryJSON = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(reviewSummaryJSON["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-artifact-summary"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0 or skipped"
        })
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsFailedReleaseArtifactSummaryWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(
            status: "failed",
            failureCheck: "bundle-version",
            failureMessage: "bundle version 0.1.0 does not match cask version 1.2.3"
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let copiedSummary = try harness.readJSON("release-artifact-summary.json")
        XCTAssertEqual(copiedSummary["status"] as? String, "failed")
        XCTAssertEqual(copiedSummary["failureCheck"] as? String, "bundle-version")
        XCTAssertTrue(try harness.read("release-artifact-summary.tsv").contains("failureCheck\tbundle-version"))
        XCTAssertTrue(try harness.read("release-artifact-summary.stderr").contains("did not report passed"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t1\trelease-artifact-summary.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-artifact-summary\t1\t0 or skipped\trelease-trust"))

        let reviewSummaryJSON = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(reviewSummaryJSON["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "release-artifact-summary"
                && check["status"] as? String == "1"
                && check["expected"] as? String == "0 or skipped"
        })
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsReleaseArtifactSummarySkippedCheckWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(
            status: "passed",
            releaseCheckStatus: "skipped"
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("release-artifact-summary.stderr").contains("check artifact-sha status \"skipped\" did not report passed"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t1\trelease-artifact-summary.tsv"))
        XCTAssertTrue(try harness.read("review-summary.tsv").contains("release-artifact-summary\t1\t0 or skipped\trelease-trust"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsReleaseArtifactSummaryChecksumMismatchWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(
            status: "passed",
            actualSHA: String(repeating: "b", count: 64)
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("release-artifact-summary.stderr").contains("expectedSHA did not match actualSHA"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t1\trelease-artifact-summary.tsv"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorRecordsReleaseArtifactSummaryArtifactNameDriftWithoutRunningCoolingCommands() throws {
        let harness = try ValidationEvidenceHarness()
        let summaryURL = try harness.writeReleaseArtifactSummary(
            status: "passed",
            expectedArtifactName: "Vifty-v9.9.9.zip"
        )

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path,
            "--release-summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("release-artifact-summary.stderr").contains("expectedArtifactName \"Vifty-v9.9.9.zip\" did not match Vifty-v1.2.3.zip"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("release-artifact-summary\t1\trelease-artifact-summary.tsv"))
        XCTAssertEqual(try harness.loggedViftyCtlInvocations(), expectedReadOnlyViftyCtlInvocations)
    }

    func testCollectorKeepsBlockedDiagnoseEvidenceWhenDiagnoseExitsNonzero() throws {
        let harness = try ValidationEvidenceHarness(diagnoseState: "blocked", diagnoseExitCode: 75)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"blocked\""))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("viftyctl-diagnose\t75\tviftyctl-diagnose.json"))
        let summary = try harness.readJSON("review-summary.json")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "viftyctl-diagnose"
                && check["status"] as? String == "75"
                && check["expected"] as? String == "0 or 75"
        })
    }

    func testCollectorFailsWhenViftyCtlIsMissing() throws {
        let harness = try ValidationEvidenceHarness(createViftyCtl: false)

        let result = try harness.runCollector([
            "--app", harness.appURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertTrue(result.stderr.contains("viftyctl is not executable"))
    }
}

private struct ValidationEvidenceProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class ValidationEvidenceHarness {
    let rootURL: URL
    let appURL: URL
    let outputURL: URL
    let viftyCtlLogURL: URL
    let helperLogURL: URL
    private let diagnoseState: String
    private let diagnoseExitCode: Int
    private let statusSchemaResourcePath: String
    private let runLifecycleAutoRestore: Bool
    private let includePrivacyLeak: Bool

    init(
        createViftyCtl: Bool = true,
        createViftyAppExecutable: Bool = true,
        createSchemaResources: Bool = true,
        statusSchemaResourcePath: String = "Contents/Resources/schemas/viftyctl-status.schema.json",
        runLifecycleAutoRestore: Bool = true,
        diagnoseState: String = "ready",
        diagnoseExitCode: Int = 0,
        includePrivacyLeak: Bool = false,
        appPathComponents: [String] = ["Vifty.app"]
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-validation-evidence-\(UUID().uuidString)", isDirectory: true)
        var appBundleURL = rootURL
        for component in appPathComponents {
            appBundleURL = appBundleURL.appendingPathComponent(component, isDirectory: true)
        }
        appURL = appBundleURL
        outputURL = rootURL.appendingPathComponent("evidence", isDirectory: true)
        viftyCtlLogURL = rootURL.appendingPathComponent("viftyctl.log")
        helperLogURL = rootURL.appendingPathComponent("helper.log")
        self.diagnoseState = diagnoseState
        self.diagnoseExitCode = diagnoseExitCode
        self.statusSchemaResourcePath = statusSchemaResourcePath
        self.runLifecycleAutoRestore = runLifecycleAutoRestore
        self.includePrivacyLeak = includePrivacyLeak

        let macOSURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        let launchDaemonsURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchDaemons", isDirectory: true)
        let schemasURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("schemas", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        if createSchemaResources {
            try FileManager.default.createDirectory(at: schemasURL, withIntermediateDirectories: true)
            try writeSchemaResources(at: schemasURL)
        }
        try writeInfoPlist()
        try writeDaemonPlist(
            launchDaemonsURL.appendingPathComponent("tech.reidar.vifty.daemon.plist")
        )

        if createViftyCtl {
            try writeExecutable(
                macOSURL.appendingPathComponent("viftyctl"),
                contents: fakeViftyCtlScript
            )
        }
        if createViftyAppExecutable {
            try writeExecutable(
                macOSURL.appendingPathComponent("Vifty"),
                contents: fakeViftyAppScript
            )
        }
        try writeExecutable(
            macOSURL.appendingPathComponent("ViftyHelper"),
            contents: fakeHelperScript
        )
        try writeExecutable(
            macOSURL.appendingPathComponent("ViftyDaemon"),
            contents: fakeDaemonScript
        )
    }

    func runCollector(_ arguments: [String]) throws -> ValidationEvidenceProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/collect-validation-evidence.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["FAKE_VIFTYCTL_LOG"] = viftyCtlLogURL.path
        environment["FAKE_VIFTYHELPER_LOG"] = helperLogURL.path
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ValidationEvidenceProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func read(_ filename: String) throws -> String {
        let data = try Data(contentsOf: outputURL.appendingPathComponent(filename))
        return String(decoding: data, as: UTF8.self)
    }

    func readJSON(_ filename: String) throws -> [String: Any] {
        let data = try Data(contentsOf: outputURL.appendingPathComponent(filename))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func readTSV(_ filename: String) throws -> [[String: String]] {
        let lines = try read(filename)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let headerLine = lines.first else {
            return []
        }
        let headers = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return lines.dropFirst().map { line in
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
                (header, index < values.count ? values[index] : "")
            })
        }
    }

    func writeReleaseArtifactSummary(
        status: String,
        caskVersion: String = "1.2.3",
        bundleVersion: String? = nil,
        expectedArtifactName: String? = nil,
        expectedSHA: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        actualSHA: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        signatureChecksSkipped: Bool = false,
        notarizationChecksSkipped: Bool = false,
        releaseCheckStatus: String? = nil,
        failureCheck: String? = nil,
        failureMessage: String? = nil
    ) throws -> URL {
        let resolvedBundleVersion = bundleVersion ?? (status == "passed" ? caskVersion : "0.1.0")
        let resolvedArtifactName = expectedArtifactName ?? "Vifty-v\(caskVersion).zip"
        let resolvedCheckStatus = releaseCheckStatus ?? (status == "passed" ? "passed" : "failed")
        let url = rootURL.appendingPathComponent("Vifty-v\(caskVersion)-artifact-summary.json")
        var summary: [String: Any] = [
            "schemaVersion": 1,
            "schemaID": "https://vifty.local/schemas/release-artifact-summary.schema.json",
            "status": status,
            "generatedAtUTC": "2026-06-11T00:00:00Z",
            "caskVersion": caskVersion,
            "caskURL": "https://github.com/reidark/vifty/releases/download/v\(caskVersion)/Vifty-v\(caskVersion).zip",
            "expectedArtifactName": resolvedArtifactName,
            "artifactPath": "/tmp/Vifty-v\(caskVersion).zip",
            "appPath": "/tmp/Vifty.app",
            "bundleVersion": resolvedBundleVersion,
            "expectedSHA": expectedSHA,
            "expectedSHASource": "cask sha256",
            "actualSHA": actualSHA,
            "expectedTeamID": "TEAMID1234",
            "requiredTeamID": "TEAMID1234",
            "signatureChecksSkipped": signatureChecksSkipped,
            "notarizationChecksSkipped": notarizationChecksSkipped,
            "checks": [
                [
                    "name": status == "passed" ? "artifact-sha" : (failureCheck ?? "artifact-sha"),
                    "status": resolvedCheckStatus,
                    "scope": "release-trust",
                    "note": status == "passed" ? "Artifact SHA-256 matched cask sha256." : (failureMessage ?? "release artifact check failed")
                ]
            ]
        ]
        if let failureCheck {
            summary["failureCheck"] = failureCheck
        }
        if let failureMessage {
            summary["failureMessage"] = failureMessage
        }

        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return url
    }

    func writeReleaseChecklist(version: String, includeFollowUp: Bool = true) throws -> URL {
        let url = rootURL.appendingPathComponent("Vifty-v\(version)-release-checklist.md")
        let followUp = includeFollowUp
            ? """

            ## Required Post-Publication Follow-Up

            - [ ] Update `Casks/vifty.rb` with the published `Vifty-v\(version).zip.sha256` using `scripts/update-cask-checksum.sh --version \(version)`.
            - [ ] Run `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"` against the public cask artifact after the checksum update.
            - [ ] Collect a release-mode evidence bundle with `scripts/collect-validation-evidence.sh --release-summary ./Vifty-v\(version)-artifact-summary.json --release-checklist ./Vifty-v\(version)-release-checklist.md`.
            - [ ] Review that bundle with `scripts/review-validation-evidence.sh --mode release --summary <evidence-dir>/review-result.json`.
            - [ ] Keep compatibility claims gated on reviewed hardware reports with `manualSmokeTestResult: "passed-auto-restored"`.

            Until the post-publication checks pass, do not describe the Homebrew path as a fully trusted public binary install.
            """
            : ""
        let contents = """
        # Vifty \(version) Release Checklist

        ## Verified By The Release Workflow

        - [x] `Vifty-v\(version).zip` and `Vifty-v\(version).zip.sha256` were generated.
        - [x] `scripts/verify-release-artifact.sh` passed before publication and wrote `Vifty-v\(version)-artifact-summary.json`.
        \(followUp)
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func loggedViftyCtlInvocations() throws -> [String] {
        try readLog(viftyCtlLogURL)
    }

    func loggedHelperInvocations() throws -> [String] {
        try readLog(helperLogURL)
    }

    private func readLog(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeExecutable(_ url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func writeInfoPlist() throws {
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>tech.reidar.vifty</string>
          <key>CFBundleShortVersionString</key>
          <string>1.2.3</string>
        </dict>
        </plist>
        """
        try contents.write(
            to: appURL.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeDaemonPlist(_ url: URL) throws {
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>tech.reidar.vifty.daemon</string>
          <key>ProgramArguments</key>
          <array>
            <string>/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>VIFTY_XPC_ALLOWED_TEAM_ID</key>
            <string>TEAMID1234</string>
          </dict>
        </dict>
        </plist>
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeSchemaResources(at schemasURL: URL) throws {
        let schemaIDs = [
            "agent-cooling-evidence-summary.schema.json": "https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json",
            "release-artifact-summary.schema.json": "https://vifty.local/schemas/release-artifact-summary.schema.json",
            "release-readiness.schema.json": "https://vifty.local/schemas/release-readiness.schema.json",
            "validation-report-index.schema.json": "https://vifty.local/schemas/validation-report-index.schema.json",
            "validation-review-result.schema.json": "https://vifty.local/schemas/validation-review-result.schema.json",
            "viftyctl-audit.schema.json": "https://vifty.local/schemas/viftyctl-audit.schema.json",
            "viftyctl-capabilities.schema.json": "https://vifty.local/schemas/viftyctl-capabilities.schema.json",
            "viftyctl-command-error.schema.json": "https://vifty.local/schemas/viftyctl-command-error.schema.json",
            "viftyctl-diagnose.schema.json": "https://vifty.local/schemas/viftyctl-diagnose.schema.json",
            "viftyctl-status.schema.json": "https://vifty.local/schemas/viftyctl-status.schema.json"
        ]
        for (filename, schemaID) in schemaIDs {
            let contents = """
            {
              "$schema": "https://json-schema.org/draft/2020-12/schema",
              "$id": "\(schemaID)",
              "type": "object"
            }
            """
            try contents.write(
                to: schemasURL.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private var fakeViftyCtlScript: String {
        """
        #!/bin/sh
        set -eu

        printf '%s\\n' "$*" >> "${FAKE_VIFTYCTL_LOG:?}"

        if [ "$#" -eq 2 ] && [ "$1" = "capabilities" ] && [ "$2" = "--json" ]; then
          printf '{"schemaVersion":1,"commands":["status","capabilities","diagnose","audit"],"workloads":["test"],"schemaResources":{"audit":"Contents/Resources/schemas/viftyctl-audit.schema.json","capabilities":"Contents/Resources/schemas/viftyctl-capabilities.schema.json","commandError":"Contents/Resources/schemas/viftyctl-command-error.schema.json","diagnose":"Contents/Resources/schemas/viftyctl-diagnose.schema.json","status":"\(statusSchemaResourcePath)"},"policy":{"enabled":true},"supportsForceRetry":true,"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":\(runLifecycleAutoRestore ? "true" : "false"),"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}\\n'
          exit 0
        fi

        if [ "$#" -eq 2 ] && [ "$1" = "status" ] && [ "$2" = "--json" ]; then
          if [ "\(includePrivacyLeak ? "1" : "0")" = "1" ]; then
            printf '{"enabled":true,"activeLease":null,"lastDecision":null,"lastErrorCode":null,"policy":{"enabled":true},"debug":"Serial Number: C02SECRET1234 /Users/private-user/Vifty.app"}\\n'
          else
            printf '{"enabled":true,"activeLease":null,"lastDecision":null,"lastErrorCode":null,"policy":{"enabled":true}}\\n'
          fi
          exit 0
        fi

        if [ "$#" -eq 4 ] && [ "$1" = "audit" ] && [ "$2" = "--limit" ] && [ "$3" = "20" ] && [ "$4" = "--json" ]; then
          printf '{"schemaVersion":1,"generatedAt":700000000,"readOnly":true,"coolingCommandsRun":false,"limit":20,"eventCount":0,"events":[]}\\n'
          exit 0
        fi

        if [ "$#" -eq 2 ] && [ "$1" = "diagnose" ] && [ "$2" = "--json" ]; then
          printf '{"schemaVersion":1,"state":"\(diagnoseState)","safeToRequestCooling":\(diagnoseState == "blocked" ? "false" : "true"),"daemonControlPathReady":\(diagnoseState == "blocked" ? "false" : "true"),"checks":[]}\\n'
          exit \(diagnoseExitCode)
        fi

        echo "unexpected viftyctl invocation: $*" >&2
        exit 99
        """
    }

    private var fakeViftyAppScript: String {
        """
        #!/bin/sh
        set -eu
        exit 0
        """
    }

    private var fakeHelperScript: String {
        """
        #!/bin/sh
        set -eu

        printf '%s\\n' "$*" >> "${FAKE_VIFTYHELPER_LOG:?}"

        if [ "$#" -eq 1 ] && [ "$1" = "probeLocal" ]; then
          printf 'fan[0] name="Left Fan" rpm=2100 min=1400 max=6000 controllable=true hardwareMode=Forced hardwareModeRawValue=1 hardwareModeKey=F0Md targetRPM=5000\\n'
          exit 0
        fi

        echo "unexpected ViftyHelper invocation: $*" >&2
        exit 99
        """
    }

    private var fakeDaemonScript: String {
        """
        #!/bin/sh
        set -eu
        exit 0
        """
    }
}
