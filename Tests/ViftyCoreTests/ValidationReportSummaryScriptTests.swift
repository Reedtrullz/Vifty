import Foundation
import XCTest

final class ValidationReportSummaryScriptTests: XCTestCase {
    func testSummarizerWritesTSVAndJSONForReviewedReports() throws {
        let harness = try ValidationReportSummaryHarness()
        try harness.writeReviewResult(
            at: "supported/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            warnings: ["manual fan-write smoke-test result is not recorded"]
        )
        try harness.writeReviewResult(
            at: "validated/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            manualSmokeTestResult: "passed-auto-restored",
            manualSmokeTestSource: "https://github.com/reidar/vifty/issues/42",
            agentRunSmokeResult: "passed-auto-restored",
            agentRunSmokeSource: "https://github.com/reidar/vifty/issues/42#agent-run-smoke",
            agentRunSmokeStartupMode: "Auto",
            agentRunSmokeStartupModeSource: "persisted"
        )
        try harness.writeReviewResult(
            at: "unsupported/review-result.json",
            status: "passed",
            mode: "unsupported-hardware",
            modelIdentifier: "Mac14,2",
            safeToRequestCooling: false
        )
        try harness.writeReviewResult(
            at: "release/review-result.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build"
        )
        try harness.writeReviewResult(
            at: "failed/review-result.json",
            status: "failed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            failures: ["viftyhelper-probeLocal status \"skipped\" was not one of 0"]
        )
        let jsonURL = harness.rootURL.appendingPathComponent("summary/report-index.json")
        let tsvURL = harness.rootURL.appendingPathComponent("summary/report-index.tsv")
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", harness.rootURL.path,
            "--output-json", jsonURL.path,
            "--output-tsv", tsvURL.path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        XCTAssertTrue(tsv.contains("source\treviewGeneratedAtUTC\tstatus\tmode\tclaim\tinstallSource\tsourceRef\tsourceSHA\tsourceArtifactName\tsourceArtifactSHA256\tmanualSmokeTestResult\tmanualSmokeTestSource\tmanualSmokeValidated\tagentRunSmokeResult"))
        XCTAssertTrue(tsv.contains("supported/review-result.json\t2026-06-11T00:00:00Z\tpassed"))
        XCTAssertTrue(tsv.contains("modelIdentifier\tmodelFamily\tisAppleSilicon\tisMacBookPro"))
        XCTAssertTrue(tsv.contains("supported-hardware-evidence-needs-manual-smoke\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("validated-hardware-evidence\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("\tpassed-auto-restored"))
        XCTAssertTrue(tsv.contains("https://github.com/reidar/vifty/issues/42\ttrue\tpassed-auto-restored\thttps://github.com/reidar/vifty/issues/42#agent-run-smoke\ttrue\tAuto\tpersisted\t\"\"\tMacBookPro18,3\tMacBookPro18"))
        XCTAssertTrue(tsv.contains("MacBookPro18,3\tMacBookPro18\ttrue\ttrue\tready\trequestCooling\tnone\ttrue\ttrue"))
        XCTAssertTrue(tsv.contains("Mac14,2\tMac14\ttrue\tfalse\tblocked\tdoNotRequestCooling\tcollectHardwareEvidence\tfalse\ttrue"))
        XCTAssertTrue(tsv.contains("safe-block-evidence\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("release-trust-evidence\tlocal-developer-id-build\tv1.1.0"))
        XCTAssertTrue(tsv.contains("rejected\tsource-build-tag\tv1.1.0"))

        let json = try harness.readJSON(jsonURL)
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            json["schemaID"] as? String,
            "https://vifty.local/schemas/validation-report-index.schema.json"
        )
        XCTAssertEqual(json["readOnly"] as? Bool, true)
        XCTAssertEqual(json["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(json["totalReports"] as? Int, 5)
        XCTAssertEqual(json["passedReports"] as? Int, 4)
        XCTAssertEqual(json["failedReports"] as? Int, 1)
        XCTAssertEqual(json["manualSmokeRequiredReports"] as? Int, 1)
        XCTAssertEqual(json["manualSmokePassedReports"] as? Int, 1)
        XCTAssertEqual(json["agentRunSmokePassedReports"] as? Int, 1)
        XCTAssertEqual(json["validatedHardwareReports"] as? Int, 1)
        let reports = try XCTUnwrap(json["reports"] as? [[String: Any]])
        let sources = reports.compactMap { $0["source"] as? String }
        XCTAssertTrue(sources.contains("supported/review-result.json"))
        XCTAssertFalse(sources.contains { $0.contains(FileManager.default.temporaryDirectory.path) })
        XCTAssertTrue(reports.allSatisfy { ($0["reviewGeneratedAtUTC"] as? String) == "2026-06-11T00:00:00Z" })
        XCTAssertTrue(reports.allSatisfy { ($0["daemonControlPathReady"] as? String) == "true" })
        XCTAssertTrue(reports.allSatisfy { ($0["manualControlActive"] as? String) == "false" })
        XCTAssertTrue(reports.contains { ($0["recommendedAgentAction"] as? String) == "doNotRequestCooling" })
        XCTAssertTrue(reports.contains { ($0["recommendedRecoveryAction"] as? String) == "collectHardwareEvidence" })
        XCTAssertTrue(reports.contains { ($0["modelIdentifier"] as? String) == "MacBookPro18,3" && ($0["modelFamily"] as? String) == "MacBookPro18" })
        XCTAssertTrue(reports.contains {
            ($0["agentRunSmokeStartupMode"] as? String) == "Auto" &&
                ($0["agentRunSmokeStartupModeSource"] as? String) == "persisted" &&
                ($0["agentRunSmokeStartupModeReadError"] as? String) == ""
        })
        XCTAssertTrue(reports.contains { ($0["modelIdentifier"] as? String) == "Mac14,2" && ($0["modelFamily"] as? String) == "Mac14" })
        let countsByClaim = try XCTUnwrap(json["countsByClaim"] as? [String: Int])
        XCTAssertEqual(countsByClaim["supported-hardware-evidence-needs-manual-smoke"], 1)
        XCTAssertEqual(countsByClaim["validated-hardware-evidence"], 1)
        XCTAssertEqual(countsByClaim["safe-block-evidence"], 1)
        XCTAssertEqual(countsByClaim["release-trust-evidence"], 1)
        XCTAssertEqual(countsByClaim["rejected"], 1)
        let countsByInstallSource = try XCTUnwrap(json["countsByInstallSource"] as? [String: Int])
        XCTAssertEqual(countsByInstallSource["source-build-tag"], 4)
        XCTAssertEqual(countsByInstallSource["local-developer-id-build"], 1)
        let countsByModelFamily = try XCTUnwrap(json["countsByModelFamily"] as? [String: Int])
        XCTAssertEqual(countsByModelFamily["MacBookPro18"], 4)
        XCTAssertEqual(countsByModelFamily["Mac14"], 1)
        let validatedByModelFamily = try XCTUnwrap(json["validatedHardwareReportsByModelFamily"] as? [String: Int])
        XCTAssertEqual(validatedByModelFamily["MacBookPro18"], 1)
        XCTAssertNil(validatedByModelFamily["Mac14"])
        let countsByRecommendedAgentAction = try XCTUnwrap(json["countsByRecommendedAgentAction"] as? [String: Int])
        XCTAssertEqual(countsByRecommendedAgentAction["requestCooling"], 4)
        XCTAssertEqual(countsByRecommendedAgentAction["doNotRequestCooling"], 1)
        let countsByRecommendedRecoveryAction = try XCTUnwrap(json["countsByRecommendedRecoveryAction"] as? [String: Int])
        XCTAssertEqual(countsByRecommendedRecoveryAction["none"], 4)
        XCTAssertEqual(countsByRecommendedRecoveryAction["collectHardwareEvidence"], 1)
        let countsBySafeToRequestCooling = try XCTUnwrap(json["countsBySafeToRequestCooling"] as? [String: Int])
        XCTAssertEqual(countsBySafeToRequestCooling["true"], 4)
        XCTAssertEqual(countsBySafeToRequestCooling["false"], 1)
        let countsByDaemonControlPathReady = try XCTUnwrap(json["countsByDaemonControlPathReady"] as? [String: Int])
        XCTAssertEqual(countsByDaemonControlPathReady["true"], 5)
        let countsByManualControlActive = try XCTUnwrap(json["countsByManualControlActive"] as? [String: Int])
        XCTAssertEqual(countsByManualControlActive["false"], 5)

        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Vifty Compatibility Matrix Draft"))
        XCTAssertTrue(markdown.contains("Generated from reviewed validation report summaries."))
        XCTAssertTrue(markdown.contains("source-first and unsigned-dev reports as compatibility evidence only"))
        XCTAssertTrue(markdown.contains("| Model family | Public status | Validated reports | Candidate reports | Agent run smoke reports | Safe-block reports | Rejected reports | Model identifiers | Install sources | Readiness | Evidence |"))
        XCTAssertTrue(markdown.contains("| Mac14 | Expected blocked | 0 | 0 | 0 | 1 | 0 | Mac14,2 | source-build-tag | safeToRequestCooling=false<br>daemonControlPathReady=true<br>manualControlActive=false<br>agentAction=doNotRequestCooling<br>recoveryAction=collectHardwareEvidence | source: v1.1.0@aaaaaaa<br>reviewed: 2026-06-11 |"))
        XCTAssertTrue(markdown.contains("| MacBookPro18 | Validated hardware evidence | 1 | 1 | 1 | 0 | 1 | MacBookPro18,3 | source-build-tag | safeToRequestCooling=true<br>daemonControlPathReady=true<br>manualControlActive=false<br>agentAction=requestCooling<br>recoveryAction=none | source: v1.1.0@aaaaaaa<br>reviewed: 2026-06-11<br>manual: https://github.com/reidar/vifty/issues/42<br>agent-run: https://github.com/reidar/vifty/issues/42#agent-run-smoke<br>agent-run startup: Auto (persisted) |"))
        XCTAssertFalse(markdown.contains("release-trust-evidence"))
    }

    func testSummarizerWritesEmptyMarkdownMatrixWhenThereAreNoReviewedHardwareRows() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "release-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build"
        )
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", reviewURL.path,
            "--output-tsv", harness.rootURL.appendingPathComponent("summary/report-index.tsv").path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("| No reviewed hardware reports | Needs validation | 0 | 0 | 0 | 0 | 0 |  |  |  | Add reviewed `review-result.json` files before changing public claims. |"))
        XCTAssertFalse(markdown.contains("MacBookPro18"))
    }

