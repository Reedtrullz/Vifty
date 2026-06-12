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
            manualSmokeTestSource: "https://github.com/reidar/vifty/issues/42"
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
            safeToRequestCooling: true
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

        let result = try harness.runSummarizer([
            "--input", harness.rootURL.path,
            "--output-json", jsonURL.path,
            "--output-tsv", tsvURL.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        let tsv = try String(contentsOf: tsvURL, encoding: .utf8)
        XCTAssertTrue(tsv.contains("source\tstatus\tmode\tclaim\tinstallSource\tsourceRef\tsourceSHA\tsourceArtifactName\tsourceArtifactSHA256\tmanualSmokeTestResult"))
        XCTAssertTrue(tsv.contains("supported-hardware-evidence-needs-manual-smoke\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("validated-hardware-evidence\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("\tpassed-auto-restored"))
        XCTAssertTrue(tsv.contains("https://github.com/reidar/vifty/issues/42\ttrue\tMacBookPro18,3"))
        XCTAssertTrue(tsv.contains("safe-block-evidence\tsource-build-tag\tv1.1.0"))
        XCTAssertTrue(tsv.contains("release-trust-evidence\tsource-build-tag\tv1.1.0"))
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
        XCTAssertEqual(json["validatedHardwareReports"] as? Int, 1)
        let countsByClaim = try XCTUnwrap(json["countsByClaim"] as? [String: Int])
        XCTAssertEqual(countsByClaim["supported-hardware-evidence-needs-manual-smoke"], 1)
        XCTAssertEqual(countsByClaim["validated-hardware-evidence"], 1)
        XCTAssertEqual(countsByClaim["safe-block-evidence"], 1)
        XCTAssertEqual(countsByClaim["release-trust-evidence"], 1)
        XCTAssertEqual(countsByClaim["rejected"], 1)
        let countsByInstallSource = try XCTUnwrap(json["countsByInstallSource"] as? [String: Int])
        XCTAssertEqual(countsByInstallSource["source-build-tag"], 5)
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
            "readOnly",
            "coolingCommandsRun",
            "totalReports",
            "validatedHardwareReports",
            "countsByInstallSource",
            "countsByClaim",
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
        let installSource = try XCTUnwrap(defs["installSource"] as? [String: Any])
        let installSourceValues = try XCTUnwrap(installSource["enum"] as? [String])
        XCTAssertTrue(installSourceValues.contains("source-build-tag"))
        XCTAssertTrue(installSourceValues.contains("source-first-unsigned-dev-zip"))
    }

    func testSummarizerPrintsTSVToStdoutWhenNoOutputTSVIsProvided() throws {
        let harness = try ValidationReportSummaryHarness()
        let reviewURL = try harness.writeReviewResult(
            at: "release-review.json",
            status: "passed",
            mode: "release",
            modelIdentifier: "MacBookPro18,3",
            safeToRequestCooling: true
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("source\tstatus\tmode\tclaim"))
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
            readOnly: false
        )

        let result = try harness.runSummarizer(["--input", reviewURL.path])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("must declare readOnly=true"))
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
        manualSmokeTestResult: String = "not-recorded",
        manualSmokeTestSource: String = "",
        failures: [String] = [],
        warnings: [String] = [],
        readOnly: Bool = true,
        coolingCommandsRun: Bool = false
    ) throws -> URL {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let json: [String: Any] = [
            "schemaVersion": 1,
            "generatedAtUTC": "2026-06-11T00:00:00Z",
            "status": status,
            "mode": mode,
            "bundlePath": url.deletingLastPathComponent().path,
            "readOnly": readOnly,
            "coolingCommandsRun": coolingCommandsRun,
            "appPath": "/Applications/Vifty.app",
            "installSource": "source-build-tag",
            "sourceRef": "v1.1.0",
            "sourceSHA": String(repeating: "a", count: 40),
            "sourceArtifactName": "",
            "sourceArtifactSHA256": "",
            "diagnoseState": mode == "unsupported-hardware" ? "blocked" : "ready",
            "recommendedAgentAction": mode == "unsupported-hardware" ? "doNotRequestCooling" : "requestCooling",
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
            "failures": failures,
            "warnings": warnings
        ]
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
