import Foundation
import XCTest

final class ReleaseArtifactScriptTests: XCTestCase {
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
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/release-artifact-summary.schema.json"
        )
        XCTAssertEqual(summary["caskVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["bundleVersion"] as? String, "1.2.3")
        XCTAssertEqual(summary["actualSHA"] as? String, harness.sha256)
        XCTAssertEqual(summary["expectedSHASource"] as? String, "cask sha256")
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["signatureChecksSkipped"] as? Bool, true)
        XCTAssertEqual(summary["notarizationChecksSkipped"] as? Bool, true)
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "artifact-sha"
                && check["status"] as? String == "passed"
        })
        XCTAssertTrue(checks.contains { check in
            check["name"] as? String == "schema-resources"
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
        XCTAssertTrue(result.stderr.contains("does not match cask sha256"))
    }

    func testVerifierAcceptsExpectedSHAOverrideBeforeCaskChecksumIsUpdated() throws {
        let harness = try ReleaseArtifactHarness(caskSHA: String(repeating: "0", count: 64))

        let result = try harness.runVerifier([
            "--expected-sha", harness.sha256,
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release artifact OK: version 1.2.3"))
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
        XCTAssertTrue(result.stderr.contains("Contents/Resources/collect-agent-cooling-evidence.sh"))
    }

    func testVerifierRejectsMissingWorkloadWrappers() throws {
        let harness = try ReleaseArtifactHarness(includeWorkloadWrappers: false)

        let result = try harness.runVerifier([
            "--skip-signature-checks",
            "--skip-notarization-checks"
        ])

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("missing executable workload wrapper"))
        XCTAssertTrue(result.stderr.contains("Contents/Resources/viftyctl-wrappers/guarded-run.sh"))
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

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "status",
            "generatedAtUTC",
            "caskVersion",
            "bundleVersion",
            "expectedSHA",
            "actualSHA",
            "signatureChecksSkipped",
            "notarizationChecksSkipped",
            "checks"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }
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

private final class ReleaseArtifactHarness {
    let rootURL: URL
    let caskURL: URL
    let artifactURL: URL
    let sha256: String

    init(
        caskVersion: String = "1.2.3",
        bundleVersion: String = "1.2.3",
        caskSHA: String? = nil,
        includeSchemaResources: Bool = true,
        includeSupportScripts: Bool = true,
        includeWorkloadWrappers: Bool = true,
        schemaResourceOverrides: [String: String] = [:]
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-artifact-\(UUID().uuidString)", isDirectory: true)
        let payloadURL = rootURL.appendingPathComponent("payload", isDirectory: true)
        caskURL = rootURL.appendingPathComponent("Casks/vifty.rb")
        artifactURL = rootURL.appendingPathComponent("Vifty-v\(caskVersion).zip")

        try FileManager.default.createDirectory(at: payloadURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: caskURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeFakeApp(
            at: payloadURL.appendingPathComponent("Vifty.app", isDirectory: true),
            version: bundleVersion,
            includeSchemaResources: includeSchemaResources,
            includeSupportScripts: includeSupportScripts,
            includeWorkloadWrappers: includeWorkloadWrappers,
            schemaResourceOverrides: schemaResourceOverrides
        )
        try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--keepParent", "Vifty.app", artifactURL.path],
            currentDirectoryURL: payloadURL
        )
        sha256 = try Self.sha256(of: artifactURL)
        try Self.writeCask(
            at: caskURL,
            version: caskVersion,
            sha: caskSHA ?? sha256
        )
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

    private static func writeFakeApp(
        at appURL: URL,
        version: String,
        includeSchemaResources: Bool,
        includeSupportScripts: Bool,
        includeWorkloadWrappers: Bool,
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
            try writeSchemaResources(at: schemasURL, overrides: schemaResourceOverrides)
        }
        try FileManager.default.createDirectory(at: launchDaemonsURL, withIntermediateDirectories: true)
        try writeInfoPlist(
            at: appURL.appendingPathComponent("Contents/Info.plist"),
            version: version
        )
        try writeDaemonPlist(
            at: launchDaemonsURL.appendingPathComponent("tech.reidar.vifty.daemon.plist")
        )
        for executable in ["Vifty", "ViftyHelper", "ViftyDaemon", "viftyctl"] {
            try writeExecutable(macOSURL.appendingPathComponent(executable))
        }
        if includeSupportScripts {
            for script in ["collect-agent-cooling-evidence.sh", "collect-agent-run-smoke-evidence.sh"] {
                try writeExecutable(resourcesURL.appendingPathComponent(script))
            }
        }
        if includeWorkloadWrappers {
            try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)
            for script in Self.workloadWrapperScripts {
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
        "swift-test.sh",
        "swift-release-build.sh",
        "xcode-build.sh",
        "xcode-test.sh",
        "make-build.sh",
        "make-test.sh",
        "make-verify.sh",
        "npm-build.sh",
        "npm-test.sh",
        "cargo-build.sh",
        "cargo-test.sh",
        "pytest.sh",
        "local-model.sh",
        "custom-workload.sh"
    ]

    private static func writeSchemaResources(at schemasURL: URL, overrides: [String: String]) throws {
        let schemaIDs = [
            "agent-cooling-evidence-summary.schema.json": "https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json",
            "agent-cooling-evidence-review.schema.json": "https://vifty.local/schemas/agent-cooling-evidence-review.schema.json",
            "agent-run-smoke-evidence-summary.schema.json": "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json",
            "guarded-run-decision.schema.json": "https://vifty.local/schemas/guarded-run-decision.schema.json",
            "manual-smoke-readiness.schema.json": "https://vifty.local/schemas/manual-smoke-readiness.schema.json",
            "release-artifact-summary.schema.json": "https://vifty.local/schemas/release-artifact-summary.schema.json",
            "release-readiness.schema.json": "https://vifty.local/schemas/release-readiness.schema.json",
            "validation-report-index.schema.json": "https://vifty.local/schemas/validation-report-index.schema.json",
            "validation-review-result.schema.json": "https://vifty.local/schemas/validation-review-result.schema.json",
            "viftyctl-audit.schema.json": "https://vifty.local/schemas/viftyctl-audit.schema.json",
            "viftyctl-capabilities.schema.json": "https://vifty.local/schemas/viftyctl-capabilities.schema.json",
            "viftyctl-command-error.schema.json": "https://vifty.local/schemas/viftyctl-command-error.schema.json",
            "viftyctl-diagnose.schema.json": "https://vifty.local/schemas/viftyctl-diagnose.schema.json",
            "viftyctl-run.schema.json": "https://vifty.local/schemas/viftyctl-run.schema.json",
            "viftyctl-status.schema.json": "https://vifty.local/schemas/viftyctl-status.schema.json"
        ]
        for (filename, schemaID) in schemaIDs {
            let contents = overrides[filename] ?? """
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

    private static func writeInfoPlist(at url: URL, version: String) throws {
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleShortVersionString</key>
          <string>\(version)</string>
        </dict>
        </plist>
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeDaemonPlist(at url: URL) throws {
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>EnvironmentVariables</key>
          <dict>
            <key>VIFTY_XPC_ALLOWED_TEAM_ID</key>
            <string>TEAM123456</string>
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
        end
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
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