    func testAgentRunSmokeDoesNotPromoteSupportedHardwareWithoutManualSmoke() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "agent-only/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,1",
            safeToRequestCooling: true,
            manualSmokeTestResult: "not-recorded",
            agentRunSmokeResult: "passed-auto-restored",
            agentRunSmokeSource: "https://github.com/reidar/vifty/issues/42#agent-run-smoke",
            warnings: ["manual fan-write smoke-test result is not recorded"]
        )
        let jsonURL = harness.rootURL.appendingPathComponent("summary/report-index.json")
        let tsvURL = harness.rootURL.appendingPathComponent("summary/report-index.tsv")
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", reviewURL.path,
            "--output-json", jsonURL.path,
            "--output-tsv", tsvURL.path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        XCTAssertTrue(tsv.contains("supported-hardware-evidence-needs-manual-smoke"))
        XCTAssertFalse(tsv.contains("validated-hardware-evidence"))

        let json = try harness.readJSON(jsonURL)
        XCTAssertEqual(json["manualSmokeRequiredReports"] as? Int, 1)
        XCTAssertEqual(json["manualSmokePassedReports"] as? Int, 0)
        XCTAssertEqual(json["agentRunSmokePassedReports"] as? Int, 1)
        XCTAssertEqual(json["validatedHardwareReports"] as? Int, 0)
        let countsByClaim = try XCTUnwrap(json["countsByClaim"] as? [String: Int])
        XCTAssertEqual(countsByClaim["supported-hardware-evidence-needs-manual-smoke"], 1)
        XCTAssertNil(countsByClaim["validated-hardware-evidence"])
        let validatedByModelFamily = try XCTUnwrap(json["validatedHardwareReportsByModelFamily"] as? [String: Int])
        XCTAssertTrue(validatedByModelFamily.isEmpty)

        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("| MacBookPro18 | Needs manual smoke | 0 | 1 | 1 | 0 | 0 | MacBookPro18,1 | source-build-tag | safeToRequestCooling=true<br>daemonControlPathReady=true<br>manualControlActive=false<br>agentAction=requestCooling<br>recoveryAction=none | source: v1.1.0@aaaaaaa<br>reviewed: 2026-06-11<br>manual: not recorded<br>agent-run: https://github.com/reidar/vifty/issues/42#agent-run-smoke |"))
    }

    func testMarkdownMatrixSurfacesUnknownManualControlReadiness() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "legacy-manual-state/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,1",
            safeToRequestCooling: true,
            manualControlActive: nil,
            warnings: ["legacy review did not record manualControlActive"]
        )
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", reviewURL.path,
            "--output-tsv", harness.rootURL.appendingPathComponent("summary/report-index.tsv").path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("manualControlActive=unknown"))
        XCTAssertFalse(markdown.contains("manualControlActive=false"))
    }

    func testSummarizerRejectsValidatedManualSmokeWithoutSource() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "source-less-manual-smoke/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,1",
            safeToRequestCooling: true,
            manualSmokeTestResult: "passed-auto-restored",
            manualSmokeTestSource: ""
        )
        let jsonURL = harness.rootURL.appendingPathComponent("summary/report-index.json")
        let tsvURL = harness.rootURL.appendingPathComponent("summary/report-index.tsv")
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", reviewURL.path,
            "--output-json", jsonURL.path,
            "--output-tsv", tsvURL.path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("manualSmokeTestSource is required when manualSmokeTestResult is passed-auto-restored"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tsvURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownURL.path))
    }

    func testValidationReportIndexSchemaDocumentsSummarizerContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/validation-report-index.schema.json")
        let schema = try ValidationReportSummaryHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/validation-report-index.schema.json")

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "generatedAtUTC",
            "readOnly",
            "coolingCommandsRun",
            "totalReports",
            "validatedHardwareReports",
            "agentRunSmokePassedReports",
            "countsByInstallSource",
            "countsByClaim",
            "countsByModelFamily",
            "validatedHardwareReportsByModelFamily",
            "countsByRecommendedAgentAction",
            "countsByRecommendedRecoveryAction",
            "countsBySafeToRequestCooling",
            "countsByDaemonControlPathReady",
            "countsByManualControlActive",
            "reports"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let claim = try XCTUnwrap(defs["claim"] as? [String: Any])
        let claimValues = try XCTUnwrap(claim["enum"] as? [String])
        XCTAssertTrue(claimValues.contains("validated-hardware-evidence"))
        XCTAssertTrue(claimValues.contains("supported-hardware-evidence-needs-manual-smoke"))
        XCTAssertTrue(claimValues.contains("release-trust-evidence"))
        XCTAssertTrue(claimValues.contains("safe-block-evidence"))
        let report = try XCTUnwrap(defs["report"] as? [String: Any])
        let reportRequired = try XCTUnwrap(report["required"] as? [String])
        XCTAssertTrue(reportRequired.contains("reviewGeneratedAtUTC"))
        XCTAssertTrue(reportRequired.contains("modelFamily"))
        XCTAssertTrue(reportRequired.contains("daemonControlPathReady"))
        XCTAssertTrue(reportRequired.contains("manualControlActive"))
        XCTAssertTrue(reportRequired.contains("agentRunSmokeStartupMode"))
        XCTAssertTrue(reportRequired.contains("agentRunSmokeStartupModeSource"))
        XCTAssertTrue(reportRequired.contains("agentRunSmokeStartupModeReadError"))
        XCTAssertTrue(reportRequired.contains("recommendedAgentAction"))
        XCTAssertTrue(reportRequired.contains("recommendedRecoveryAction"))
        let agentAction = try XCTUnwrap(defs["readinessAgentAction"] as? [String: Any])
        let agentActionValues = try XCTUnwrap(agentAction["enum"] as? [String])
        XCTAssertTrue(agentActionValues.contains("requestCooling"))
        XCTAssertTrue(agentActionValues.contains("doNotRequestCooling"))
        let installSource = try XCTUnwrap(defs["installSource"] as? [String: Any])
        let installSourceValues = try XCTUnwrap(installSource["enum"] as? [String])
        XCTAssertTrue(installSourceValues.contains(""))
        XCTAssertTrue(installSourceValues.contains("source-build-tag"))
        XCTAssertTrue(installSourceValues.contains("source-first-unsigned-dev-zip"))
        XCTAssertNotNil(defs["requiredGitSHA"] as? [String: Any])
        let requiredNonEmptyString = try XCTUnwrap(defs["requiredNonEmptyString"] as? [String: Any])
        XCTAssertEqual(requiredNonEmptyString["pattern"] as? String, "\\S")
        let utcTimestamp = try XCTUnwrap(defs["utcTimestamp"] as? [String: Any])
        XCTAssertEqual(utcTimestamp["pattern"] as? String, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
        let reportProperties = try XCTUnwrap(report["properties"] as? [String: Any])
        let reportGeneratedAt = try XCTUnwrap(reportProperties["reviewGeneratedAtUTC"] as? [String: Any])
        XCTAssertEqual(reportGeneratedAt["$ref"] as? String, "#/$defs/utcTimestamp")
        let reportStartupMode = try XCTUnwrap(reportProperties["agentRunSmokeStartupMode"] as? [String: Any])
        XCTAssertEqual(
            reportStartupMode["description"] as? String,
            "Read-only startup mode copied from reviewed supervised agent-run smoke preflight app preferences when present."
        )
        XCTAssertNotNil(defs["versionTag"] as? [String: Any])
        let reportAllOf = try XCTUnwrap(report["allOf"] as? [[String: Any]])
        XCTAssertTrue(reportAllOf.contains { condition in
            guard
                let ifBlock = condition["if"] as? [String: Any],
                let ifProperties = ifBlock["properties"] as? [String: Any],
                let result = ifProperties["manualSmokeTestResult"] as? [String: Any],
                result["const"] as? String == "passed-auto-restored",
                let thenBlock = condition["then"] as? [String: Any],
                let thenProperties = thenBlock["properties"] as? [String: Any],
                let source = thenProperties["manualSmokeTestSource"] as? [String: Any]
            else { return false }
            return source["$ref"] as? String == "#/$defs/requiredNonEmptyString"
        })
        let releaseInstallSource = try XCTUnwrap(defs["releaseInstallSource"] as? [String: Any])
        let releaseInstallSourceValues = try XCTUnwrap(releaseInstallSource["enum"] as? [String])
        XCTAssertTrue(releaseInstallSourceValues.contains("notarized-github-release"))
        XCTAssertTrue(releaseInstallSourceValues.contains("homebrew-cask"))
        XCTAssertTrue(releaseInstallSourceValues.contains("local-developer-id-build"))
    }

    func testValidationReviewResultSchemaDocumentsReviewerContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/validation-review-result.schema.json")
        let schema = try ValidationReportSummaryHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/validation-review-result.schema.json")

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "readOnly",
            "coolingCommandsRun",
            "installSource",
            "sourceSHA",
            "sourceArtifactSHA256",
            "sourceArtifactBytes",
            "recommendedAgentAction",
            "recommendedRecoveryAction",
            "daemonControlPathReady",
            "manualControlActive",
            "modelIdentifier",
            "modelFamily",
            "manualSmokeTestResult",
            "agentRunSmokeResult",
            "failures",
            "warnings"
        ] {
            XCTAssertTrue(required.contains(field), "review-result schema should require \(field)")
        }
        XCTAssertFalse(required.contains("agentRunSmokeStartupMode"))
        XCTAssertFalse(required.contains("agentRunSmokeStartupModeSource"))
        XCTAssertFalse(required.contains("agentRunSmokeStartupModeReadError"))

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let startupMode = try XCTUnwrap(properties["agentRunSmokeStartupMode"] as? [String: Any])
        XCTAssertEqual(startupMode["$ref"] as? String, "#/$defs/agentRunSmokeStartupMode")

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let installSource = try XCTUnwrap(defs["installSource"] as? [String: Any])
        let installSourceValues = try XCTUnwrap(installSource["enum"] as? [String])
        XCTAssertTrue(installSourceValues.contains("source-build-tag"))
        XCTAssertTrue(installSourceValues.contains("source-first-unsigned-dev-zip"))
        XCTAssertNotNil(defs["requiredGitSHA"] as? [String: Any])
        let requiredNonEmptyString = try XCTUnwrap(defs["requiredNonEmptyString"] as? [String: Any])
        XCTAssertEqual(requiredNonEmptyString["pattern"] as? String, "\\S")
        XCTAssertNotNil(defs["versionTag"] as? [String: Any])
        let allOf = try XCTUnwrap(schema["allOf"] as? [[String: Any]])
        XCTAssertTrue(allOf.contains { condition in
            guard
                let ifBlock = condition["if"] as? [String: Any],
                let ifProperties = ifBlock["properties"] as? [String: Any],
                let result = ifProperties["manualSmokeTestResult"] as? [String: Any],
                result["const"] as? String == "passed-auto-restored",
                let thenBlock = condition["then"] as? [String: Any],
                let thenProperties = thenBlock["properties"] as? [String: Any],
                let source = thenProperties["manualSmokeTestSource"] as? [String: Any]
            else { return false }
            return source["$ref"] as? String == "#/$defs/requiredNonEmptyString"
        })
    }

    func testSummarizerPrintsTSVToStdoutWhenNoOutputTSVIsProvided() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "release-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("source\treviewGeneratedAtUTC\tstatus\tmode\tclaim"))
        XCTAssertTrue(result.stdout.contains("release-trust-evidence"))
    }

    func testSummarizerRejectsMissingInput() throws {
        let harness = try ValidationReportSummaryHarness()
        let missingURL = harness.rootURL.appendingPathComponent("missing")

        let result = try harness.runSummarizer(["--input", missingURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("input not found"))
    }

    func testSummarizerRejectsNonReadOnlyReviewResult() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "mutating-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build",
            readOnly: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must declare readOnly=true"))
    }

    func testSummarizerRejectsReviewResultWithoutSchemaID() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "missing-schema-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build",
            includeSchemaID: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("schemaID must be https://vifty.local/schemas/validation-review-result.schema.json"))
    }

    func testSummarizerRejectsReviewResultWithoutGeneratedAtUTC() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "missing-generated-at-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            includeGeneratedAtUTC: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("generatedAtUTC must be an ISO-8601 UTC timestamp"))
    }

    func testSummarizerRejectsReviewResultWithMalformedGeneratedAtUTC() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "bad-generated-at-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            generatedAtUTC: "2026-06-11 00:00:00"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("generatedAtUTC must be an ISO-8601 UTC timestamp"))
    }

    func testSummarizerRejectsReviewResultWithSchemaIDDrift() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "stale-schema-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build",
            schemaID: "https://vifty.local/schemas/old-validation-review-result.schema.json"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("schemaID must be https://vifty.local/schemas/validation-review-result.schema.json"))
    }

    func testSummarizerRejectsInvalidSourceArtifactBytes() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "bad-artifact-bytes-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            sourceArtifactBytes: "0"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("sourceArtifactBytes must be a positive integer"))
    }

    func testSummarizerRejectsReleaseModeFromSourceFirstInstallSource() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "source-first-release-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "source-build-tag"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains("release mode requires installSource notarized-github-release, homebrew-cask, or local-developer-id-build"),
            result.stderr
        )
    }

    func testSummarizerRejectsSourceEvidenceWithoutImmutableSourceSHA() throws {
        for installSource in ["source-build-tag", "source-first-unsigned-dev-zip", "local-ad-hoc-build"] {
            let harness = try ValidationReportSummaryHarness()
            try harness.writeReviewResult(
                at: "\(installSource)/review-result.json",
                status: "passed",
                mode: "supported-hardware",
                modelIdentifier: "MacBookPro18,3",
                safeToRequestCooling: true,
                installSource: installSource,
                sourceRef: installSource == "local-ad-hoc-build" ? "" : "v1.1.0",
                sourceSHA: ""
            )

            let result = try harness.runSummarizer(["--input", harness.rootURL.path])

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(
                result.stderr.contains("\(installSource) review result requires sourceSHA"),
                installSource
            )
        }
    }

    func testSummarizerRejectsSourceBuildEvidenceWithoutVersionTagRef() throws {
        for installSource in ["source-build-tag", "source-first-unsigned-dev-zip"] {
            let harness = try ValidationReportSummaryHarness()
            try harness.writeReviewResult(
                at: "\(installSource)/review-result.json",
                status: "passed",
                mode: "supported-hardware",
                modelIdentifier: "MacBookPro18,3",
                safeToRequestCooling: true,
                installSource: installSource,
                sourceRef: "main",
                sourceSHA: String(repeating: "d", count: 40)
            )

            let result = try harness.runSummarizer(["--input", harness.rootURL.path])

            XCTAssertEqual(result.exitCode, 65)
            XCTAssertTrue(
                result.stderr.contains("\(installSource) review result requires sourceRef"),
                installSource
            )
        }
    }

    func testSummarizerDoesNotWriteCandidateRowsWhenSourceSHAIsMissing() throws {
        let harness = try ValidationReportSummaryHarness()
        try harness.writeReviewResult(
            at: "supported/review-result.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "source-build-tag",
            sourceRef: "v1.1.0",
            sourceSHA: ""
        )
        let jsonURL = harness.rootURL.appendingPathComponent("summary/report-index.json")
        let tsvURL = harness.rootURL.appendingPathComponent("summary/report-index.tsv")
        let markdownURL = harness.rootURL.appendingPathComponent("summary/compatibility-matrix.md")

        let result = try harness.runSummarizer([
            "--input", harness.rootURL.path,
            "--output-json", jsonURL.path,
            "--output-tsv", tsvURL.path,
            "--output-markdown", markdownURL.path
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("source-build-tag review result requires sourceSHA"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tsvURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markdownURL.path))
    }

    func testSummarizerRejectsReviewResultWithoutDaemonControlPathReadiness() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "missing-control-path-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            includeDaemonControlPathReady: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("daemonControlPathReady must be true or false"))
    }

    func testSummarizerRejectsReviewResultWithoutRecommendedRecoveryAction() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "missing-recovery-action-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            includeRecommendedRecoveryAction: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("recommendedRecoveryAction is not a supported value"))
    }

    func testSummarizerRejectsReviewResultWithModelFamilyDrift() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "drifted-model-family-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            modelFamily: "Mac14"
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(
            result.stderr.contains(#"modelFamily "Mac14" did not match derived modelIdentifier family "MacBookPro18""#),
            result.stderr
        )
    }

    func testSummarizerRejectsReviewResultWithoutRecommendedAgentAction() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "missing-agent-action-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            includeRecommendedAgentAction: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("recommendedAgentAction is not a supported value"))
    }

    func testSummarizerRejectsReviewResultThatRanCoolingCommands() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "cooling-review.json",
            status: "passed",
            mode: "supported-hardware",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            coolingCommandsRun: true
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must declare coolingCommandsRun=false"))
    }

    func testSummarizerRejectsPassedReviewResultWithFailures() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "contradictory-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true,
            installSource: "local-developer-id-build",
            failures: ["release-artifact-summary status \"1\" was not one of 0"]
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("passed review results must not contain failures"))
    }

    func testSummarizerRejectsUnsupportedReviewMode() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "unknown-mode-review.json",
            status: "passed",
            mode: "marketing-claim",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("mode must be release, supported-hardware, or unsupported-hardware"))
    }
}

