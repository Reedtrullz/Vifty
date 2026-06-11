import Foundation
import XCTest

final class GitHubMetadataScriptTests: XCTestCase {
    func testCheckerAcceptsRequiredTopicsAndLabels() throws {
        let harness = try GitHubMetadataHarness()

        let result = try harness.runChecker(json: true)

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "passed")

        let checks = summary["checks"] as? [[String: Any]]
        XCTAssertEqual(checkStatus(named: "topics", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "labels", in: checks), "passed")
    }

    func testCheckerBlocksMissingTopicsAndLabelDrift() throws {
        let harness = try GitHubMetadataHarness()
        try harness.writeTopicFixture(missing: "apple-silicon")
        try harness.writeLabelFixture(
            missing: "release-trust",
            colorOverride: ["agent-cooling": "ffffff"]
        )

        let result = try harness.runChecker(json: true)

        XCTAssertEqual(result.exitCode, 1)
        let summary = try result.json()
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["missingTopics"] as? [String], ["apple-silicon"])
        XCTAssertEqual(summary["missingLabels"] as? [String], ["release-trust"])

        let mismatchedLabels = summary["mismatchedLabels"] as? [[String: Any]]
        XCTAssertTrue(mismatchedLabels?.contains(where: {
            $0["name"] as? String == "agent-cooling"
                && $0["field"] as? String == "color"
                && $0["expected"] as? String == "0E8A16"
                && $0["actual"] as? String == "FFFFFF"
        }) == true)
    }

    func testMetadataManifestCoversTriageAndIssueTemplateLabels() throws {
        let harness = try GitHubMetadataHarness()
        let labelNames = Set(harness.labels.map { $0.name })
        let supportTriage = try harness.read("docs/support-triage.md")

        for label in ["release-trust", "hardware-validation", "unsupported-hardware", "helper-install", "smc-telemetry", "agent-cooling", "ui", "security"] {
            XCTAssertTrue(labelNames.contains(label), "Expected manifest to include \(label)")
            XCTAssertTrue(supportTriage.contains("`\(label)`"), "Expected support triage to mention \(label)")
        }

        let releaseTrustTemplate = try harness.read(".github/ISSUE_TEMPLATE/release-trust.yml")
        let hardwareTemplate = try harness.read(".github/ISSUE_TEMPLATE/hardware-validation.yml")
        let agentTemplate = try harness.read(".github/ISSUE_TEMPLATE/agent-cooling.yml")

        XCTAssertTrue(releaseTrustTemplate.contains("labels: [\"release-trust\"]"))
        XCTAssertTrue(hardwareTemplate.contains("labels: [\"hardware-validation\"]"))
        XCTAssertTrue(agentTemplate.contains("labels: [\"agent-cooling\"]"))
    }

    private func checkStatus(named name: String, in checks: [[String: Any]]?) -> String? {
        checks?.first { $0["name"] as? String == name }?["status"] as? String
    }
}

private struct GitHubMetadataProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    func json() throws -> [String: Any] {
        let data = Data(stdout.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class GitHubMetadataHarness {
    struct Label {
        var name: String
        var color: String
        var description: String
    }

    let repositoryRoot: URL
    let rootURL: URL
    let metadataURL: URL
    let topicsURL: URL
    let labelsURL: URL
    let requiredTopics: [String]
    let labels: [Label]

    init() throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-github-metadata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        metadataURL = repositoryRoot.appendingPathComponent(".github/repo-metadata.json")
        topicsURL = rootURL.appendingPathComponent("topics.json")
        labelsURL = rootURL.appendingPathComponent("labels.json")

        let data = try Data(contentsOf: metadataURL)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        requiredTopics = try XCTUnwrap(metadata["requiredTopics"] as? [String])
        let labelObjects = try XCTUnwrap(metadata["labels"] as? [[String: Any]])
        labels = try labelObjects.map { label in
            Label(
                name: try XCTUnwrap(label["name"] as? String),
                color: try XCTUnwrap(label["color"] as? String),
                description: try XCTUnwrap(label["description"] as? String)
            )
        }

        try writeTopicFixture()
        try writeLabelFixture()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runChecker(json: Bool = false) throws -> GitHubMetadataProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/check-github-metadata.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [
            script.path,
            "--metadata", metadataURL.path,
            "--topic-list-file", topicsURL.path,
            "--label-list-file", labelsURL.path
        ] + (json ? ["--json"] : [])

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return GitHubMetadataProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func writeTopicFixture(missing missingTopic: String? = nil) throws {
        let topics = requiredTopics
            .filter { $0 != missingTopic }
            .map { ["name": $0] }
        try writeJSON(["repositoryTopics": topics], to: topicsURL)
    }

    func writeLabelFixture(
        missing missingLabel: String? = nil,
        colorOverride: [String: String] = [:],
        descriptionOverride: [String: String] = [:]
    ) throws {
        let labelObjects = labels
            .filter { $0.name != missingLabel }
            .map { label in
                [
                    "name": label.name,
                    "color": colorOverride[label.name] ?? label.color,
                    "description": descriptionOverride[label.name] ?? label.description
                ]
            }
        try writeJSON(labelObjects, to: labelsURL)
    }

    func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
