import Foundation
import XCTest

final class ReleaseMetadataScriptTests: XCTestCase {
    func testValidatorAcceptsAlignedReleaseMetadata() throws {
        let harness = try ReleaseMetadataHarness()

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Release metadata OK: version 1.0.0"))
    }

    func testValidatorRejectsInvalidCaskSHA() throws {
        let harness = try ReleaseMetadataHarness(caskSHA: "not-a-real-sha")

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

    func testValidatorRejectsMissingPrivilegedHelperCleanupPath() throws {
        let harness = try ReleaseMetadataHarness(privilegedHelperCleanupPath: nil)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must document removal of /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon"))
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

    func testValidatorRejectsWorkflowWithoutReleaseTeamIDEnvironment() throws {
        let harness = try ReleaseMetadataHarness(includeReleaseTeamIDEnvironment: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must build releases with VIFTY_XPC_ALLOWED_TEAM_ID from APPLE_TEAM_ID"))
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

    func testValidatorRejectsWorkflowWithoutVerifyTagPublicationGuard() throws {
        let harness = try ReleaseMetadataHarness(includeVerifyTag: false)

        let result = try harness.runValidator()

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must verify the Git tag before publishing"))
    }

    func testCaskChecksumUpdaterAppliesReleaseChecksumAndRevalidatesMetadata() throws {
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness()
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

    func testCaskChecksumUpdaterRejectsMetadataRegressionBeforeEditingCask() throws {
        let oldSHA = String(repeating: "a", count: 64)
        let newSHA = String(repeating: "b", count: 64)
        let harness = try ReleaseMetadataHarness(
            caskSHA: oldSHA,
            includeAdHocSigningIdentity: true
        )
        let checksumFile = try harness.writeChecksumFile(contents: "\(newSHA)  .build/Vifty-v1.0.0.zip\n")

        let result = try harness.runCaskChecksumUpdater(["--checksum-file", checksumFile.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("must not declare ad-hoc signing"))
        XCTAssertTrue(try harness.readCask().contains("sha256 \"\(oldSHA)\""))
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
        caskSHA: String = String(repeating: "a", count: 64),
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
        includePublishedZip: Bool = true,
        includePublishedChecksum: Bool = true,
        includeVerifyTag: Bool = true
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

        try writeInfoPlist(version: version)
        try writeCask(
            version: version,
            sha: caskSHA,
            includeAdHocSigningIdentity: includeAdHocSigningIdentity,
            privilegedHelperCleanupPath: privilegedHelperCleanupPath
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
            includePublishedZip: includePublishedZip,
            includePublishedChecksum: includePublishedChecksum,
            includeVerifyTag: includeVerifyTag
        )
    }

    func runValidator() throws -> ReleaseMetadataProcessResult {
        let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/validate-release-metadata.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
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

    func writeChecksumFile(
        named name: String = "Vifty-v1.0.0.zip.sha256",
        contents: String
    ) throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func readCask() throws -> String {
        try String(
            contentsOf: rootURL.appendingPathComponent("Casks/vifty.rb"),
            encoding: .utf8
        )
    }

    private func writeInfoPlist(version: String) throws {
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
        try contents.write(
            to: rootURL.appendingPathComponent("Resources/Info.plist"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCask(
        version: String,
        sha: String,
        includeAdHocSigningIdentity: Bool,
        privilegedHelperCleanupPath: String?
    ) throws {
        let signingIdentityLine = includeAdHocSigningIdentity
            ? "\n  signing_identity identity: \"-\"\n"
            : ""
        let helperCleanupLine = privilegedHelperCleanupPath.map { "    sudo rm \($0)\n" } ?? ""
        let contents = """
        cask "vifty" do
          version "\(version)"
          sha256 "\(sha)"

          url "https://github.com/Reedtrullz/Vifty/releases/download/v#{version}/Vifty-v#{version}.zip"
          \(signingIdentityLine)
          caveats <<~EOS
            To uninstall the privileged helper alongside the app:
        \(helperCleanupLine)  EOS
        end
        """
        try contents.write(
            to: rootURL.appendingPathComponent("Casks/vifty.rb"),
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
        includePublishedZip: Bool,
        includePublishedChecksum: Bool,
        includeVerifyTag: Bool
    ) throws {
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
                --expected-sha "${EXPECTED_SHA}" \\
                --team-id "${APPLE_TEAM_ID}"\(verifierSkipSignatureLine)\(verifierSkipNotarizationLine)\(includeReleaseArtifactSummary ? " \\\n              --summary \"${SUMMARY_PATH}\"" : "")
            """
            : ""
        let artifactSummaryLine = includeReleaseArtifactSummary
            ? "SUMMARY_PATH=\".build/Vifty-v${VERSION}-artifact-summary.json\""
            : ""
        let publishArtifactSummaryLine = includeReleaseArtifactSummary
            ? "\"${SUMMARY_PATH}#Vifty ${VERSION} release artifact verification summary\" \\"
            : ""
        let publishZipLine = includePublishedZip
            ? "\"${ZIP_PATH}#Vifty ${VERSION} notarized app\" \\"
            : ""
        let publishChecksumLine = includePublishedChecksum
            ? "\"${CHECKSUM_PATH}#Vifty ${VERSION} SHA-256 checksum\" \\"
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
        let verifyTagLine = includeVerifyTag
            ? "                    --verify-tag"
            : ""
        let contents = """
        name: Release
        jobs:
          signed-notarized-app:
            steps:
              - name: Validate release version
                run: |
                  TAG="${RELEASE_TAG}"
                  \(tagVersionDerivationLine)
                  BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
                  \(tagPrefixCheckLines)
                  \(bundleVersionTagCheckLines)
                  \(validatedVersionExportLine)
              - name: Build signed app
                env:
                  SIGNING_IDENTITY: ${{ secrets.DEVELOPER_ID_APPLICATION_IDENTITY }}
        \(releaseTeamIDEnvLine)                run: |
                  \(buildCommand)
                  \(launchDaemonTeamIDVerificationLine)
              - name: Create release artifacts
                run: |
                  ZIP_PATH=".build/Vifty-v${VERSION}.zip"
                  CHECKSUM_PATH="${ZIP_PATH}.sha256"
                  \(artifactSummaryLine)
                  \(notarizationLines)
                  \(gatekeeperLine)
                  \(artifactVerificationLines)
              - name: Publish GitHub release
                run: |
                  gh release create "${RELEASE_TAG}" \\
                    \(publishZipLine)
                    \(publishChecksumLine)
                    \(publishArtifactSummaryLine)
                    --title "Vifty ${VERSION}"
        \(verifyTagLine)
        """
        try contents.write(
            to: rootURL.appendingPathComponent(".github/workflows/release.yml"),
            atomically: true,
            encoding: .utf8
        )
    }
}