private struct ValidationReportSummaryProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class ValidationReportSummaryHarness {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-validation-report-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @discardableResult
    func writeReviewResult(
        at relativePath: String,
        status: String,
        mode: String,
        modelIdentifier: String,
        safeToRequestCooling: Bool,
        installSource: String = "source-build-tag",
        daemonControlPathReady: Bool = true,
        manualControlActive: Bool? = false,
        includeDaemonControlPathReady: Bool = true,
        includeRecommendedAgentAction: Bool = true,
        includeRecommendedRecoveryAction: Bool = true,
        manualSmokeTestResult: String = "not-recorded",
        manualSmokeTestSource: String = "",
        agentRunSmokeResult: String = "not-recorded",
        agentRunSmokeSource: String = "",
        agentRunSmokeStartupMode: String = "",
        agentRunSmokeStartupModeSource: String = "",
        agentRunSmokeStartupModeReadError: String = "",
        failures: [String] = [],
        warnings: [String] = [],
        readOnly: Bool = true,
        coolingCommandsRun: Bool = false,
        includeSchemaID: Bool = true,
        schemaID: String = "https://vifty.local/schemas/validation-review-result.schema.json",
        generatedAtUTC: String = "2026-06-11T00:00:00Z",
        includeGeneratedAtUTC: Bool = true,
        sourceArtifactBytes: String = "",
        sourceRef: String = "v1.1.0",
        sourceSHA: String = String(repeating: "a", count: 40),
        modelFamily: String? = nil
    ) throws -> URL {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var json: [String: Any] = [
            "schemaVersion": 1,
            "status": status,
            "mode": mode,
            "bundlePath": url.deletingLastPathComponent().path,
            "readOnly": readOnly,
            "coolingCommandsRun": coolingCommandsRun,
            "appPath": "/Applications/Vifty.app",
            "installSource": installSource,
            "sourceRef": sourceRef,
            "sourceSHA": sourceSHA,
            "sourceArtifactName": "",
            "sourceArtifactSHA256": "",
            "sourceArtifactBytes": sourceArtifactBytes,
            "diagnoseState": mode == "unsupported-hardware" ? "blocked" : "ready",
            "safeToRequestCooling": safeToRequestCooling,
            "modelIdentifier": modelIdentifier,
            "isAppleSilicon": modelIdentifier.hasPrefix("MacBookPro") || modelIdentifier.hasPrefix("Mac"),
            "isMacBookPro": modelIdentifier.hasPrefix("MacBookPro"),
            "fanCount": modelIdentifier.hasPrefix("MacBookPro") ? 2 : 0,
            "controllableFanCount": modelIdentifier.hasPrefix("MacBookPro") ? 2 : 0,
            "temperatureSensorCount": modelIdentifier.hasPrefix("MacBookPro") ? 2 : 0,
            "thermalPressure": "nominal",
            "manualSmokeTestResult": manualSmokeTestResult,
            "manualSmokeTestSource": manualSmokeTestSource,
            "agentRunSmokeResult": agentRunSmokeResult,
            "agentRunSmokeSource": agentRunSmokeSource,
            "agentRunSmokeStartupMode": agentRunSmokeStartupMode,
            "agentRunSmokeStartupModeSource": agentRunSmokeStartupModeSource,
            "agentRunSmokeStartupModeReadError": agentRunSmokeStartupModeReadError,
            "failures": failures,
            "warnings": warnings
        ]
        if let modelFamily {
            json["modelFamily"] = modelFamily
        }
        if includeGeneratedAtUTC {
            json["generatedAtUTC"] = generatedAtUTC
        }
        if includeSchemaID {
            json["schemaID"] = schemaID
        }
        if includeDaemonControlPathReady {
            json["daemonControlPathReady"] = daemonControlPathReady
        }
        json["manualControlActive"] = manualControlActive as Any? ?? NSNull()
        if includeRecommendedAgentAction {
            json["recommendedAgentAction"] = mode == "unsupported-hardware" ? "doNotRequestCooling" : "requestCooling"
        }
        if includeRecommendedRecoveryAction {
            json["recommendedRecoveryAction"] = mode == "unsupported-hardware" ? "collectHardwareEvidence" : "none"
        }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return url
    }

    func runSummarizer(_ arguments: [String]) throws -> ValidationReportSummaryProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/summarize-validation-reports.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ValidationReportSummaryProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func readJSON(_ url: URL) throws -> [String: Any] {
        try Self.readJSON(url)
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
