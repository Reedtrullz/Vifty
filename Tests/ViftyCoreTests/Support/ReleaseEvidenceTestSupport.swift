import Foundation
import CryptoKit

// Shared fixture construction only; collector/reviewer assertions remain independent.
enum ReleaseEvidenceTestSupport {
    static func writeTaggedCandidateManifest(
        releaseSourceRepositoryURL: URL,
        releaseSourceCommit: inout String,
        version: String,
        build: Int,
        sha: String?
    ) throws -> String {
        let manifestURL = releaseSourceRepositoryURL
            .appendingPathComponent(".github/release-manifest.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let priorSourceCommit = releaseSourceCommit
        let candidateSHA: Any = sha ?? NSNull()
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
                "developerTeamID": "TEAMID1234",
                "signedTagsRequiredFromVersion": "1.0.0"
            ],
            "historicalReleases": [],
            "publishedRelease": [
                "version": "0.0.1",
                "build": 1,
                "tag": "v0.0.1",
                "sourceCommit": priorSourceCommit,
                "sourceCIRunID": 1,
                "releaseWorkflowRunID": 1,
                "artifact": "Vifty-v0.0.1.zip",
                "checksumAsset": "Vifty-v0.0.1.zip.sha256",
                "artifactSummary": "Vifty-v0.0.1-artifact-summary.json",
                "releaseChecklist": "Vifty-v0.0.1-release-checklist.md",
                "sha256": String(repeating: "0", count: 64),
                "artifactTrust": "passed",
                "signingTrust": "developer-id-notarized",
                "tagTrust": "historical-unsigned",
                "installedReleaseReview": "pending",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ],
            "candidate": [
                "version": version,
                "build": build,
                "tag": "v\(version)",
                "artifact": "Vifty-v\(version).zip",
                "checksumAsset": "Vifty-v\(version).zip.sha256",
                "artifactSummary": "Vifty-v\(version)-artifact-summary.json",
                "releaseChecklist": "Vifty-v\(version)-release-checklist.md",
                "sha256": candidateSHA,
                "artifactTrust": "pending",
                "signingTrust": "pending",
                "tagTrust": "signed-required",
                "installedReleaseReview": "pending",
                "manualCompatibility": "pending",
                "manualCompatibilityScope": NSNull()
            ]
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL)
        _ = try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", releaseSourceRepositoryURL.path, "add", ".github/release-manifest.json"]
        )
        _ = try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "-C", releaseSourceRepositoryURL.path,
                "-c", "user.name=Vifty Tests",
                "-c", "user.email=vifty-tests@example.invalid",
                "commit", "--quiet", "-m", "tagged release manifest"
            ]
        )
        releaseSourceCommit = try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", releaseSourceRepositoryURL.path, "rev-parse", "HEAD"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try Self.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["-C", releaseSourceRepositoryURL.path, "tag", "-f", "v\(version)", releaseSourceCommit]
        )
        return SHA256.hash(data: try Data(contentsOf: manifestURL)).map { String(format: "%02x", $0) }.joined()
    }

    static func writeAuthoritativeReleaseManifest(
        releaseManifestURL: URL,
        releaseSourceCommit: String,
        caskVersion: String,
        releaseVersion: String,
        releaseEntryKind: String,
        selectedSHA: String,
        selectedBuild: Int,
        candidateHasManifestSHA: Bool
    ) throws {
        func release(
            version: String,
            build: Int,
            sha: Any,
            sourceCommit: Any,
            tagTrust: String
        ) -> [String: Any] {
            [
                "version": version,
                "build": build,
                "tag": "v\(version)",
                "sourceCommit": sourceCommit,
                "artifact": "Vifty-v\(version).zip",
                "checksumAsset": "Vifty-v\(version).zip.sha256",
                "artifactSummary": "Vifty-v\(version)-artifact-summary.json",
                "releaseChecklist": "Vifty-v\(version)-release-checklist.md",
                "sha256": sha,
                "tagTrust": tagTrust
            ]
        }

        let selectedPublished = releaseEntryKind == "published"
        let publishedVersion = selectedPublished ? releaseVersion : caskVersion
        let publishedBuild = selectedPublished ? selectedBuild : selectedBuild + 1
        let publishedSHA = selectedPublished ? selectedSHA : String(repeating: "b", count: 64)
        let published = release(
            version: publishedVersion,
            build: publishedBuild,
            sha: publishedSHA,
            sourceCommit: releaseSourceCommit,
            tagTrust: "signed-verified"
        )
        let historical: [[String: Any]] = releaseEntryKind == "historical"
            ? [release(
                version: releaseVersion,
                build: selectedBuild,
                sha: selectedSHA,
                sourceCommit: releaseSourceCommit,
                tagTrust: "signed-verified"
            )]
            : []
        let candidate: Any
        if releaseEntryKind == "candidate" {
            let candidateSHA: Any
            if candidateHasManifestSHA {
                candidateSHA = selectedSHA
            } else {
                candidateSHA = NSNull()
            }
            candidate = release(
                version: releaseVersion,
                build: selectedBuild,
                sha: candidateSHA,
                sourceCommit: NSNull(),
                tagTrust: "signed-required"
            )
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
                "developerTeamID": "TEAMID1234",
                "signedTagsRequiredFromVersion": "1.0.0"
            ],
            "historicalReleases": historical,
            "publishedRelease": published,
            "candidate": candidate
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: releaseManifestURL)
    }

    @discardableResult
    static func run(executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
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
                domain: "ReleaseEvidenceTestSupport",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        return output
    }
}
