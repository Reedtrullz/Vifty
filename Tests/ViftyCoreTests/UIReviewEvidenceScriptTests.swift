import CryptoKit
import Darwin
import Foundation
import XCTest
import zlib
import ViftyBuildProvenance
@testable import ViftyAXEvidenceCore

final class UIReviewEvidenceScriptTests: XCTestCase {
    func testCommittedManifestIsAnEmptyPendingTemplateAndRuntimeEvidenceStaysLocal() throws {
        let manifestURL = repositoryRoot.appendingPathComponent("docs/ui-review/evidence-manifest.json")
        let manifest = try readJSON(manifestURL)
        let fixtureRows = try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]])
        let visualRows = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let accessibilityRows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        let release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        let human = try XCTUnwrap(manifest["humanAttestations"] as? [String: Any])

        XCTAssertEqual(manifest["status"] as? String, "pending")
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertEqual(fixtureRows.count, 9)
        XCTAssertEqual(visualRows.count, 28)
        XCTAssertEqual(accessibilityRows.count, 13)
        for row in fixtureRows + visualRows + accessibilityRows {
            XCTAssertEqual(row["status"] as? String, "pending")
            XCTAssertTrue(row["captureID"] is NSNull)
        }
        XCTAssertEqual(release["status"] as? String, "pending")
        XCTAssertTrue(release["sha256"] is NSNull)
        for name in ["visual", "voiceOver"] {
            let binding = try XCTUnwrap(human[name] as? [String: Any])
            XCTAssertEqual(binding["status"] as? String, "pending")
            XCTAssertTrue(binding["sha256"] is NSNull)
        }

        let serialized = String(decoding: try Data(contentsOf: manifestURL), as: UTF8.self)
        XCTAssertFalse(serialized.contains("/Users/"), serialized)
        XCTAssertFalse(serialized.contains("/private/"), serialized)
        XCTAssertFalse(serialized.contains("/var/folders/"), serialized)

        let gitignore = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        let makefile = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"),
            encoding: .utf8
        )
        XCTAssertTrue(gitignore.contains("docs/ui-review/evidence-manifest.local.json"))
        XCTAssertTrue(makefile.contains("UI_REVIEW_MANIFEST ?= $(CURDIR)/docs/ui-review/evidence-manifest.local.json"))
        XCTAssertTrue(makefile.contains("UI_REVIEW_REPOSITORY_ROOT ?= $(CURDIR)"))

        let ignored = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["check-ignore", "-q", "docs/ui-review/evidence-manifest.local.json"],
            currentDirectory: repositoryRoot
        )
        XCTAssertEqual(ignored.status, 0, ignored.output)
        let trackedEvidence = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["ls-files", ".build/ui-review-evidence"],
            currentDirectory: repositoryRoot
        )
        XCTAssertEqual(trackedEvidence.status, 0, trackedEvidence.output)
        XCTAssertTrue(trackedEvidence.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testAutomatedCheckpointWriterEmitsDeterministicPortableExactLedgerWithoutHumanAttestations() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let collector = fixture.collectorExecutable

        var manifest = fixture.manifest
        manifest["humanAttestations"] = [
            "visual": [
                "status": "passed",
                "artifact": "attestations/visual.json",
                "sha256": String(repeating: "a", count: 64),
                "reviewer": "must-not-carry-forward"
            ],
            "voiceOver": [
                "status": "passed",
                "artifact": "attestations/voiceover.json",
                "sha256": String(repeating: "b", count: 64),
                "reviewer": "must-not-carry-forward"
            ]
        ]
        manifest["fixtureReports"] = Array(
            try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]]).reversed()
        )
        manifest["visualCells"] = Array(
            try XCTUnwrap(manifest["visualCells"] as? [[String: Any]]).reversed()
        )
        manifest["accessibilityChecks"] = Array(
            try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]]).reversed()
        )
        try writeJSON(manifest, to: fixture.manifestURL)

        let visualRows = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let heroRow = try XCTUnwrap(visualRows.first { $0["id"] as? String == "main-1180x820-light" })
        let heroCaptureID = try XCTUnwrap(heroRow["captureID"] as? String)
        let ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        let heroCapture = try XCTUnwrap(ledger[heroCaptureID] as? [String: Any])
        let heroScreenshot = try XCTUnwrap(heroCapture["screenshot"] as? [String: Any])
        let heroURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(heroScreenshot["artifact"] as? String)
        )
        let checkpointRepository = try prepareCheckpointRepository(
            fixture: fixture,
            heroSource: heroURL
        )
        let output = checkpointRepository.output
        let sourceCommit = checkpointRepository.sourceCommit

        let first = try runCheckpointWriter(
            fixture: fixture,
            collector: collector,
            sourceCommit: sourceCommit,
            output: output,
            hero: checkpointRepository.hero
        )
        XCTAssertEqual(first.status, 0, first.output)
        let firstBytes = try Data(contentsOf: output)
        let checkpoint = try readJSON(output)

        XCTAssertEqual(checkpoint["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            checkpoint["schemaID"] as? String,
            "https://vifty.app/schemas/ui-review-automated-checkpoint-v1.schema.json"
        )
        XCTAssertEqual(checkpoint["status"] as? String, "automated-passed")
        let source = try XCTUnwrap(checkpoint["source"] as? [String: Any])
        XCTAssertEqual(source["commit"] as? String, sourceCommit)
        XCTAssertEqual(source["tree"] as? String, checkpointRepository.sourceTree)
        XCTAssertEqual(source["manifestSHA256"] as? String, try sha256(fixture.manifestURL))
        let products = try XCTUnwrap(checkpoint["products"] as? [String: Any])
        let transactionID = try XCTUnwrap(products["buildTransactionID"] as? String)
        XCTAssertEqual(transactionID, String(repeating: "d", count: 64))
        XCTAssertEqual(products["debugFixtureSHA256"] as? String, try sha256(fixture.debugExecutable))
        XCTAssertEqual(products["releaseExclusionSHA256"] as? String, try sha256(fixture.releaseBinary))
        XCTAssertEqual(products["axCollectorSHA256"] as? String, try sha256(collector))
        let debugProvenance = try XCTUnwrap(
            products["debugFixtureProvenance"] as? [String: Any]
        )
        let releaseProvenance = try XCTUnwrap(
            products["releaseExclusionProvenance"] as? [String: Any]
        )
        let collectorProvenance = try XCTUnwrap(
            products["axCollectorProvenance"] as? [String: Any]
        )
        for (provenance, role, configuration) in [
            (debugProvenance, "debug-fixture-app", "debug"),
            (releaseProvenance, "release-exclusion", "release"),
            (collectorProvenance, "ax-collector", "debug")
        ] {
            XCTAssertEqual(provenance["sourceCommit"] as? String, sourceCommit)
            XCTAssertEqual(provenance["sourceTree"] as? String, checkpointRepository.sourceTree)
            XCTAssertEqual(provenance["buildTransactionID"] as? String, transactionID)
            XCTAssertEqual(provenance["productRole"] as? String, role)
            XCTAssertEqual(provenance["configuration"] as? String, configuration)
        }
        XCTAssertEqual(
            products["debugFixtureProvenanceSHA256"] as? String,
            try canonicalJSONSHA256(debugProvenance)
        )
        XCTAssertEqual(
            products["releaseExclusionProvenanceSHA256"] as? String,
            try canonicalJSONSHA256(releaseProvenance)
        )
        XCTAssertEqual(
            products["axCollectorProvenanceSHA256"] as? String,
            try canonicalJSONSHA256(collectorProvenance)
        )
        let counts = try XCTUnwrap(checkpoint["counts"] as? [String: Any])
        XCTAssertEqual(counts["fixture"] as? Int, 9)
        XCTAssertEqual(counts["visual"] as? Int, 28)
        XCTAssertEqual(counts["accessibility"] as? Int, 13)
        XCTAssertEqual(counts["total"] as? Int, 50)

        let rows = try XCTUnwrap(checkpoint["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 50)
        XCTAssertEqual(Set(rows.compactMap { $0["captureIDHash"] as? String }).count, 50)
        XCTAssertTrue(rows.allSatisfy { $0["captureID"] == nil })
        XCTAssertEqual(rows.filter { $0["kind"] as? String == "fixture" }.count, 9)
        XCTAssertEqual(rows.filter { $0["kind"] as? String == "visual" }.count, 28)
        XCTAssertEqual(rows.filter { $0["kind"] as? String == "accessibility" }.count, 13)
        XCTAssertTrue(rows.allSatisfy { ($0["requestSHA256"] as? String)?.count == 64 })
        XCTAssertTrue(rows.allSatisfy { ($0["fixtureReportSHA256"] as? String)?.count == 64 })
        XCTAssertTrue(rows.allSatisfy {
            ($0["debugFixtureSHA256"] as? String) ==
                (products["debugFixtureSHA256"] as? String) &&
                ($0["debugBuildProvenanceSHA256"] as? String) ==
                (products["debugFixtureProvenanceSHA256"] as? String)
        })
        let expectedOrder = expectedFixtureRows().compactMap { $0["state"] as? String } +
            expectedVisualRows().compactMap { $0["id"] as? String } +
            expectedAccessibilityRows().compactMap { $0["id"] as? String }
        XCTAssertEqual(rows.compactMap { $0["id"] as? String }, expectedOrder)
        XCTAssertTrue(
            rows.filter { $0["kind"] as? String == "visual" }.allSatisfy {
                ($0["screenshotSHA256"] as? String)?.count == 64 &&
                    ($0["canonicalPixelSHA256"] as? String)?.count == 64
            }
        )
        XCTAssertTrue(
            rows.filter { $0["kind"] as? String == "accessibility" }.allSatisfy {
                ($0["accessibilityRawSHA256"] as? String)?.count == 64 &&
                    ($0["accessibilitySealedSHA256"] as? String)?.count == 64 &&
                    ($0["axCollectorSHA256"] as? String) ==
                    (products["axCollectorSHA256"] as? String) &&
                    ($0["axCollectorBuildProvenanceSHA256"] as? String) ==
                    (products["axCollectorProvenanceSHA256"] as? String)
            }
        )

        let safety = try XCTUnwrap(checkpoint["safetyAggregate"] as? [String: Any])
        XCTAssertEqual(safety["finalReportsPassed"] as? Int, 50)
        XCTAssertEqual(safety["modelStartSkipped"] as? Int, 50)
        XCTAssertEqual(safety["attemptedHardwareCommands"] as? Int, 0)
        XCTAssertEqual(safety["attemptedExternalMutations"] as? Int, 0)
        XCTAssertEqual(safety["realControlPathConstructions"] as? Int, 0)

        let hero = try XCTUnwrap(checkpoint["hero"] as? [String: Any])
        XCTAssertEqual(hero["rowID"] as? String, "main-1180x820-light")
        XCTAssertEqual(hero["captureIDHash"] as? String, sha256String(heroCaptureID))
        XCTAssertNil(hero["captureID"])
        XCTAssertEqual(hero["screenshotSHA256"] as? String, heroScreenshot["sha256"] as? String)
        XCTAssertEqual(
            hero["canonicalPixelSHA256"] as? String,
            heroScreenshot["canonicalPixelSHA256"] as? String
        )
        XCTAssertEqual(hero["heroArtifactSHA256"] as? String, try sha256(checkpointRepository.hero))

        let review = try XCTUnwrap(checkpoint["reviewGates"] as? [String: Any])
        let visual = try XCTUnwrap(review["visual"] as? [String: Any])
        let voiceOver = try XCTUnwrap(review["voiceOver"] as? [String: Any])
        XCTAssertEqual(visual["status"] as? String, "pending")
        XCTAssertEqual(visual["priorEvidence"] as? String, "superseded")
        XCTAssertEqual(visual["claims"] as? [String], [])
        XCTAssertEqual(voiceOver["status"] as? String, "pending")
        XCTAssertEqual(voiceOver["decision"] as? String, "skipped-by-owner")
        XCTAssertEqual(voiceOver["claims"] as? [String], [])
        XCTAssertEqual(
            checkpoint["nonClaims"] as? [String],
            [
                "full-evidence-bundle-not-committed",
                "hardware-compatibility-not-claimed",
                "release-readiness-not-claimed"
            ]
        )

        let checkpointText = String(decoding: firstBytes, as: UTF8.self)
        for forbidden in [fixture.root.path, "/Users/", "/private/", "/var/folders/", "processIdentifier", "windowNumber", "reviewer", "humanAttestations"] {
            XCTAssertFalse(checkpointText.contains(forbidden), forbidden)
        }
        XCTAssertFalse(checkpointText.contains(heroCaptureID), checkpointText)

        let second = try runCheckpointWriter(
            fixture: fixture,
            collector: collector,
            sourceCommit: sourceCommit,
            output: output,
            hero: checkpointRepository.hero
        )
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertEqual(try Data(contentsOf: output), firstBytes)

        var verifierRejectedManifest = manifest
        var rejectedFixtureRows = try XCTUnwrap(
            verifierRejectedManifest["fixtureReports"] as? [[String: Any]]
        )
        rejectedFixtureRows[0]["status"] = "pending"
        verifierRejectedManifest["fixtureReports"] = rejectedFixtureRows
        try writeJSON(verifierRejectedManifest, to: fixture.manifestURL)

        let verifierRejected = try runCheckpointWriter(
            fixture: fixture,
            collector: collector,
            sourceCommit: sourceCommit,
            output: output,
            hero: checkpointRepository.hero
        )
        XCTAssertNotEqual(verifierRejected.status, 0, verifierRejected.output)
        XCTAssertTrue(
            verifierRejected.output.contains("automated UI verification failed"),
            verifierRejected.output
        )
        XCTAssertEqual(try Data(contentsOf: output), firstBytes)
    }

    func testCheckpointWriterRequiresExactCleanHEADCanonicalTrackedHeroAndStrictSchema() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeJSON(fixture.manifest, to: fixture.manifestURL)
        let visualRows = try XCTUnwrap(fixture.manifest["visualCells"] as? [[String: Any]])
        let heroRow = try XCTUnwrap(visualRows.first { $0["id"] as? String == "main-1180x820-light" })
        let captureID = try XCTUnwrap(heroRow["captureID"] as? String)
        let ledger = try XCTUnwrap(fixture.manifest["captureLedger"] as? [String: Any])
        let capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let heroSource = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        var repository = try prepareCheckpointRepository(fixture: fixture, heroSource: heroSource)

        let baseline = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertEqual(baseline.status, 0, baseline.output)
        let baselineBytes = try Data(contentsOf: repository.output)

        let wrongSource = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: String(repeating: "a", count: 40),
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(wrongSource.status, 0, wrongSource.output)
        XCTAssertTrue(wrongSource.output.contains("does not match repository HEAD"), wrongSource.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)

        let gitignore = fixture.root.appendingPathComponent(".gitignore")
        let originalGitignore = try Data(contentsOf: gitignore)
        var dirtyGitignore = originalGitignore
        dirtyGitignore.append(Data("dirty\n".utf8))
        try dirtyGitignore.write(to: gitignore)
        let dirtyTracked = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(dirtyTracked.status, 0, dirtyTracked.output)
        XCTAssertTrue(dirtyTracked.output.contains("source-affecting worktree changes"), dirtyTracked.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)
        try originalGitignore.write(to: gitignore)

        let unexpectedSource = fixture.root.appendingPathComponent("Sources/Unexpected.swift")
        try FileManager.default.createDirectory(
            at: unexpectedSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("let unexpected = true\n".utf8).write(to: unexpectedSource)
        let dirtyUntracked = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(dirtyUntracked.status, 0, dirtyUntracked.output)
        XCTAssertTrue(dirtyUntracked.output.contains("Sources/Unexpected.swift"), dirtyUntracked.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)
        try FileManager.default.removeItem(at: unexpectedSource.deletingLastPathComponent())

        let omittedHero = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: nil
        )
        XCTAssertNotEqual(omittedHero.status, 0, omittedHero.output)
        XCTAssertTrue(omittedHero.output.contains("--hero"), omittedHero.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)

        let wrongHero = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: heroSource
        )
        XCTAssertNotEqual(wrongHero.status, 0, wrongHero.output)
        XCTAssertTrue(wrongHero.output.contains("canonical tracked hero"), wrongHero.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)

        let originalHero = try Data(contentsOf: repository.hero)
        try Data("not the bound PNG\n".utf8).write(to: repository.hero)
        let mismatchedHero = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(mismatchedHero.status, 0, mismatchedHero.output)
        XCTAssertTrue(mismatchedHero.output.contains("does not match"), mismatchedHero.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)
        try originalHero.write(to: repository.hero)

        let wrongOutput = fixture.root.appendingPathComponent("automated-checkpoint.json")
        let noncanonicalOutput = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: wrongOutput,
            hero: repository.hero
        )
        XCTAssertNotEqual(noncanonicalOutput.status, 0, noncanonicalOutput.output)
        XCTAssertTrue(noncanonicalOutput.output.contains("canonical checkpoint output"), noncanonicalOutput.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wrongOutput.path))
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)

        let schemaURL = fixture.root.appendingPathComponent(
            "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
        )
        var schema = try readJSON(schemaURL)
        var properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        properties["status"] = ["const": "schema-deliberately-impossible"]
        schema["properties"] = properties
        try writeJSON(schema, to: schemaURL)
        for arguments in [
            ["add", "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"],
            ["commit", "-q", "-m", "make checkpoint schema impossible"]
        ] {
            let result = try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
                currentDirectory: fixture.root
            )
            XCTAssertEqual(result.status, 0, result.output)
        }
        let newHead = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: fixture.root
        )
        repository.sourceCommit = newHead.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTree = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rev-parse", "HEAD^{tree}"],
            currentDirectory: fixture.root
        )
        XCTAssertEqual(newTree.status, 0, newTree.output)
        repository.sourceTree = newTree.output.trimmingCharacters(in: .whitespacesAndNewlines)

        let staleProductsRejected = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(staleProductsRejected.status, 0, staleProductsRejected.output)
        XCTAssertTrue(
            staleProductsRejected.output.contains("product build provenance is invalid") &&
                staleProductsRejected.output.contains("source commit"),
            staleProductsRejected.output
        )
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)

        try rebindFixtureProducts(
            fixture: fixture,
            sourceCommit: repository.sourceCommit,
            sourceTree: repository.sourceTree
        )
        let schemaRejected = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertNotEqual(schemaRejected.status, 0, schemaRejected.output)
        XCTAssertTrue(schemaRejected.output.contains("schema validation failed"), schemaRejected.output)
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)
    }

    func testCheckpointWriterRejectsPostVerifierManifestTOCTOUAndPreservesOutput() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeJSON(fixture.manifest, to: fixture.manifestURL)
        let visualRows = try XCTUnwrap(fixture.manifest["visualCells"] as? [[String: Any]])
        let heroRow = try XCTUnwrap(visualRows.first { $0["id"] as? String == "main-1180x820-light" })
        let captureID = try XCTUnwrap(heroRow["captureID"] as? String)
        let ledger = try XCTUnwrap(fixture.manifest["captureLedger"] as? [String: Any])
        let capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let heroSource = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        let repository = try prepareCheckpointRepository(fixture: fixture, heroSource: heroSource)
        let baseline = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        XCTAssertEqual(baseline.status, 0, baseline.output)
        let baselineBytes = try Data(contentsOf: repository.output)

        let mutator = Process()
        mutator.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        mutator.arguments = [
            "-rjson",
            "-e",
            ##"sleep 0.15; path = ARGV.fetch(0); 400.times do |index|; document = JSON.parse(File.binread(path)); document["toctouNonce"] = index.even? ? "a" : "b"; temporary = "#{path}.mutator"; File.binwrite(temporary, JSON.generate(document)); File.rename(temporary, path); sleep 0.005; end"##,
            fixture.manifestURL.path
        ]
        mutator.standardOutput = FileHandle.nullDevice
        mutator.standardError = FileHandle.nullDevice
        try mutator.run()
        let rejected = try runCheckpointWriter(
            fixture: fixture,
            collector: fixture.collectorExecutable,
            sourceCommit: repository.sourceCommit,
            output: repository.output,
            hero: repository.hero
        )
        if mutator.isRunning {
            mutator.terminate()
        }
        mutator.waitUntilExit()

        XCTAssertNotEqual(rejected.status, 0, rejected.output)
        XCTAssertTrue(
            rejected.output.contains("manifest changed after automated verification") ||
                rejected.output.contains("manifest changed before checkpoint publication"),
            rejected.output
        )
        XCTAssertEqual(try Data(contentsOf: repository.output), baselineBytes)
    }

    func testAutomatedCheckpointWriterAndSchemaRejectPrivateOrAbsoluteStrings() throws {
        let schema = try readJSON(
            repositoryRoot.appendingPathComponent(
                "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
            )
        )
        XCTAssertEqual(
            schema["$id"] as? String,
            "https://vifty.app/schemas/ui-review-automated-checkpoint-v1.schema.json"
        )
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let rows = try XCTUnwrap(properties["rows"] as? [String: Any])
        XCTAssertEqual(rows["minItems"] as? Int, 50)
        XCTAssertEqual(rows["maxItems"] as? Int, 50)
        let schemaText = String(
            decoding: try Data(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
                )
            ),
            as: UTF8.self
        )
        XCTAssertFalse(schemaText.contains("executablePath"))
        XCTAssertFalse(schemaText.contains("artifactPath"))
        XCTAssertFalse(schemaText.contains("\"captureID\":"))
        XCTAssertTrue(schemaText.contains("\"captureIDHash\""))

        let script = repositoryRoot.appendingPathComponent("scripts/write-ui-review-checkpoint.rb")
        for leaked in ["/tmp/leak", "/Users/reidar/leak", "prefix /private/leak", "prefix /var/folders/leak"] {
            let result = try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/ruby"),
                arguments: [
                    "-r", script.path,
                    "-e", "ViftyUIReview::CheckpointWriter.ensure_portable!({\"value\" => ARGV.fetch(0)})",
                    leaked
                ],
                currentDirectory: repositoryRoot
            )
            XCTAssertNotEqual(result.status, 0, leaked)
            XCTAssertTrue(result.output.contains("non-portable string"), result.output)
        }

        let leakedKey = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/ruby"),
            arguments: [
                "-r", script.path,
                "-e", "ViftyUIReview::CheckpointWriter.ensure_portable!({ARGV.fetch(0) => \"safe\"})",
                "/Users/reidar/private-key"
            ],
            currentDirectory: repositoryRoot
        )
        XCTAssertNotEqual(leakedKey.status, 0, leakedKey.output)
        XCTAssertTrue(leakedKey.output.contains("non-portable string"), leakedKey.output)
    }

    func testCommittedPendingManifestIsRejectedAsEvidence() throws {
        let result = try runVerifier(
            manifest: repositoryRoot.appendingPathComponent("docs/ui-review/evidence-manifest.json"),
            evidenceDirectory: repositoryRoot.appendingPathComponent(".build/ui-review-missing-test-evidence"),
            releaseBinary: repositoryRoot.appendingPathComponent(".build/ui-review-missing-release"),
            debugExecutable: repositoryRoot.appendingPathComponent(".build/ui-review-missing-debug")
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("evidence directory is missing"), result.output)
    }

    func testExplicitOrchestrationAndVerificationModesAreAdvertised() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/run-ui-review-fixture.sh"),
            encoding: .utf8
        )

        for mode in ["--capture", "--collect-ax", "--seal", "--verify-automated", "--verify-matrix"] {
            XCTAssertTrue(script.contains(mode), mode)
        }
        XCTAssertTrue(script.contains("--debug-executable"))
        XCTAssertTrue(script.contains("--manifest"))
        XCTAssertTrue(script.contains("--evidence-dir"))
        XCTAssertTrue(script.contains("--release-binary"))
        XCTAssertFalse(script.contains("/usr/bin/open"))
        XCTAssertFalse(script.contains("mode=\"launch\""))
    }

    func testCaptureRejectsLedgerBoundToDifferentProductTransactionBeforeArtifacts() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = try readJSON(fixture.manifest)
        var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        release["buildProvenance"] = try jsonObject(
            TestBuildProvenance.identity(
                role: "release-exclusion",
                transactionID: String(repeating: "e", count: 64)
            )
        )
        manifest["releaseExclusion"] = release
        try writeJSON(manifest, to: fixture.manifest)

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("PRODUCT_BINDING_MISMATCH"), result.output)
        XCTAssertTrue(
            try FileManager.default.subpathsOfDirectory(atPath: fixture.evidence.path).isEmpty,
            result.output
        )
    }

    func testCaptureModeRetainsDirectExecutablePIDAndCompletesBoundedLifecycle() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "visual",
            "--row-id", "main-1180x820-light",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertEqual(result.status, 0, result.output)
        let document = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
        let capture = try XCTUnwrap(document)
        XCTAssertEqual(capture["mode"] as? String, "capture")
        XCTAssertEqual(capture["status"] as? String, "passed")
        XCTAssertEqual(capture["completionSignalSent"] as? Bool, true)
        let processIdentifier = try XCTUnwrap(capture["processIdentifier"] as? Int)
        XCTAssertGreaterThan(processIdentifier, 0)
        let artifact = try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        let report = try readJSON(fixture.evidence.appendingPathComponent(artifact))
        XCTAssertEqual(report["phase"] as? String, "final")
        let identity = try XCTUnwrap(report["runtimeIdentity"] as? [String: Any])
        XCTAssertEqual(identity["processIdentifier"] as? Int, processIdentifier)
        XCTAssertEqual(identity["executablePath"] as? String, try canonicalFilesystemPath(fixture.debugExecutable))
    }

    func testCaptureModePassesPersistenceIsolationArgumentsToFixtureProcess() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertEqual(result.status, 0, result.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
        )
        let reportArtifact = try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        let report = try readJSON(fixture.evidence.appendingPathComponent(reportArtifact))
        let launchArguments = try XCTUnwrap(report["launchArguments"] as? [String])
        XCTAssertEqual(Array(launchArguments.prefix(2)), ["-ApplePersistenceIgnoreState", "YES"])
        XCTAssertEqual(
            launchArguments.filter { $0 == "-ApplePersistenceIgnoreState" }.count,
            1,
            launchArguments.joined(separator: "\n")
        )
        let deadlineIndex = try XCTUnwrap(
            launchArguments.firstIndex(of: "--ui-review-readiness-deadline-uptime")
        )
        let deadlineValue = try XCTUnwrap(
            Double(launchArguments[deadlineIndex + 1])
        )
        XCTAssertTrue(deadlineValue.isFinite)
        XCTAssertGreaterThan(deadlineValue, 0)
    }

    func testCaptureModePreservesStructuredReadyTimeoutAndCleansUpChild() throws {
        let fixture = try orchestrationFixture(mode: .readyTimeout)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "0.5"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("READY_TIMEOUT"), result.output)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
        )
        let processIdentifier = try XCTUnwrap(document["processIdentifier"] as? Int)
        errno = 0
        XCTAssertEqual(Darwin.kill(pid_t(processIdentifier), 0), -1, result.output)
        XCTAssertEqual(errno, ESRCH, result.output)
        let failureArtifacts = try FileManager.default.subpathsOfDirectory(atPath: fixture.evidence.path)
        XCTAssertTrue(failureArtifacts.contains { $0.hasSuffix("orchestration.json") })
        XCTAssertTrue(failureArtifacts.contains { $0.hasSuffix("process.log") })
        XCTAssertFalse(
            failureArtifacts.contains { $0.contains("window-capture-00000000-0000-0000-0000-000000000000.png") },
            failureArtifacts.joined(separator: "\n")
        )
    }

    func testCaptureModeReportsExitedFixtureInsteadOfReadyTimeoutForZombieChild() throws {
        let fixture = try orchestrationFixture(mode: .immediateExit)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "0.5"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("PROCESS_EXITED"), result.output)
        XCTAssertFalse(result.output.contains("READY_TIMEOUT"), result.output)
    }

    func testTransientWindowCaptureCleanupRejectsSymlinkWithoutDeletingItsTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-ui-review-cleanup-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let evidence = root.appendingPathComponent("evidence", isDirectory: true)
        let fixture = evidence.appendingPathComponent("captures/test/fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("outside.png")
        try Data("must remain".utf8).write(to: target)
        let link = fixture.appendingPathComponent(
            "window-capture-00000000-0000-0000-0000-000000000000.png"
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-r", repositoryRoot.appendingPathComponent("scripts/lib/ui_review_orchestrator.rb").path,
            "-e",
            "begin; ViftyUIReview::Orchestrator.cleanup_transient_window_captures!(ARGV.fetch(0), ARGV.fetch(1)); rescue ViftyUIReview::OrchestrationError => error; STDOUT.write(error.code); exit 75; end",
            try canonicalFilesystemPath(fixture),
            try canonicalFilesystemPath(evidence)
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 75, output)
        XCTAssertEqual(output, "UNSAFE_PATH")
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try Data(contentsOf: target), Data("must remain".utf8))
    }

    func testCanonicalIncreaseContrastRequestAlsoRequiresReducedTransparency() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-r", repositoryRoot.appendingPathComponent("scripts/lib/ui_review_contract.rb").path,
            "-r", "json",
            "-e",
            "STDOUT.write(JSON.generate(ViftyUIReview.expected_visual_requests.fetch('main-increase-contrast')))"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(request["contrast"] as? String, "increased")
        XCTAssertEqual(request["transparency"] as? String, "reduced")
    }

    func testCaptureModeReportsFixtureFailureWithoutMislabelingItAsATimeout() throws {
        let fixture = try orchestrationFixture(mode: .reportedFailure)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FIXTURE_REPORTED_FAILURE"), result.output)
        XCTAssertTrue(result.output.contains("synthetic observation failure"), result.output)
        XCTAssertFalse(result.output.contains("READY_TIMEOUT"), result.output)
    }

    func testCaptureTimeoutKillsSurvivingProcessGroupChildBeforeArtifactCleanup() throws {
        let fixture = try orchestrationFixture(mode: .readyTimeoutWithSurvivingChild)
        let childPIDURL = fixture.debugExecutable.deletingLastPathComponent()
            .appendingPathComponent("child-pid")
        var childPID: pid_t?
        defer {
            if let childPID {
                _ = Darwin.kill(childPID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: fixture.root)
        }

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "fixture",
            "--row-id", "healthy-auto",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "0.5"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("READY_TIMEOUT"), result.output)
        childPID = pid_t(try XCTUnwrap(Int32(
            String(decoding: Data(contentsOf: childPIDURL), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )))
        Thread.sleep(forTimeInterval: 0.4)
        errno = 0
        XCTAssertEqual(Darwin.kill(try XCTUnwrap(childPID), 0), -1, result.output)
        XCTAssertEqual(errno, ESRCH, result.output)
        let artifacts = try FileManager.default.subpathsOfDirectory(atPath: fixture.evidence.path)
        XCTAssertFalse(
            artifacts.contains { $0.contains("window-capture-11111111-1111-1111-1111-111111111111.png") },
            artifacts.joined(separator: "\n")
        )
    }

    func testCaptureRejectsSymlinkedCapturesDirectoryBeforeLaunchOrWrite() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside-captures", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.evidence.appendingPathComponent("captures"),
            withDestinationURL: outside
        )

        let result = try runOrchestrator([
            "--capture",
            "--row-kind", "visual",
            "--row-id", "main-1180x820-light",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("UNSAFE_PATH"), result.output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testCollectAXRejectsSymlinkedNestedAXDirectoryBeforeCollectorWrite() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)
        let completionArtifact = try XCTUnwrap(capture["completionArtifact"] as? String)
        XCTAssertTrue(
            completionArtifact.hasSuffix("/fixture/completion.signal"),
            completionArtifact
        )
        let outside = fixture.root.appendingPathComponent("outside-ax", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let axDirectory = fixture.evidence
            .appendingPathComponent("captures")
            .appendingPathComponent(captureID)
            .appendingPathComponent("ax")
        try FileManager.default.createSymbolicLink(at: axDirectory, withDestinationURL: outside)

        let result = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("UNSAFE_PATH"), result.output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    func testCollectAXPreservesPermissionBlockAndStillFinalizesFixture() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let captureDocument = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(captureDocument["status"] as? String, "ready")
        let captureID = try XCTUnwrap(captureDocument["captureID"] as? String)

        let collectResult = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertEqual(collectResult.status, 77, collectResult.output)
        XCTAssertTrue(collectResult.output.contains("AX_PERMISSION_MISSING"), collectResult.output)
        let collectDocument = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(collectResult.output.utf8)) as? [String: Any]
        )
        let rawArtifact = try XCTUnwrap(collectDocument["rawAccessibilityArtifact"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.evidence.appendingPathComponent(rawArtifact).path))
        let reportArtifact = try XCTUnwrap(collectDocument["fixtureReportArtifact"] as? String)
        XCTAssertEqual(
            try readJSON(fixture.evidence.appendingPathComponent(reportArtifact))["phase"] as? String,
            "final"
        )
    }

    func testDefaultAXCollectionTimeoutMatchesCollectorBound() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let captureDocument = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(captureDocument["timeoutSeconds"] as? Double, 5.0)
        XCTAssertEqual(captureDocument["fixtureHoldSeconds"] as? Double, 120.0)
        let captureID = try XCTUnwrap(captureDocument["captureID"] as? String)

        let collectResult = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path
        ])

        XCTAssertEqual(collectResult.status, 77, collectResult.output)
        XCTAssertTrue(collectResult.output.contains("AX_PERMISSION_MISSING"), collectResult.output)

        let outOfRange = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "10.1"
        ])
        XCTAssertEqual(outOfRange.status, 64, outOfRange.output)
        XCTAssertTrue(outOfRange.output.contains("between 0.1 and 10"), outOfRange.output)

        let excessiveNodes = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--maximum-nodes", "16385"
        ])
        XCTAssertEqual(excessiveNodes.status, 64, excessiveNodes.output)
        XCTAssertTrue(excessiveNodes.output.contains("maximum-nodes is outside"), excessiveNodes.output)
    }

    func testCollectAXRejectsTamperedSessionRequestChecksumBeforeCollector() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2",
            "--fixture-hold-seconds", "60"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)
        let sessionURL = fixture.evidence
            .appendingPathComponent("captures")
            .appendingPathComponent(captureID)
            .appendingPathComponent("session.json")
        var session = try readJSON(sessionURL)
        session["requestSHA256"] = String(repeating: "0", count: 64)
        try writeJSON(session, to: sessionURL)

        let rejected = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertEqual(rejected.status, 75, rejected.output)
        XCTAssertTrue(rejected.output.contains("SESSION_INTEGRITY_MISMATCH"), rejected.output)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.evidence
                .appendingPathComponent("captures/\(captureID)/ax/raw.json").path
        ))
    }

    func testCollectAXRejectsUnsafeSessionPIDsWithoutSignalingThem() throws {
        for unsafePID in [0, 1, -7] {
            let fixture = try orchestrationFixture(mode: .successful)
            defer {
                terminateHeldCaptures(in: fixture.evidence)
                try? FileManager.default.removeItem(at: fixture.root)
            }
            let collector = try permissionBlockedCollector(in: fixture.root)
            let captureResult = try runOrchestrator([
                "--capture",
                "--row-kind", "accessibility",
                "--row-id", "confirmed-owner-headline",
                "--manifest", fixture.manifest.path,
                "--evidence-dir", fixture.evidence.path,
                "--debug-executable", fixture.debugExecutable.path,
                "--timeout-seconds", "2",
                "--fixture-hold-seconds", "60"
            ])
            XCTAssertEqual(captureResult.status, 0, captureResult.output)
            let capture = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
            )
            let captureID = try XCTUnwrap(capture["captureID"] as? String)
            let sessionURL = fixture.evidence
                .appendingPathComponent("captures")
                .appendingPathComponent(captureID)
                .appendingPathComponent("session.json")
            var session = try readJSON(sessionURL)
            session["processIdentifier"] = unsafePID
            try writeJSON(session, to: sessionURL)

            let rejected = try runOrchestrator([
                "--collect-ax",
                "--capture-id", captureID,
                "--manifest", fixture.manifest.path,
                "--evidence-dir", fixture.evidence.path,
                "--debug-executable", fixture.debugExecutable.path,
                "--collector-executable", collector.path,
                "--timeout-seconds", "2"
            ])

            XCTAssertEqual(rejected.status, 75, rejected.output)
            XCTAssertTrue(rejected.output.contains("SESSION_INTEGRITY_MISMATCH"), rejected.output)
            XCTAssertTrue(rejected.output.contains("safe positive process ID"), rejected.output)
        }
    }

    func testCollectAXDoesNotSignalIdentityMismatchedProcessGroupLeader() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2",
            "--fixture-hold-seconds", "60"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)

        let sentinelReady = fixture.root.appendingPathComponent("sentinel-ready")
        let sentinel = Process()
        sentinel.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        sentinel.arguments = [
            "-e",
            "Process.setpgid(0, 0); File.write(ARGV.fetch(0), Process.pid.to_s); sleep 60",
            sentinelReady.path
        ]
        sentinel.standardOutput = FileHandle.nullDevice
        sentinel.standardError = FileHandle.nullDevice
        try sentinel.run()
        let sentinelPID = pid_t(sentinel.processIdentifier)
        defer {
            if sentinel.isRunning {
                _ = Darwin.kill(-sentinelPID, SIGKILL)
                sentinel.waitUntilExit()
            }
        }
        let readyDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: sentinelReady.path), Date() < readyDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinelReady.path))
        XCTAssertEqual(Darwin.getpgid(sentinelPID), sentinelPID)

        let sessionURL = fixture.evidence
            .appendingPathComponent("captures")
            .appendingPathComponent(captureID)
            .appendingPathComponent("session.json")
        var session = try readJSON(sessionURL)
        session["processIdentifier"] = Int(sentinelPID)
        try writeJSON(session, to: sessionURL)

        let rejected = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "2"
        ])

        XCTAssertEqual(rejected.status, 75, rejected.output)
        XCTAssertTrue(rejected.output.contains("PID_IDENTITY_MISMATCH"), rejected.output)
        errno = 0
        XCTAssertEqual(Darwin.kill(sentinelPID, 0), 0, rejected.output)
        XCTAssertEqual(errno, 0, rejected.output)
    }

    func testCollectorWallTimeoutIsIndependentFromAXMessageTimeout() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try slowSuccessfulCollector(in: fixture.root, delay: 0.5)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2",
            "--fixture-hold-seconds", "60"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)

        let collected = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "0.2",
            "--collector-wall-timeout-seconds", "2"
        ])

        XCTAssertEqual(collected.status, 0, collected.output)
        XCTAssertTrue(collected.output.contains("\"status\":\"collected\""), collected.output)
    }

    func testAXCollectorIdentityIsFrozenAtCollectionAndMustMatchAtSeal() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try slowSuccessfulCollector(in: fixture.root, delay: 0)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2",
            "--fixture-hold-seconds", "60"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)
        let collected = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "2",
            "--collector-wall-timeout-seconds", "2"
        ])
        XCTAssertEqual(collected.status, 0, collected.output)
        let collectDocument = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(collected.output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            collectDocument["collectorExecutablePath"] as? String,
            try canonicalFilesystemPath(collector)
        )
        XCTAssertEqual(collectDocument["collectorExecutableSHA256"] as? String, try sha256(collector))

        let substitute = try permissionBlockedCollector(in: fixture.root)
        let rejected = try runOrchestrator([
            "--seal",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", substitute.path,
            "--timeout-seconds", "2"
        ])
        XCTAssertEqual(rejected.status, 75, rejected.output)
        XCTAssertTrue(rejected.output.contains("AX_COLLECTOR_MISMATCH"), rejected.output)

        let manifest = try readJSON(fixture.manifest)
        let checks = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let row = try XCTUnwrap(checks.first { $0["id"] as? String == "confirmed-owner-headline" })
        XCTAssertEqual(row["status"] as? String, "pending")
        XCTAssertTrue(row["captureID"] is NSNull)
    }

    func testCollectAXReservesBothFinalReportAndProcessExitTimeouts() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer {
            terminateHeldCaptures(in: fixture.evidence)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let collector = try permissionBlockedCollector(in: fixture.root)
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "accessibility",
            "--row-id", "confirmed-owner-headline",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2",
            "--fixture-hold-seconds", "30"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let capture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(capture["captureID"] as? String)

        let rejected = try runOrchestrator([
            "--collect-ax",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--collector-executable", collector.path,
            "--timeout-seconds", "5",
            "--collector-wall-timeout-seconds", "20"
        ])

        XCTAssertEqual(rejected.status, 75, rejected.output)
        XCTAssertTrue(rejected.output.contains("FIXTURE_HOLD_INSUFFICIENT"), rejected.output)
    }

    func testSealModeWritesImmutableVisualLedgerBinding() throws {
        let fixture = try orchestrationFixture(mode: .successful)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try resetVisualRowForSealTesting(
            manifestURL: fixture.manifest,
            rowID: "main-1180x820-light"
        )
        let captureResult = try runOrchestrator([
            "--capture",
            "--row-kind", "visual",
            "--row-id", "main-1180x820-light",
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--timeout-seconds", "2"
        ])
        XCTAssertEqual(captureResult.status, 0, captureResult.output)
        let captureDocument = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
        )
        let captureID = try XCTUnwrap(captureDocument["captureID"] as? String)

        let sealResult = try runOrchestrator([
            "--seal",
            "--capture-id", captureID,
            "--manifest", fixture.manifest.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path
        ])
        XCTAssertEqual(sealResult.status, 0, sealResult.output)

        let manifest = try readJSON(fixture.manifest)
        let rows = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == "main-1180x820-light" })
        XCTAssertEqual(row["status"] as? String, "passed")
        XCTAssertEqual(row["captureID"] as? String, captureID)
        let ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        let capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        XCTAssertEqual(capture["request"] as? NSDictionary, row["request"] as? NSDictionary)
        XCTAssertEqual(capture["debugExecutablePath"] as? String, try canonicalFilesystemPath(fixture.debugExecutable))
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        XCTAssertNotNil(screenshot["canonicalPixelSHA256"] as? String)
    }

    func testSealRejectsRuntimeIdentityRecorderAndScreenshotReportDriftBeforeManifestMutation() throws {
        let mutations = ["container", "geometry", "window-id", "screenshot-path", "unknown-read", "runtime-failure"]
        for mutation in mutations {
            let fixture = try orchestrationFixture(mode: .successful)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try resetVisualRowForSealTesting(
                manifestURL: fixture.manifest,
                rowID: "main-1180x820-light"
            )
            let baselineLedger = try XCTUnwrap(
                try readJSON(fixture.manifest)["captureLedger"] as? [String: Any]
            )
            let captureResult = try runOrchestrator([
                "--capture",
                "--row-kind", "visual",
                "--row-id", "main-1180x820-light",
                "--manifest", fixture.manifest.path,
                "--evidence-dir", fixture.evidence.path,
                "--debug-executable", fixture.debugExecutable.path,
                "--timeout-seconds", "2"
            ])
            XCTAssertEqual(captureResult.status, 0, "\(mutation): \(captureResult.output)")
            let session = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(captureResult.output.utf8)) as? [String: Any]
            )
            let captureID = try XCTUnwrap(session["captureID"] as? String)
            let reportURL = fixture.evidence.appendingPathComponent(
                try XCTUnwrap(session["fixtureReportArtifact"] as? String)
            )
            var report = try readJSON(reportURL)
            if mutation == "runtime-failure" {
                report["runtimeFailure"] = "late-fixture-failure"
            } else if mutation == "unknown-read" {
                var recorder = try XCTUnwrap(report["recorder"] as? [String: Any])
                var reads = try XCTUnwrap(recorder["readOperations"] as? [String])
                reads.append("network-read")
                recorder["readOperations"] = reads
                report["recorder"] = recorder
            } else if mutation == "screenshot-path" {
                var screenshot = try XCTUnwrap(report["screenshot"] as? [String: Any])
                screenshot["artifactPath"] = "substituted.png"
                report["screenshot"] = screenshot
            } else {
                var identity = try XCTUnwrap(report["runtimeIdentity"] as? [String: Any])
                var observed = try XCTUnwrap(report["observed"] as? [String: Any])
                var window = try XCTUnwrap(observed["window"] as? [String: Any])
                switch mutation {
                case "container":
                    identity["containerKind"] = "settings-window"
                    window["containerKind"] = "settings-window"
                case "geometry":
                    identity["contentWidth"] = 1_179
                    window["contentWidth"] = 1_179
                case "window-id":
                    identity["windowIdentifier"] = "substituted-window"
                    window["windowIdentifier"] = "substituted-window"
                default:
                    XCTFail("Unhandled mutation \(mutation)")
                }
                observed["window"] = window
                report["observed"] = observed
                report["runtimeIdentity"] = identity
            }
            try writeJSON(report, to: reportURL)

            let sealed = try runOrchestrator([
                "--seal",
                "--capture-id", captureID,
                "--manifest", fixture.manifest.path,
                "--evidence-dir", fixture.evidence.path,
                "--debug-executable", fixture.debugExecutable.path
            ])
            XCTAssertNotEqual(sealed.status, 0, "\(mutation): \(sealed.output)")
            let expectedCode = switch mutation {
            case "unknown-read": "UNSAFE_FIXTURE"
            case "screenshot-path": "SCREENSHOT_REPORT_MISMATCH"
            case "runtime-failure": "REPORT_BINDING_MISMATCH"
            default: "RUNTIME_IDENTITY_MISMATCH"
            }
            XCTAssertTrue(sealed.output.contains(expectedCode), "\(mutation): \(sealed.output)")
            let manifest = try readJSON(fixture.manifest)
            let rows = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
            let row = try XCTUnwrap(rows.first { $0["id"] as? String == "main-1180x820-light" })
            XCTAssertEqual(row["status"] as? String, "pending", mutation)
            XCTAssertTrue(row["captureID"] is NSNull, mutation)
            XCTAssertEqual(
                try XCTUnwrap(manifest["captureLedger"] as? NSDictionary),
                baselineLedger as NSDictionary,
                mutation
            )
        }
    }

    func testPopoverRuntimeGeometryKeepsFittingHeightVariable() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-r", repositoryRoot.appendingPathComponent("scripts/lib/ui_review_orchestrator.rb").path,
            "-r", "json",
            "-e",
            "request = ViftyUIReview.expected_visual_requests.fetch('menu-popover'); STDOUT.write(JSON.generate(ViftyUIReview::Orchestrator.exact_runtime_geometry(request)))"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
        let geometry = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        XCTAssertEqual(geometry.first as? Int, 320)
        XCTAssertTrue(geometry.last is NSNull)
    }

    func testAutomatedAndMatrixVerificationKeepHumanGatesDistinctAndExact() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var automatedManifest = fixture.manifest
        automatedManifest["status"] = "pending"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &automatedManifest)
        try markSystemSettingVisualRowsPending(manifest: &automatedManifest)
        try writeJSON(automatedManifest, to: fixture.manifestURL)
        let automatedPassed = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )
        XCTAssertEqual(automatedPassed.status, 0, automatedPassed.output)
        XCTAssertTrue(automatedPassed.output.contains("autonomous subset"), automatedPassed.output)
        XCTAssertTrue(automatedPassed.output.contains("main-increase-contrast"), automatedPassed.output)
        XCTAssertTrue(automatedPassed.output.contains("main-reduce-transparency"), automatedPassed.output)
        XCTAssertTrue(automatedPassed.output.contains("human"), automatedPassed.output)

        let contractBlocked = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable
        )
        XCTAssertNotEqual(contractBlocked.status, 0)
        let contractErrors = contractBlocked.output.split(whereSeparator: \.isNewline)
        XCTAssertEqual(contractErrors.count, 4, contractBlocked.output)
        XCTAssertTrue(
            contractErrors.allSatisfy { line in
                let message = String(line)
                return message.contains("main-increase-contrast") ||
                    message.contains("main-reduce-transparency")
            },
            contractBlocked.output
        )
        XCTAssertFalse(contractBlocked.output.contains("accessibility report schemaVersion must be 2"))

        var unexpectedPendingManifest = automatedManifest
        try markRequirementPending(
            rowsKey: "visualCells",
            rowID: "main-1180x820-light",
            manifest: &unexpectedPendingManifest
        )
        try writeJSON(unexpectedPendingManifest, to: fixture.manifestURL)
        let unexpectedPending = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )
        XCTAssertNotEqual(unexpectedPending.status, 0)
        XCTAssertTrue(unexpectedPending.output.contains("main-1180x820-light"), unexpectedPending.output)
        XCTAssertTrue(unexpectedPending.output.contains("must be passed"), unexpectedPending.output)

        var matrixManifest = fixture.manifest
        matrixManifest["status"] = "passed"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &matrixManifest)
        try installValidAttestations(fixture: fixture, manifest: &matrixManifest)
        try writeJSON(matrixManifest, to: fixture.manifestURL)

        let matrix = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-matrix"
        )

        XCTAssertEqual(matrix.status, 0, matrix.output)
        XCTAssertTrue(matrix.output.contains("visual-inspection"), matrix.output)
        XCTAssertTrue(matrix.output.contains("voiceover-session"), matrix.output)

        var tamperedManifest = matrixManifest
        var human = try XCTUnwrap(tamperedManifest["humanAttestations"] as? [String: Any])
        var visualBinding = try XCTUnwrap(human["visual"] as? [String: Any])
        let visualURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(visualBinding["artifact"] as? String)
        )
        var visual = try readJSON(visualURL)
        visual["method"] = "voiceover-session"
        var bindings = try XCTUnwrap(visual["captureBindings"] as? [[String: Any]])
        bindings[0]["fixtureReportSHA256"] = String(repeating: "0", count: 64)
        bindings[0]["screenshotSHA256"] = String(repeating: "1", count: 64)
        bindings[0]["screenshotCanonicalPixelSHA256"] = String(repeating: "2", count: 64)
        visual["captureBindings"] = bindings
        try writeJSON(visual, to: visualURL)
        visualBinding["sha256"] = try sha256(visualURL)
        human["visual"] = visualBinding

        var voiceBinding = try XCTUnwrap(human["voiceOver"] as? [String: Any])
        let voiceURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(voiceBinding["artifact"] as? String)
        )
        var voice = try readJSON(voiceURL)
        voice["method"] = "macos-accessibility-api"
        var voiceBindings = try XCTUnwrap(voice["captureBindings"] as? [[String: Any]])
        voiceBindings[0]["accessibilityRawSHA256"] = String(repeating: "3", count: 64)
        voiceBindings[0]["accessibilitySealedSHA256"] = String(repeating: "4", count: 64)
        voice["captureBindings"] = voiceBindings
        try writeJSON(voice, to: voiceURL)
        voiceBinding["sha256"] = try sha256(voiceURL)
        human["voiceOver"] = voiceBinding
        tamperedManifest["humanAttestations"] = human
        try writeJSON(tamperedManifest, to: fixture.manifestURL)

        let tampered = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-matrix"
        )
        XCTAssertNotEqual(tampered.status, 0)
        XCTAssertTrue(tampered.output.contains("visual-inspection"), tampered.output)
        XCTAssertTrue(tampered.output.contains("voiceover-session"), tampered.output)
        XCTAssertTrue(tampered.output.contains("fixture report checksum binding mismatch"), tampered.output)
        XCTAssertTrue(tampered.output.contains("PNG checksum binding mismatch"), tampered.output)
        XCTAssertTrue(tampered.output.contains("canonical pixel checksum binding mismatch"), tampered.output)
        XCTAssertTrue(tampered.output.contains("raw AX checksum binding mismatch"), tampered.output)
        XCTAssertTrue(tampered.output.contains("sealed AX checksum binding mismatch"), tampered.output)

        try FileManager.default.removeItem(at: voiceURL)
        try writeJSON(matrixManifest, to: fixture.manifestURL)
        let missing = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-matrix"
        )

        XCTAssertNotEqual(missing.status, 0)
        XCTAssertTrue(missing.output.contains("voiceOver attestation artifact is missing"), missing.output)
    }

    func testVerifierRejectsSubstitutedAndMixedAXCollectorsAcrossExactThirteenRows() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let substitute = fixture.root.appendingPathComponent("substitute-collector")
        var substituteData = try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "ax-collector")
        )
        substituteData.append(0)
        try substituteData.write(to: substitute)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: substitute.path)
        let substituted = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: substitute
        )
        XCTAssertNotEqual(substituted.status, 0, substituted.output)
        XCTAssertEqual(
            substituted.output.components(separatedBy: "AX collector executable path mismatch").count - 1,
            13,
            substituted.output
        )
        XCTAssertEqual(
            substituted.output.components(separatedBy: "AX collector executable checksum mismatch").count - 1,
            13,
            substituted.output
        )

        var mixed = fixture.manifest
        var ledger = try XCTUnwrap(mixed["captureLedger"] as? [String: Any])
        let checks = try XCTUnwrap(mixed["accessibilityChecks"] as? [[String: Any]])
        let firstCaptureID = try XCTUnwrap(checks.first?["captureID"] as? String)
        var capture = try XCTUnwrap(ledger[firstCaptureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        accessibility["collectorExecutableSHA256"] = try sha256(substitute)
        capture["accessibility"] = accessibility
        ledger[firstCaptureID] = capture
        mixed["captureLedger"] = ledger
        try writeJSON(mixed, to: fixture.manifestURL)

        let mixedResult = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable
        )
        XCTAssertNotEqual(mixedResult.status, 0, mixedResult.output)
        XCTAssertEqual(
            mixedResult.output.components(separatedBy: "AX collector executable checksum mismatch").count - 1,
            1,
            mixedResult.output
        )
        XCTAssertTrue(mixedResult.output.contains(firstCaptureID), mixedResult.output)
    }

    func testMatrixVerifierRejectsVoiceOverTemplatePlaceholdersGenericNotesAndWrongStepRows() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var baselineManifest = fixture.manifest
        baselineManifest["status"] = "passed"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &baselineManifest)
        try installValidAttestations(fixture: fixture, manifest: &baselineManifest)

        let baselineHuman = try XCTUnwrap(baselineManifest["humanAttestations"] as? [String: Any])
        let baselineVoiceBinding = try XCTUnwrap(baselineHuman["voiceOver"] as? [String: Any])
        let voiceURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(baselineVoiceBinding["artifact"] as? String)
        )
        let baselineVoice = try readJSON(voiceURL)

        let mutations: [(name: String, expectedError: String, apply: (inout [String: Any]) throws -> Void)] = [
            (
                "reviewer placeholder",
                "reviewer must replace the template placeholder",
                { $0["reviewer"] = "REPLACE_WITH_REVIEWER_NAME" }
            ),
            (
                "timestamp placeholder",
                "reviewedAt must replace the template placeholder",
                { $0["reviewedAt"] = "1970-01-01T00:00:00Z" }
            ),
            (
                "generic notes",
                "notes must record a specific observed result",
                { voice in
                    var steps = try XCTUnwrap(voice["steps"] as? [[String: Any]])
                    steps[0]["notes"] = "Completed the scripted voiceover-session check."
                    voice["steps"] = steps
                }
            ),
            (
                "wrong per-step rows",
                "step adjustable-controls covered rows mismatch",
                { voice in
                    var steps = try XCTUnwrap(voice["steps"] as? [[String: Any]])
                    let index = try XCTUnwrap(
                        steps.firstIndex { $0["id"] as? String == "adjustable-controls" }
                    )
                    steps[index]["coveredRowIDs"] = [
                        "confirmed-owner-headline",
                        "six-adjustable-point-controls"
                    ]
                    voice["steps"] = steps
                }
            ),
            (
                "over-broad action sequence",
                "actionSequence must match the exact safe UI-only sequence",
                { voice in
                    var actions = try XCTUnwrap(voice["actionSequence"] as? [String])
                    actions.append("apply-curve")
                    voice["actionSequence"] = actions
                }
            ),
            (
                "over-broad inspect-only groups",
                "inspectOnlyControlGroups must match the exact announce-only groups",
                { voice in
                    var groups = try XCTUnwrap(voice["inspectOnlyControlGroups"] as? [String])
                    groups.append("fan-controls")
                    voice["inspectOnlyControlGroups"] = groups
                }
            ),
            (
                "recorded disallowed action",
                "disallowedActionsPerformed must be empty",
                { $0["disallowedActionsPerformed"] = ["apply-curve"] }
            )
        ]

        for mutation in mutations {
            var voice = baselineVoice
            try mutation.apply(&voice)
            try writeJSON(voice, to: voiceURL)

            var manifest = baselineManifest
            var human = try XCTUnwrap(manifest["humanAttestations"] as? [String: Any])
            var voiceBinding = try XCTUnwrap(human["voiceOver"] as? [String: Any])
            voiceBinding["sha256"] = try sha256(voiceURL)
            human["voiceOver"] = voiceBinding
            manifest["humanAttestations"] = human
            try writeJSON(manifest, to: fixture.manifestURL)

            let rejected = try runVerifier(
                manifest: fixture.manifestURL,
                evidenceDirectory: fixture.evidence,
                releaseBinary: fixture.releaseBinary,
                debugExecutable: fixture.debugExecutable,
                collectorExecutable: fixture.collectorExecutable,
                verificationMode: "--verify-matrix"
            )

            XCTAssertNotEqual(rejected.status, 0, "\(mutation.name): \(rejected.output)")
            XCTAssertTrue(
                rejected.output.contains(mutation.expectedError),
                "\(mutation.name): \(rejected.output)"
            )
        }
    }

    func testAutomatedVerifierRejectsForgedPassedAssertionOverInvalidRawObservations() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["status"] = "pending"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &manifest)
        try markSystemSettingVisualRowsPending(manifest: &manifest)

        let rowID = "confirmed-owner-headline"
        let rows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == rowID })
        let captureID = try XCTUnwrap(row["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let rawURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["rawArtifact"] as? String)
        )
        var raw = try readJSON(rawURL)
        var observations = try XCTUnwrap(raw["observations"] as? [[String: Any]])
        let titleIndex = try XCTUnwrap(
            observations.firstIndex { $0["identifier"] as? String == AXEvidenceIdentifier.controlSessionTitle }
        )
        observations[titleIndex]["label"] = "Forged owner headline"
        raw["observations"] = observations
        try writeJSON(raw, to: rawURL)
        let changedRawSHA = try sha256(rawURL)
        accessibility["rawSHA256"] = changedRawSHA

        let sealedURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        var sealed = try readJSON(sealedURL)
        var rawBinding = try XCTUnwrap(sealed["rawCapture"] as? [String: Any])
        rawBinding["sha256"] = changedRawSHA
        sealed["rawCapture"] = rawBinding
        try writeJSON(sealed, to: sealedURL)
        accessibility["sha256"] = try sha256(sealedURL)
        capture["accessibility"] = accessibility
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: fixture.manifestURL)

        let rejected = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )

        XCTAssertNotEqual(rejected.status, 0, rejected.output)
        XCTAssertTrue(rejected.output.contains("independently recomputed AX predicate failed"), rejected.output)
        XCTAssertTrue(rejected.output.contains("label mismatch"), rejected.output)
        XCTAssertTrue(rejected.output.contains("does not match the independently recomputed AX predicate"), rejected.output)
    }

    func testAutomatedVerifierIndependentlyRejectsTamperedUpdateControlHelp() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["status"] = "pending"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &manifest)
        try markSystemSettingVisualRowsPending(manifest: &manifest)

        let rowID = "settings-logical-traversal"
        let rows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == rowID })
        let captureID = try XCTUnwrap(row["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let rawURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["rawArtifact"] as? String)
        )
        var raw = try readJSON(rawURL)
        var observations = try XCTUnwrap(raw["observations"] as? [[String: Any]])
        let latestIndex = try XCTUnwrap(
            observations.firstIndex {
                $0["identifier"] as? String == AXEvidenceIdentifier.settingsUpdateLatest
            }
        )
        observations[latestIndex]["help"] = "Downloads and installs automatically."
        raw["observations"] = observations
        try writeJSON(raw, to: rawURL)
        let changedRawSHA = try sha256(rawURL)
        accessibility["rawSHA256"] = changedRawSHA

        let sealedURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        var sealed = try readJSON(sealedURL)
        var rawBinding = try XCTUnwrap(sealed["rawCapture"] as? [String: Any])
        rawBinding["sha256"] = changedRawSHA
        sealed["rawCapture"] = rawBinding
        try writeJSON(sealed, to: sealedURL)
        accessibility["sha256"] = try sha256(sealedURL)
        capture["accessibility"] = accessibility
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: fixture.manifestURL)

        let rejected = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )

        XCTAssertNotEqual(rejected.status, 0, rejected.output)
        XCTAssertTrue(rejected.output.contains("independently recomputed AX predicate failed"), rejected.output)
        XCTAssertTrue(rejected.output.contains("Update to latest version help mismatch"), rejected.output)
        XCTAssertTrue(rejected.output.contains("does not match the independently recomputed AX predicate"), rejected.output)
    }

    func testAutomatedVerifierIndependentlyRejectsOffscreenSeparateFanCurvesToggle() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["status"] = "pending"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &manifest)
        try markSystemSettingVisualRowsPending(manifest: &manifest)

        let rowID = "six-adjustable-point-controls"
        let rows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == rowID })
        let captureID = try XCTUnwrap(row["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let rawURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["rawArtifact"] as? String)
        )
        var raw = try readJSON(rawURL)
        var observations = try XCTUnwrap(raw["observations"] as? [[String: Any]])
        let toggleIndex = try XCTUnwrap(
            observations.firstIndex {
                $0["identifier"] as? String == AXEvidenceIdentifier.curveSeparateFans
            }
        )
        observations[toggleIndex]["position"] = ["x": 120, "y": 990]
        raw["observations"] = observations
        try writeJSON(raw, to: rawURL)
        let changedRawSHA = try sha256(rawURL)
        accessibility["rawSHA256"] = changedRawSHA

        let sealedURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        var sealed = try readJSON(sealedURL)
        var rawBinding = try XCTUnwrap(sealed["rawCapture"] as? [String: Any])
        rawBinding["sha256"] = changedRawSHA
        sealed["rawCapture"] = rawBinding
        try writeJSON(sealed, to: sealedURL)
        accessibility["sha256"] = try sha256(sealedURL)
        capture["accessibility"] = accessibility
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: fixture.manifestURL)

        let rejected = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )

        XCTAssertNotEqual(rejected.status, 0, rejected.output)
        XCTAssertTrue(rejected.output.contains("independently recomputed AX predicate failed"), rejected.output)
        XCTAssertTrue(
            rejected.output.contains("separate fan curves toggle must be fully visible inside the capture root"),
            rejected.output
        )
        XCTAssertTrue(rejected.output.contains("does not match the independently recomputed AX predicate"), rejected.output)
    }

    func testAutomatedVerifierIndependentlyRejectsTamperedEffectiveCurveSummary() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["status"] = "pending"
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &manifest)
        try markSystemSettingVisualRowsPending(manifest: &manifest)

        let rowID = "six-adjustable-point-controls"
        let rows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == rowID })
        let captureID = try XCTUnwrap(row["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let rawURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["rawArtifact"] as? String)
        )
        var raw = try readJSON(rawURL)
        var observations = try XCTUnwrap(raw["observations"] as? [[String: Any]])
        let summaryIndex = try XCTUnwrap(
            observations.firstIndex {
                $0["identifier"] as? String == AXEvidenceIdentifier.leftFanEffectiveSummary
            }
        )
        var value = try XCTUnwrap(observations[summaryIndex]["value"] as? [String: Any])
        value["value"] = "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5600 RPM"
        observations[summaryIndex]["value"] = value
        raw["observations"] = observations
        try writeJSON(raw, to: rawURL)
        let changedRawSHA = try sha256(rawURL)
        accessibility["rawSHA256"] = changedRawSHA

        let sealedURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        var sealed = try readJSON(sealedURL)
        var rawBinding = try XCTUnwrap(sealed["rawCapture"] as? [String: Any])
        rawBinding["sha256"] = changedRawSHA
        sealed["rawCapture"] = rawBinding
        try writeJSON(sealed, to: sealedURL)
        accessibility["sha256"] = try sha256(sealedURL)
        capture["accessibility"] = accessibility
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: fixture.manifestURL)

        let rejected = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable,
            verificationMode: "--verify-automated"
        )

        XCTAssertNotEqual(rejected.status, 0, rejected.output)
        XCTAssertTrue(rejected.output.contains("independently recomputed AX predicate failed"), rejected.output)
        XCTAssertTrue(
            rejected.output.contains("vifty.ax.curve.fan-0.effective-summary value mismatch"),
            rejected.output
        )
        XCTAssertTrue(rejected.output.contains("does not match the independently recomputed AX predicate"), rejected.output)
    }

    func testHumanAttestationTemplatesSchemaDocsAndMakefileContract() throws {
        let visual = try readJSON(
            repositoryRoot.appendingPathComponent("docs/ui-review/visual-attestation-template.json")
        )
        let voiceOver = try readJSON(
            repositoryRoot.appendingPathComponent("docs/ui-review/voiceover-attestation-template.json")
        )
        let schema = try readJSON(
            repositoryRoot.appendingPathComponent("docs/schemas/ui-review-attestation-v1.schema.json")
        )
        let documentation = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/ui-review/README.md"),
            encoding: .utf8
        )
        let makefile = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"),
            encoding: .utf8
        )

        XCTAssertEqual(visual["method"] as? String, "visual-inspection")
        XCTAssertEqual(voiceOver["method"] as? String, "voiceover-session")
        XCTAssertEqual(
            voiceOver["actionSequence"] as? [String],
            [
                "settings-general",
                "settings-menu-bar",
                "settings-notifications",
                "settings-agent-workflows",
                "settings-general"
            ]
        )
        XCTAssertEqual(
            voiceOver["inspectOnlyControlGroups"] as? [String],
            ["curve-point-adjustables", "notification-actions", "sensor-buttons"]
        )
        XCTAssertEqual(voiceOver["disallowedActionsPerformed"] as? [String], [])
        let voiceOverSteps = try XCTUnwrap(voiceOver["steps"] as? [[String: Any]])
        XCTAssertEqual(
            voiceOverSteps.compactMap { $0["id"] as? String },
            voiceOverStepRowIDs.map(\.id)
        )
        for step in voiceOverSteps {
            let stepID = try XCTUnwrap(step["id"] as? String)
            let expectedRows = try XCTUnwrap(
                voiceOverStepRowIDs.first { $0.id == stepID }?.rowIDs
            )
            XCTAssertEqual(step["coveredRowIDs"] as? [String], expectedRows, stepID)
            XCTAssertTrue(
                (step["notes"] as? String)?.hasPrefix("REPLACE_WITH_OBSERVED_RESULT:") == true,
                stepID
            )
        }
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.app/schemas/ui-review-attestation-v1.schema.json")
        let schemaProperties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let reviewerSchema = try XCTUnwrap(schemaProperties["reviewer"] as? [String: Any])
        let reviewerNot = try XCTUnwrap(reviewerSchema["not"] as? [String: Any])
        XCTAssertEqual(reviewerNot["const"] as? String, "REPLACE_WITH_REVIEWER_NAME")
        let reviewedAtSchema = try XCTUnwrap(schemaProperties["reviewedAt"] as? [String: Any])
        let reviewedAtNot = try XCTUnwrap(reviewedAtSchema["not"] as? [String: Any])
        XCTAssertEqual(reviewedAtNot["const"] as? String, "1970-01-01T00:00:00Z")
        let schemaDefinitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let stepSchema = try XCTUnwrap(schemaDefinitions["step"] as? [String: Any])
        let stepProperties = try XCTUnwrap(stepSchema["properties"] as? [String: Any])
        let notesSchema = try XCTUnwrap(stepProperties["notes"] as? [String: Any])
        XCTAssertEqual(notesSchema["minLength"] as? Int, 24)
        let schemaAllOf = try XCTUnwrap(schema["allOf"] as? [[String: Any]])
        XCTAssertFalse(schemaAllOf.isEmpty)
        XCTAssertTrue(documentation.contains("AX_PERMISSION_MISSING"))
        XCTAssertTrue(documentation.contains("exit 77"))
        XCTAssertTrue(documentation.contains("visual-inspection"))
        XCTAssertTrue(documentation.contains("voiceover-session"))
        XCTAssertTrue(documentation.contains("--verify-automated"))
        XCTAssertTrue(documentation.contains("--verify-matrix"))
        XCTAssertTrue(documentation.contains("General -> Menu Bar -> Notifications -> Agent Workflows -> General"))
        XCTAssertTrue(documentation.contains("inspect and announce only"))
        XCTAssertTrue(documentation.contains("Do not invoke the six curve-point adjustables"))
        XCTAssertTrue(documentation.contains("Do not activate notification actions"))
        XCTAssertTrue(documentation.contains("--fixture-hold-seconds 300"))
        XCTAssertTrue(documentation.contains("more than 40 seconds remain before the fixture deadline"))
        XCTAssertTrue(documentation.contains("human VoiceOver observation while that exact fixture remains at `ready`"))
        XCTAssertTrue(documentation.contains("Visual review remains post-seal"))
        XCTAssertTrue(makefile.contains("ui-review-verify-automated:"))
        XCTAssertTrue(makefile.contains("--manifest \"$(UI_REVIEW_MANIFEST)\""))
        let verifyRecipe = try XCTUnwrap(
            makefile.components(separatedBy: "verify: ##").last?
                .components(separatedBy: "verify-full:").first
        )
        XCTAssertFalse(verifyRecipe.contains("ui-review-verify"))
    }

    func testVerifierRejectsLegacyV2Manifest() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["schemaVersion"] = 2

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("schemaVersion must be 3"), blocked.output)
    }

    func testContractVerifierRequiresHonestPendingTopLevelStatus() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        manifest["status"] = "automated-passed"

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("status must remain pending"), blocked.output)
    }

    func testVerifierRejectsNonObjectManifestFixtureAndAccessibilityReports() throws {
        let manifestFixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: manifestFixture.root) }
        try Data("null".utf8).write(to: manifestFixture.manifestURL)
        let nonObjectManifest = try runVerifier(
            manifest: manifestFixture.manifestURL,
            evidenceDirectory: manifestFixture.evidence,
            releaseBinary: manifestFixture.releaseBinary,
            debugExecutable: manifestFixture.debugExecutable,
            collectorExecutable: manifestFixture.collectorExecutable
        )
        XCTAssertNotEqual(nonObjectManifest.status, 0)
        XCTAssertTrue(nonObjectManifest.output.contains("manifest must be a JSON object"), nonObjectManifest.output)

        let reportFixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: reportFixture.root) }
        var reportManifest = reportFixture.manifest
        let fixtureRows = try XCTUnwrap(reportManifest["fixtureReports"] as? [[String: Any]])
        let fixtureCaptureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)
        var reportLedger = try XCTUnwrap(reportManifest["captureLedger"] as? [String: Any])
        var reportCapture = try XCTUnwrap(reportLedger[fixtureCaptureID] as? [String: Any])
        let reportURL = reportFixture.evidence.appendingPathComponent(
            try XCTUnwrap(reportCapture["fixtureReportArtifact"] as? String)
        )
        try Data("null".utf8).write(to: reportURL)
        reportCapture["fixtureReportSHA256"] = try sha256(reportURL)
        reportLedger[fixtureCaptureID] = reportCapture
        reportManifest["captureLedger"] = reportLedger
        let nonObjectReport = try verify(reportFixture, manifest: reportManifest)
        XCTAssertNotEqual(nonObjectReport.status, 0)
        XCTAssertTrue(nonObjectReport.output.contains("fixture report must be a JSON object"), nonObjectReport.output)

        let accessibilityFixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: accessibilityFixture.root) }
        var accessibilityManifest = accessibilityFixture.manifest
        let checks = try XCTUnwrap(accessibilityManifest["accessibilityChecks"] as? [[String: Any]])
        let accessibilityCaptureID = try XCTUnwrap(checks.first?["captureID"] as? String)
        var accessibilityLedger = try XCTUnwrap(accessibilityManifest["captureLedger"] as? [String: Any])
        var accessibilityCapture = try XCTUnwrap(accessibilityLedger[accessibilityCaptureID] as? [String: Any])
        var accessibility = try XCTUnwrap(accessibilityCapture["accessibility"] as? [String: Any])
        let accessibilityURL = accessibilityFixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        try Data("false".utf8).write(to: accessibilityURL)
        accessibility["sha256"] = try sha256(accessibilityURL)
        accessibilityCapture["accessibility"] = accessibility
        accessibilityLedger[accessibilityCaptureID] = accessibilityCapture
        accessibilityManifest["captureLedger"] = accessibilityLedger
        let nonObjectAccessibility = try verify(accessibilityFixture, manifest: accessibilityManifest)
        XCTAssertNotEqual(nonObjectAccessibility.status, 0)
        XCTAssertTrue(
            nonObjectAccessibility.output.contains("accessibility report must be a JSON object"),
            nonObjectAccessibility.output
        )
    }

    func testVerifierRejectsMissingAndOrphanedCaptureLedgerEntries() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var missingManifest = fixture.manifest
        let fixtureRows = try XCTUnwrap(missingManifest["fixtureReports"] as? [[String: Any]])
        let missingCaptureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)
        var missingLedger = try XCTUnwrap(missingManifest["captureLedger"] as? [String: Any])
        missingLedger.removeValue(forKey: missingCaptureID)
        missingManifest["captureLedger"] = missingLedger

        let missing = try verify(fixture, manifest: missingManifest)
        XCTAssertNotEqual(missing.status, 0)
        XCTAssertTrue(missing.output.contains(missingCaptureID), missing.output)

        var orphanedManifest = fixture.manifest
        var orphanedLedger = try XCTUnwrap(orphanedManifest["captureLedger"] as? [String: Any])
        let existingEntry = try XCTUnwrap(orphanedLedger.values.first as? [String: Any])
        let orphanedCaptureID = "orphaned-capture"
        orphanedLedger[orphanedCaptureID] = existingEntry
        orphanedManifest["captureLedger"] = orphanedLedger

        let orphaned = try verify(fixture, manifest: orphanedManifest)
        XCTAssertNotEqual(orphaned.status, 0)
        XCTAssertTrue(orphaned.output.contains(orphanedCaptureID), orphaned.output)
    }

    func testVerifierFailsClosedForMalformedRowsLedgerAndRuntimeIdentity() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var malformedRowsManifest = fixture.manifest
        var visualRows = try XCTUnwrap(malformedRowsManifest["visualCells"] as? [Any])
        visualRows.append("not-a-visual-row")
        malformedRowsManifest["visualCells"] = visualRows
        let malformedRows = try verify(fixture, manifest: malformedRowsManifest)
        XCTAssertNotEqual(malformedRows.status, 0)
        XCTAssertTrue(malformedRows.output.contains("visual cell row must be an object"), malformedRows.output)

        var malformedRequestManifest = fixture.manifest
        var requestRows = try XCTUnwrap(malformedRequestManifest["visualCells"] as? [[String: Any]])
        requestRows[0]["request"] = "not-a-request-object"
        malformedRequestManifest["visualCells"] = requestRows
        let malformedRequest = try verify(fixture, manifest: malformedRequestManifest)
        XCTAssertNotEqual(malformedRequest.status, 0)
        XCTAssertTrue(malformedRequest.output.contains("request must be an object"), malformedRequest.output)
        XCTAssertFalse(malformedRequest.output.contains("NoMethodError"), malformedRequest.output)

        var emptyRowManifest = fixture.manifest
        var rowsWithEmptyObject = try XCTUnwrap(emptyRowManifest["visualCells"] as? [Any])
        rowsWithEmptyObject.append([String: Any]())
        emptyRowManifest["visualCells"] = rowsWithEmptyObject
        let emptyRow = try verify(fixture, manifest: emptyRowManifest)
        XCTAssertNotEqual(emptyRow.status, 0)
        XCTAssertTrue(emptyRow.output.contains("visual cell count must be exactly"), emptyRow.output)

        var smuggledKeyManifest = fixture.manifest
        var fixtureRowsWithExtraKey = try XCTUnwrap(smuggledKeyManifest["fixtureReports"] as? [[String: Any]])
        fixtureRowsWithExtraKey[0]["id"] = "bogus-named-row"
        let smuggledCaptureID = try XCTUnwrap(fixtureRowsWithExtraKey[0]["captureID"] as? String)
        smuggledKeyManifest["fixtureReports"] = fixtureRowsWithExtraKey
        let smuggledCapture = try captureEntry(smuggledCaptureID, in: smuggledKeyManifest)
        let smuggledReportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(smuggledCapture["fixtureReportArtifact"] as? String)
        )
        var smuggledReport = try readJSON(smuggledReportURL)
        var smuggledRecorder = try XCTUnwrap(smuggledReport["recorder"] as? [String: Any])
        smuggledRecorder["attemptedHardwareCommands"] = ["smuggled-unsafe-attempt"]
        smuggledReport["recorder"] = smuggledRecorder
        smuggledReport["passed"] = false
        try updateFixtureReport(
            smuggledReport,
            captureID: smuggledCaptureID,
            fixture: fixture,
            manifest: &smuggledKeyManifest
        )
        let smuggledKey = try verify(fixture, manifest: smuggledKeyManifest)
        XCTAssertNotEqual(smuggledKey.status, 0)
        XCTAssertTrue(smuggledKey.output.contains("row keys do not match"), smuggledKey.output)

        var malformedLedgerManifest = fixture.manifest
        let fixtureRows = try XCTUnwrap(malformedLedgerManifest["fixtureReports"] as? [[String: Any]])
        let fixtureCaptureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)
        var malformedLedger = try XCTUnwrap(malformedLedgerManifest["captureLedger"] as? [String: Any])
        malformedLedger[fixtureCaptureID] = "not-a-capture-object"
        malformedLedgerManifest["captureLedger"] = malformedLedger
        let malformedCapture = try verify(fixture, manifest: malformedLedgerManifest)
        XCTAssertNotEqual(malformedCapture.status, 0)
        XCTAssertTrue(malformedCapture.output.contains("captureLedger entry \(fixtureCaptureID) must be an object"), malformedCapture.output)

        var smuggledLedgerManifest = fixture.manifest
        var smuggledLedger = try XCTUnwrap(smuggledLedgerManifest["captureLedger"] as? [String: Any])
        var smuggledLedgerCapture = try XCTUnwrap(smuggledLedger[fixtureCaptureID] as? [String: Any])
        smuggledLedgerCapture["status"] = "passed"
        smuggledLedger[fixtureCaptureID] = smuggledLedgerCapture
        smuggledLedgerManifest["captureLedger"] = smuggledLedger
        let smuggledLedgerResult = try verify(fixture, manifest: smuggledLedgerManifest)
        XCTAssertNotEqual(smuggledLedgerResult.status, 0)
        XCTAssertTrue(
            smuggledLedgerResult.output.contains("capture record keys do not match"),
            smuggledLedgerResult.output
        )

        var malformedIdentityManifest = fixture.manifest
        let visualEntries = try XCTUnwrap(malformedIdentityManifest["visualCells"] as? [[String: Any]])
        let visualCaptureID = try XCTUnwrap(visualEntries.first?["captureID"] as? String)
        var identityLedger = try XCTUnwrap(malformedIdentityManifest["captureLedger"] as? [String: Any])
        var identityCapture = try XCTUnwrap(identityLedger[visualCaptureID] as? [String: Any])
        var runtimeIdentity = try XCTUnwrap(identityCapture["runtimeIdentity"] as? [String: Any])
        runtimeIdentity.removeValue(forKey: "contentWidth")
        identityCapture["runtimeIdentity"] = runtimeIdentity
        identityLedger[visualCaptureID] = identityCapture
        malformedIdentityManifest["captureLedger"] = identityLedger
        let malformedIdentity = try verify(fixture, manifest: malformedIdentityManifest)
        XCTAssertNotEqual(malformedIdentity.status, 0)
        XCTAssertTrue(malformedIdentity.output.contains("window width is invalid"), malformedIdentity.output)
        XCTAssertFalse(malformedIdentity.output.contains("NoMethodError"), malformedIdentity.output)
    }

    func testVerifierRejectsArtifactTraversalThroughSymlinkedParent() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var manifest = fixture.manifest
        let fixtureRows = try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]])
        let captureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        let originalArtifact = try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        let originalURL = fixture.evidence.appendingPathComponent(originalArtifact)
        let outsideDirectory = fixture.root.appendingPathComponent("outside-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let outsideReport = outsideDirectory.appendingPathComponent("fixture-report.json")
        try FileManager.default.copyItem(at: originalURL, to: outsideReport)
        let symlink = fixture.evidence.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideDirectory)
        capture["fixtureReportArtifact"] = "escape/fixture-report.json"
        capture["fixtureReportSHA256"] = try sha256(outsideReport)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("escapes the evidence directory"), blocked.output)
    }

    func testVerifierRejectsCoordinatedCanonicalRequestTampering() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        var visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let visualIndex = try XCTUnwrap(
            visualCells.firstIndex { $0["id"] as? String == "main-780x480-light" }
        )
        var visual = visualCells[visualIndex]
        var request = try XCTUnwrap(visual["request"] as? [String: Any])
        request["appearance"] = "dark"
        visual["request"] = request
        visualCells[visualIndex] = visual
        manifest["visualCells"] = visualCells

        let captureID = try XCTUnwrap(visual["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        capture["request"] = request
        capture["requestSHA256"] = try canonicalJSONSHA256(request)
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(reportURL)
        report["request"] = request
        report["requestSHA256"] = try canonicalJSONSHA256(request)
        var observed = try XCTUnwrap(report["observed"] as? [String: Any])
        var environment = try XCTUnwrap(observed["environment"] as? [String: Any])
        environment["appearance"] = "dark"
        observed["environment"] = environment
        report["observed"] = observed
        try writeJSON(report, to: reportURL)
        capture["fixtureReportSHA256"] = try sha256(reportURL)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("main-780x480-light"), blocked.output)
        XCTAssertTrue(blocked.output.localizedCaseInsensitiveContains("request"), blocked.output)
    }

    func testVerifierRejectsDebugExecutablePIDAndWindowIdentityDrift() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fixtureRows = try XCTUnwrap(fixture.manifest["fixtureReports"] as? [[String: Any]])
        let captureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)

        var executableManifest = fixture.manifest
        var executableLedger = try XCTUnwrap(executableManifest["captureLedger"] as? [String: Any])
        var executableCapture = try XCTUnwrap(executableLedger[captureID] as? [String: Any])
        executableCapture["debugExecutableSHA256"] = try sha256(fixture.releaseBinary)
        executableLedger[captureID] = executableCapture
        executableManifest["captureLedger"] = executableLedger
        let executableDrift = try verify(fixture, manifest: executableManifest)
        XCTAssertNotEqual(executableDrift.status, 0)
        XCTAssertTrue(executableDrift.output.contains(captureID), executableDrift.output)
        XCTAssertTrue(
            executableDrift.output.localizedCaseInsensitiveContains("debug executable"),
            executableDrift.output
        )

        var processManifest = fixture.manifest
        var processLedger = try XCTUnwrap(processManifest["captureLedger"] as? [String: Any])
        var processCapture = try XCTUnwrap(processLedger[captureID] as? [String: Any])
        var processIdentity = try XCTUnwrap(processCapture["runtimeIdentity"] as? [String: Any])
        processIdentity["processIdentifier"] = 9_999
        processCapture["runtimeIdentity"] = processIdentity
        processLedger[captureID] = processCapture
        processManifest["captureLedger"] = processLedger
        let processDrift = try verify(fixture, manifest: processManifest)
        XCTAssertNotEqual(processDrift.status, 0)
        XCTAssertTrue(processDrift.output.contains(captureID), processDrift.output)
        XCTAssertTrue(processDrift.output.localizedCaseInsensitiveContains("process"), processDrift.output)

        var windowManifest = fixture.manifest
        var windowLedger = try XCTUnwrap(windowManifest["captureLedger"] as? [String: Any])
        var windowCapture = try XCTUnwrap(windowLedger[captureID] as? [String: Any])
        var windowIdentity = try XCTUnwrap(windowCapture["runtimeIdentity"] as? [String: Any])
        windowIdentity["windowNumber"] = 9_999
        windowIdentity["windowIdentifier"] = "drifted-window-identity"
        windowCapture["runtimeIdentity"] = windowIdentity
        windowLedger[captureID] = windowCapture
        windowManifest["captureLedger"] = windowLedger
        let windowDrift = try verify(fixture, manifest: windowManifest)
        XCTAssertNotEqual(windowDrift.status, 0)
        XCTAssertTrue(windowDrift.output.contains(captureID), windowDrift.output)
        XCTAssertTrue(windowDrift.output.localizedCaseInsensitiveContains("window"), windowDrift.output)
    }

    func testVerifierRejectsExecutablePathProvenanceVisibilityAndAccessibilityIdentifierDrift() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let fixtureRows = try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]])
        let captureID = try XCTUnwrap(fixtureRows.first?["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        capture["debugExecutablePath"] = "/tmp/spoofed-vifty"
        var identity = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
        identity["executablePath"] = "/tmp/spoofed-vifty"
        identity["executableSHA256"] = String(repeating: "0", count: 64)
        identity["provenance"] = "self-declared-window"
        identity["isVisible"] = false
        identity["windowIdentifier"] = "spoofed-window"
        identity["accessibilityIdentifier"] = "spoofed-accessibility-window"
        capture["runtimeIdentity"] = identity

        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(reportURL)
        report["debugExecutablePath"] = "/tmp/spoofed-vifty"
        report["runtimeIdentity"] = identity
        var observed = try XCTUnwrap(report["observed"] as? [String: Any])
        var window = try XCTUnwrap(observed["window"] as? [String: Any])
        window["provenance"] = identity["provenance"]
        window["isVisible"] = identity["isVisible"]
        window["windowIdentifier"] = identity["windowIdentifier"]
        window["accessibilityIdentifier"] = identity["accessibilityIdentifier"]
        observed["window"] = window
        report["observed"] = observed
        try writeJSON(report, to: reportURL)
        capture["fixtureReportSHA256"] = try sha256(reportURL)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("debug executable path mismatch"), blocked.output)
        XCTAssertTrue(blocked.output.contains("runtime executable checksum mismatch"), blocked.output)
        XCTAssertTrue(blocked.output.contains("window provenance mismatch"), blocked.output)
        XCTAssertTrue(blocked.output.contains("window is not visible"), blocked.output)
        XCTAssertTrue(blocked.output.contains("window identifier mismatch"), blocked.output)
        XCTAssertTrue(blocked.output.contains("accessibility identifier mismatch"), blocked.output)
    }

    func testVerifierPinsAllNineStateVisualCoverageAndNativePopoverGeometry() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var coverageManifest = fixture.manifest
        var visualCells = try XCTUnwrap(coverageManifest["visualCells"] as? [[String: Any]])
        let removedID = "state-active-manual"
        let removedIndex = try XCTUnwrap(
            visualCells.firstIndex { $0["id"] as? String == removedID }
        )
        let removedCaptureID = try XCTUnwrap(visualCells[removedIndex]["captureID"] as? String)
        visualCells.remove(at: removedIndex)
        coverageManifest["visualCells"] = visualCells
        var coverageLedger = try XCTUnwrap(coverageManifest["captureLedger"] as? [String: Any])
        coverageLedger.removeValue(forKey: removedCaptureID)
        coverageManifest["captureLedger"] = coverageLedger

        let missingState = try verify(fixture, manifest: coverageManifest)
        XCTAssertNotEqual(missingState.status, 0)
        XCTAssertTrue(missingState.output.contains(removedID), missingState.output)

        let settingsGeometry = try verifierResultAfterChangingGeometry(
            fixture: fixture,
            visualID: "settings-general",
            width: 780,
            height: 480
        )
        XCTAssertNotEqual(settingsGeometry.status, 0)
        XCTAssertTrue(settingsGeometry.output.contains("settings-general"), settingsGeometry.output)
        XCTAssertTrue(
            settingsGeometry.output.localizedCaseInsensitiveContains("width") ||
                settingsGeometry.output.localizedCaseInsensitiveContains("geometry"),
            settingsGeometry.output
        )

        let popoverGeometry = try verifierResultAfterChangingGeometry(
            fixture: fixture,
            visualID: "menu-popover",
            width: 321,
            height: 360
        )
        XCTAssertNotEqual(popoverGeometry.status, 0)
        XCTAssertTrue(popoverGeometry.output.contains("menu-popover"), popoverGeometry.output)
        XCTAssertTrue(
            popoverGeometry.output.localizedCaseInsensitiveContains("width") ||
                popoverGeometry.output.localizedCaseInsensitiveContains("geometry"),
            popoverGeometry.output
        )
    }

    func testVerifierAcceptsCompleteLinkedContractFixtureAndRejectsLateHardwareAttempt() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let passing = try verify(fixture)
        XCTAssertEqual(passing.status, 0, passing.output)
        XCTAssertTrue(passing.output.contains("UI request/ledger verifier checks passed"), passing.output)

        var manifest = fixture.manifest
        let fixtureReports = try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]])
        let firstFixture = fixtureReports[0]
        let captureID = try XCTUnwrap(firstFixture["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let fixturePath = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var unsafeReport = try readJSON(fixturePath)
        var recorder = try XCTUnwrap(unsafeReport["recorder"] as? [String: Any])
        recorder["attemptedHardwareCommands"] = ["late-restore-auto"]
        unsafeReport["recorder"] = recorder
        unsafeReport["passed"] = false
        try updateFixtureReport(
            unsafeReport,
            captureID: captureID,
            fixture: fixture,
            manifest: &manifest
        )

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("attemptedHardwareCommands must be empty"), blocked.output)
        XCTAssertTrue(blocked.output.contains("did not pass"), blocked.output)
    }

    func testVerifierRejectsVisualSemanticRequestThatDoesNotMatchLinkedFixtureReport() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        var visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        var entry = visualCells[0]
        var request = try XCTUnwrap(entry["request"] as? [String: Any])
        request["appearance"] = "dark"
        entry["request"] = request
        visualCells[0] = entry
        manifest["visualCells"] = visualCells
        try writeJSON(manifest, to: fixture.manifestURL)

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("semantic request mismatch"), blocked.output)
    }

    func testVerifierRejectsUnobservedOrRequestEchoedEnvironment() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let fixtureReports = try XCTUnwrap(manifest["fixtureReports"] as? [[String: Any]])
        let entry = fixtureReports[0]
        let captureID = try XCTUnwrap(entry["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(reportURL)
        report.removeValue(forKey: "observed")
        try updateFixtureReport(
            report,
            captureID: captureID,
            fixture: fixture,
            manifest: &manifest
        )

        let unobserved = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(unobserved.status, 0)
        XCTAssertTrue(unobserved.output.contains("observed environment is missing"), unobserved.output)

        report = try fixtureReport(
            request: try XCTUnwrap(entry["request"] as? [String: Any]),
            captureID: captureID,
            runtimeIdentity: try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any]),
            debugExecutablePath: try XCTUnwrap(capture["debugExecutablePath"] as? String),
            debugExecutableSHA256: try XCTUnwrap(capture["debugExecutableSHA256"] as? String),
            debugBuildProvenance: try ViftyBuildProvenanceReader.read(
                at: fixture.debugExecutable,
                expectedRole: "debug-fixture-app",
                expectedConfiguration: "debug"
            )
        )
        var observed = try XCTUnwrap(report["observed"] as? [String: Any])
        var environment = try XCTUnwrap(observed["environment"] as? [String: Any])
        environment["source"] = "requested-arguments"
        observed["environment"] = environment
        report["observed"] = observed
        try updateFixtureReport(
            report,
            captureID: captureID,
            fixture: fixture,
            manifest: &manifest
        )

        let echoed = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(echoed.status, 0)
        XCTAssertTrue(echoed.output.contains("environment source must be swiftui-environment"), echoed.output)
    }

    func testVerifierRejectsSignatureOnlyPNG() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let entry = visualCells[0]
        let captureID = try XCTUnwrap(entry["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let imageURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        try Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).write(to: imageURL)
        try updateScreenshot(captureID: captureID, fixture: fixture, manifest: &manifest)

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("PNG has no IHDR chunk"), blocked.output)
    }

    func testVerifierRejectsMalformedDecompressedPNGScanlines() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let entry = visualCells[0]
        let captureID = try XCTUnwrap(entry["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let imageURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        try malformedScanlinePNG(width: 780, height: 480).write(to: imageURL)
        try updateScreenshot(captureID: captureID, fixture: fixture, manifest: &manifest)

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("decompressed scanline length"), blocked.output)
    }

    func testVerifierRejectsFullyTransparentAndSolidPNGs() throws {
        let transparentFixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: transparentFixture.root) }
        var transparentManifest = transparentFixture.manifest
        let transparent = try pngFixture(
            width: 780,
            height: 480,
            colorType: 6,
            seed: 201,
            pattern: .transparent
        )
        try replaceScreenshot(
            visualID: "main-780x480-light",
            png: transparent,
            fixture: transparentFixture,
            manifest: &transparentManifest
        )

        let transparentResult = try verify(
            transparentFixture,
            manifest: transparentManifest
        )
        XCTAssertNotEqual(transparentResult.status, 0)
        XCTAssertTrue(
            transparentResult.output.contains("PNG has no visible pixels"),
            transparentResult.output
        )

        let solidFixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: solidFixture.root) }
        var solidManifest = solidFixture.manifest
        let solid = try pngFixture(
            width: 780,
            height: 480,
            colorType: 2,
            seed: 202,
            pattern: .solid
        )
        try replaceScreenshot(
            visualID: "main-780x480-light",
            png: solid,
            fixture: solidFixture,
            manifest: &solidManifest
        )

        let solidResult = try verify(solidFixture, manifest: solidManifest)
        XCTAssertNotEqual(solidResult.status, 0)
        XCTAssertTrue(
            solidResult.output.contains("PNG has fewer than two visible colors"),
            solidResult.output
        )
    }

    func testVerifierRejectsCanonicalPixelDuplicatesAcrossCells() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let first = try pngFixture(
            width: 780,
            height: 480,
            colorType: 6,
            seed: 203,
            filters: [0],
            compressionLevel: Z_BEST_SPEED
        )
        let second = try pngFixture(
            width: 780,
            height: 480,
            colorType: 6,
            seed: 203,
            filters: [4],
            compressionLevel: Z_BEST_COMPRESSION,
            splitIDAT: true
        )
        XCTAssertEqual(first.canonicalPixelSHA256, second.canonicalPixelSHA256)
        XCTAssertNotEqual(
            SHA256.hash(data: first.data),
            SHA256.hash(data: second.data)
        )
        try replaceScreenshot(
            visualID: "main-780x480-light",
            png: first,
            fixture: fixture,
            manifest: &manifest
        )
        try replaceScreenshot(
            visualID: "main-780x480-dark",
            png: second,
            fixture: fixture,
            manifest: &manifest
        )

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("duplicate canonical pixels"), blocked.output)
        XCTAssertTrue(blocked.output.contains("main-780x480-light"), blocked.output)
        XCTAssertTrue(blocked.output.contains("main-780x480-dark"), blocked.output)
    }

    func testVerifierAcceptsUniqueOpaquePatternedPNGsAcrossSupportedColorTypes() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let replacements: [(String, UInt8, Int)] = [
            ("main-780x480-light", 0, 211),
            ("main-780x480-dark", 2, 212),
            ("main-1180x820-light", 4, 213),
            ("main-1180x820-dark", 6, 214)
        ]
        for (visualID, colorType, seed) in replacements {
            let request = try XCTUnwrap(
                (manifest["visualCells"] as? [[String: Any]])?
                    .first { $0["id"] as? String == visualID }?["request"] as? [String: Any]
            )
            let dimensions = try windowDimensions(request)
            let png = try pngFixture(
                width: dimensions.width,
                height: dimensions.height,
                colorType: colorType,
                seed: seed,
                filters: [0, 1, 2, 3, 4]
            )
            try replaceScreenshot(
                visualID: visualID,
                png: png,
                fixture: fixture,
                manifest: &manifest
            )
        }

        let result = try verify(fixture, manifest: manifest)
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testPNGAnalyzerMatchesGoldenFiltersAndNormalizesTransparentRGB() throws {
        let goldenScanlines = Data([
            0, 10, 20, 30, 255, 40, 50, 60, 255,
            1, 11, 21, 31, 255, 30, 30, 30, 0,
            2, 1, 1, 1, 0, 1, 1, 1, 0,
            3, 7, 12, 17, 128, 16, 16, 16, 0,
            4, 1, 1, 1, 0, 1, 1, 1, 0
        ])
        let golden = try pngFromFilteredScanlines(
            width: 2,
            height: 5,
            colorType: 6,
            scanlines: goldenScanlines
        )
        let goldenResult = try runPNGAnalyzer(golden, width: 2, height: 5)
        XCTAssertEqual(goldenResult.status, 0, goldenResult.output)
        let goldenJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(goldenResult.output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            goldenJSON["canonical_pixel_sha256"] as? String,
            "6a633e4b70cad0e5a6a5c2bae5e9e250be94113244a7d2c3249817e490df2684"
        )

        let visible = [
            UInt8(10), 20, 30, 255,
            40, 50, 60, 255
        ]
        let first = try pngFromFilteredScanlines(
            width: 4,
            height: 1,
            colorType: 6,
            scanlines: Data([0] + visible + [1, 2, 3, 0, 4, 5, 6, 0])
        )
        let second = try pngFromFilteredScanlines(
            width: 4,
            height: 1,
            colorType: 6,
            scanlines: Data([0] + visible + [101, 102, 103, 0, 204, 205, 206, 0])
        )
        let firstResult = try runPNGAnalyzer(first, width: 4, height: 1)
        let secondResult = try runPNGAnalyzer(second, width: 4, height: 1)
        XCTAssertEqual(firstResult.status, 0, firstResult.output)
        XCTAssertEqual(secondResult.status, 0, secondResult.output)
        let firstJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(firstResult.output.utf8)) as? [String: Any]
        )
        let secondJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(secondResult.output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            firstJSON["canonical_pixel_sha256"] as? String,
            secondJSON["canonical_pixel_sha256"] as? String
        )
    }

    func testPNGAnalyzerRejectsInvalidFiltersCRCStreamTerminationAndChunkOrdering() throws {
        let validScanline = Data([0, 10, 20, 30, 255, 40, 50, 60, 255])
        let validCompressed = try zlibCompress(validScanline, level: Z_BEST_SPEED)

        let invalidFilter = try pngFromFilteredScanlines(
            width: 2,
            height: 1,
            colorType: 6,
            scanlines: Data([5, 10, 20, 30, 255, 40, 50, 60, 255])
        )
        try assertPNGAnalyzerRejects(
            invalidFilter,
            width: 2,
            height: 1,
            containing: "filter type is invalid"
        )

        var crcBytes = [UInt8](try pngWithIDATPayload(
            width: 2,
            height: 1,
            colorType: 6,
            compressed: validCompressed
        ))
        crcBytes[crcBytes.count - 13] ^= 0x01
        try assertPNGAnalyzerRejects(
            Data(crcBytes),
            width: 2,
            height: 1,
            containing: "checksum mismatch"
        )

        try assertPNGAnalyzerRejects(
            try pngWithIDATPayload(
                width: 2,
                height: 1,
                colorType: 6,
                compressed: validCompressed.dropLast()
            ),
            width: 2,
            height: 1,
            containing: "cannot be decompressed"
        )
        try assertPNGAnalyzerRejects(
            try pngWithIDATPayload(
                width: 2,
                height: 1,
                colorType: 6,
                compressed: validCompressed + Data([0])
            ),
            width: 2,
            height: 1,
            containing: "trailing compressed data"
        )
        try assertPNGAnalyzerRejects(
            try pngWithIDATPayload(
                width: 2,
                height: 1,
                colorType: 6,
                compressed: validCompressed,
                splitWithAncillary: true
            ),
            width: 2,
            height: 1,
            containing: "IDAT chunks must be contiguous"
        )
        try assertPNGAnalyzerRejects(
            try pngWithIDATPayload(
                width: 2,
                height: 1,
                colorType: 6,
                compressed: validCompressed,
                reservedBitChunk: true
            ),
            width: 2,
            height: 1,
            containing: "reserved lowercase bit"
        )
        try assertPNGAnalyzerRejects(
            try pngWithIDATPayload(
                width: 2,
                height: 1,
                colorType: 6,
                compressed: validCompressed
            ) + Data([0]),
            width: 2,
            height: 1,
            containing: "trailing data after IEND"
        )
    }

    func testVerifierFailsClosedForNonFiniteBackingScaleFactor() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let captureID = try XCTUnwrap(visualCells.first?["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var identity = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
        identity["backingScaleFactor"] = "__VIFTY_INFINITY__"
        capture["runtimeIdentity"] = identity

        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(reportURL)
        report["runtimeIdentity"] = identity
        var observed = try XCTUnwrap(report["observed"] as? [String: Any])
        var window = try XCTUnwrap(observed["window"] as? [String: Any])
        window["backingScaleFactor"] = "__VIFTY_INFINITY__"
        observed["window"] = window
        report["observed"] = observed
        try writeJSON(report, to: reportURL)
        try replaceInfinitySentinel(at: reportURL)
        capture["fixtureReportSHA256"] = try sha256(reportURL)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: fixture.manifestURL)
        try replaceInfinitySentinel(at: fixture.manifestURL)

        let blocked = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable
        )
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("backing scale is invalid"), blocked.output)
        XCTAssertFalse(blocked.output.contains("FloatDomainError"), blocked.output)
    }

    func testContractVerifierRejectsLegacyV2AccessibilityReport() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let checks = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        let entry = checks[0]
        let captureID = try XCTUnwrap(entry["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        let identity = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
        let observationPath = "AXApplication[0]/AXWindow[0]/AXGroup[0]"
        let legacyV2Report: [String: Any] = [
            "schemaVersion": 2,
            "id": entry["id"] as Any,
            "status": "passed",
            "request": entry["request"] as Any,
            "provenance": [
                "source": "macos-accessibility-api",
                "captureID": captureID,
                "fixtureReportArtifact": capture["fixtureReportArtifact"] as Any,
                "fixtureReportSHA256": capture["fixtureReportSHA256"] as Any,
                "processIdentifier": identity["processIdentifier"] as Any
            ],
            "observations": [[
                "path": observationPath,
                "role": "AXGroup",
                "label": entry["id"] as Any,
                "value": "observed",
                "actions": ["AXPress"],
                "order": 0
            ]],
            "assertions": [[
                "id": entry["id"] as Any,
                "status": "passed",
                "observationPaths": [observationPath],
                "details": "Validated from the captured macOS accessibility hierarchy."
            ]]
        ]
        try writeJSON(legacyV2Report, to: reportURL)
        try updateAccessibility(captureID: captureID, fixture: fixture, manifest: &manifest)

        let blocked = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(blocked.status, 0)
        XCTAssertTrue(blocked.output.contains("sealed schemaVersion must be 1"), blocked.output)
        XCTAssertTrue(blocked.output.contains("sealed schema ID mismatch"), blocked.output)
        XCTAssertFalse(blocked.output.contains("accessibility report schemaVersion must be 2"), blocked.output)
    }

    func testVerifierRejectsDebugFixtureMarkerInReleaseBinary() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        let handle = try FileHandle(forWritingTo: fixture.releaseBinary)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" release --ui-review-fixture marker".utf8))
        try handle.close()
        var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        release["sha256"] = try sha256(fixture.releaseBinary)
        manifest["releaseExclusion"] = release
        try writeJSON(manifest, to: fixture.manifestURL)

        let result = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("release binary contains debug fixture marker"), result.output)
    }

    func testVerifierRejectsMarkerFreeFakeDataAndNonExecutableMachOReleaseArtifacts() throws {
        do {
            let fixture = try populatedFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            var manifest = fixture.manifest
            try Data("marker-free but not executable object code".utf8).write(to: fixture.releaseBinary)
            var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
            release["sha256"] = try sha256(fixture.releaseBinary)
            manifest["releaseExclusion"] = release

            let rejected = try verify(fixture, manifest: manifest)
            XCTAssertNotEqual(rejected.status, 0)
            XCTAssertTrue(rejected.output.contains("release binary is not a Mach-O executable"), rejected.output)
        }

        do {
            let fixture = try populatedFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: fixture.releaseBinary.path
            )

            let rejected = try verify(fixture)
            XCTAssertNotEqual(rejected.status, 0)
            XCTAssertTrue(rejected.output.contains("release binary is not executable"), rejected.output)
        }
    }

    func testVerifierRejectsReleaseManifestMarkerAndBinaryPathDrift() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var manifest = fixture.manifest
        var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        release["binary"] = "release/Vifty"
        release["forbiddenMarkers"] = ["ViftyReviewFixture", "--ui-review-fixture"]
        manifest["releaseExclusion"] = release

        let rejected = try verify(fixture, manifest: manifest)
        XCTAssertNotEqual(rejected.status, 0)
        XCTAssertTrue(
            rejected.output.contains(
                "release exclusion binary must be .build/ui-review-products/release/Vifty"
            ),
            rejected.output
        )
        XCTAssertTrue(rejected.output.contains("authoritative marker set"), rejected.output)
    }

    func testVerifierRejectsWrongDebugExecutableAndReleaseCallerPath() throws {
        let fixture = try populatedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let wrongRelease = fixture.root.appendingPathComponent("alternate/Vifty")
        try FileManager.default.createDirectory(
            at: wrongRelease.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.releaseBinary, to: wrongRelease)

        let wrongReleaseResult = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: wrongRelease,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable
        )
        XCTAssertNotEqual(wrongReleaseResult.status, 0)
        XCTAssertTrue(wrongReleaseResult.output.contains("release binary path does not match"), wrongReleaseResult.output)

        let wrongDebugResult = try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.releaseBinary,
            collectorExecutable: fixture.collectorExecutable
        )
        XCTAssertNotEqual(wrongDebugResult.status, 0)
        XCTAssertTrue(wrongDebugResult.output.contains("debug executable path mismatch"), wrongDebugResult.output)
    }

    private enum FakeFixtureMode {
        case successful
        case immediateExit
        case readyTimeout
        case readyTimeoutWithSurvivingChild
        case reportedFailure
    }

    private struct OrchestrationFixture {
        var root: URL
        var evidence: URL
        var manifest: URL
        var debugExecutable: URL
    }

    private func orchestrationFixture(mode: FakeFixtureMode) throws -> OrchestrationFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-ui-review-orchestration-tests-\(UUID().uuidString)", isDirectory: true)
        let evidence = root.appendingPathComponent("evidence", isDirectory: true)
        let manifest = root.appendingPathComponent("evidence-manifest.json")
        let debugDirectory = root.appendingPathComponent("debug", isDirectory: true)
        let debugExecutable = debugDirectory.appendingPathComponent("Vifty")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("docs/ui-review/evidence-manifest.json"),
            to: manifest
        )

        let script: String
        switch mode {
        case .immediateExit:
            script = #"""
            #!/usr/bin/ruby
            exit 0
            """#
        case .readyTimeout:
            script = #"""
            #!/usr/bin/ruby
            # --ui-review-fixture --ui-review-capture-id --ui-review-output
            require "fileutils"
            options = {}
            ARGV.each_slice(2) { |key, value| options[key] = value }
            output = options.fetch("--ui-review-output")
            FileUtils.mkdir_p(output)
            File.write(
              File.join(output, "window-capture-00000000-0000-0000-0000-000000000000.png"),
              "partial full-window capture"
            )
            marker = File.join(__dir__, "terminated")
            Signal.trap("TERM") do
              File.write(marker, Process.pid.to_s)
              exit 0
            end
            loop { sleep 0.05 }
            """#
        case .readyTimeoutWithSurvivingChild:
            script = #"""
            #!/usr/bin/ruby
            # --ui-review-fixture --ui-review-capture-id --ui-review-output
            require "fileutils"
            options = {}
            ARGV.each_slice(2) { |key, value| options[key] = value }
            output = options.fetch("--ui-review-output")
            FileUtils.mkdir_p(output)
            child_pid = fork do
              Signal.trap("TERM", "IGNORE")
              sleep 0.7
              File.write(
                File.join(output, "window-capture-11111111-1111-1111-1111-111111111111.png"),
                "late partial full-window capture"
              )
              loop { sleep 0.05 }
            end
            File.write(File.join(__dir__, "child-pid"), child_pid.to_s)
            Signal.trap("TERM") { exit 0 }
            loop { sleep 0.05 }
            """#
        case .reportedFailure:
            script = #"""
            #!/usr/bin/ruby
            require "fileutils"
            require "json"
            options = {}
            ARGV.each_slice(2) { |key, value| options[key] = value }
            output = options.fetch("--ui-review-output")
            FileUtils.mkdir_p(output)
            File.write(
              File.join(output, "fixture-report.json"),
              JSON.pretty_generate({
                "phase" => "final",
                "runtimeFailure" => "synthetic observation failure"
              })
            )
            Signal.trap("TERM") { exit 0 }
            loop { sleep 0.05 }
            """#
        case .successful:
            let png = try pngFixture(width: 1_180, height: 820, colorType: 6, seed: 701)
            try png.data.write(to: debugDirectory.appendingPathComponent("source.png"))
            script = #"""
            #!/usr/bin/ruby
            require "digest"
            require "fileutils"
            require "json"

            options = {}
            index = 0
            while index < ARGV.length
              key = ARGV.fetch(index)
              value = ARGV[index + 1]
              options[key] = value
              index += 2
            end

            output = options.fetch("--ui-review-output")
            capture_id = options.fetch("--ui-review-capture-id")
            completion = options.fetch("--ui-review-completion-file")
            FileUtils.mkdir_p(output)
            executable = ENV.fetch("VIFTY_FAKE_EXECUTABLE")
            fixture_pid = Integer(ENV.fetch("VIFTY_FAKE_PROCESS_IDENTIFIER"))
            executable_sha = Digest::SHA256.file(executable).hexdigest
            embedded_build_provenance = JSON.parse(
              File.read(File.join(__dir__, "provenance.json"))
            )
            request = {
              "appearance" => options.fetch("--ui-review-appearance"),
              "contrast" => options.fetch("--ui-review-contrast"),
              "interaction" => options.fetch("--ui-review-interaction"),
              "state" => options.fetch("--ui-review-fixture"),
              "surface" => options.fetch("--ui-review-surface"),
              "textSize" => options.fetch("--ui-review-text-size"),
              "transparency" => options.fetch("--ui-review-transparency"),
              "window" => options.fetch("--ui-review-window")
            }
            request_sha = Digest::SHA256.hexdigest(JSON.generate(request.sort.to_h))
            width, height = case request.fetch("window")
                            when "native" then [600, 420]
                            when "320xauto" then [320, 360]
                            else request.fetch("window").split("x", 2).map(&:to_i)
                            end
            provenance, container = case request.fetch("surface")
                                    when "main" then ["swiftui-main-window", "main-window"]
                                    when "menu-popover" then ["ns-popover-status-item", "popover"]
                                    else ["swiftui-settings-scene", "settings-window"]
                                    end
            identity = {
              "processIdentifier" => fixture_pid,
              "executablePath" => executable,
              "executableSHA256" => executable_sha,
              "windowIdentifier" => "vifty-ui-review-window-#{capture_id}",
              "accessibilityIdentifier" => "vifty-ui-review-ax-window-#{capture_id}",
              "windowNumber" => fixture_pid + 100,
              "windowClass" => "NSWindow",
              "containerKind" => container,
              "provenance" => provenance,
              "isVisible" => true,
              "contentWidth" => width,
              "contentHeight" => height,
              "backingScaleFactor" => 1
            }
            screenshot = nil
            if options["--ui-review-screenshot"]
              screenshot_path = options.fetch("--ui-review-screenshot")
              FileUtils.cp(File.join(__dir__, "source.png"), screenshot_path)
              screenshot = {
                "method" => "native-window-screencapture-crop",
                "artifactPath" => File.basename(screenshot_path),
                "sha256" => Digest::SHA256.file(screenshot_path).hexdigest,
                "pointWidth" => width,
                "pointHeight" => height,
                "pixelWidth" => width,
                "pixelHeight" => height,
                "backingScaleFactor" => 1
              }
            end
            report = {
              "schemaVersion" => 3,
              "captureID" => capture_id,
              "request" => request,
              "requestSHA256" => request_sha,
              "debugExecutablePath" => executable,
              "debugExecutableSHA256" => executable_sha,
              "debugBuildProvenance" => embedded_build_provenance,
              "runtimeIdentity" => identity,
              "observed" => {
                "environment" => {
                  "source" => "swiftui-environment",
                  "appearance" => request.fetch("appearance"),
                  "contrast" => request.fetch("contrast"),
                  "transparency" => request.fetch("transparency"),
                  "textSize" => request.fetch("textSize")
                },
                "window" => identity.merge("source" => "nswindow-content-layout-rect").reject do |key, _|
                  ["processIdentifier", "executablePath", "executableSHA256"].include?(key)
                end
              },
              "screenshot" => screenshot,
              "phase" => "ready",
              "modelStartSkipped" => true,
              "recorder" => {
                "fixtureConstructions" => %w[hardware notification-center login-item helper-installer daemon-client power-client],
                "readOperations" => %w[notification-authorization login-item-status hardware-snapshot fan-control-ownership power thermal-pressure daemon-ping agent-status],
                "attemptedHardwareCommands" => [],
                "attemptedExternalMutations" => [],
                "realControlPathConstructions" => []
              },
              "runtimeFailure" => nil,
              "launchArguments" => ARGV,
              "passed" => true
            }
            report_path = File.join(output, "fixture-report.json")
            write_report = lambda do
              temporary = "#{report_path}.tmp"
              File.write(temporary, JSON.pretty_generate(report))
              File.rename(temporary, report_path)
            end
            write_report.call
            Signal.trap("TERM") { exit 0 }
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(options.fetch("--ui-review-timeout-seconds"))
            until File.exist?(completion)
              exit 70 if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              sleep 0.02
            end
            report["phase"] = "final"
            write_report.call
            """#
        }

        try compileProvenanceRubyLauncher(
            script: script,
            directory: debugDirectory,
            executable: debugExecutable,
            role: "debug-fixture-app"
        )
        var boundManifest = try readJSON(manifest)
        var releaseExclusion = try XCTUnwrap(
            boundManifest["releaseExclusion"] as? [String: Any]
        )
        releaseExclusion["status"] = "passed"
        releaseExclusion["sha256"] = String(repeating: "d", count: 64)
        releaseExclusion["buildProvenance"] = try jsonObject(
            TestBuildProvenance.identity(role: "release-exclusion")
        )
        boundManifest["releaseExclusion"] = releaseExclusion
        try writeJSON(boundManifest, to: manifest)
        return OrchestrationFixture(
            root: root,
            evidence: evidence,
            manifest: manifest,
            debugExecutable: debugExecutable
        )
    }

    private func resetVisualRowForSealTesting(manifestURL: URL, rowID: String) throws {
        var manifest = try readJSON(manifestURL)
        var rows = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let rowIndex = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == rowID })
        let previousCaptureID = rows[rowIndex]["captureID"] as? String
        rows[rowIndex]["status"] = "pending"
        rows[rowIndex]["captureID"] = NSNull()
        manifest["visualCells"] = rows

        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        if let previousCaptureID {
            ledger.removeValue(forKey: previousCaptureID)
        }
        manifest["captureLedger"] = ledger
        try writeJSON(manifest, to: manifestURL)
    }

    private func permissionBlockedCollector(in root: URL) throws -> URL {
        let directory = root.appendingPathComponent("collector", isDirectory: true)
        let collector = directory.appendingPathComponent("ViftyAXCollector")
        let script = #"""
        #!/usr/bin/ruby
        require "fileutils"
        require "json"
        options = {}
        ARGV.drop(1).each_slice(2) { |key, value| options[key] = value }
        timeout = Float(options.fetch("--timeout-seconds"))
        exit 64 unless timeout >= 0.1 && timeout <= 10.0
        output = options.fetch("--output")
        FileUtils.mkdir_p(File.dirname(output))
        document = {
          "schemaVersion" => 1,
          "status" => "blocked",
          "error" => { "code" => "AX_PERMISSION_MISSING" },
          "promptRequested" => false
        }
        File.write(output, JSON.generate(document))
        STDOUT.write(JSON.generate(document))
        exit 77
        """#
        try compileProvenanceRubyLauncher(
            script: script,
            directory: directory,
            executable: collector,
            role: "ax-collector"
        )
        return collector
    }

    private func slowSuccessfulCollector(in root: URL, delay: Double) throws -> URL {
        let directory = root.appendingPathComponent("slow-collector", isDirectory: true)
        let collector = directory.appendingPathComponent("ViftyAXCollector")
        let script = #"""
        #!/usr/bin/ruby
        require "json"
        options = {}
        ARGV.drop(1).each_slice(2) { |key, value| options[key] = value }
        timeout = Float(options.fetch("--timeout-seconds"))
        exit 64 unless timeout >= 0.1 && timeout <= 10.0
        sleep \#(delay)
        embedded_build_provenance = JSON.parse(
          File.read(File.join(__dir__, "provenance.json"))
        )
        File.write(
          options.fetch("--output"),
          JSON.generate({
            "synthetic" => true,
            "collectorBuildProvenance" => embedded_build_provenance
          })
        )
        exit 0
        """#
        try compileProvenanceRubyLauncher(
            script: script,
            directory: directory,
            executable: collector,
            role: "ax-collector"
        )
        return collector
    }

    private func compileProvenanceRubyLauncher(
        script: String,
        directory: URL,
        executable: URL,
        role: String
    ) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let fixtureScript = directory.appendingPathComponent("fixture.rb")
        let provenanceFile = directory.appendingPathComponent("provenance.json")
        let launcherSource = directory.appendingPathComponent("launcher.c")
        try Data(script.utf8).write(to: fixtureScript)
        try TestBuildProvenance.identity(role: role).canonicalData.write(to: provenanceFile)
        try Data(
            #"""
            #include <errno.h>
            #include <limits.h>
            #include <signal.h>
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>
            #include <sys/wait.h>
            #include <unistd.h>

            static pid_t child_pid = -1;

            static void forward_signal(int signal_number) {
                if (child_pid > 0) {
                    (void)kill(child_pid, signal_number);
                }
            }

            int main(int argc, char **argv) {
                char executable_path[PATH_MAX];
                if (realpath(argv[0], executable_path) == NULL) {
                    return 126;
                }
                char directory[PATH_MAX];
                if (snprintf(directory, sizeof(directory), "%s", executable_path) < 0) {
                    return 126;
                }
                char *separator = strrchr(directory, '/');
                if (separator == NULL) {
                    return 126;
                }
                *separator = '\0';
                char script_path[PATH_MAX];
                if (snprintf(script_path, sizeof(script_path), "%s/fixture.rb", directory) >= (int)sizeof(script_path)) {
                    return 126;
                }
                char process_identifier[32];
                (void)snprintf(process_identifier, sizeof(process_identifier), "%d", getpid());
                if (setenv("VIFTY_FAKE_EXECUTABLE", executable_path, 1) != 0 ||
                    setenv("VIFTY_FAKE_PROCESS_IDENTIFIER", process_identifier, 1) != 0) {
                    return 126;
                }

                char **child_arguments = calloc((size_t)argc + 2, sizeof(char *));
                if (child_arguments == NULL) {
                    return 126;
                }
                child_arguments[0] = "/usr/bin/ruby";
                child_arguments[1] = script_path;
                for (int index = 1; index < argc; index += 1) {
                    child_arguments[index + 1] = argv[index];
                }
                child_arguments[argc + 1] = NULL;

                child_pid = fork();
                if (child_pid < 0) {
                    return 126;
                }
                if (child_pid == 0) {
                    execv(child_arguments[0], child_arguments);
                    _exit(126);
                }
                (void)signal(SIGTERM, forward_signal);
                (void)signal(SIGINT, forward_signal);
                int status = 0;
                while (waitpid(child_pid, &status, 0) < 0) {
                    if (errno != EINTR) {
                        return 126;
                    }
                }
                if (WIFEXITED(status)) {
                    return WEXITSTATUS(status);
                }
                if (WIFSIGNALED(status)) {
                    return 128 + WTERMSIG(status);
                }
                return 126;
            }
            """#.utf8
        ).write(to: launcherSource)
        let compile = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [
                launcherSource.path,
                "-o", executable.path,
                "-Wl,-sectcreate,__TEXT,__vifty_src,\(provenanceFile.path)"
            ],
            currentDirectory: directory
        )
        guard compile.status == 0 else {
            throw NSError(
                domain: "UIReviewEvidenceScriptTests",
                code: Int(compile.status),
                userInfo: [NSLocalizedDescriptionKey: compile.output]
            )
        }
    }

    private func runOrchestrator(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/run-ui-review-fixture.sh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output, as: UTF8.self)
        )
    }

    private func terminateHeldCaptures(in evidence: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: evidence,
            includingPropertiesForKeys: nil
        ) else { return }
        for case let url as URL in enumerator where url.lastPathComponent == "session.json" {
            let completion = url.deletingLastPathComponent().appendingPathComponent("completion.signal")
            FileManager.default.createFile(atPath: completion.path, contents: Data())
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    private func installValidAttestations(
        fixture: PopulatedFixture,
        manifest: inout [String: Any]
    ) throws {
        var human = try XCTUnwrap(manifest["humanAttestations"] as? [String: Any])
        let ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        let configurations: [(binding: String, method: String, rowsKey: String, steps: [String])] = [
            (
                "visual",
                "visual-inspection",
                "visualCells",
                ["clipping", "overlap", "legibility", "hierarchy", "transient-state"]
            ),
            (
                "voiceOver",
                "voiceover-session",
                "accessibilityChecks",
                [
                    "spoken-labels-values",
                    "focus-movement",
                    "rotor-grouping",
                    "adjustable-controls",
                    "buttons",
                    "scroll-reachability",
                    "safe-action-announcements"
                ]
            )
        ]

        for configuration in configurations {
            let rows = try XCTUnwrap(manifest[configuration.rowsKey] as? [[String: Any]])
            let idKey = configuration.rowsKey == "visualCells" ? "id" : "id"
            let sortedRows = rows.sorted {
                ($0[idKey] as? String ?? "") < ($1[idKey] as? String ?? "")
            }
            let coveredRowIDs = try sortedRows.map { try XCTUnwrap($0[idKey] as? String) }
            let captureBindings: [[String: Any]] = try sortedRows.map { row in
                let rowID = try XCTUnwrap(row[idKey] as? String)
                let captureID = try XCTUnwrap(row["captureID"] as? String)
                let capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
                let screenshot = capture["screenshot"] as? [String: Any]
                let accessibility = capture["accessibility"] as? [String: Any]
                return [
                    "rowID": rowID,
                    "captureID": captureID,
                    "requestSHA256": capture["requestSHA256"] as Any,
                    "debugExecutableSHA256": capture["debugExecutableSHA256"] as Any,
                    "fixtureReportSHA256": capture["fixtureReportSHA256"] as Any,
                    "screenshotSHA256": screenshot?["sha256"] ?? NSNull(),
                    "screenshotCanonicalPixelSHA256": screenshot?["canonicalPixelSHA256"] ?? NSNull(),
                    "accessibilityRawSHA256": accessibility?["rawSHA256"] ?? NSNull(),
                    "accessibilitySealedSHA256": accessibility?["sha256"] ?? NSNull()
                ]
            }
            let stepRows: [String: [String]] = configuration.method == "voiceover-session"
                ? Dictionary(uniqueKeysWithValues: voiceOverStepRowIDs.map { ($0.id, $0.rowIDs) })
                : [:]
            let observations: [String: String] = [
                "clipping": "Reviewed every bound screenshot; no controls, labels, or values were clipped.",
                "overlap": "Reviewed every bound screenshot; no controls, labels, or values overlapped.",
                "legibility": "Reviewed every bound screenshot; text and state indicators remained legible.",
                "hierarchy": "Reviewed every bound screenshot; visual hierarchy matched the represented state.",
                "transient-state": "Reviewed every bound screenshot; transient state copy and controls were coherent.",
                "spoken-labels-values": "VoiceOver announced the bound headlines, targets, temperatures, chart points, actions, and displayed values.",
                "focus-movement": "VoiceOver focus moved through the bound chart, sensor, notification, and Settings controls in a coherent order.",
                "rotor-grouping": "VoiceOver rotor and group navigation exposed the session headline, chart, and Settings groups without duplicate chart content.",
                "adjustable-controls": "VoiceOver announced all six curve points as adjustable; no adjustable was invoked and no fan-control action occurred.",
                "buttons": "VoiceOver named the bound sensor, notification, and Settings buttons; this announcement-only step activated none of them.",
                "scroll-reachability": "VoiceOver navigation reached each bound compact-main and Settings end anchor at Accessibility text size.",
                "safe-action-announcements": "Activated only General, Menu Bar, Notifications, Agent Workflows, then General; VoiceOver announced each selected section."
            ]
            let steps: [[String: Any]] = configuration.steps.map { step in
                [
                    "id": step,
                    "status": "passed",
                    "coveredRowIDs": stepRows[step] ?? coveredRowIDs,
                    "notes": observations[step]!
                ]
            }
            var attestation: [String: Any] = [
                "schemaVersion": 1,
                "method": configuration.method,
                "reviewer": "Fixture Reviewer",
                "reviewedAt": "2026-07-15T00:00:00Z",
                "coveredRowIDs": coveredRowIDs,
                "captureBindings": captureBindings,
                "steps": steps,
                "overallStatus": "passed"
            ]
            if configuration.method == "voiceover-session" {
                attestation["actionSequence"] = [
                    "settings-general",
                    "settings-menu-bar",
                    "settings-notifications",
                    "settings-agent-workflows",
                    "settings-general"
                ]
                attestation["inspectOnlyControlGroups"] = [
                    "curve-point-adjustables",
                    "notification-actions",
                    "sensor-buttons"
                ]
                attestation["disallowedActionsPerformed"] = [String]()
            }
            let artifact = "attestations/\(configuration.binding == "visual" ? "visual" : "voiceover")-attestation.json"
            let artifactURL = fixture.evidence.appendingPathComponent(artifact)
            try writeJSON(attestation, to: artifactURL)
            human[configuration.binding] = [
                "status": "passed",
                "artifact": artifact,
                "sha256": try sha256(artifactURL)
            ]
        }
        manifest["humanAttestations"] = human
    }

    private var voiceOverStepRowIDs: [(id: String, rowIDs: [String])] {
        [
            (
                "spoken-labels-values",
                [
                    "confirmed-owner-headline",
                    "correct-per-fan-target",
                    "explicit-temperature-role",
                    "no-duplicate-chart-elements",
                    "notification-actions",
                    "sensor-selected-trait-value",
                    "settings-logical-traversal",
                    "six-adjustable-point-controls"
                ]
            ),
            (
                "focus-movement",
                [
                    "no-duplicate-chart-elements",
                    "notification-actions",
                    "sensor-selected-trait-value",
                    "settings-logical-traversal",
                    "six-adjustable-point-controls"
                ]
            ),
            (
                "rotor-grouping",
                [
                    "confirmed-owner-headline",
                    "no-duplicate-chart-elements",
                    "settings-logical-traversal"
                ]
            ),
            ("adjustable-controls", ["six-adjustable-point-controls"]),
            (
                "buttons",
                [
                    "notification-actions",
                    "sensor-selected-trait-value",
                    "settings-logical-traversal"
                ]
            ),
            (
                "scroll-reachability",
                [
                    "compact-main-scroll-reachable",
                    "settings-agent-workflows-scroll-reachable",
                    "settings-general-scroll-reachable",
                    "settings-menu-bar-scroll-reachable",
                    "settings-notifications-scroll-reachable"
                ]
            ),
            ("safe-action-announcements", ["settings-logical-traversal"])
        ]
    }

    private func installSealedAccessibilityEvidence(
        fixture: PopulatedFixture,
        manifest: inout [String: Any]
    ) throws {
        let debugBuildProvenance = try ViftyBuildProvenanceReader.read(
            at: fixture.debugExecutable,
            expectedRole: "debug-fixture-app",
            expectedConfiguration: "debug"
        )
        let collectorBuildProvenance = try ViftyBuildProvenanceReader.read(
            at: fixture.collectorExecutable,
            expectedRole: "ax-collector",
            expectedConfiguration: "debug"
        )
        let rows = try XCTUnwrap(manifest["accessibilityChecks"] as? [[String: Any]])
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        for row in rows {
            let rowID = try XCTUnwrap(row["id"] as? String)
            let captureID = try XCTUnwrap(row["captureID"] as? String)
            let semanticRequest = try XCTUnwrap(row["request"] as? [String: Any])
            var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
            let identity = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
            let processIdentifier = try XCTUnwrap(identity["processIdentifier"] as? Int)
            let windowIdentifier = try XCTUnwrap(identity["accessibilityIdentifier"] as? String)
            let expectedRequest = try XCTUnwrap(AXPredicateCatalog.expectedRequest(for: rowID))
            let expectedRequestJSON = try XCTUnwrap(
                JSONSerialization.jsonObject(with: AXCanonicalJSON.data(expectedRequest)) as? NSDictionary
            )
            XCTAssertEqual(expectedRequestJSON, semanticRequest as NSDictionary, rowID)
            let raw = try validAXCapture(
                id: rowID,
                captureID: captureID,
                processIdentifier: Int32(processIdentifier),
                windowIdentifier: windowIdentifier,
                collectorBuildProvenance: collectorBuildProvenance
            )
            let rawArtifact = "ax/\(rowID)-raw.json"
            let rawURL = fixture.evidence.appendingPathComponent(rawArtifact)
            try FileManager.default.createDirectory(
                at: rawURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try AXCanonicalJSON.data(raw).write(to: rawURL)
            let rawSHA = try sha256(rawURL)
            let fixtureArtifact = try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
            let fixtureURL = fixture.evidence.appendingPathComponent(fixtureArtifact)
            let assertion = try AXPredicateCatalog.evaluate(id: rowID, capture: raw)
            XCTAssertTrue(assertion.passed, "\(rowID): \(assertion.failures)")
            let fixtureSHA = try XCTUnwrap(capture["fixtureReportSHA256"] as? String)
            let executableSHA = try XCTUnwrap(capture["debugExecutableSHA256"] as? String)
            let sealed = AXSealedReport(
                request: raw.request,
                rawCapture: AXArtifactBinding(artifact: rawURL.path, sha256: rawSHA),
                fixtureReport: AXArtifactBinding(artifact: fixtureURL.path, sha256: fixtureSHA),
                debugExecutableSHA256: executableSHA,
                debugBuildProvenance: debugBuildProvenance,
                collectorBuildProvenance: collectorBuildProvenance,
                runtimeIdentity: raw.finalTarget,
                assertion: assertion,
                actionsPerformed: []
            )
            let sealedArtifact = "ax/\(rowID)-sealed.json"
            let sealedURL = fixture.evidence.appendingPathComponent(sealedArtifact)
            try AXCanonicalJSON.data(sealed).write(to: sealedURL)
            capture["accessibility"] = [
                "rawArtifact": rawArtifact,
                "rawSHA256": rawSHA,
                "artifact": sealedArtifact,
                "sha256": try sha256(sealedURL),
                "collectorExecutablePath": try canonicalFilesystemPath(fixture.collectorExecutable),
                "collectorExecutableSHA256": try sha256(fixture.collectorExecutable),
                "collectorBuildProvenance": try jsonObject(collectorBuildProvenance)
            ]
            ledger[captureID] = capture
        }
        manifest["captureLedger"] = ledger
    }

    private func validAXCapture(
        id: String,
        captureID: String,
        processIdentifier: Int32,
        windowIdentifier: String,
        collectorBuildProvenance: ViftyBuildProvenance
    ) throws -> AXRawCapture {
        let semanticRequest = try XCTUnwrap(AXPredicateCatalog.expectedRequest(for: id))
        let request = AXEvidenceRequest(
            checkID: id,
            captureID: captureID,
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier,
            rootIdentifier: "vifty.ax.fixture.root.\(captureID)",
            semanticRequest: semanticRequest
        )
        let target = AXTargetIdentity(
            processIdentifier: processIdentifier,
            windowIdentifier: windowIdentifier,
            rootIdentifier: request.rootIdentifier
        )
        let fixture: (observations: [AXObservation], scroll: [AXScrollEvidence])
        switch id {
        case "confirmed-owner-headline":
            fixture = ([
                axObservation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.controlSession),
                axObservation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.controlSessionTitle, label: "Vifty manual control active"),
                axObservation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.controlSessionSummary, label: "Owner: Vifty manual control")
            ], [])
        case "correct-per-fan-target":
            fixture = ([
                axObservation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.fanStatus),
                axObservation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.leftFanDraftTarget, label: "Left Fan draft target", value: "Draft 2493 RPM"),
                axObservation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.rightFanDraftTarget, label: "Right Fan draft target", value: "Draft 3080 RPM")
            ], [])
        case "six-adjustable-point-controls", "no-duplicate-chart-elements":
            let labelsAndValues = [
                ("Start temperature", "55 °C"),
                ("Start RPM", "1200 RPM"),
                ("Ramp temperature", "70 °C"),
                ("Ramp RPM", "3500 RPM"),
                ("High temperature", "85 °C"),
                ("High RPM", "6200 RPM")
            ]
            let controls = zip(AXEvidenceIdentifier.curveControls, labelsAndValues).enumerated().map {
                offset, pair in
                axObservation(
                    offset + 2,
                    "1/\(offset)",
                    role: "AXSlider",
                    identifier: pair.0,
                    label: pair.1.0,
                    value: AXTypedValue.string(pair.1.1),
                    actions: ["AXIncrement", "AXDecrement"]
                )
            }
            let summaries = [
                axObservation(
                    8,
                    "2/0",
                    role: "AXStaticText",
                    identifier: AXEvidenceIdentifier.leftFanEffectiveSummary,
                    label: "Left Fan effective curve",
                    value: "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5700 RPM"
                ),
                axObservation(
                    9,
                    "2/1",
                    role: "AXStaticText",
                    identifier: AXEvidenceIdentifier.rightFanEffectiveSummary,
                    label: "Right Fan effective curve",
                    value: "Start 55 °C, 2100 RPM; Ramp 70 °C, 4200 RPM; High 85 °C, 6400 RPM"
                )
            ]
            fixture = ([
                axObservation(
                    0,
                    "0",
                    role: "AXCheckBox",
                    identifier: AXEvidenceIdentifier.curveSeparateFans,
                    label: "Separate fan curves",
                    selected: true,
                    actions: ["AXPress"],
                    position: AXPoint(x: 120, y: 180),
                    size: AXSize(width: 200, height: 22)
                ),
                axObservation(
                    1,
                    "1",
                    role: "AXGroup",
                    identifier: AXEvidenceIdentifier.curveChart,
                    position: AXPoint(x: 100, y: 220),
                    size: AXSize(width: 600, height: 300)
                )
            ] + controls + [
                axObservation(
                    8,
                    "2",
                    role: "AXGroup",
                    identifier: AXEvidenceIdentifier.curveEffectiveSummaries,
                    position: AXPoint(x: 100, y: 540),
                    size: AXSize(width: 600, height: 44)
                )
            ] + summaries, [])
        case "sensor-selected-trait-value":
            fixture = ([
                axObservation(0, "0", role: "AXOpaqueProviderGroup", identifier: AXEvidenceIdentifier.sensorList, actions: ["AXScrollToBottom", "AXScrollToTop"]),
                axObservation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.sensorCPU, label: "CPU Efficiency", value: "64.0 degrees Celsius, SMC", selected: true, actions: ["AXPress", "AXScrollToVisible"]),
                axObservation(2, "0/1", role: "AXButton", identifier: AXEvidenceIdentifier.sensorGPU, label: "GPU Hotspot", value: "83.0 degrees Celsius, HID", actions: ["AXPress", "AXScrollToVisible"]),
                axObservation(3, "0/2", role: "AXButton", identifier: AXEvidenceIdentifier.sensorPalm, label: "Palm Rest", value: "37.0 degrees Celsius, HID", actions: ["AXPress", "AXScrollToVisible"])
            ], [])
        case "explicit-temperature-role":
            fixture = ([
                axObservation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.temperatureMetrics),
                axObservation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.curveSensorMetric, label: "Curve sensor", value: "Curve sensor · CPU Efficiency"),
                axObservation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.highestTemperatureMetric, label: "Highest temperature", value: "Highest 83.0 °C")
            ], [])
        case "notification-actions":
            let labels = [
                "Helper failure",
                "High thermal pressure",
                "Auto restore failure",
                "Plugged-in battery drain",
                "Agent cooling attention"
            ]
            let events = zip(AXEvidenceIdentifier.notificationEvents, labels).enumerated().map {
                offset, pair in
                axObservation(
                    offset + 2,
                    "0/\(offset + 1)",
                    role: "AXCheckBox",
                    identifier: pair.0,
                    label: pair.1,
                    selected: true,
                    actions: ["AXPress"]
                )
            }
            fixture = ([
                axObservation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.notifications),
                axObservation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.notificationOpenSettings, label: "Open Notification Settings", actions: ["AXPress"])
            ] + events, [])
        case "settings-logical-traversal":
            fixture = ([
                axObservation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.settingsTabs, label: "Settings sections"),
                axObservation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabGeneral, label: "General", value: .string("Selected"), selected: true, actions: ["AXPress"]),
                axObservation(2, "0/1", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabMenuBar, label: "Menu Bar", value: .string("Not selected"), actions: ["AXPress"]),
                axObservation(3, "0/2", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabNotifications, label: "Notifications", value: .string("Not selected"), actions: ["AXPress"]),
                axObservation(4, "0/3", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabAgentWorkflows, label: "Agent Workflows", value: .string("Not selected"), actions: ["AXPress"]),
                axObservation(5, "1", role: "AXGroup", identifier: AXEvidenceIdentifier.settingsPaneGeneral, label: "General settings"),
                axObservation(6, "1/0", role: "AXCheckBox", identifier: AXEvidenceIdentifier.settingsUpdateAutomatic, label: "Automatically check for updates", selected: true, actions: ["AXPress"], position: AXPoint(x: 130, y: 160), size: AXSize(width: 300, height: 22)),
                axObservation(7, "1/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.settingsUpdateStatus, label: "Vifty 1.3.3 is available.", position: AXPoint(x: 130, y: 190), size: AXSize(width: 300, height: 18)),
                axObservation(8, "1/2", role: "AXButton", identifier: AXEvidenceIdentifier.settingsUpdateLatest, label: "Update to latest version", help: "Opens Vifty's fixed GitHub release page in your default browser. Vifty does not download or install the update.", actions: ["AXPress"], position: AXPoint(x: 130, y: 220), size: AXSize(width: 190, height: 28)),
                axObservation(9, "1/3", role: "AXButton", identifier: AXEvidenceIdentifier.settingsUpdateCheck, label: "Check now", help: "Refreshes GitHub release availability without downloading or installing.", actions: ["AXPress"], position: AXPoint(x: 330, y: 220), size: AXSize(width: 90, height: 28)),
                axObservation(10, "1/4", role: "AXCheckBox", identifier: AXEvidenceIdentifier.settingsLaunchAtLogin, label: "Start Vifty at startup", selected: false, actions: ["AXPress"], position: AXPoint(x: 130, y: 360), size: AXSize(width: 250, height: 22))
            ], [])
        default:
            let contract = try XCTUnwrap(AXPredicateCatalog.scrollContract(for: id))
            fixture = ([
                axObservation(
                    0,
                    "0",
                    role: "AXScrollArea",
                    identifier: contract.scrollIdentifier,
                    actions: ["AXScrollDownByPage", "AXScrollUpByPage"],
                    position: AXPoint(x: 100, y: 100),
                    size: AXSize(width: 600, height: 420)
                ),
                axObservation(
                    1,
                    "0/0",
                    role: "AXStaticText",
                    identifier: contract.anchorIdentifier,
                    label: "End of content",
                    position: AXPoint(x: 100, y: 700),
                    size: AXSize(width: 100, height: 20)
                ),
                axObservation(
                    2,
                    "0/@vertical",
                    role: "AXScrollBar",
                    identifier: "\(contract.scrollIdentifier).vertical",
                    value: .number(0)
                )
            ], [
                AXScrollEvidence(
                    scrollAreaPath: "0",
                    verticalScrollBarPath: "0/@vertical",
                    minimumValue: 0,
                    maximumValue: 1,
                    currentValue: 0,
                    viewportHeight: 420,
                    contentHeight: 840
                )
            ])
        }

        let root = axObservation(
            0,
            "root",
            role: "AXGroup",
            identifier: request.rootIdentifier,
            label: "Vifty UI review fixture",
            position: AXPoint(x: 0, y: 0),
            size: AXSize(width: 1_000, height: 1_000)
        )
        var observations = [root] + fixture.observations.map { observation in
            var observation = observation
            observation.path = "root/\(observation.path)"
            observation.order += 1
            observation.depth += 1
            return observation
        }
        normalizeAXTraversalMetadata(&observations)
        let scrollEvidence = fixture.scroll.map { evidence in
            var evidence = evidence
            evidence.scrollAreaPath = "root/\(evidence.scrollAreaPath)"
            evidence.verticalScrollBarPath = "root/\(evidence.verticalScrollBarPath)"
            return evidence
        }
        return AXRawCapture(
            request: request,
            collectorBuildProvenance: collectorBuildProvenance,
            source: "macos-accessibility-api",
            permissionTrusted: true,
            promptRequested: false,
            initialTarget: target,
            finalTarget: target,
            traversal: AXTraversal(
                complete: true,
                nodeCount: observations.count,
                maximumNodeCount: 2_048,
                maximumDepth: 32,
                truncationReasons: []
            ),
            observations: observations,
            scrollEvidence: scrollEvidence,
            actionsPerformed: [],
            readErrors: []
        )
    }

    private func axObservation(
        _ order: Int,
        _ path: String,
        role: String,
        identifier: String,
        label: String? = nil,
        value: AXTypedValue? = nil,
        help: String? = nil,
        selected: Bool? = nil,
        actions: [String] = [],
        position: AXPoint? = nil,
        size: AXSize? = nil
    ) -> AXObservation {
        AXObservation(
            path: path,
            order: order,
            depth: path.split(separator: "/").count - 1,
            role: role,
            identifier: identifier,
            description: label,
            label: label,
            help: help,
            value: value,
            enabled: true,
            selected: selected,
            position: position,
            size: size,
            actions: actions
        )
    }

    private func normalizeAXTraversalMetadata(_ observations: inout [AXObservation]) {
        for index in observations.indices {
            observations[index].order = index
            let path = observations[index].path
            observations[index].depth = path.split(separator: "/").count - 1
            let prefix = path + "/"
            observations[index].childCount = observations.filter { candidate in
                guard candidate.path.hasPrefix(prefix) else { return false }
                let suffix = candidate.path.dropFirst(prefix.count)
                return !suffix.contains("/") && Int(suffix) != nil
            }.count
        }
    }

    private func markSystemSettingVisualRowsPending(manifest: inout [String: Any]) throws {
        for rowID in ["main-increase-contrast", "main-reduce-transparency"] {
            try markRequirementPending(rowsKey: "visualCells", rowID: rowID, manifest: &manifest)
        }
    }

    private func markRequirementPending(
        rowsKey: String,
        rowID: String,
        manifest: inout [String: Any]
    ) throws {
        var rows = try XCTUnwrap(manifest[rowsKey] as? [[String: Any]])
        let index = try XCTUnwrap(rows.firstIndex { $0["id"] as? String == rowID })
        let captureID = try XCTUnwrap(rows[index]["captureID"] as? String)
        rows[index]["status"] = "pending"
        rows[index]["captureID"] = NSNull()
        manifest[rowsKey] = rows
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        ledger.removeValue(forKey: captureID)
        manifest["captureLedger"] = ledger
    }

    private struct PopulatedFixture {
        var root: URL
        var evidence: URL
        var releaseBinary: URL
        var debugExecutable: URL
        var collectorExecutable: URL
        var manifestURL: URL
        var manifest: [String: Any]
    }

    private struct CheckpointRepository {
        var sourceCommit: String
        var sourceTree: String
        var hero: URL
        var output: URL
    }

    private func prepareCheckpointRepository(
        fixture: PopulatedFixture,
        heroSource: URL
    ) throws -> CheckpointRepository {
        let gitignore = fixture.root.appendingPathComponent(".gitignore")
        try Data(
            """
            .build/
            debug/
            evidence/
            evidence-manifest.json*
            ViftyAXCollector
            """.utf8
        ).write(to: gitignore)
        let hero = fixture.root.appendingPathComponent("docs/images/vifty-screenshot.png")
        try FileManager.default.createDirectory(
            at: hero.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: heroSource, to: hero)
        let schema = fixture.root.appendingPathComponent(
            "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
        )
        try FileManager.default.createDirectory(
            at: schema.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent(
                "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
            ),
            to: schema
        )
        for arguments in [
            ["init", "-q"],
            ["config", "user.email", "ui-evidence-tests@vifty.invalid"],
            ["config", "user.name", "Vifty UI Evidence Tests"],
            ["config", "commit.gpgsign", "false"],
            ["add", ".gitignore", "docs/images/vifty-screenshot.png", "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"],
            ["commit", "-q", "-m", "checkpoint test fixture"]
        ] {
            let result = try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: arguments,
                currentDirectory: fixture.root
            )
            XCTAssertEqual(result.status, 0, result.output)
        }
        let head = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: fixture.root
        )
        XCTAssertEqual(head.status, 0, head.output)
        let tree = try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["rev-parse", "HEAD^{tree}"],
            currentDirectory: fixture.root
        )
        XCTAssertEqual(tree.status, 0, tree.output)
        let sourceCommit = head.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTree = tree.output.trimmingCharacters(in: .whitespacesAndNewlines)
        try rebindFixtureProducts(
            fixture: fixture,
            sourceCommit: sourceCommit,
            sourceTree: sourceTree
        )
        return CheckpointRepository(
            sourceCommit: sourceCommit,
            sourceTree: sourceTree,
            hero: hero,
            output: URL(
                fileURLWithPath: try canonicalFilesystemPath(fixture.root),
                isDirectory: true
            ).appendingPathComponent("docs/ui-review/automated-checkpoint.json")
        )
    }

    private func rebindFixtureProducts(
        fixture: PopulatedFixture,
        sourceCommit: String,
        sourceTree: String
    ) throws {
        let transactionID = String(repeating: "d", count: 64)
        let debugBuildProvenance = TestBuildProvenance.identity(
            role: "debug-fixture-app",
            sourceCommit: sourceCommit,
            sourceTree: sourceTree,
            transactionID: transactionID
        )
        let releaseBuildProvenance = TestBuildProvenance.identity(
            role: "release-exclusion",
            sourceCommit: sourceCommit,
            sourceTree: sourceTree,
            transactionID: transactionID
        )
        let collectorBuildProvenance = TestBuildProvenance.identity(
            role: "ax-collector",
            sourceCommit: sourceCommit,
            sourceTree: sourceTree,
            transactionID: transactionID
        )
        for (url, provenance) in [
            (fixture.debugExecutable, debugBuildProvenance),
            (fixture.releaseBinary, releaseBuildProvenance),
            (fixture.collectorExecutable, collectorBuildProvenance)
        ] {
            try TestBuildProvenance.thinMachO(provenance: provenance).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }

        var manifest = try readJSON(fixture.manifestURL)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        let debugSHA = try sha256(fixture.debugExecutable)
        let debugPath = try canonicalFilesystemPath(fixture.debugExecutable)
        let debugProvenanceJSON = try jsonObject(debugBuildProvenance)
        for captureID in ledger.keys.sorted() {
            var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
            capture["debugExecutablePath"] = debugPath
            capture["debugExecutableSHA256"] = debugSHA
            capture["debugBuildProvenance"] = debugProvenanceJSON
            var runtime = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
            runtime["executablePath"] = debugPath
            runtime["executableSHA256"] = debugSHA
            capture["runtimeIdentity"] = runtime

            let artifact = try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
            let reportURL = fixture.evidence.appendingPathComponent(artifact)
            var report = try readJSON(reportURL)
            report["debugExecutablePath"] = debugPath
            report["debugExecutableSHA256"] = debugSHA
            report["debugBuildProvenance"] = debugProvenanceJSON
            report["runtimeIdentity"] = runtime
            try writeJSON(report, to: reportURL)
            capture["fixtureReportSHA256"] = try sha256(reportURL)
            ledger[captureID] = capture
        }
        manifest["captureLedger"] = ledger
        var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        release["sha256"] = try sha256(fixture.releaseBinary)
        release["buildProvenance"] = try jsonObject(releaseBuildProvenance)
        manifest["releaseExclusion"] = release

        var reboundFixture = fixture
        reboundFixture.manifest = manifest
        try installSealedAccessibilityEvidence(fixture: reboundFixture, manifest: &manifest)
        try writeJSON(manifest, to: fixture.manifestURL)
    }

    private func populatedFixture() throws -> PopulatedFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-ui-review-evidence-tests-\(UUID().uuidString)", isDirectory: true)
        let evidence = root.appendingPathComponent("evidence", isDirectory: true)
        let releaseBinary = root.appendingPathComponent(
            ".build/ui-review-products/release/Vifty"
        )
        let debugExecutable = root.appendingPathComponent(
            ".build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty"
        )
        let collectorExecutable = root.appendingPathComponent(
            ".build/ui-review-products/debug/ViftyAXCollector"
        )
        let manifestURL = root.appendingPathComponent("evidence-manifest.json")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: releaseBinary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: debugExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "release-exclusion")
        ).write(to: releaseBinary)
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: debugExecutable)
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "ax-collector")
        ).write(to: collectorExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: releaseBinary.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: debugExecutable.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: collectorExecutable.path
        )

        var manifest = try readJSON(
            repositoryRoot.appendingPathComponent("docs/ui-review/evidence-manifest.json")
        )
        manifest["schemaVersion"] = 3
        manifest["status"] = "pending"
        manifest["fixtureStates"] = fixtureStates
        let fixtureReports = expectedFixtureRows()
        manifest["fixtureReports"] = fixtureReports
        let visualCells = expectedVisualRows()
        manifest["visualCells"] = visualCells
        let accessibilityChecks = expectedAccessibilityRows()
        manifest["accessibilityChecks"] = accessibilityChecks

        let debugExecutableSHA256 = try sha256(debugExecutable)
        let debugExecutablePath = try canonicalFilesystemPath(debugExecutable)
        var captureLedger: [String: Any] = [:]
        var windowNumber = 100

        for entry in fixtureReports {
            let captureID = try XCTUnwrap(entry["captureID"] as? String)
            let request = try XCTUnwrap(entry["request"] as? [String: Any])
            captureLedger[captureID] = try baseCaptureEntry(
                evidence: evidence,
                captureID: captureID,
                request: request,
                debugExecutablePath: debugExecutablePath,
                debugExecutableSHA256: debugExecutableSHA256,
                windowNumber: windowNumber
            )
            windowNumber += 1
        }

        let supportedColorTypes: [UInt8] = [0, 2, 4, 6]
        for (visualIndex, entry) in visualCells.enumerated() {
            let id = try XCTUnwrap(entry["id"] as? String)
            let request = try XCTUnwrap(entry["request"] as? [String: Any])
            let captureID = try XCTUnwrap(entry["captureID"] as? String)
            var capture = try baseCaptureEntry(
                evidence: evidence,
                captureID: captureID,
                request: request,
                debugExecutablePath: debugExecutablePath,
                debugExecutableSHA256: debugExecutableSHA256,
                windowNumber: windowNumber
            )
            windowNumber += 1

            let dimensions = try windowDimensions(request)
            let png = try pngFixture(
                width: dimensions.width,
                height: dimensions.height,
                colorType: supportedColorTypes[visualIndex % supportedColorTypes.count],
                seed: visualIndex + 1
            )
            let screenshotArtifact = "screenshots/\(id).png"
            let artifact = evidence.appendingPathComponent(screenshotArtifact)
            try FileManager.default.createDirectory(
                at: artifact.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try png.data.write(to: artifact)
            let screenshotSHA = try sha256(artifact)
            capture["screenshot"] = [
                "artifact": screenshotArtifact,
                "sha256": screenshotSHA,
                "canonicalPixelSHA256": png.canonicalPixelSHA256
            ]
            let reportURL = evidence.appendingPathComponent(
                try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
            )
            var report = try readJSON(reportURL)
            report["screenshot"] = [
                "method": "native-window-screencapture-crop",
                "artifactPath": "screenshot.png",
                "sha256": screenshotSHA,
                "pointWidth": dimensions.width,
                "pointHeight": dimensions.height,
                "pixelWidth": dimensions.width,
                "pixelHeight": dimensions.height,
                "backingScaleFactor": 1
            ]
            try writeJSON(report, to: reportURL)
            capture["fixtureReportSHA256"] = try sha256(reportURL)
            captureLedger[captureID] = capture
        }

        for entry in accessibilityChecks {
            let request = try XCTUnwrap(entry["request"] as? [String: Any])
            let captureID = try XCTUnwrap(entry["captureID"] as? String)
            let capture = try baseCaptureEntry(
                evidence: evidence,
                captureID: captureID,
                request: request,
                debugExecutablePath: debugExecutablePath,
                debugExecutableSHA256: debugExecutableSHA256,
                windowNumber: windowNumber
            )
            windowNumber += 1
            captureLedger[captureID] = capture
        }
        manifest["captureLedger"] = captureLedger

        var release = try XCTUnwrap(manifest["releaseExclusion"] as? [String: Any])
        release["status"] = "passed"
        release["sha256"] = try sha256(releaseBinary)
        release["buildProvenance"] = try jsonObject(
            TestBuildProvenance.identity(role: "release-exclusion")
        )
        manifest["releaseExclusion"] = release
        var fixture = PopulatedFixture(
            root: root,
            evidence: evidence,
            releaseBinary: releaseBinary,
            debugExecutable: debugExecutable,
            collectorExecutable: collectorExecutable,
            manifestURL: manifestURL,
            manifest: manifest
        )
        try installSealedAccessibilityEvidence(fixture: fixture, manifest: &manifest)
        fixture.manifest = manifest
        try writeJSON(manifest, to: manifestURL)
        return fixture
    }

    private var fixtureStates: [String] {
        [
            "healthy-auto",
            "divergent-per-fan-curve-draft",
            "active-manual",
            "recovery-mixed-ownership",
            "helper-blocked",
            "notification-denied",
            "edited-profile",
            "selected-vs-highest-temperature",
            "raw-spike-telemetry"
        ]
    }

    private func semanticRequest(
        state: String = "healthy-auto",
        surface: String = "main",
        window: String = "1180x820",
        appearance: String = "light",
        contrast: String = "standard",
        transparency: String = "standard",
        textSize: String = "standard",
        interaction: String = "none"
    ) -> [String: Any] {
        [
            "state": state,
            "surface": surface,
            "window": window,
            "appearance": appearance,
            "contrast": contrast,
            "transparency": transparency,
            "textSize": textSize,
            "interaction": interaction
        ]
    }

    private func expectedFixtureRows() -> [[String: Any]] {
        fixtureStates.map { state in
            [
                "state": state,
                "status": "passed",
                "captureID": "fixture-\(state)",
                "request": semanticRequest(state: state)
            ]
        }
    }

    private func expectedVisualRows() -> [[String: Any]] {
        var rows: [[String: Any]] = []

        for window in ["780x480", "1180x820", "1280x720", "1500x900"] {
            for appearance in ["light", "dark"] {
                let id = "main-\(window)-\(appearance)"
                rows.append(visualRow(
                    id: id,
                    request: semanticRequest(window: window, appearance: appearance)
                ))
            }
        }

        for state in fixtureStates.dropFirst() {
            let id = "state-\(state)"
            let request = state == "notification-denied"
                ? semanticRequest(
                    state: state,
                    surface: "settings-notifications",
                    window: "native"
                )
                : semanticRequest(state: state)
            rows.append(visualRow(id: id, request: request))
        }

        rows.append(visualRow(
            id: "settings-general",
            request: semanticRequest(surface: "settings-general", window: "native")
        ))
        rows.append(visualRow(
            id: "settings-menu-bar",
            request: semanticRequest(surface: "settings-menu-bar", window: "native")
        ))
        rows.append(visualRow(
            id: "settings-notifications",
            request: semanticRequest(surface: "settings-notifications", window: "native")
        ))
        rows.append(visualRow(
            id: "settings-agent-workflows",
            request: semanticRequest(surface: "settings-agent-workflows", window: "native")
        ))
        rows.append(visualRow(
            id: "menu-popover",
            request: semanticRequest(surface: "menu-popover", window: "320xauto")
        ))
        rows.append(visualRow(
            id: "main-increase-contrast",
            request: semanticRequest(contrast: "increased", transparency: "reduced")
        ))
        rows.append(visualRow(
            id: "main-reduce-transparency",
            request: semanticRequest(transparency: "reduced")
        ))
        rows.append(visualRow(
            id: "main-accessibility-text",
            request: semanticRequest(textSize: "accessibility")
        ))
        rows.append(visualRow(
            id: "settings-general-accessibility-text",
            request: semanticRequest(
                surface: "settings-general",
                window: "native",
                textSize: "accessibility"
            )
        ))
        rows.append(visualRow(
            id: "settings-menu-bar-accessibility-text",
            request: semanticRequest(
                surface: "settings-menu-bar",
                window: "native",
                textSize: "accessibility"
            )
        ))
        rows.append(visualRow(
            id: "settings-notifications-accessibility-text",
            request: semanticRequest(
                state: "notification-denied",
                surface: "settings-notifications",
                window: "native",
                textSize: "accessibility"
            )
        ))
        rows.append(visualRow(
            id: "settings-agent-workflows-accessibility-text",
            request: semanticRequest(
                surface: "settings-agent-workflows",
                window: "native",
                textSize: "accessibility"
            )
        ))
        return rows
    }

    private func visualRow(id: String, request: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "status": "passed",
            "captureID": "visual-\(id)",
            "request": request
        ]
    }

    private func expectedAccessibilityRows() -> [[String: Any]] {
        [
            accessibilityRow(
                id: "confirmed-owner-headline",
                request: semanticRequest(state: "active-manual")
            ),
            accessibilityRow(
                id: "correct-per-fan-target",
                request: semanticRequest(state: "divergent-per-fan-curve-draft")
            ),
            accessibilityRow(
                id: "six-adjustable-point-controls",
                request: semanticRequest(state: "divergent-per-fan-curve-draft")
            ),
            accessibilityRow(
                id: "sensor-selected-trait-value",
                request: semanticRequest(state: "selected-vs-highest-temperature")
            ),
            accessibilityRow(
                id: "explicit-temperature-role",
                request: semanticRequest(state: "selected-vs-highest-temperature")
            ),
            accessibilityRow(
                id: "notification-actions",
                request: semanticRequest(
                    state: "notification-denied",
                    surface: "settings-notifications",
                    window: "native"
                )
            ),
            accessibilityRow(
                id: "settings-logical-traversal",
                request: semanticRequest(surface: "settings-general", window: "native")
            ),
            accessibilityRow(
                id: "no-duplicate-chart-elements",
                request: semanticRequest(state: "divergent-per-fan-curve-draft")
            ),
            accessibilityRow(
                id: "compact-main-scroll-reachable",
                request: semanticRequest(
                    window: "780x480",
                    textSize: "accessibility",
                    interaction: "structural-scroll"
                )
            ),
            accessibilityRow(
                id: "settings-general-scroll-reachable",
                request: semanticRequest(
                    surface: "settings-general",
                    window: "native",
                    textSize: "accessibility",
                    interaction: "structural-scroll"
                )
            ),
            accessibilityRow(
                id: "settings-menu-bar-scroll-reachable",
                request: semanticRequest(
                    surface: "settings-menu-bar",
                    window: "native",
                    textSize: "accessibility",
                    interaction: "structural-scroll"
                )
            ),
            accessibilityRow(
                id: "settings-notifications-scroll-reachable",
                request: semanticRequest(
                    state: "notification-denied",
                    surface: "settings-notifications",
                    window: "native",
                    textSize: "accessibility",
                    interaction: "structural-scroll"
                )
            ),
            accessibilityRow(
                id: "settings-agent-workflows-scroll-reachable",
                request: semanticRequest(
                    surface: "settings-agent-workflows",
                    window: "native",
                    textSize: "accessibility",
                    interaction: "structural-scroll"
                )
            )
        ]
    }

    private func accessibilityRow(id: String, request: [String: Any]) -> [String: Any] {
        [
            "id": id,
            "status": "passed",
            "captureID": "ax-\(id)",
            "request": request
        ]
    }

    private func baseCaptureEntry(
        evidence: URL,
        captureID: String,
        request: [String: Any],
        debugExecutablePath: String,
        debugExecutableSHA256: String,
        windowNumber: Int
    ) throws -> [String: Any] {
        let runtimeIdentity = try runtimeIdentity(
            captureID: captureID,
            request: request,
            debugExecutablePath: debugExecutablePath,
            debugExecutableSHA256: debugExecutableSHA256,
            windowNumber: windowNumber
        )
        let debugBuildProvenance = TestBuildProvenance.identity(role: "debug-fixture-app")
        let fixtureReportArtifact = "reports/\(captureID)/fixture-report.json"
        let fixtureReportURL = evidence.appendingPathComponent(fixtureReportArtifact)
        try writeJSON(
            try fixtureReport(
                request: request,
                captureID: captureID,
                runtimeIdentity: runtimeIdentity,
                debugExecutablePath: debugExecutablePath,
                debugExecutableSHA256: debugExecutableSHA256,
                debugBuildProvenance: debugBuildProvenance
            ),
            to: fixtureReportURL
        )
        return [
            "request": request,
            "requestSHA256": try canonicalJSONSHA256(request),
            "fixtureReportArtifact": fixtureReportArtifact,
            "fixtureReportSHA256": try sha256(fixtureReportURL),
            "debugExecutablePath": debugExecutablePath,
            "debugExecutableSHA256": debugExecutableSHA256,
            "debugBuildProvenance": try jsonObject(debugBuildProvenance),
            "runtimeIdentity": runtimeIdentity
        ]
    }

    private func fixtureReport(
        request: [String: Any],
        captureID: String,
        runtimeIdentity: [String: Any],
        debugExecutablePath: String,
        debugExecutableSHA256: String,
        debugBuildProvenance: ViftyBuildProvenance
    ) throws -> [String: Any] {
        return [
            "schemaVersion": 3,
            "captureID": captureID,
            "request": request,
            "requestSHA256": try canonicalJSONSHA256(request),
            "debugExecutablePath": debugExecutablePath,
            "debugExecutableSHA256": debugExecutableSHA256,
            "debugBuildProvenance": try jsonObject(debugBuildProvenance),
            "runtimeIdentity": runtimeIdentity,
            "observed": [
                "environment": [
                    "source": "swiftui-environment",
                    "appearance": request["appearance"] as Any,
                    "contrast": request["contrast"] as Any,
                    "transparency": request["transparency"] as Any,
                    "textSize": request["textSize"] as Any
                ],
                "window": [
                    "source": "nswindow-content-layout-rect",
                    "provenance": runtimeIdentity["provenance"] as Any,
                    "containerKind": runtimeIdentity["containerKind"] as Any,
                    "windowClass": runtimeIdentity["windowClass"] as Any,
                    "windowIdentifier": runtimeIdentity["windowIdentifier"] as Any,
                    "accessibilityIdentifier": runtimeIdentity["accessibilityIdentifier"] as Any,
                    "windowNumber": runtimeIdentity["windowNumber"] as Any,
                    "isVisible": runtimeIdentity["isVisible"] as Any,
                    "contentWidth": runtimeIdentity["contentWidth"] as Any,
                    "contentHeight": runtimeIdentity["contentHeight"] as Any,
                    "backingScaleFactor": runtimeIdentity["backingScaleFactor"] as Any
                ]
            ],
            "phase": "final",
            "modelStartSkipped": true,
            "recorder": [
                "fixtureConstructions": [
                    "hardware",
                    "notification-center",
                    "login-item",
                    "helper-installer",
                    "daemon-client",
                    "power-client"
                ],
                "readOperations": [
                    "notification-authorization",
                    "login-item-status",
                    "hardware-snapshot",
                    "fan-control-ownership",
                    "power",
                    "thermal-pressure",
                    "daemon-ping",
                    "agent-status"
                ],
                "attemptedHardwareCommands": [],
                "attemptedExternalMutations": [],
                "realControlPathConstructions": []
            ],
            "passed": true
        ]
    }

    private func runtimeIdentity(
        captureID: String,
        request: [String: Any],
        debugExecutablePath: String,
        debugExecutableSHA256: String,
        windowNumber: Int
    ) throws -> [String: Any] {
        let dimensions = try windowDimensions(request)
        let surface = try XCTUnwrap(request["surface"] as? String)
        return [
            "processIdentifier": 4_242,
            "executablePath": debugExecutablePath,
            "executableSHA256": debugExecutableSHA256,
            "provenance": expectedProvenance(surface: surface),
            "windowNumber": windowNumber,
            "windowIdentifier": "vifty-ui-review-window-\(captureID)",
            "accessibilityIdentifier": "vifty-ui-review-ax-window-\(captureID)",
            "windowClass": "NSWindow",
            "containerKind": expectedContainerKind(surface: surface),
            "isVisible": true,
            "contentWidth": dimensions.width,
            "contentHeight": dimensions.height,
            "backingScaleFactor": 1
        ]
    }

    private func expectedContainerKind(surface: String) -> String {
        switch surface {
        case "main": "main-window"
        case "menu-popover": "popover"
        default: "settings-window"
        }
    }

    private func expectedProvenance(surface: String) -> String {
        switch surface {
        case "main": "swiftui-main-window"
        case "menu-popover": "ns-popover-status-item"
        default: "swiftui-settings-scene"
        }
    }

    private func windowDimensions(_ request: [String: Any]) throws -> (width: Int, height: Int) {
        let raw = try XCTUnwrap(request["window"] as? String)
        if raw == "native" {
            return (600, 420)
        }
        if raw == "320xauto" {
            return (320, 360)
        }
        let parts = raw.split(separator: "x", maxSplits: 1).compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        return (try XCTUnwrap(parts.first), try XCTUnwrap(parts.last))
    }

    private func verifierResultAfterChangingGeometry(
        fixture: PopulatedFixture,
        visualID: String,
        width: Int,
        height: Int
    ) throws -> (status: Int32, output: String) {
        var manifest = fixture.manifest
        let visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let visual = try XCTUnwrap(visualCells.first { $0["id"] as? String == visualID })
        let captureID = try XCTUnwrap(visual["captureID"] as? String)
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var identity = try XCTUnwrap(capture["runtimeIdentity"] as? [String: Any])
        identity["contentWidth"] = width
        identity["contentHeight"] = height
        capture["runtimeIdentity"] = identity

        let fixtureReportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(fixtureReportURL)
        report["runtimeIdentity"] = identity
        var observed = try XCTUnwrap(report["observed"] as? [String: Any])
        var observedWindow = try XCTUnwrap(observed["window"] as? [String: Any])
        observedWindow["contentWidth"] = width
        observedWindow["contentHeight"] = height
        observed["window"] = observedWindow
        report["observed"] = observed
        try writeJSON(report, to: fixtureReportURL)
        capture["fixtureReportSHA256"] = try sha256(fixtureReportURL)

        var screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let screenshotURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        let scale = try XCTUnwrap(identity["backingScaleFactor"] as? NSNumber).doubleValue
        let pixelWidth = Int((Double(width) * scale).rounded())
        let pixelHeight = Int((Double(height) * scale).rounded())
        let png = try pngFixture(
            width: pixelWidth,
            height: pixelHeight,
            colorType: 6,
            seed: 204
        )
        try png.data.write(to: screenshotURL)
        screenshot["sha256"] = try sha256(screenshotURL)
        screenshot["canonicalPixelSHA256"] = png.canonicalPixelSHA256
        capture["screenshot"] = screenshot
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
        return try verify(fixture, manifest: manifest)
    }

    private func captureEntry(
        _ captureID: String,
        in manifest: [String: Any]
    ) throws -> [String: Any] {
        let ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        return try XCTUnwrap(ledger[captureID] as? [String: Any])
    }

    private func updateFixtureReport(
        _ report: [String: Any],
        captureID: String,
        fixture: PopulatedFixture,
        manifest: inout [String: Any]
    ) throws {
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        try writeJSON(report, to: reportURL)
        capture["fixtureReportSHA256"] = try sha256(reportURL)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
    }

    private func updateScreenshot(
        captureID: String,
        fixture: PopulatedFixture,
        manifest: inout [String: Any],
        canonicalPixelSHA256: String? = nil
    ) throws {
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let screenshotURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        let screenshotSHA = try sha256(screenshotURL)
        screenshot["sha256"] = screenshotSHA
        if let canonicalPixelSHA256 {
            screenshot["canonicalPixelSHA256"] = canonicalPixelSHA256
        }
        capture["screenshot"] = screenshot
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(capture["fixtureReportArtifact"] as? String)
        )
        var report = try readJSON(reportURL)
        var reportScreenshot = try XCTUnwrap(report["screenshot"] as? [String: Any])
        reportScreenshot["sha256"] = screenshotSHA
        report["screenshot"] = reportScreenshot
        try writeJSON(report, to: reportURL)
        capture["fixtureReportSHA256"] = try sha256(reportURL)
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
    }

    private func updateAccessibility(
        captureID: String,
        fixture: PopulatedFixture,
        manifest: inout [String: Any]
    ) throws {
        var ledger = try XCTUnwrap(manifest["captureLedger"] as? [String: Any])
        var capture = try XCTUnwrap(ledger[captureID] as? [String: Any])
        var accessibility = try XCTUnwrap(capture["accessibility"] as? [String: Any])
        let reportURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(accessibility["artifact"] as? String)
        )
        accessibility["sha256"] = try sha256(reportURL)
        capture["accessibility"] = accessibility
        ledger[captureID] = capture
        manifest["captureLedger"] = ledger
    }

    private struct PNGFixture {
        let data: Data
        let canonicalPixelSHA256: String
    }

    private enum PNGPattern: Equatable {
        case patterned
        case transparent
        case solid
    }

    private func replaceScreenshot(
        visualID: String,
        png: PNGFixture,
        fixture: PopulatedFixture,
        manifest: inout [String: Any]
    ) throws {
        let visualCells = try XCTUnwrap(manifest["visualCells"] as? [[String: Any]])
        let visual = try XCTUnwrap(visualCells.first { $0["id"] as? String == visualID })
        let captureID = try XCTUnwrap(visual["captureID"] as? String)
        let capture = try captureEntry(captureID, in: manifest)
        let screenshot = try XCTUnwrap(capture["screenshot"] as? [String: Any])
        let imageURL = fixture.evidence.appendingPathComponent(
            try XCTUnwrap(screenshot["artifact"] as? String)
        )
        try png.data.write(to: imageURL)
        try updateScreenshot(
            captureID: captureID,
            fixture: fixture,
            manifest: &manifest,
            canonicalPixelSHA256: png.canonicalPixelSHA256
        )
    }

    private func pngFixture(
        width: Int,
        height: Int,
        colorType: UInt8,
        seed: Int,
        pattern: PNGPattern = .patterned,
        filters: [UInt8] = [0],
        compressionLevel: Int32 = Z_BEST_SPEED,
        splitIDAT: Bool = false
    ) throws -> PNGFixture {
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        XCTAssertFalse(filters.isEmpty)
        XCTAssertTrue(filters.allSatisfy { $0 <= 4 })
        let bytesPerPixel: Int
        switch colorType {
        case 0: bytesPerPixel = 1
        case 2: bytesPerPixel = 3
        case 4: bytesPerPixel = 2
        case 6: bytesPerPixel = 4
        default:
            XCTFail("Unsupported PNG fixture color type \(colorType)")
            throw CocoaError(.fileWriteUnknown)
        }

        var sampleRow = Data()
        sampleRow.reserveCapacity(width * bytesPerPixel)
        var canonicalRow = Data()
        canonicalRow.reserveCapacity(width * 4)
        let base = UInt8(16 + ((seed * 7) % 180))
        let alternate = UInt8(min(Int(base) + 30, 250))
        for x in 0..<width {
            let useAlternate = pattern == .patterned && ((x / 37) % 2 == 1)
            let value = useAlternate ? alternate : base
            let red = value
            let green = UInt8((Int(value) + 41) % 251)
            let blue = UInt8((Int(value) + 89) % 251)
            let alpha: UInt8 = pattern == .transparent ? 0 : 255
            switch colorType {
            case 0:
                sampleRow.append(value)
                canonicalRow.append(contentsOf: [value, value, value, 255])
            case 2:
                sampleRow.append(contentsOf: [red, green, blue])
                canonicalRow.append(contentsOf: [red, green, blue, 255])
            case 4:
                sampleRow.append(contentsOf: [value, alpha])
                canonicalRow.append(contentsOf: alpha == 0
                    ? [0, 0, 0, 0]
                    : [value, value, value, alpha])
            case 6:
                sampleRow.append(contentsOf: [red, green, blue, alpha])
                canonicalRow.append(contentsOf: alpha == 0
                    ? [0, 0, 0, 0]
                    : [red, green, blue, alpha])
            default:
                fatalError("Validated above")
            }
        }

        var scanlines = Data()
        scanlines.reserveCapacity(height * (1 + sampleRow.count))
        let zeroRow = Data(repeating: 0, count: sampleRow.count)
        for y in 0..<height {
            let filter = filters[y % filters.count]
            scanlines.append(filter)
            if filter == 0 {
                scanlines.append(sampleRow)
                continue
            }
            let previous = y == 0 ? zeroRow : sampleRow
            for index in sampleRow.indices {
                let raw = Int(sampleRow[index])
                let left = index >= bytesPerPixel ? Int(sampleRow[index - bytesPerPixel]) : 0
                let up = Int(previous[index])
                let upperLeft = index >= bytesPerPixel ? Int(previous[index - bytesPerPixel]) : 0
                let predictor: Int
                switch filter {
                case 0: predictor = 0
                case 1: predictor = left
                case 2: predictor = up
                case 3: predictor = (left + up) / 2
                case 4: predictor = paeth(left, up, upperLeft)
                default: fatalError("Validated above")
                }
                scanlines.append(UInt8(truncatingIfNeeded: raw - predictor))
            }
        }

        var canonicalHasher = SHA256()
        for _ in 0..<height {
            canonicalHasher.update(data: canonicalRow)
        }
        let canonicalPixelSHA256 = canonicalHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()

        var ihdr = Data()
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [8, colorType, 0, 0, 0])
        let compressed = try zlibCompress(scanlines, level: compressionLevel)
        var png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        png.append(pngChunk(type: "IHDR", payload: ihdr))
        if splitIDAT && compressed.count > 1 {
            let split = compressed.count / 2
            png.append(pngChunk(type: "IDAT", payload: compressed.prefix(split)))
            png.append(pngChunk(type: "IDAT", payload: compressed.suffix(from: split)))
        } else {
            png.append(pngChunk(type: "IDAT", payload: compressed))
        }
        png.append(pngChunk(type: "IEND", payload: Data()))
        return PNGFixture(data: png, canonicalPixelSHA256: canonicalPixelSHA256)
    }

    private func zlibCompress(_ source: Data, level: Int32) throws -> Data {
        var destinationLength = compressBound(UInt(source.count))
        var destination = Data(count: Int(destinationLength))
        let status = destination.withUnsafeMutableBytes { destinationBytes in
            source.withUnsafeBytes { sourceBytes in
                compress2(
                    destinationBytes.bindMemory(to: UInt8.self).baseAddress,
                    &destinationLength,
                    sourceBytes.bindMemory(to: UInt8.self).baseAddress,
                    UInt(source.count),
                    level
                )
            }
        }
        guard status == Z_OK else {
            throw CocoaError(.fileWriteUnknown)
        }
        destination.count = Int(destinationLength)
        return destination
    }

    private func paeth(_ left: Int, _ up: Int, _ upperLeft: Int) -> Int {
        let estimate = left + up - upperLeft
        let leftDistance = abs(estimate - left)
        let upDistance = abs(estimate - up)
        let upperLeftDistance = abs(estimate - upperLeft)
        if leftDistance <= upDistance && leftDistance <= upperLeftDistance {
            return left
        }
        return upDistance <= upperLeftDistance ? up : upperLeft
    }

    private func pngFromFilteredScanlines(
        width: Int,
        height: Int,
        colorType: UInt8,
        scanlines: Data
    ) throws -> Data {
        try pngWithIDATPayload(
            width: width,
            height: height,
            colorType: colorType,
            compressed: zlibCompress(scanlines, level: Z_BEST_SPEED)
        )
    }

    private func pngWithIDATPayload(
        width: Int,
        height: Int,
        colorType: UInt8,
        compressed: Data,
        splitWithAncillary: Bool = false,
        reservedBitChunk: Bool = false
    ) throws -> Data {
        var ihdr = Data()
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [8, colorType, 0, 0, 0])
        var png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        png.append(pngChunk(type: "IHDR", payload: ihdr))
        if reservedBitChunk {
            png.append(pngChunk(type: "abca", payload: Data()))
        }
        if splitWithAncillary {
            let split = max(1, compressed.count / 2)
            png.append(pngChunk(type: "IDAT", payload: Data(compressed.prefix(split))))
            png.append(pngChunk(type: "tEXt", payload: Data("x".utf8)))
            png.append(pngChunk(type: "IDAT", payload: Data(compressed.suffix(from: split))))
        } else {
            png.append(pngChunk(type: "IDAT", payload: compressed))
        }
        png.append(pngChunk(type: "IEND", payload: Data()))
        return png
    }

    private func assertPNGAnalyzerRejects(
        _ png: Data,
        width: Int,
        height: Int,
        containing expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let result = try runPNGAnalyzer(png, width: width, height: height)
        XCTAssertNotEqual(result.status, 0, result.output, file: file, line: line)
        XCTAssertTrue(result.output.contains(expected), result.output, file: file, line: line)
    }

    private func runPNGAnalyzer(
        _ png: Data,
        width: Int,
        height: Int
    ) throws -> (status: Int32, output: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-png-analyzer-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("fixture.png")
        try png.write(to: image)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-I", repositoryRoot.appendingPathComponent("scripts/lib").path,
            "-rui_review_contract",
            "-rjson",
            "-e",
            "begin; puts JSON.generate(ViftyUIReview.analyze_png(ARGV[0], expected_width: Integer(ARGV[1]), expected_height: Integer(ARGV[2]))); rescue ViftyUIReview::PNGError => error; warn error.message; exit 1; end",
            image.path,
            String(width),
            String(height)
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private func replaceInfinitySentinel(at url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let replaced = content.replacingOccurrences(
            of: "\"__VIFTY_INFINITY__\"",
            with: "1e400"
        )
        try Data(replaced.utf8).write(to: url, options: .atomic)
    }

    private func malformedScanlinePNG(width: Int, height: Int) throws -> Data {
        var ihdr = Data()
        appendBigEndian(UInt32(width), to: &ihdr)
        appendBigEndian(UInt32(height), to: &ihdr)
        ihdr.append(contentsOf: [8, 6, 0, 0, 0])

        // Valid RFC 1950 zlib stream whose deflate payload expands to one zero byte.
        let compressed = Data([0x78, 0x9c, 0x63, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01])
        var png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        png.append(pngChunk(type: "IHDR", payload: ihdr))
        png.append(pngChunk(type: "IDAT", payload: compressed))
        png.append(pngChunk(type: "IEND", payload: Data()))
        return png
    }

    private func pngChunk(type: String, payload: Data) -> Data {
        let typeData = Data(type.utf8)
        var chunk = Data()
        appendBigEndian(UInt32(payload.count), to: &chunk)
        chunk.append(typeData)
        chunk.append(payload)
        appendBigEndian(crc32(typeData + payload), to: &chunk)
        return chunk
    }

    private func appendBigEndian(_ value: UInt32, to data: inout Data) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1
            }
        }
        return crc ^ UInt32.max
    }

    private func verify(
        _ fixture: PopulatedFixture,
        manifest: [String: Any]? = nil
    ) throws -> (status: Int32, output: String) {
        if let manifest {
            try writeJSON(manifest, to: fixture.manifestURL)
        }
        return try runVerifier(
            manifest: fixture.manifestURL,
            evidenceDirectory: fixture.evidence,
            releaseBinary: fixture.releaseBinary,
            debugExecutable: fixture.debugExecutable,
            collectorExecutable: fixture.collectorExecutable
        )
    }

    private func runVerifier(
        manifest: URL,
        evidenceDirectory: URL,
        releaseBinary: URL,
        debugExecutable: URL,
        collectorExecutable: URL? = nil,
        verificationMode: String = "--verify-request-ledger-contract"
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/run-ui-review-fixture.sh")
        process.arguments = [
            verificationMode,
            "--manifest", manifest.path,
            "--evidence-dir", evidenceDirectory.path,
            "--release-binary", releaseBinary.path,
            "--debug-executable", debugExecutable.path,
            "--collector-executable", (collectorExecutable ?? manifest.deletingLastPathComponent()
                .appendingPathComponent("ViftyAXCollector")).path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(
            decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }

    private func runCheckpointWriter(
        fixture: PopulatedFixture,
        collector: URL,
        sourceCommit: String,
        output: URL,
        hero: URL?
    ) throws -> (status: Int32, output: String) {
        var arguments = [
            "--repository-root", fixture.root.path,
            "--manifest", fixture.manifestURL.path,
            "--evidence-dir", fixture.evidence.path,
            "--debug-executable", fixture.debugExecutable.path,
            "--release-binary", fixture.releaseBinary.path,
            "--collector-executable", collector.path,
            "--source-commit", sourceCommit,
            "--output", output.path
        ]
        if let hero {
            arguments.append(contentsOf: ["--hero", hero.path])
        }
        return try runProcess(
            executable: repositoryRoot.appendingPathComponent("scripts/write-ui-review-checkpoint.rb"),
            arguments: arguments,
            currentDirectory: fixture.root
        )
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output, as: UTF8.self)
        )
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: AXCanonicalJSON.data(value)) as? [String: Any]
        )
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    private func canonicalJSONSHA256(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func sha256String(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func canonicalFilesystemPath(_ url: URL) throws -> String {
        guard let resolved = realpath(url.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
