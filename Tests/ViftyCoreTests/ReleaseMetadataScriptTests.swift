import Foundation
import XCTest

final class ReleaseMetadataScriptTests: XCTestCase {
    func testValidatorAcceptsAlignedReleaseMetadata() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release metadata OK: version 1.0.0"))
    }

    func testValidatorAcceptsManifestCandidateBeforeArtifactChecksumExists() throws {
        let harness = try ReleaseMetadataHarness(
            version: "1.1.0",
            caskVersion: "1.0.0",
            publishedVersion: "1.0.0",
            bundleBuild: 2,
            candidateVersion: "1.1.0",
            candidateBuild: 2
        )

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Release metadata OK: version 1.1.0"))
    }

    func testValidatorKeepsCaskOnPublishedReleaseWhenCandidateChecksumExists() throws {
        let expectedSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(
            version: "1.1.0",
            caskVersion: "1.0.0",
            publishedVersion: "1.0.0",
            bundleBuild: 2,
            candidateVersion: "1.1.0",
            candidateBuild: 2,
            candidateSHA: expectedSHA
        )

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 0, result.stderr)
    }

    func testValidatorRejectsCaskRepointedToUnpublishedCandidate() throws {
        let harness = try ReleaseMetadataHarness(
            version: "1.1.0",
            caskVersion: "1.1.0",
            publishedVersion: "1.0.0",
            bundleBuild: 2,
            candidateVersion: "1.1.0",
            candidateBuild: 2
        )

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("cask version 1.1.0 must remain on published manifest version 1.0.0"), result.stderr)
    }

    func testDeveloperIDValidatorRejectsBundleCaskVersionDrift() throws {
        let harness = try ReleaseMetadataHarness(version: "1.1.1", caskVersion: "1.1.0")

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("bundle version 1.1.1 does not match published manifest 1.1.0 or candidate null"), result.stderr)
    }

    func testDeveloperIDValidatorRejectsDisabledHomebrewCask() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Casks/vifty.rb must not be disabled for a Developer ID/Homebrew release"))
    }

    func testSourceFirstValidatorAllowsBundleVersionWithoutUpdatingDisabledHomebrew() throws {
        let harness = try ReleaseMetadataHarness(
            version: "1.1.1",
            caskVersion: "1.1.0",
            includeCaskDisable: true
        )

        let result = try harness.runValidator(["--mode", "source-first"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Source-first release metadata OK: bundle version 1.1.1, cask version 1.1.0"))
        XCTAssertTrue(result.stdout.contains("Homebrew cask is disabled and held until a future Developer ID release"))
        XCTAssertTrue(result.stdout.contains("source-first mode does not publish or require Vifty-v1.1.1.zip"))
    }

    func testSourceFirstValidatorRejectsEnabledHomebrewCask() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runValidator(["--mode", "source-first"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Casks/vifty.rb must remain disabled for a source-first release"))
    }

    func testSourceFirstValidatorRejectsSparkleUpdaterKeys() throws {
        let harness = try ReleaseMetadataHarness(
            sparkleInfoPlistKeys: ["SUFeedURL"],
            includeCaskDisable: true
        )

        let result = try harness.runValidator(["--mode", "source-first"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("source-first Info.plist must not include Sparkle updater metadata: SUFeedURL"))
    }

    func testSourceFirstValidatorRejectsGenericSparkleMetadataKeys() throws {
        let harness = try ReleaseMetadataHarness(
            sparkleInfoPlistKeys: ["SUFutureUpdaterKey"],
            includeCaskDisable: true
        )

        let result = try harness.runValidator(["--mode", "source-first"])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("source-first Info.plist must not include Sparkle updater metadata: SUFutureUpdaterKey"))
    }

    func testValidatorRejectsInvalidCaskSHA() throws {
        let harness = try ReleaseMetadataHarness(
            caskSHA: "not-a-real-sha",
            manifestSHA: String(repeating: "a", count: 64)
        )

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("lowercase 64-character SHA-256 checksum"))
    }

    func testValidatorRejectsAdHocCaskSigningIdentity() throws {
        let harness = try ReleaseMetadataHarness(includeAdHocSigningIdentity: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not declare ad-hoc signing"))
    }

    func testValidatorRejectsOldPrivilegedHelperCleanupPath() throws {
        let harness = try ReleaseMetadataHarness(privilegedHelperCleanupPath: "/Library/PrivilegedHelperTools/ViftyDaemon")

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("old ViftyDaemon privileged helper path"))
    }

    func testValidatorRejectsMissingSafeUninstallLifecycleScript() throws {
        let harness = try ReleaseMetadataHarness(privilegedHelperCleanupPath: nil)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must use the bundled safe uninstall lifecycle script"))
    }

    func testValidatorRejectsWorkflowWithoutTagVersionDerivation() throws {
        let harness = try ReleaseMetadataHarness(includeTagVersionDerivation: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must derive VERSION from the release tag"))
    }

    func testValidatorRejectsWorkflowWithoutTagPrefixCheck() throws {
        let harness = try ReleaseMetadataHarness(includeTagPrefixCheck: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must require release tags to start with v"))
    }

    func testValidatorRejectsWorkflowWithoutBundleVersionTagCheck() throws {
        let harness = try ReleaseMetadataHarness(includeBundleVersionTagCheck: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must compare release tag version to CFBundleShortVersionString"))
    }

    func testValidatorRejectsWorkflowWithoutValidatedVersionExport() throws {
        let harness = try ReleaseMetadataHarness(includeValidatedVersionExport: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must export the validated release VERSION"))
    }

    func testValidatorRejectsCIWorkflowWithoutNode24ActionsRuntime() throws {
        let harness = try ReleaseMetadataHarness(includeCIWorkflowNode24ActionsRuntime: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/ci.yml must opt GitHub JavaScript actions into Node.js 24"))
    }

    func testValidatorRejectsCIWorkflowUsingNode20CacheAction() throws {
        let harness = try ReleaseMetadataHarness(includeCINode24CacheAction: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/ci.yml must use actions/cache@v5 for native Node.js 24 support"))
    }

    func testValidatorRejectsCIWorkflowWithoutIsolatedSwiftBuildPath() throws {
        let harness = try ReleaseMetadataHarness(includeCIWorkflowSwiftBuildPath: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/ci.yml must isolate SwiftPM products with SWIFT_BUILD_PATH"))
    }

    func testValidatorRejectsCIWorkflowWithoutFullVerificationTarget() throws {
        let harness = try ReleaseMetadataHarness(includeCIWorkflowFullVerification: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/ci.yml must run make verify-full so GitHub Actions carries the slow XCTest suites"))
    }

    func testValidatorRejectsCIWorkflowWithRunnerTempInJobEnv() throws {
        let harness = try ReleaseMetadataHarness(includeCIWorkflowRunnerTempJobEnv: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/ci.yml must not use runner.temp in job-level SWIFT_BUILD_PATH env"))
    }

    func testValidatorRejectsReleaseWorkflowWithoutNode24ActionsRuntime() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseWorkflowNode24ActionsRuntime: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/release.yml must opt GitHub JavaScript actions into Node.js 24"))
    }

    func testValidatorRejectsReleaseWorkflowWithoutIsolatedSwiftBuildPath() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseWorkflowSwiftBuildPath: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/release.yml must isolate SwiftPM products with SWIFT_BUILD_PATH"))
    }

    func testValidatorRejectsReleaseWorkflowWithRunnerTempInJobEnv() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseWorkflowRunnerTempJobEnv: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains(".github/workflows/release.yml must not use runner.temp in job-level SWIFT_BUILD_PATH env"))
    }

    func testValidatorRejectsWorkflowWithoutNotarization() throws {
        let harness = try ReleaseMetadataHarness(includeNotarization: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must submit the app for notarization"))
    }

    func testValidatorRejectsWorkflowWithoutGatekeeperAssessment() throws {
        let harness = try ReleaseMetadataHarness(includeGatekeeperAssessment: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must run Gatekeeper assessment"))
    }

    func testValidatorRejectsWorkflowWithoutReleaseArtifactVerification() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseArtifactVerification: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must verify the release artifact before publishing"))
    }

    func testValidatorRejectsWorkflowThatSkipsReleaseSignatureChecks() throws {
        let harness = try ReleaseMetadataHarness(includeVerifierSkipSignatureChecks: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not skip release artifact signature checks"))
    }

    func testValidatorRejectsWorkflowThatSkipsReleaseNotarizationChecks() throws {
        let harness = try ReleaseMetadataHarness(includeVerifierSkipNotarizationChecks: true)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not skip release artifact notarization checks"))
    }

    func testValidatorRejectsWorkflowWithoutReleaseArtifactSummaryPublication() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseArtifactSummary: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must write a release artifact verification summary"))
    }

    func testValidatorRejectsWorkflowWithoutReleaseChecklistPublication() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseChecklist: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("release checklist"))
    }

    func testValidatorRejectsWorkflowWithoutReleaseTeamIDEnvironment() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseTeamIDEnvironment: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must bind protected signing to APPLE_TEAM_ID"), result.stderr)
    }

    func testValidatorRejectsAdHocXPCDevelopmentKeysInPublicReleaseMetadata() throws {
        let harness = try ReleaseMetadataHarness()
        let daemonPlist = harness.rootURL.appendingPathComponent("Resources/tech.reidar.vifty.daemon.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>EnvironmentVariables</key>
          <dict>
            <key>VIFTY_XPC_ALLOWED_TEAM_ID</key>
            <string>X88J3853S2</string>
            <key>VIFTY_XPC_ADHOC_ALLOWED_UID</key>
            <string>501</string>
          </dict>
        </dict>
        </plist>
        """.write(to: daemonPlist, atomically: true, encoding: .utf8)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("public release metadata must not contain VIFTY_XPC_ADHOC_* keys"), result.stderr)
    }

    func testValidatorRejectsWorkflowWithoutReleaseTeamIDBuildArgument() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseTeamIDBuildArgument: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must pass VIFTY_XPC_ALLOWED_TEAM_ID into make app"))
    }

    func testValidatorRejectsWorkflowWithoutLaunchDaemonTeamIDVerification() throws {
        let harness = try ReleaseMetadataHarness(includeLaunchDaemonTeamIDVerification: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must verify the bundled LaunchDaemon TeamID allowlist"))
    }

    func testValidatorRejectsWorkflowWithoutHelperIdentifierVerification() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseHelperIdentifierVerification: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must verify ViftyHelper signing identifier"))
    }

    func testValidatorRejectsWorkflowWithoutPublishedZipArtifact() throws {
        let harness = try ReleaseMetadataHarness(includePublishedZip: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must publish the notarized zip artifact"))
    }

    func testValidatorRejectsWorkflowWithoutPublishedChecksumArtifact() throws {
        let harness = try ReleaseMetadataHarness(includePublishedChecksum: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must publish the release artifact checksum"))
    }

    func testValidatorRejectsWorkflowWithoutExactRemoteTagIdentityGuard() throws {
        let harness = try ReleaseMetadataHarness(includeVerifyTag: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must verify the exact remote tag object and peeled commit"))
    }

    func testValidatorRejectsTagBasedReleaseMutation() throws {
        let harness = try ReleaseMetadataHarness()
        let workflowURL = harness.rootURL.appendingPathComponent(".github/workflows/release.yml")
        var workflow = try String(contentsOf: workflowURL, encoding: .utf8)
        workflow += "\n# regression fixture\ngh release edit \"${RELEASE_TAG}\" --draft=false\n"
        try workflow.write(to: workflowURL, atomically: true, encoding: .utf8)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not mutate a GitHub Release by tag"))
    }

    func testCaskChecksumUpdaterAppliesReleaseChecksumAndRevalidatesMetadata() throws {
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(manifestSHA: newSHA)
        let checksumFile = try harness.writeChecksumFile(contents: "\(newSHA)  .build/Vifty-v1.0.0.zip\n")

        let result = try harness.runCaskChecksumUpdater([
            "--checksum-file", checksumFile.path,
            "--version", "1.0.0"
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Updated"))
        XCTAssertTrue(result.stdout.contains(newSHA))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(newSHA)\""))
    }

    func testCaskChecksumUpdaterAtomicallyAdvancesPublishedVersionAndChecksum() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(
            version: "1.1.0",
            caskVersion: "1.0.0",
            caskSHA: oldSHA,
            manifestSHA: newSHA,
            publishedVersion: "1.1.0"
        )
        let checksumFile = try harness.writeChecksumFile(contents: "\(newSHA)  .build/Vifty-v1.1.0.zip\n")

        let result = try harness.runCaskChecksumUpdater([
            "--checksum-file", checksumFile.path,
            "--version", "1.1.0"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let cask = try harness.readCask()
        XCTAssertTrue(cask.contains("version \"1.1.0\""))
        XCTAssertTrue(cask.contains("sha256 \"\(newSHA)\""))
        XCTAssertFalse(cask.contains("version \"1.0.0\""))
    }

    func testCaskChecksumUpdaterRejectsMalformedChecksumWithoutEditingCask() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let harness = try ReleaseMetadataHarness(caskSHA: oldSHA)
        let checksumFile = try harness.writeChecksumFile(contents: "NOT-A-SHA  .build/Vifty-v1.0.0.zip\n")

        let result = try harness.runCaskChecksumUpdater(["--checksum-file", checksumFile.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("checksum file must start"))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(oldSHA)\""))
    }

    func testCaskChecksumUpdaterRejectsWrongArtifactVersionWithoutEditingCask() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(caskSHA: oldSHA)
        let checksumFile = try harness.writeChecksumFile(contents: "\(newSHA)  .build/Vifty-v9.9.9.zip\n")

        let result = try harness.runCaskChecksumUpdater(["--checksum-file", checksumFile.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("does not match Vifty-v1.0.0.zip"))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(oldSHA)\""))
    }

    func testCaskChecksumUpdaterRejectsChecksumNotAuthorizedByPublishedManifest() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let untrustedSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(caskSHA: oldSHA)
        let checksumFile = try harness.writeChecksumFile(contents: "\(untrustedSHA)  .build/Vifty-v1.0.0.zip\n")

        let result = try harness.runCaskChecksumUpdater(["--checksum-file", checksumFile.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("does not match published manifest checksum \(oldSHA)"))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(oldSHA)\""))
    }

    func testCaskChecksumUpdaterRejectsMetadataRegressionBeforeEditingCask() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(
            caskSHA: oldSHA,
            manifestSHA: newSHA,
            includeAdHocSigningIdentity: true
        )
        let checksumFile = try harness.writeChecksumFile(contents: "\(newSHA)  .build/Vifty-v1.0.0.zip\n")

        let result = try harness.runCaskChecksumUpdater(["--checksum-file", checksumFile.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not declare ad-hoc signing"))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(oldSHA)\""))
    }

    func testReleaseSecretPreflightAcceptsRequiredSecretNames() throws {
        let harness = try ReleaseMetadataHarness()
        let secretList = try harness.writeSecretList(contents: """
        APPLE_TEAM_ID\t2026-06-11T10:00:00Z
        APPLE_ID\t2026-06-11T10:00:00Z
        APPLE_APP_SPECIFIC_PASSWORD\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_IDENTITY\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD\t2026-06-11T10:00:00Z
        """)

        let result = try harness.runReleaseSecretChecker(["--secret-list-file", secretList.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release environment secrets OK for release"))
        XCTAssertTrue(result.stdout.contains("6 required names"))
    }

    func testReleaseSecretPreflightUsesReleaseEnvironmentAndFailsClosedWhenItIsAbsent() throws {
        let harness = try ReleaseMetadataHarness()
        let fakeBin = harness.rootURL.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let argumentsFile = harness.rootURL.appendingPathComponent("gh-arguments.txt")
        let fakeGH = fakeBin.appendingPathComponent("gh")
        try """
        #!/bin/sh
        printf '%s\n' "$@" > "$VIFTY_GH_ARGUMENTS_FILE"
        exit 1
        """.write(to: fakeGH, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGH.path)

        let result = try harness.runReleaseSecretChecker(
            ["--repo", "Reedtrullz/Vifty"],
            environment: [
                "PATH": "\(fakeBin.path):/usr/bin:/bin",
                "VIFTY_GH_ARGUMENTS_FILE": argumentsFile.path
            ]
        )

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertEqual(
            try String(contentsOf: argumentsFile, encoding: .utf8),
            "secret\nlist\n--env\nrelease\n--repo\nReedtrullz/Vifty\n"
        )
        XCTAssertTrue(result.stderr.contains("could not list GitHub Actions secrets for environment release"))
        XCTAssertTrue(result.stderr.contains("repository-scoped secrets do not satisfy this release gate"))
    }

    func testReleaseSecretPreflightRejectsMissingSecretNames() throws {
        let harness = try ReleaseMetadataHarness()
        let secretList = try harness.writeSecretList(contents: """
        APPLE_ID\t2026-06-11T10:00:00Z
        APPLE_APP_SPECIFIC_PASSWORD\t2026-06-11T10:00:00Z
        """)

        let result = try harness.runReleaseSecretChecker(["--secret-list-file", secretList.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Missing required release secret: APPLE_TEAM_ID"))
        XCTAssertTrue(result.stderr.contains("Missing required release secret: DEVELOPER_ID_APPLICATION_IDENTITY"))
        XCTAssertTrue(result.stderr.contains("Missing required release secret: DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64"))
        XCTAssertTrue(result.stderr.contains("Missing required release secret: DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD"))
        XCTAssertTrue(result.stderr.contains("docs/release.md"))
    }

    func testReleaseReadinessAcceptsCompleteTrustInputs() throws {
        let sourceSHA = String(repeating: "b", count: 40)
        let harness = try ReleaseMetadataHarness(
            publishedSourceCommit: sourceSHA,
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            headBranch: "main",
            event: "workflow_dispatch",
            displayTitle: "Release v1.0.0",
            attempt: 1
        )
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:2:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/release-readiness.schema.json"
        )
        XCTAssertEqual(summary["version"] as? String, "1.0.0")
        XCTAssertEqual(summary["tag"] as? String, "v1.0.0")
        XCTAssertEqual(summary["releaseMode"] as? String, "developer-id")
        XCTAssertEqual(summary["sourceCommit"] as? String, sourceSHA)
        XCTAssertEqual(summary["status"] as? String, "ready")
        XCTAssertEqual(summary["knownReadinessBlockersClear"] as? Bool, true)
        XCTAssertEqual(summary["blockers"] as? [String], [])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-mode", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-metadata", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-workflow", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-secrets", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "source-ci", in: checks)?.contains("exact manifest run 1") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("exact manifest run 2") == true)
    }

    func testReleaseReadinessAcceptsMainDispatchWhenTagCommitIsItsAncestor() throws {
        let harness = try ReleaseMetadataHarness(
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let sourceSHA = try harness.initializeGitRepoWithTaggedCommit(tag: "v1.0.0")
        try harness.rewritePublishedSourceCommit(sourceSHA)
        let dispatchSHA = try harness.appendGitCommit()
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: dispatchSHA,
            headBranch: "main",
            event: "workflow_dispatch",
            displayTitle: "Release v1.0.0",
            attempt: 1
        )
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:2:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "ready")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(
            checkMessage(named: "release-workflow", in: checks)?
                .contains("https://github.com/Reedtrullz/Vifty/actions/runs/2") == true
        )
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("dispatch source \(dispatchSHA)") == true)
    }

    func testReleaseReadinessRejectsTagPushRunForSignedManifestRelease() throws {
        let sourceSHA = String(repeating: "b", count: 40)
        let harness = try ReleaseMetadataHarness(
            publishedSourceCommit: sourceSHA,
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:2:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["release-workflow"])
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        let message = try XCTUnwrap(checkMessage(named: "release-workflow", in: checks))
        XCTAssertTrue(message.contains("event \"push\" is not workflow_dispatch"))
        XCTAssertTrue(message.contains("headBranch \"v1.0.0\" is not main"))
    }

    func testReleaseReadinessRejectsWrongManifestRunIDs() throws {
        let sourceSHA = String(repeating: "b", count: 40)
        let harness = try ReleaseMetadataHarness(
            publishedSourceCommit: sourceSHA,
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA, databaseID: 99)
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            databaseID: 98,
            headBranch: "main",
            event: "workflow_dispatch",
            displayTitle: "Release v1.0.0",
            attempt: 1
        )
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:2:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["source-ci", "release-workflow"])
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checkMessage(named: "source-ci", in: checks)?.contains("manifest ID 1, found 0") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("manifest ID 2, found 0") == true)
    }

    func testReleaseReadinessRejectsDispatchTitleAndReleaseOwnerMarkerDrift() throws {
        let sourceSHA = String(repeating: "b", count: 40)
        let harness = try ReleaseMetadataHarness(
            publishedSourceCommit: sourceSHA,
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            headBranch: "main",
            event: "workflow_dispatch",
            displayTitle: "Release v9.9.9",
            attempt: 1
        )
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:99:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["release-workflow", "github-release"])
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("does not bind input v1.0.0") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("marker run 99 does not match manifest run 2") == true)
    }

    func testReleaseReadinessRejectsSameNameRunsFromWrongWorkflowPaths() throws {
        let sourceSHA = String(repeating: "b", count: 40)
        let harness = try ReleaseMetadataHarness(
            publishedSourceCommit: sourceSHA,
            publishedTagTrust: "signed-verified",
            signedTagBoundary: "1.0.0"
        )
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(
            sourceSHA: sourceSHA,
            path: ".github/workflows/not-ci.yml"
        )
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            headBranch: "main",
            event: "workflow_dispatch",
            displayTitle: "Release v1.0.0",
            attempt: 1,
            path: ".github/workflows/not-release.yml"
        )
        let releaseView = try harness.writeReleaseView(
            body: "<!-- vifty-release-owner:2:1:\(String(repeating: "a", count: 64)) -->"
        )

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["source-ci", "release-workflow"])
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(checkMessage(named: "source-ci", in: checks)?.contains("workflow path") == true)
        XCTAssertTrue(checkMessage(named: "source-ci", in: checks)?.contains(".github/workflows/ci.yml") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("workflow path") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains(".github/workflows/release.yml") == true)
    }

    func testReleaseReadinessKeepsHistoricalTagPushCompatibility() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "ready")
        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertTrue(
            checkMessage(named: "release-workflow", in: checks)?
                .contains("https://github.com/Reedtrullz/Vifty/actions/runs/2") == true
        )
    }

    func testReleaseReadinessAcceptsMatchingRequiredSourceRef() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--require-source-ref", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "ready")
        XCTAssertEqual(summary["blockers"] as? [String], [])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-source-ref", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-source-ref", in: checks)?.contains("matches required source ref") == true)
    }

    func testReleaseReadinessRejectsSourceSHAMismatchWhenLocalTagResolves() throws {
        let harness = try ReleaseMetadataHarness()
        let tagSHA = try harness.initializeGitRepoWithTaggedCommit(tag: "v1.0.0")
        try harness.rewritePublishedSourceCommit(tagSHA)
        let suppliedSHA = String(repeating: "c", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: tagSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: tagSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", suppliedSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["sourceCommit"] as? String, tagSHA)
        XCTAssertEqual(summary["blockers"] as? [String], ["release-source-ref"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-source-ref", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-workflow", in: checks), "passed")
        let message = try XCTUnwrap(checkMessage(named: "release-source-ref", in: checks))
        XCTAssertTrue(message.contains("resolves locally to \(tagSHA)"))
        XCTAssertTrue(message.contains("--source-sha supplied \(suppliedSHA)"))
    }

    func testReleaseReadinessRejectsAbbreviatedSourceSHA() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", "bbbbbbb",
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("--source-sha must be a 40-character hexadecimal commit SHA"))
        XCTAssertTrue(result.stdout.isEmpty)
    }

    func testReleaseReadinessBlocksStaleRequiredSourceRef() throws {
        let harness = try ReleaseMetadataHarness()
        let tagSHA = String(repeating: "b", count: 40)
        let requiredSHA = String(repeating: "c", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: tagSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: tagSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", tagSHA,
            "--require-source-ref", requiredSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["release-source-ref"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-source-ref", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-source-ref", in: checks)?.contains("points to \(tagSHA)") == true)
        XCTAssertTrue(checkMessage(named: "release-source-ref", in: checks)?.contains("resolves to \(requiredSHA)") == true)
    }

    func testReleaseReadinessReportsMissingSecretsAsBlocker() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeSecretList(contents: """
        APPLE_ID\t2026-06-11T10:00:00Z
        APPLE_APP_SPECIFIC_PASSWORD\t2026-06-11T10:00:00Z
        """)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["knownReadinessBlockersClear"] as? Bool, false)
        XCTAssertEqual(summary["blockers"] as? [String], ["release-secrets"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-secrets", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-secrets", in: checks)?.contains("APPLE_TEAM_ID") == true)
    }

    func testReleaseReadinessBlocksMissingReleaseAssets() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(assetNames: [
            "Vifty-v1.0.0.zip"
        ])

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("missing assets") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("Vifty-v1.0.0.zip.sha256") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("Vifty-v1.0.0-artifact-summary.json") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("Vifty-v1.0.0-release-checklist.md") == true)
    }

    func testDeveloperIDReadinessRejectsUnsignedDevAssetsOnTrustedRelease() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(assetNames: [
            "Vifty-v1.0.0.zip",
            "Vifty-v1.0.0.zip.sha256",
            "Vifty-v1.0.0-artifact-summary.json",
            "Vifty-v1.0.0-release-checklist.md",
            "Vifty-v1.0.0-unsigned-dev.zip",
            "Vifty-v1.0.0-unsigned-dev.zip.sha256"
        ])

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        let message = try XCTUnwrap(checkMessage(named: "github-release", in: checks))
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertTrue(message.contains("Developer ID releases must not publish source-first unsigned-dev assets"))
        XCTAssertTrue(message.contains("Vifty-v1.0.0-unsigned-dev.zip"))
        XCTAssertTrue(message.contains("Vifty-v1.0.0-unsigned-dev.zip.sha256"))
    }

    func testReleaseReadinessBlocksFailedReleaseWorkflowSeparatelyFromMissingAssets() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            status: "completed",
            conclusion: "failure"
        )
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["release-workflow"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-workflow", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "release-secrets", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("completed/failure") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("https://github.com/Reedtrullz/Vifty/actions/runs/2") == true)
    }

    func testSourceFirstReadinessAcceptsUnsignedDevAssetsWithoutAppleSecretsOrReleaseWorkflow() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let unsignedDevAssets = try harness.writeUnsignedDevReleaseAssets()
        let releaseRunList = try harness.writeReleaseRunList(
            sourceSHA: sourceSHA,
            status: "completed",
            conclusion: "failure"
        )
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--unsigned-dev-artifact-file", unsignedDevAssets.zip.path,
            "--unsigned-dev-checksum-file", unsignedDevAssets.checksum.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["releaseMode"] as? String, "source-first")
        XCTAssertEqual(summary["status"] as? String, "ready")
        XCTAssertEqual(summary["blockers"] as? [String], [])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-mode", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-metadata", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-workflow", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "release-secrets", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "source-first-unsigned-dev-assets", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-metadata", in: checks)?.contains("source-first mode does not publish or require Vifty-v1.0.0.zip") == true)
        XCTAssertFalse(checkMessage(named: "release-metadata", in: checks)?.contains("artifact Vifty-v1.0.0.zip") == true)
        XCTAssertTrue(checkMessage(named: "release-workflow", in: checks)?.contains("does not require") == true)
        XCTAssertTrue(checkMessage(named: "release-secrets", in: checks)?.contains("does not require Apple Developer Program secrets") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("unsigned tester assets") == true)
        XCTAssertTrue(checkMessage(named: "source-first-unsigned-dev-assets", in: checks)?.contains("checksum verified") == true)
    }

    func testSourceFirstReadinessRejectsUnsignedDevAssetsWithoutSidecarWarning() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let unsignedDevAssets = try harness.writeUnsignedDevReleaseAssets()
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(
                version: "1.0.0",
                includeUnsignedDevSidecarWarning: false
            )
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--unsigned-dev-artifact-file", unsignedDevAssets.zip.path,
            "--unsigned-dev-checksum-file", unsignedDevAssets.checksum.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "source-first-unsigned-dev-assets", in: checks), "passed")
        let message = try XCTUnwrap(checkMessage(named: "github-release", in: checks))
        XCTAssertTrue(message.contains("release notes for unsigned-dev assets must include"))
        XCTAssertTrue(message.contains("Vifty-v1.0.0-unsigned-dev.zip"))
        XCTAssertTrue(message.contains("Vifty-v1.0.0-unsigned-dev.zip.sha256"))
        XCTAssertTrue(message.contains("The unsigned-dev zip is valid only with its `.sha256` sidecar"))
        XCTAssertTrue(message.contains("SHA-256 digest in that sidecar must match the zip bytes"))
    }

    func testSourceFirstReadinessAcceptsReleaseWithoutUnsignedDevAssets() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "ready")
        XCTAssertEqual(summary["blockers"] as? [String], [])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "source-first-unsigned-dev-assets", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "source-first-unsigned-dev-assets", in: checks)?.contains("No unsigned-dev tester assets published") == true)
    }

    func testSourceFirstReadinessRejectsUnsignedDevChecksumMismatch() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let unsignedDevAssets = try harness.writeUnsignedDevReleaseAssets(
            checksumContents: "\(String(repeating: "0", count: 64))  Vifty-v1.0.0-unsigned-dev.zip\n"
        )
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--unsigned-dev-artifact-file", unsignedDevAssets.zip.path,
            "--unsigned-dev-checksum-file", unsignedDevAssets.checksum.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["source-first-unsigned-dev-assets"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "source-first-unsigned-dev-assets", in: checks), "blocked")
        let message = try XCTUnwrap(checkMessage(named: "source-first-unsigned-dev-assets", in: checks))
        XCTAssertTrue(message.contains("checksum mismatch"))
        XCTAssertTrue(message.contains("Vifty-v1.0.0-unsigned-dev.zip"))
    }

    func testSourceFirstReadinessAllowsHomebrewCaskToRemainOnPriorVersion() throws {
        let harness = try ReleaseMetadataHarness(
            version: "1.1.1",
            caskVersion: "1.1.0",
            includeCaskDisable: true
        )
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let unsignedDevAssets = try harness.writeUnsignedDevReleaseAssets(version: "1.1.1")
        let releaseView = try harness.writeReleaseView(
            version: "1.1.1",
            assetNames: [
                "Vifty-v1.1.1-unsigned-dev.zip",
                "Vifty-v1.1.1-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.1.1")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.1.1",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--unsigned-dev-artifact-file", unsignedDevAssets.zip.path,
            "--unsigned-dev-checksum-file", unsignedDevAssets.checksum.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 0)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "ready")

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-metadata", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "release-metadata", in: checks)?.contains("bundle version 1.1.1, cask version 1.1.0") == true)
        XCTAssertTrue(checkMessage(named: "release-metadata", in: checks)?.contains("Homebrew cask is disabled and held") == true)
        XCTAssertTrue(checkMessage(named: "release-metadata", in: checks)?.contains("source-first mode does not publish or require Vifty-v1.1.1.zip") == true)
    }

    func testSourceFirstReadinessRejectsEnabledHomebrewCask() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["release-metadata"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "release-metadata", in: checks), "blocked")
        XCTAssertTrue(checkMessage(named: "release-metadata", in: checks)?.contains("Casks/vifty.rb must remain disabled for a source-first release") == true)
    }

    func testSourceFirstReadinessRejectsCanonicalTrustedBinaryAssets() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0.zip",
                "Vifty-v1.0.0.zip.sha256",
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["releaseMode"] as? String, "source-first")
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("must not publish canonical trusted binary assets") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("Vifty-v1.0.0.zip") == true)
    }

    func testSourceFirstReadinessRejectsTrustedUpdaterAndHomebrewClaims() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0") + """

            Auto-update is available. The Homebrew cask is updated. The attached app is the official trusted binary.
            This is a Developer ID signed app, notarized app, Gatekeeper approved, and Homebrew-trusted.
            """
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        let message = try XCTUnwrap(checkMessage(named: "github-release", in: checks))
        XCTAssertTrue(message.contains("auto-update is available"))
        XCTAssertTrue(message.contains("Homebrew cask is updated"))
        XCTAssertTrue(message.contains("official trusted binary"))
        XCTAssertTrue(message.contains("Developer ID signed app"))
        XCTAssertTrue(message.contains("notarized app"))
        XCTAssertTrue(message.contains("Gatekeeper approved"))
        XCTAssertTrue(message.contains("Homebrew-trusted"))
    }

    func testSourceFirstReadinessRejectsUnsignedDevZipWithoutChecksum() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0")
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("is present without Vifty-v1.0.0-unsigned-dev.zip.sha256") == true)
    }

    func testSourceFirstReadinessRejectsReleaseNotesWithoutSourceProvenance() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let ciRunList = try harness.writeCIRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView(
            assetNames: [
                "Vifty-v1.0.0-unsigned-dev.zip",
                "Vifty-v1.0.0-unsigned-dev.zip.sha256"
            ],
            body: sourceFirstReleaseNotes(version: "1.0.0", includeProvenance: false)
        )

        let result = try harness.runReleaseReadiness([
            "--mode", "source-first",
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--ci-run-list-file", ciRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["blockers"] as? [String], ["github-release"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "blocked")
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("## Source Provenance") == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains(sourceSHA) == true)
        XCTAssertTrue(checkMessage(named: "github-release", in: checks)?.contains("post-release hardening") == true)
    }

    func testReleaseReadinessBlocksFailedSourceCI() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let secretList = try harness.writeRequiredSecretList()
        let ciRunList = try harness.writeCIRunList(
            sourceSHA: sourceSHA,
            status: "completed",
            conclusion: "failure"
        )
        let releaseRunList = try harness.writeReleaseRunList(sourceSHA: sourceSHA)
        let releaseView = try harness.writeReleaseView()

        let result = try harness.runReleaseReadiness([
            "--version", "1.0.0",
            "--source-sha", sourceSHA,
            "--secret-list-file", secretList.path,
            "--ci-run-list-file", ciRunList.path,
            "--release-run-list-file", releaseRunList.path,
            "--release-view-file", releaseView.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 1)
        let summary = try decodeReadinessSummary(result.stdout)
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["blockers"] as? [String], ["source-ci"])

        let checks = try XCTUnwrap(summary["checks"] as? [[String: Any]])
        XCTAssertEqual(checkStatus(named: "source-ci", in: checks), "blocked")
        XCTAssertEqual(checkStatus(named: "release-secrets", in: checks), "passed")
        XCTAssertEqual(checkStatus(named: "github-release", in: checks), "passed")
        XCTAssertTrue(checkMessage(named: "source-ci", in: checks)?.contains("Manifest CI run 1 is invalid: status is completed/failure") == true)
    }

    func testReleaseChecklistWriterCreatesChecklistForVersion() throws {
        let harness = try ReleaseMetadataHarness()
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-release-checklist.md")

        let result = try harness.runReleaseChecklistWriter([
            "--version", "1.2.3",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Wrote"))

        let checklist = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(checklist.contains("# Vifty 1.2.3 Release Checklist"))
        XCTAssertTrue(checklist.contains("Verified By The Release Workflow"))
        XCTAssertTrue(checklist.contains("Required Post-Publication Follow-Up"))
        XCTAssertTrue(checklist.contains("Vifty-v1.2.3.zip"))
        XCTAssertTrue(checklist.contains("scripts/update-cask-checksum.sh --version 1.2.3"))
        XCTAssertTrue(checklist.contains("make validation-evidence-review"))
        XCTAssertTrue(checklist.contains("VALIDATION_EVIDENCE_REVIEW_MODE=release"))
        XCTAssertTrue(checklist.contains("manualSmokeTestResult: \"passed-auto-restored\""))
        XCTAssertTrue(checklist.contains("do not describe the Homebrew path as a fully trusted public binary install"))
        XCTAssertFalse(checklist.contains("Source Provenance"))
        XCTAssertFalse(checklist.contains("Source commit"))
    }

    func testReleaseChecklistWriterResolvesExplicitRelativeOutputFromInvocationDirectory() throws {
        let harness = try ReleaseMetadataHarness()
        let invocationDirectory = harness.rootURL.appendingPathComponent("workflow-job", isDirectory: true)
        try FileManager.default.createDirectory(at: invocationDirectory, withIntermediateDirectories: true)

        let result = try harness.runReleaseChecklistWriter(
            [
                "--version", "1.2.3",
                "--output", ".build/release-output/Vifty-v1.2.3-release-checklist.md"
            ],
            currentDirectoryURL: invocationDirectory
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let expectedOutput = invocationDirectory
            .appendingPathComponent(".build/release-output/Vifty-v1.2.3-release-checklist.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedOutput.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: harness.rootURL
                    .appendingPathComponent(".build/release-output/Vifty-v1.2.3-release-checklist.md")
                    .path
            )
        )
    }

    func testReleaseChecklistWriterCreatesSourceFirstReleaseNotes() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = try harness.initializeGitRepoWithTaggedCommit(tag: "v1.2.3")
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-source-first-release-notes.md")

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Wrote"))

        let notes = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(notes.contains("# Vifty 1.2.3 Source-First Release Notes"))
        XCTAssertTrue(notes.contains("This is a source-first release. Vifty v1.2.3 does not yet include a Developer ID signed or notarized public binary"))
        XCTAssertTrue(notes.contains("For the most trusted path, build from source."))
        XCTAssertTrue(notes.contains("## Source Provenance"))
        XCTAssertTrue(notes.contains("- Source ref: `v1.2.3`"))
        XCTAssertTrue(notes.contains("- Source commit: `\(sourceSHA)`"))
        XCTAssertTrue(notes.contains("The `v1.2.3` tag is the source release boundary at commit `\(sourceSHA)`."))
        XCTAssertFalse(notes.contains("Record the immutable tag commit SHA before publishing"))
        XCTAssertTrue(notes.contains("Later `main` commits are post-release hardening until a future release is cut."))
        XCTAssertTrue(notes.contains("Vifty-v1.2.3-unsigned-dev.zip"))
        XCTAssertTrue(notes.contains("Vifty-v1.2.3-unsigned-dev.zip.sha256"))
        XCTAssertTrue(notes.contains("The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes."))
        XCTAssertTrue(notes.contains("Any attached unsigned-dev zip uses the `Vifty-v1.2.3-unsigned-dev.zip` name and has a `.sha256` sidecar whose digest matches the zip bytes."))
        XCTAssertTrue(notes.contains("Do not use `Vifty-v1.2.3.zip` for the unsigned build"))
        XCTAssertTrue(notes.contains("Do not update the Homebrew cask for this source-first release."))
        XCTAssertTrue(notes.contains("--require-source-ref <candidate-ref-or-sha>"))
        XCTAssertTrue(notes.contains("After publication, `scripts/check-release-readiness.sh --mode source-first --version 1.2.3 --repo Reedtrullz/Vifty --json` passed"))
        XCTAssertTrue(notes.contains("Do not require `origin/main` after `main` has moved on."))
        XCTAssertFalse(notes.contains("source-first --version 1.2.3 --repo Reedtrullz/Vifty --require-source-ref origin/main"))
    }

    func testReleaseChecklistWriterAcceptsExplicitMatchingSourceRefAndSHA() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "b", count: 40)
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-source-first-release-notes.md")

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--source-ref", sourceSHA.uppercased(),
            "--source-sha", sourceSHA,
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let notes = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(notes.contains("- Source ref: `\(sourceSHA.uppercased())`"))
        XCTAssertTrue(notes.contains("- Source commit: `\(sourceSHA)`"))
        XCTAssertFalse(notes.contains("Record the immutable tag commit SHA"))
    }

    func testReleaseChecklistWriterAcceptsSourceSHAWithoutPretendingTagResolved() throws {
        let harness = try ReleaseMetadataHarness()
        let sourceSHA = String(repeating: "d", count: 40)
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-source-first-release-notes.md")

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--source-sha", sourceSHA,
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        let notes = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(notes.contains("- Source ref: `\(sourceSHA)`"))
        XCTAssertTrue(notes.contains("- Source commit: `\(sourceSHA)`"))
        XCTAssertTrue(notes.contains("The `\(sourceSHA)` source ref is the source release boundary at commit `\(sourceSHA)`."))
        XCTAssertFalse(notes.contains("The `v1.2.3` tag is the source release boundary at commit `\(sourceSHA)`."))
    }

    func testReleaseChecklistWriterRejectsMismatchedSourceRefAndSHA() throws {
        let harness = try ReleaseMetadataHarness()
        let refSHA = String(repeating: "b", count: 40)
        let sourceSHA = String(repeating: "c", count: 40)
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-source-first-release-notes.md")

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--source-ref", refSHA,
            "--source-sha", sourceSHA,
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("source ref"))
        XCTAssertTrue(result.stderr.contains("does not match --source-sha"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testReleaseChecklistWriterFailsSourceFirstWhenDefaultTagCannotResolve() throws {
        let harness = try ReleaseMetadataHarness()
        let output = harness.rootURL.appendingPathComponent("Vifty-v1.2.3-source-first-release-notes.md")

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--output", output.path
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("could not resolve source ref v1.2.3"))
        XCTAssertTrue(result.stderr.contains("run git fetch origin --tags"))
        XCTAssertTrue(result.stderr.contains("--source-ref"))
        XCTAssertTrue(result.stderr.contains("--source-sha"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testReleaseChecklistWriterRejectsMalformedSourceSHA() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runReleaseChecklistWriter([
            "--mode", "source-first",
            "--version", "1.2.3",
            "--source-sha", "bbbbbbb"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("--source-sha must be a 40-character hexadecimal commit SHA"))
    }

    func testReleaseChecklistWriterRejectsMalformedVersion() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runReleaseChecklistWriter(["--version", "1.x"])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("release version must be a SemVer-like value"))
    }

    func testUnsignedDevArtifactBuilderAcceptsMatchingRequiredSourceRef() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        try harness.writeUnsignedDevAppBundleFixture()
        let output = harness.rootURL.appendingPathComponent("unsigned-output", isDirectory: true)
        let sourceSHA = String(repeating: "b", count: 40)

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.0.0",
            "--skip-build",
            "--output-dir", output.path,
            "--source-sha", sourceSHA,
            "--require-source-ref", sourceSHA.uppercased()
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Source provenance OK"))
        XCTAssertTrue(result.stdout.contains("Vifty-v1.0.0-unsigned-dev.zip"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.0.0-unsigned-dev.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.0.0-unsigned-dev.zip.sha256").path))
    }

    func testUnsignedDevArtifactBuilderRejectsSparkleUpdaterKeysBeforeZip() throws {
        let harness = try ReleaseMetadataHarness(
            sparkleInfoPlistKeys: ["SUPublicEDKey"],
            includeCaskDisable: true
        )
        try harness.writeUnsignedDevAppBundleFixture()
        let output = harness.rootURL.appendingPathComponent("unsigned-output", isDirectory: true)

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.0.0",
            "--skip-build",
            "--output-dir", output.path
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("source-first Info.plist must not include Sparkle updater metadata: SUPublicEDKey"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.0.0-unsigned-dev.zip").path))
    }

    func testUnsignedDevArtifactBuilderRejectsStaleAppBundleSparkleKeysBeforeZip() throws {
        let harness = try ReleaseMetadataHarness(includeCaskDisable: true)
        try harness.writeUnsignedDevAppBundleFixture(sparkleInfoPlistKeys: ["SUFeedURL"])
        let output = harness.rootURL.appendingPathComponent("unsigned-output", isDirectory: true)

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.0.0",
            "--skip-build",
            "--output-dir", output.path
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("unsigned-dev app bundle must not include Sparkle updater metadata: SUFeedURL"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.0.0-unsigned-dev.zip").path))
    }

    func testUnsignedDevArtifactBuilderRejectsRequiredSourceRefDrift() throws {
        let harness = try ReleaseMetadataHarness()
        try harness.writeUnsignedDevAppBundleFixture()
        let output = harness.rootURL.appendingPathComponent("unsigned-output", isDirectory: true)
        let sourceSHA = String(repeating: "b", count: 40)
        let requiredSHA = String(repeating: "c", count: 40)

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.0.0",
            "--skip-build",
            "--output-dir", output.path,
            "--source-sha", sourceSHA,
            "--require-source-ref", requiredSHA
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("refusing to build Vifty-v1.0.0-unsigned-dev.zip from source \(sourceSHA)"))
        XCTAssertTrue(result.stderr.contains("required source ref \(requiredSHA) resolves to \(requiredSHA)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.0.0-unsigned-dev.zip").path))
    }

    func testUnsignedDevArtifactBuilderRequiresGitOrSourceSHAForRequiredSourceRef() throws {
        let harness = try ReleaseMetadataHarness()
        try harness.writeUnsignedDevAppBundleFixture()

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.0.0",
            "--skip-build",
            "--require-source-ref", "v1.0.0"
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("--require-source-ref needs a Git checkout or explicit --source-sha"))
    }

    func testUnsignedDevArtifactBuilderExplainsMissingRequiredSourceRef() throws {
        let harness = try ReleaseMetadataHarness()
        try harness.writeUnsignedDevAppBundleFixture()
        let output = harness.rootURL.appendingPathComponent("unsigned-output", isDirectory: true)

        let result = try harness.runUnsignedDevArtifactBuilder([
            "--version", "1.1.1",
            "--skip-build",
            "--output-dir", output.path,
            "--source-sha", String(repeating: "b", count: 40),
            "--require-source-ref", "v1.1.1"
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("could not resolve required source ref v1.1.1"))
        XCTAssertTrue(result.stderr.contains("run git fetch origin --tags before building a release attachment"))
        XCTAssertTrue(result.stderr.contains("pass an explicit commit SHA to --require-source-ref"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Vifty-v1.1.1-unsigned-dev.zip").path))
    }

    private func decodeReadinessSummary(_ stdout: String) throws -> [String: Any] {
        let data = Data(stdout.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func checkStatus(named name: String, in checks: [[String: Any]]) -> String? {
        checks.first { $0["name"] as? String == name }?["status"] as? String
    }

    private func checkMessage(named name: String, in checks: [[String: Any]]) -> String? {
        checks.first { $0["name"] as? String == name }?["message"] as? String
    }

    private func sourceFirstReleaseNotes(
        version: String,
        includeProvenance: Bool = true,
        includeUnsignedDevSidecarWarning: Bool = true
    ) -> String {
        var notes = """
        This is a source-first release. Vifty v\(version) does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.

        A convenience unsigned `.app` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.
        """
        if includeUnsignedDevSidecarWarning {
            notes += """

            Unsigned-dev artifact integrity: `Vifty-v\(version)-unsigned-dev.zip` is accompanied by `Vifty-v\(version)-unsigned-dev.zip.sha256`. The unsigned-dev zip is valid only with its `.sha256` sidecar. The SHA-256 digest in that sidecar must match the zip bytes before opening the app.
            """
        }
        if includeProvenance {
            notes += """

            ## Source Provenance

            The `v\(version)` tag is the source release boundary. Record the immutable tag commit SHA before publishing: \(String(repeating: "b", count: 40)). Later `main` commits are post-release hardening until a future release is cut.
            """
        }
        return notes
    }
}

private struct ReleaseMetadataProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

private final class ReleaseMetadataHarness {
    let rootURL: URL

    init(
        version: String = "1.0.0",
        sparkleInfoPlistKeys: [String] = [],
        caskVersion: String? = nil,
        caskSHA: String = String(repeating: "a", count: 64),
        manifestSHA: String? = nil,
        publishedVersion: String? = nil,
        publishedSourceCommit: String = String(repeating: "b", count: 40),
        publishedSourceCIRunID: Int = 1,
        publishedReleaseWorkflowRunID: Int = 2,
        publishedTagTrust: String = "historical-unsigned",
        signedTagBoundary: String? = nil,
        bundleBuild: Int = 1,
        candidateVersion: String? = nil,
        candidateBuild: Int = 2,
        candidateSHA: String? = nil,
        includeAdHocSigningIdentity: Bool = false,
        privilegedHelperCleanupPath: String? = "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
        includeTagVersionDerivation: Bool = true,
        includeTagPrefixCheck: Bool = true,
        includeBundleVersionTagCheck: Bool = true,
        includeValidatedVersionExport: Bool = true,
        includeNotarization: Bool = true,
        includeGatekeeperAssessment: Bool = true,
        includeReleaseArtifactVerification: Bool = true,
        includeVerifierSkipSignatureChecks: Bool = false,
        includeVerifierSkipNotarizationChecks: Bool = false,
        includeReleaseArtifactSummary: Bool = true,
        includeReleaseTeamIDEnvironment: Bool = true,
        includeReleaseTeamIDBuildArgument: Bool = true,
        includeLaunchDaemonTeamIDVerification: Bool = true,
        includeReleaseHelperIdentifierVerification: Bool = true,
        includePublishedZip: Bool = true,
        includePublishedChecksum: Bool = true,
        includeReleaseChecklist: Bool = true,
        includeVerifyTag: Bool = true,
        includeCIWorkflowNode24ActionsRuntime: Bool = true,
        includeCINode24CacheAction: Bool = true,
        includeCIWorkflowSwiftBuildPath: Bool = true,
        includeCIWorkflowFullVerification: Bool = true,
        includeCIWorkflowRunnerTempJobEnv: Bool = false,
        includeReleaseWorkflowNode24ActionsRuntime: Bool = true,
        includeReleaseWorkflowSwiftBuildPath: Bool = true,
        includeReleaseWorkflowRunnerTempJobEnv: Bool = false,
        includeCaskDisable: Bool = false
    ) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-release-metadata-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Casks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent(".github/workflows", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("docs/schemas", isDirectory: true),
            withIntermediateDirectories: true
        )
        let fixtureScripts = rootURL.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureScripts, withIntermediateDirectories: true)
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for scriptName in [
            "check-release-manifest-history-from-git.sh",
            "check-release-manifest-history.rb"
        ] {
            try FileManager.default.copyItem(
                at: repositoryRoot.appendingPathComponent("scripts/\(scriptName)"),
                to: fixtureScripts.appendingPathComponent(scriptName)
            )
        }

        let caskReleaseVersion = caskVersion ?? version
        let manifestPublishedVersion = publishedVersion ?? caskReleaseVersion
        try writeReleaseManifest(
            version: manifestPublishedVersion,
            sha: manifestSHA ?? caskSHA,
            sourceCommit: publishedSourceCommit,
            sourceCIRunID: publishedSourceCIRunID,
            releaseWorkflowRunID: publishedReleaseWorkflowRunID,
            tagTrust: publishedTagTrust,
            signedTagBoundary: signedTagBoundary,
            candidateVersion: candidateVersion,
            candidateBuild: candidateBuild,
            candidateSHA: candidateSHA
        )
        try writeInfoPlist(version: version, build: bundleBuild, sparkleKeys: sparkleInfoPlistKeys)
        try writeCask(
            version: caskReleaseVersion,
            sha: caskSHA,
            includeAdHocSigningIdentity: includeAdHocSigningIdentity,
            privilegedHelperCleanupPath: privilegedHelperCleanupPath,
            includeCaskDisable: includeCaskDisable
        )
        try writeCIWorkflow(
            includeNode24ActionsRuntime: includeCIWorkflowNode24ActionsRuntime,
            includeNode24CacheAction: includeCINode24CacheAction,
            includeSwiftBuildPath: includeCIWorkflowSwiftBuildPath,
            includeFullVerification: includeCIWorkflowFullVerification,
            includeRunnerTempJobEnv: includeCIWorkflowRunnerTempJobEnv
        )
        try writeReleaseWorkflow(
            includeTagVersionDerivation: includeTagVersionDerivation,
            includeTagPrefixCheck: includeTagPrefixCheck,
            includeBundleVersionTagCheck: includeBundleVersionTagCheck,
            includeValidatedVersionExport: includeValidatedVersionExport,
            includeNotarization: includeNotarization,
            includeGatekeeperAssessment: includeGatekeeperAssessment,
            includeReleaseArtifactVerification: includeReleaseArtifactVerification,
            includeVerifierSkipSignatureChecks: includeVerifierSkipSignatureChecks,
            includeVerifierSkipNotarizationChecks: includeVerifierSkipNotarizationChecks,
            includeReleaseArtifactSummary: includeReleaseArtifactSummary,
            includeReleaseTeamIDEnvironment: includeReleaseTeamIDEnvironment,
            includeReleaseTeamIDBuildArgument: includeReleaseTeamIDBuildArgument,
            includeLaunchDaemonTeamIDVerification: includeLaunchDaemonTeamIDVerification,
            includeReleaseHelperIdentifierVerification: includeReleaseHelperIdentifierVerification,
            includePublishedZip: includePublishedZip,
            includePublishedChecksum: includePublishedChecksum,
            includeReleaseChecklist: includeReleaseChecklist,
            includeVerifyTag: includeVerifyTag,
            includeNode24ActionsRuntime: includeReleaseWorkflowNode24ActionsRuntime,
            includeSwiftBuildPath: includeReleaseWorkflowSwiftBuildPath,
            includeRunnerTempJobEnv: includeReleaseWorkflowRunnerTempJobEnv
        )
    }

    func runValidator(_ arguments: [String] = []) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/validate-release-metadata.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runCaskChecksumUpdater(_ arguments: [String]) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/update-cask-checksum.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runReleaseSecretChecker(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/check-release-secrets.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            environment.merging(
                ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
                uniquingKeysWith: { old, _ in old }
            ),
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runReleaseReadiness(_ arguments: [String]) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/check-release-readiness.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runReleaseChecklistWriter(
        _ arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/write-release-checklist.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func runUnsignedDevArtifactBuilder(_ arguments: [String]) throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/build-unsigned-dev-artifact.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["VIFTY_RELEASE_METADATA_ROOT": rootURL.path],
            uniquingKeysWith: { _, new in new }
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    func initializeGitRepoWithTaggedCommit(tag: String) throws -> String {
        _ = try runGit(["init"])
        _ = try runGit(["config", "user.email", "vifty-release-tests@example.invalid"])
        _ = try runGit(["config", "user.name", "Vifty Release Tests"])
        _ = try runGit(["config", "commit.gpgsign", "false"])
        _ = try runGit(["config", "tag.gpgSign", "false"])
        try "source boundary\n".write(
            to: rootURL.appendingPathComponent("release-source.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "release-source.txt"])
        _ = try runGit(["commit", "-m", "source boundary"])
        _ = try runGit(["tag", tag])
        return try runGit(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func appendGitCommit() throws -> String {
        try "dispatch source\n".write(
            to: rootURL.appendingPathComponent("release-dispatch-source.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "release-dispatch-source.txt"])
        _ = try runGit(["commit", "-m", "dispatch source"])
        return try runGit(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rewritePublishedSourceCommit(_ sourceCommit: String) throws {
        let manifestURL = rootURL.appendingPathComponent(".github/release-manifest.json")
        let data = try Data(contentsOf: manifestURL)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var published = try XCTUnwrap(manifest["publishedRelease"] as? [String: Any])
        published["sourceCommit"] = sourceCommit
        manifest["publishedRelease"] = published
        let updated = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try (updated + Data("\n".utf8)).write(to: manifestURL)
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> ReleaseMetadataProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = rootURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let result = ReleaseMetadataProcessResult(
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitCode: process.terminationStatus
        )
        XCTAssertEqual(result.exitCode, 0, "git \(arguments.joined(separator: " ")) failed: \(result.stderr)")
        return result
    }

    func writeUnsignedDevAppBundleFixture(sparkleInfoPlistKeys: [String] = []) throws {
        let appURL = rootURL.appendingPathComponent(".build/Vifty.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "fixture".write(
            to: appURL.appendingPathComponent("Contents/MacOS/Vifty"),
            atomically: true,
            encoding: .utf8
        )
        try infoPlistContents(version: "1.0.0", sparkleKeys: sparkleInfoPlistKeys).write(
            to: appURL.appendingPathComponent("Contents/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeChecksumFile(
        named name: String = "Vifty-v1.0.0.zip.sha256",
        contents: String
    ) throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeUnsignedDevReleaseAssets(
        version: String = "1.0.0",
        checksumContents: String? = nil
    ) throws -> (zip: URL, checksum: URL) {
        let zipName = "Vifty-v\(version)-unsigned-dev.zip"
        let checksumName = "\(zipName).sha256"
        let zipURL = rootURL.appendingPathComponent(zipName)
        let checksumURL = rootURL.appendingPathComponent(checksumName)

        try "unsigned dev zip fixture\n".write(
            to: zipURL,
            atomically: true,
            encoding: .utf8
        )
        let checksum = checksumContents ?? "53df399db4ab2c3dd719a9bb974a4708899c5c4f4af04db276991d237908fecd  \(zipName)\n"
        try checksum.write(to: checksumURL, atomically: true, encoding: .utf8)
        return (zipURL, checksumURL)
    }

    func writeSecretList(contents: String) throws -> URL {
        let url = rootURL.appendingPathComponent("release-secrets.tsv")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeRequiredSecretList() throws -> URL {
        try writeSecretList(contents: """
        APPLE_TEAM_ID\t2026-06-11T10:00:00Z
        APPLE_ID\t2026-06-11T10:00:00Z
        APPLE_APP_SPECIFIC_PASSWORD\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_IDENTITY\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64\t2026-06-11T10:00:00Z
        DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD\t2026-06-11T10:00:00Z
        """)
    }

    func writeCIRunList(
        sourceSHA: String,
        status: String = "completed",
        conclusion: String = "success",
        databaseID: Int = 1,
        path: String = ".github/workflows/ci.yml"
    ) throws -> URL {
        let contents = """
        [
          {
            "databaseId": \(databaseID),
            "workflowName": "CI",
            "path": "\(path)",
            "headBranch": "main",
            "headSha": "\(sourceSHA)",
            "status": "\(status)",
            "conclusion": "\(conclusion)",
            "event": "push",
            "url": "https://github.com/Reedtrullz/Vifty/actions/runs/1"
          }
        ]
        """
        let url = rootURL.appendingPathComponent("ci-runs.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeReleaseRunList(
        sourceSHA: String,
        status: String = "completed",
        conclusion: String = "success",
        version: String = "1.0.0",
        databaseID: Int = 2,
        headBranch: String? = nil,
        event: String = "push",
        displayTitle: String? = nil,
        attempt: Int? = nil,
        path: String = ".github/workflows/release.yml"
    ) throws -> URL {
        let displayTitleJSON = displayTitle.map { "\"\($0)\"" } ?? "null"
        let attemptJSON = attempt.map(String.init) ?? "null"
        let contents = """
        [
          {
            "workflowName": "Release",
            "path": "\(path)",
            "headBranch": "\(headBranch ?? "v\(version)")",
            "headSha": "\(sourceSHA)",
            "status": "\(status)",
            "conclusion": "\(conclusion)",
            "event": "\(event)",
            "databaseId": \(databaseID),
            "displayTitle": \(displayTitleJSON),
            "attempt": \(attemptJSON),
            "url": "https://github.com/Reedtrullz/Vifty/actions/runs/\(databaseID)"
          }
        ]
        """
        let url = rootURL.appendingPathComponent("release-runs.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeReleaseView(
        version: String = "1.0.0",
        tagName: String? = nil,
        isDraft: Bool = false,
        assetNames: [String]? = nil,
        body: String = ""
    ) throws -> URL {
        let assets = assetNames ?? [
            "Vifty-v\(version).zip",
            "Vifty-v\(version).zip.sha256",
            "Vifty-v\(version)-artifact-summary.json",
            "Vifty-v\(version)-release-checklist.md"
        ]
        let assetEntries = assets.map { #"{"name": "\#($0)"}"# }.joined(separator: ", ")
        let escapedBody = body
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
            .replacingOccurrences(of: "\n", with: #"\\n"#)
        let contents = """
        {
          "tagName": "\(tagName ?? "v\(version)")",
          "isDraft": \(isDraft ? "true" : "false"),
          "isPrerelease": false,
          "body": "\(escapedBody)",
          "assets": [\(assetEntries)]
        }
        """
        let url = rootURL.appendingPathComponent("release-view.json")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func readCask() throws -> String {
        try String(
            contentsOf: rootURL.appendingPathComponent("Casks/vifty.rb"),
            encoding: .utf8
        )
    }

    private func writeInfoPlist(version: String, build: Int, sparkleKeys: [String]) throws {
        try infoPlistContents(version: version, build: build, sparkleKeys: sparkleKeys).write(
            to: rootURL.appendingPathComponent("Resources/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func infoPlistContents(version: String, build: Int = 1, sparkleKeys: [String]) -> String {
        let sparkleMetadata = sparkleKeys.map { key in
            """
              <key>\(key)</key>
              <string>fixture</string>
            """
        }.joined(separator: "\n")
        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>tech.reidar.vifty</string>
          <key>CFBundleShortVersionString</key>
          <string>\(version)</string>
          <key>CFBundleVersion</key>
          <string>\(build)</string>
          <key>LSMinimumSystemVersion</key>
          <string>15.0</string>
        \(sparkleMetadata)
        </dict>
        </plist>
        """
        return contents
    }

    private func writeCask(
        version: String,
        sha: String,
        includeAdHocSigningIdentity: Bool,
        privilegedHelperCleanupPath: String?,
        includeCaskDisable: Bool
    ) throws {
        let signingIdentityLine = includeAdHocSigningIdentity
            ? "\n  signing_identity identity: \"-\"\n"
            : ""
        let disableLine = includeCaskDisable
            ? "\n  disable! date: \"2026-06-16\", because: \"requires a Developer ID signed and notarized release\"\n"
            : ""
        let uninstallBlock: String
        let uninstallCaveat: String
        if let privilegedHelperCleanupPath {
            uninstallBlock = """

          uninstall script: {
            executable: "#{appdir}/Vifty.app/Contents/Resources/uninstall-vifty.sh",
            args:       ["--app", "#{appdir}/Vifty.app"],
            sudo:       false,
          }
        """
            uninstallCaveat = privilegedHelperCleanupPath == "/Library/PrivilegedHelperTools/ViftyDaemon"
                ? "    legacy path: \(privilegedHelperCleanupPath)\n"
                : "    Safe helper teardown requires verified Auto/System ownership.\n"
        } else {
            uninstallBlock = ""
            uninstallCaveat = ""
        }
        let contents = """
        cask "vifty" do
          version "\(version)"
          sha256 "\(sha)"
          depends_on arch: :arm64
        \(disableLine)

          url "https://github.com/Reedtrullz/Vifty/releases/download/v#{version}/Vifty-v#{version}.zip"
          \(signingIdentityLine)
        \(uninstallBlock)
          caveats <<~EOS
            To uninstall the privileged helper alongside the app:
        \(uninstallCaveat)  EOS
        end
        """
        try contents.write(
            to: rootURL.appendingPathComponent("Casks/vifty.rb"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeReleaseManifest(
        version: String,
        sha: String,
        sourceCommit: String,
        sourceCIRunID: Int,
        releaseWorkflowRunID: Int,
        tagTrust: String,
        signedTagBoundary: String?,
        candidateVersion: String?,
        candidateBuild: Int,
        candidateSHA: String?
    ) throws {
        let schemaSource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/release-manifest.schema.json")
        let schemaDestination = rootURL.appendingPathComponent("docs/schemas/release-manifest.schema.json")
        try FileManager.default.copyItem(at: schemaSource, to: schemaDestination)

        let candidateJSON: String
        if let candidateVersion {
            let shaJSON = candidateSHA.map { "\"\($0)\"" } ?? "null"
            candidateJSON = """
            {
              "version": "\(candidateVersion)",
              "build": \(candidateBuild),
              "tag": "v\(candidateVersion)",
              "artifact": "Vifty-v\(candidateVersion).zip",
              "checksumAsset": "Vifty-v\(candidateVersion).zip.sha256",
              "artifactSummary": "Vifty-v\(candidateVersion)-artifact-summary.json",
              "releaseChecklist": "Vifty-v\(candidateVersion)-release-checklist.md",
              "sha256": \(shaJSON),
              "artifactTrust": "pending",
              "signingTrust": "pending",
              "tagTrust": "signed-required",
              "installedReleaseReview": "pending",
              "manualCompatibility": "pending",
              "manualCompatibilityScope": null
            }
            """
        } else {
            candidateJSON = "null"
        }
        let effectiveSignedTagBoundary = signedTagBoundary ?? candidateVersion ?? "99.0.0"
        let manifest = """
        {
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "schemaVersion": 1,
          "schemaID": "https://vifty.local/schemas/release-manifest.schema.json",
          "product": {
            "bundleID": "tech.reidar.vifty",
            "daemonID": "tech.reidar.vifty.daemon",
            "helperID": "tech.reidar.vifty.helper",
            "ctlID": "tech.reidar.vifty.ctl",
            "architectures": ["arm64"],
            "minimumMacOS": "15.0"
          },
          "releasePolicy": {
            "developerTeamID": "X88J3853S2",
            "signedTagsRequiredFromVersion": "\(effectiveSignedTagBoundary)"
          },
          "historicalReleases": [],
          "publishedRelease": {
            "version": "\(version)",
            "build": 1,
            "tag": "v\(version)",
            "sourceCommit": "\(sourceCommit)",
            "sourceCIRunID": \(sourceCIRunID),
            "releaseWorkflowRunID": \(releaseWorkflowRunID),
            "artifact": "Vifty-v\(version).zip",
            "checksumAsset": "Vifty-v\(version).zip.sha256",
            "artifactSummary": "Vifty-v\(version)-artifact-summary.json",
            "releaseChecklist": "Vifty-v\(version)-release-checklist.md",
            "sha256": "\(sha)",
            "artifactTrust": "passed",
            "signingTrust": "developer-id-notarized",
            "tagTrust": "\(tagTrust)",
            "installedReleaseReview": "pending",
            "manualCompatibility": "pending",
            "manualCompatibilityScope": null
          },
          "candidate": \(candidateJSON)
        }
        """
        try manifest.write(
            to: rootURL.appendingPathComponent(".github/release-manifest.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeReleaseWorkflow(
        includeTagVersionDerivation: Bool,
        includeTagPrefixCheck: Bool,
        includeBundleVersionTagCheck: Bool,
        includeValidatedVersionExport: Bool,
        includeNotarization: Bool,
        includeGatekeeperAssessment: Bool,
        includeReleaseArtifactVerification: Bool,
        includeVerifierSkipSignatureChecks: Bool,
        includeVerifierSkipNotarizationChecks: Bool,
        includeReleaseArtifactSummary: Bool,
        includeReleaseTeamIDEnvironment: Bool,
        includeReleaseTeamIDBuildArgument: Bool,
        includeLaunchDaemonTeamIDVerification: Bool,
        includeReleaseHelperIdentifierVerification: Bool,
        includePublishedZip: Bool,
        includePublishedChecksum: Bool,
        includeReleaseChecklist: Bool,
        includeVerifyTag: Bool,
        includeNode24ActionsRuntime: Bool,
        includeSwiftBuildPath: Bool,
        includeRunnerTempJobEnv: Bool
    ) throws {
        let node24RuntimeLines = includeNode24ActionsRuntime
            ? """
        env:
          FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"

        """
            : ""
        let tagVersionDerivationLine = includeTagVersionDerivation
            ? "VERSION=\"${TAG#v}\""
            : ""
        let tagPrefixCheckLines = includeTagPrefixCheck
            ? """
                  if [[ "${TAG}" == "${VERSION}" ]]; then
                    echo "Release tag must start with v, e.g. v1.0.1" >&2
                    exit 1
                  fi
            """
            : ""
        let bundleVersionTagCheckLines = includeBundleVersionTagCheck
            ? """
                  if [[ "${VERSION}" != "${BUNDLE_VERSION}" ]]; then
                    echo "Release version ${VERSION} does not match CFBundleShortVersionString ${BUNDLE_VERSION}" >&2
                    exit 1
                  fi
            """
            : ""
        let validatedVersionExportLine = includeValidatedVersionExport
            ? "echo \"VERSION=${VERSION}\" >> \"${GITHUB_ENV}\""
            : ""
        let notarizationLines = includeNotarization
            ? """
              xcrun notarytool submit "${NOTARY_ZIP}" --wait
              xcrun stapler staple .build/Vifty.app
              xcrun stapler validate .build/Vifty.app
            """
            : ""
        let gatekeeperLine = includeGatekeeperAssessment
            ? "/usr/sbin/spctl --assess --type execute --verbose .build/Vifty.app"
            : ""
        let verifierSkipSignatureLine = includeVerifierSkipSignatureChecks
            ? " \\\n              --skip-signature-checks"
            : ""
        let verifierSkipNotarizationLine = includeVerifierSkipNotarizationChecks
            ? " \\\n              --skip-notarization-checks"
            : ""
        let artifactVerificationLines = includeReleaseArtifactVerification
            ? """
              EXPECTED_SHA="$(awk '{print $1}' "${CHECKSUM_PATH}")"
              scripts/verify-release-artifact.sh \\
                --artifact "${ZIP_PATH}" \\
                --release-version "${VERSION}" \\
                --expected-sha "${EXPECTED_SHA}" \\
                --team-id "${APPLE_TEAM_ID}"\(verifierSkipSignatureLine)\(verifierSkipNotarizationLine)\(includeReleaseArtifactSummary ? " \\\n              --summary \"${SUMMARY_PATH}\"" : "")
            """
            : ""
        let artifactSummaryLine = includeReleaseArtifactSummary
            ? "SUMMARY_PATH=\".build/Vifty-v${VERSION}-artifact-summary.json\""
            : ""
        let publishArtifactSummaryLine = includeReleaseArtifactSummary
            ? "upload_release_asset_by_id \"${SUMMARY_PATH}\" \"Vifty ${VERSION} release artifact verification summary\""
            : ""
        let releaseChecklistLines = includeReleaseChecklist
            ? """
              RELEASE_CHECKLIST_PATH=".build/Vifty-v${VERSION}-release-checklist.md"
              scripts/write-release-checklist.sh --version "${VERSION}" --output "${RELEASE_CHECKLIST_PATH}"
              echo "RELEASE_CHECKLIST_PATH=${RELEASE_CHECKLIST_PATH}" >> "${GITHUB_ENV}"
            """
            : ""
        let publishReleaseChecklistLine = includeReleaseChecklist
            ? "upload_release_asset_by_id \"${RELEASE_CHECKLIST_PATH}\" \"Vifty ${VERSION} release checklist\""
            : ""
        let releaseChecklistNotesLine = includeReleaseChecklist
            ? "body = File.read(checklist_path).rstrip"
            : ""
        let publishZipLine = includePublishedZip
            ? "upload_release_asset_by_id \"${ZIP_PATH}\" \"Vifty ${VERSION} notarized app\""
            : ""
        let publishChecksumLine = includePublishedChecksum
            ? "upload_release_asset_by_id \"${CHECKSUM_PATH}\" \"Vifty ${VERSION} SHA-256 checksum\""
            : ""
        let releaseTeamIDEnvLine = includeReleaseTeamIDEnvironment
            ? "          VIFTY_XPC_ALLOWED_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}\n"
            : ""
        let buildCommand = includeReleaseTeamIDBuildArgument
            ? "make app CONFIGURATION=release SIGNING_IDENTITY=\"${SIGNING_IDENTITY}\" VIFTY_XPC_ALLOWED_TEAM_ID=\"${VIFTY_XPC_ALLOWED_TEAM_ID}\""
            : "make app CONFIGURATION=release SIGNING_IDENTITY=\"${SIGNING_IDENTITY}\""
        let launchDaemonTeamIDVerificationLine = includeLaunchDaemonTeamIDVerification
            ? "/usr/bin/plutil -extract EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID raw -o - .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist | grep \"^${VIFTY_XPC_ALLOWED_TEAM_ID}$\""
            : ""
        let releaseHelperIdentifierVerificationLine = includeReleaseHelperIdentifierVerification
            ? "codesign -dvvv .build/Vifty.app/Contents/MacOS/ViftyHelper 2>&1 | grep 'Identifier=tech.reidar.vifty.helper'"
            : ""
        let verifyTagLine = includeVerifyTag
            ? """
                  verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"
                  verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"
                  verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"
            """
            : ""
        let swiftBuildPathEnvLine = includeRunnerTempJobEnv
            ? "              SWIFT_BUILD_PATH: ${{ runner.temp }}/vifty-release-swiftpm-build\n"
            : ""
        let swiftBuildPathSetupStep = includeSwiftBuildPath
            ? """
              - name: Configure SwiftPM build path
                run: echo "SWIFT_BUILD_PATH=${RUNNER_TEMP}/vifty-release-swiftpm-build" >> "${GITHUB_ENV}"
        """
            : ""
        let testCommand = includeSwiftBuildPath
            ? "swift test --build-path \"${SWIFT_BUILD_PATH}\""
            : "swift test"
        let contents = """
        name: Release
        \(node24RuntimeLines)jobs:
          signed-notarized-app:
            env:
        \(swiftBuildPathEnvLine)      RELEASE_TAG: ${{ github.event_name == 'workflow_dispatch' && inputs.tag || github.ref_name }}
            steps:
        \(swiftBuildPathSetupStep)
              - name: Validate release version
                run: |
                  TAG="${RELEASE_TAG}"
                  \(tagVersionDerivationLine)
                  BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
                  \(tagPrefixCheckLines)
                  \(bundleVersionTagCheckLines)
                  scripts/check-release-manifest.sh \
                    --publication-version "${VERSION}" \
                    --base-ref "${GITHUB_SHA}^" \
                    --require-base
                  test -f scripts/check-release-manifest-history-from-git.sh
                  test -f scripts/check-release-manifest-history.rb
                  test -f scripts/lib/release_artifact_contract.rb
                  git verify-tag "${RELEASE_TAG}"
                  \(validatedVersionExportLine)
              - name: Build signed app
                env:
                  SIGNING_IDENTITY: ${{ secrets.DEVELOPER_ID_APPLICATION_IDENTITY }}
        \(releaseTeamIDEnvLine)                run: |
                  \(buildCommand)
                  \(releaseHelperIdentifierVerificationLine)
                  \(launchDaemonTeamIDVerificationLine)
              - name: Run tests
                run: \(testCommand)
              - name: Create release artifacts
                run: |
                  ZIP_PATH=".build/Vifty-v${VERSION}.zip"
                  CHECKSUM_PATH="${ZIP_PATH}.sha256"
                  \(artifactSummaryLine)
                  \(releaseChecklistLines)
                  \(notarizationLines)
                  \(gatekeeperLine)
                  \(artifactVerificationLines)
              - name: Publish GitHub release
                run: |
                  CREATE_PAYLOAD="${RUNNER_TEMP}/create.json"
                  CREATE_RESPONSE="${RUNNER_TEMP}/create-response.json"
                  \(releaseChecklistNotesLine)
                  gh api --method POST \\
                    "repos/${GITHUB_REPOSITORY}/releases" \\
                    --input "${CREATE_PAYLOAD}" > "${CREATE_RESPONSE}"
                  RELEASE_ID="$(capture_owned_draft_release_id "${CREATE_RESPONSE}")"
                  ruby -rjson -e '
                    data = JSON.parse(File.read(ARGV.fetch(0)))
                    contract = JSON.parse(File.read(ARGV.fetch(1)))
                    abort unless data["releaseSourceCommit"] == contract.fetch("tagCommitSHA")
                    abort unless data["releaseManifestSHA256"] == contract.fetch("releaseManifestSHA256")
                  ' "${SUMMARY_PATH}" "${PUBLICATION_CONTRACT_PATH}"
        \(verifyTagLine)
                  \(publishZipLine)
                  \(publishChecksumLine)
                  \(publishArtifactSummaryLine)
                  \(publishReleaseChecklistLine)
        """
        try contents.write(
            to: rootURL.appendingPathComponent(".github/workflows/release.yml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCIWorkflow(
        includeNode24ActionsRuntime: Bool,
        includeNode24CacheAction: Bool,
        includeSwiftBuildPath: Bool,
        includeFullVerification: Bool,
        includeRunnerTempJobEnv: Bool
    ) throws {
        let node24RuntimeLines = includeNode24ActionsRuntime
            ? """
        env:
          FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"

        """
            : ""
        let cacheAction = includeNode24CacheAction ? "actions/cache@v5" : "actions/cache@v4"
        let swiftBuildPathEnvLines = includeRunnerTempJobEnv
            ? """
            env:
              SWIFT_BUILD_PATH: ${{ runner.temp }}/vifty-ci-swiftpm-build

        """
            : ""
        let swiftBuildPathSetupStep = includeSwiftBuildPath
            ? """
              - name: Configure SwiftPM build path
                run: echo "SWIFT_BUILD_PATH=${RUNNER_TEMP}/vifty-ci-swiftpm-build" >> "${GITHUB_ENV}"

        """
            : ""
        let cachePath = includeSwiftBuildPath
            ? "                path: ${{ runner.temp }}/vifty-ci-swiftpm-build"
            : "                path: .build"
        let testCommand = includeFullVerification
            ? "make verify-full"
            : (includeSwiftBuildPath
                ? "swift test --build-path \"${SWIFT_BUILD_PATH}\""
                : "swift test")
        let contents = """
        name: CI
        \(node24RuntimeLines)jobs:
          swiftpm:
        \(swiftBuildPathEnvLines)    steps:
        \(swiftBuildPathSetupStep)
              - name: Verify trusted base release-manifest continuity
                run: |
                  BASE_SHA="${GITHUB_SHA}^"
                  scripts/check-release-manifest.sh \
                    --base-ref "${BASE_SHA}" \
                    --require-base
              - name: Cache SPM build artifacts
                uses: \(cacheAction)
                with:
        \(cachePath)
              - name: Run verification
                run: \(testCommand)
              - name: Build release app bundle
                run: make app CONFIGURATION=release
        """
        try contents.write(
            to: rootURL.appendingPathComponent(".github/workflows/ci.yml"),
            atomically: true,
            encoding: .utf8
        )
    }
}
