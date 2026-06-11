import Foundation
import XCTest

final class ValidationEvidenceReviewScriptTests: XCTestCase {
    func testReviewAcceptsSupportedHardwareEvidenceBundle() throws {
        let harness = try ValidationEvidenceReviewHarness()

        let result = try harness.runReview(mode: "supported-hardware")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode supported-hardware"))
        XCTAssertTrue(result.stderr.contains("manual fan-write smoke-test result is not recorded"))
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

    func testReviewAcceptsUnsupportedHardwareSafeBlockBundle() throws {
        let harness = try ValidationEvidenceReviewHarness(
            diagnoseStatus: "75",
            diagnose: .unsupportedBlocked
        )

        let result = try harness.runReview(mode: "unsupported-hardware")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode unsupported-hardware"))
    }

    func testReviewAcceptsInstalledReleaseTrustEvidenceBundle() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
            releaseArtifactStatus: "0"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Validation evidence review OK: mode release"))
    }

    func testReviewRejectsReleaseEvidenceWhenReleaseSummaryCheckWasSkipped() throws {
        let harness = try ValidationEvidenceReviewHarness(
            includeReleaseSummary: true,
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
            releaseArtifactStatus: "0",
            releaseSummarySchemaID: "https://vifty.local/schemas/old-release-summary.schema.json"
        )

        let result = try harness.runReview(mode: "release")

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("release-artifact-summary.json schemaID must be https://vifty.local/schemas/release-artifact-summary.schema.json"))
    }

    func testReviewWritesPassingMachineReadableSummary() throws {
        let harness = try ValidationEvidenceReviewHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("summaries/supported-review.json")

        let result = try harness.runReview(mode: "supported-hardware", summaryURL: summaryURL)

        XCTAssertEqual(result.exitCode, 0)
        let summary = try harness.readJSON(summaryURL)
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["mode"] as? String, "supported-hardware")
        XCTAssertEqual(summary["bundlePath"] as? String, harness.bundleURL.path)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["diagnoseState"] as? String, "ready")
        XCTAssertEqual(summary["recommendedAgentAction"] as? String, "requestCooling")
        XCTAssertEqual(summary["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(summary["modelIdentifier"] as? String, "MacBookPro18,3")
        XCTAssertEqual(summary["isAppleSilicon"] as? Bool, true)
        XCTAssertEqual(summary["isMacBookPro"] as? Bool, true)
        XCTAssertEqual(summary["fanCount"] as? Int, 2)
        XCTAssertEqual(summary["controllableFanCount"] as? Int, 2)
        XCTAssertEqual(summary["temperatureSensorCount"] as? Int, 2)
        XCTAssertEqual(summary["thermalPressure"] as? String, "nominal")
        XCTAssertEqual(summary["manualSmokeTestResult"] as? String, "not-recorded")
        XCTAssertEqual(summary["manualSmokeTestSource"] as? String, "")
        XCTAssertTrue((summary["failures"] as? [String])?.isEmpty == true)
        XCTAssertTrue((summary["warnings"] as? [String])?.contains {
            $0.contains("manual fan-write smoke-test result")
        } == true)
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

    var safeToRequestCooling: Bool {
        switch self {
        case .supportedReady:
            true
        case .unsupportedBlocked:
            false
        }
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
        probeLocalText: String = "fan[0] id=0 name=\"Left Fan\" currentRPM=2200 minimumRPM=1400 maximumRPM=6800 hardwareMode=Auto hardwareModeRawValue=0 targetRPM=nil",
        includeReleaseSummary: Bool = false,
        releaseArtifactStatus: String = "skipped",
        signatureChecksSkipped: Bool = false,
        notarizationChecksSkipped: Bool = false,
        releaseSummarySchemaID: String = "https://vifty.local/schemas/release-artifact-summary.schema.json",
        releaseSummaryExpectedArtifactName: String = "Vifty-v1.2.3.zip",
        releaseSummaryExpectedSHA: String = String(repeating: "a", count: 64),
        releaseSummaryActualSHA: String = String(repeating: "a", count: 64),
        releaseSummaryCheckStatus: String = "passed",
        launchDaemonTeamID: String = "TEAMID1234"
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-validation-review-\(UUID().uuidString)", isDirectory: true)
        bundleURL = rootURL.appendingPathComponent("evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var statuses: [String: String] = [
            "app-info-plist": "0",
            "bundle-executables": "0",
            "schema-resources": "0",
            "capabilities-schema-resources": "0",
            "launchdaemon-lint": "0",
            "viftyctl-capabilities": "0",
            "viftyctl-status": "0",
            "viftyctl-diagnose": diagnoseStatus,
            "viftyctl-audit": "0",
            "viftyhelper-probeLocal": probeLocalStatus,
            "release-artifact-summary": releaseArtifactStatus,
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

        try writeReviewSummary(
            statuses: statuses,
            releaseArtifactSummaryPath: includeReleaseSummary ? "/tmp/Vifty-v1.2.3-artifact-summary.json" : ""
        )
        try writeText("review-summary.tsv", contents: tsvSummary(statuses))
        try writeText("manifest.tsv", contents: "name\tstatus\tstdout\tstderr\n")
        try writeText("metadata.txt", contents: "readOnly=true\ncoolingCommandsRun=false\n")
        try writeText("checksums.tsv", contents: "sha256\tbytes\tfile\n")
        try writeText("bundle-executables.tsv", contents: bundleExecutablesTSV)
        try writeText("schema-resources.tsv", contents: schemaResourcesTSV)
        try writeText("capabilities-schema-resources.tsv", contents: capabilitiesSchemaResourcesTSV)
        try writeDiagnose(diagnose)
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
    }

    func runReview(
        mode: String,
        summaryURL: URL? = nil,
        manualSmokeResult: String? = nil,
        manualSmokeSource: String? = nil
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

    func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func writeReviewSummary(
        statuses: [String: String],
        releaseArtifactSummaryPath: String
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

    private func writeDiagnose(_ fixture: ValidationEvidenceDiagnoseFixture) throws {
        let supportedPasses = fixture.supportedHardwareCheckPasses
        let json: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": 700000000,
            "state": fixture.status,
            "recommendedAgentAction": fixture.recommendedAgentAction,
            "safeToRequestCooling": fixture.safeToRequestCooling,
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
                    "id": "supportedHardware",
                    "severity": supportedPasses ? "info" : "error",
                    "passed": supportedPasses,
                    "message": supportedPasses
                        ? "Apple Silicon MacBook Pro hardware detected."
                        : "This machine is outside Vifty's supported fan-control scope."
                ]
            ]
        ]
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

    private var bundleExecutablesTSV: String {
        """
        executable\tsha256\tbytes\tbundlePath
        Vifty\t\(String(repeating: "a", count: 64))\t2301952\tContents/MacOS/Vifty
        ViftyHelper\t\(String(repeating: "b", count: 64))\t1407120\tContents/MacOS/ViftyHelper
        ViftyDaemon\t\(String(repeating: "c", count: 64))\t1427184\tContents/MacOS/ViftyDaemon
        viftyctl\t\(String(repeating: "d", count: 64))\t1395104\tContents/MacOS/viftyctl
        """
    }

    private var schemaResourcesTSV: String {
        """
        schema\tsha256\tbytes\tbundlePath
        release-artifact-summary.schema.json\t\(String(repeating: "f", count: 64))\t3300\tContents/Resources/schemas/release-artifact-summary.schema.json
        viftyctl-audit.schema.json\t\(String(repeating: "e", count: 64))\t1390\tContents/Resources/schemas/viftyctl-audit.schema.json
        viftyctl-capabilities.schema.json\t\(String(repeating: "a", count: 64))\t5170\tContents/Resources/schemas/viftyctl-capabilities.schema.json
        viftyctl-command-error.schema.json\t\(String(repeating: "b", count: 64))\t1461\tContents/Resources/schemas/viftyctl-command-error.schema.json
        viftyctl-diagnose.schema.json\t\(String(repeating: "c", count: 64))\t5697\tContents/Resources/schemas/viftyctl-diagnose.schema.json
        viftyctl-status.schema.json\t\(String(repeating: "d", count: 64))\t4828\tContents/Resources/schemas/viftyctl-status.schema.json
        """
    }

    private var capabilitiesSchemaResourcesTSV: String {
        """
        key\tadvertisedResource\texpectedResource
        audit\tContents/Resources/schemas/viftyctl-audit.schema.json\tContents/Resources/schemas/viftyctl-audit.schema.json
        capabilities\tContents/Resources/schemas/viftyctl-capabilities.schema.json\tContents/Resources/schemas/viftyctl-capabilities.schema.json
        commandError\tContents/Resources/schemas/viftyctl-command-error.schema.json\tContents/Resources/schemas/viftyctl-command-error.schema.json
        diagnose\tContents/Resources/schemas/viftyctl-diagnose.schema.json\tContents/Resources/schemas/viftyctl-diagnose.schema.json
        status\tContents/Resources/schemas/viftyctl-status.schema.json\tContents/Resources/schemas/viftyctl-status.schema.json
        """
    }
}
