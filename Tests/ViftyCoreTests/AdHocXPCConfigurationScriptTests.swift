import Darwin
import Foundation
import XCTest

final class AdHocXPCConfigurationScriptTests: XCTestCase {
    func testDefaultDebugConfigurationOmitsEveryAdHocKey() throws {
        let fixture = try XPCPlistFixture()
        defer { fixture.remove() }

        let result = try fixture.configure(configuration: "debug")

        XCTAssertEqual(result.exitCode, 0, result.output)
        let environment = try fixture.environment()
        XCTAssertEqual(environment["VIFTY_XPC_ALLOWED_TEAM_ID"] as? String, "")
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_DEVELOPMENT"])
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_ALLOWED_UID"])
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_APP_PATH"])
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_CTL_PATH"])
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_HELPER_PATH"])
    }

    func testExplicitDebugOptInWritesUIDAndCanonicalClientPaths() throws {
        let fixture = try XPCPlistFixture()
        defer { fixture.remove() }

        let result = try fixture.configure(
            configuration: "debug",
            development: true,
            uid: "501",
            appPath: "/Users/test/Applications/Vifty.app/Contents/MacOS/Vifty",
            ctlPath: "/Users/test/Applications/Vifty.app/Contents/MacOS/viftyctl"
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        let environment = try fixture.environment()
        XCTAssertEqual(environment["VIFTY_XPC_ADHOC_DEVELOPMENT"] as? String, "1")
        XCTAssertEqual(environment["VIFTY_XPC_ADHOC_ALLOWED_UID"] as? String, "501")
        XCTAssertEqual(environment["VIFTY_XPC_ADHOC_APP_PATH"] as? String, "/Users/test/Applications/Vifty.app/Contents/MacOS/Vifty")
        XCTAssertEqual(environment["VIFTY_XPC_ADHOC_CTL_PATH"] as? String, "/Users/test/Applications/Vifty.app/Contents/MacOS/viftyctl")
        XCTAssertNil(environment["VIFTY_XPC_ADHOC_HELPER_PATH"])
    }

    func testPartialOrLegacyHelperConfigurationIsRejectedWithoutChangingPlist() throws {
        for arguments in [
            ["--enable-adhoc", "--adhoc-uid", "501", "--adhoc-app-path", "/Applications/Vifty.app/Contents/MacOS/Vifty"],
            ["--adhoc-helper-path", "/Applications/Vifty.app/Contents/MacOS/ViftyHelper"]
        ] {
            let fixture = try XPCPlistFixture()
            defer { fixture.remove() }
            let before = try Data(contentsOf: fixture.plist)

            let result = try fixture.configure(configuration: "debug", extraArguments: arguments)

            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertEqual(try Data(contentsOf: fixture.plist), before)
        }
    }

    func testReleaseRejectsAdHocValuesBeforeChangingPlist() throws {
        let fixture = try XPCPlistFixture()
        defer { fixture.remove() }
        let before = try Data(contentsOf: fixture.plist)

        let result = try fixture.configure(
            configuration: "release",
            development: true,
            uid: "501",
            appPath: "/Applications/Vifty.app/Contents/MacOS/Vifty",
            ctlPath: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.plist), before)
    }

    func testAdHocInstallCopyFailurePreservesExistingDestinationAndBoundPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-install-preflight-\(UUID().uuidString)", isDirectory: true)
        defer {
            let clearFlags = try? Process.run(
                URL(fileURLWithPath: "/usr/bin/chflags"),
                arguments: ["-R", "nouchg", root.path]
            )
            clearFlags?.waitUntilExit()
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let fixtureHome = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureHome, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixtureHome.path)
        let buildApp = root.appendingPathComponent("build/Vifty.app", isDirectory: true)
        let destination = root.appendingPathComponent("install/Vifty.app", isDirectory: true)
        let helperTarget = root.appendingPathComponent("installed-helper/tech.reidar.vifty.daemon")
        try FileManager.default.createDirectory(
            at: buildApp.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        let executable = buildApp.appendingPathComponent("Contents/MacOS/Vifty")
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        _ = try executableScript(root: buildApp, name: "Contents/MacOS/ViftyDaemon", body: "exit 0")
        _ = try executableScript(root: buildApp, name: "Contents/MacOS/ViftyHelper", body: "exit 0")
        _ = try executableScript(root: destination, name: "Contents/MacOS/Vifty", body: "exit 0")
        _ = try executableScript(root: destination, name: "Contents/MacOS/ViftyDaemon", body: "exit 0")
        _ = try executableScript(root: destination, name: "Contents/MacOS/ViftyHelper", body: "exit 0")
        try FileManager.default.createDirectory(
            at: helperTarget.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try executableScript(root: helperTarget.deletingLastPathComponent(), name: helperTarget.lastPathComponent, body: "exit 0")
        let generatedAt = Date().timeIntervalSinceReferenceDate
        let safeReplacementReport = """
        {"schemaVersion":1,"generatedAt":\(generatedAt),"checks":[{"id":"daemonSnapshotAvailable","passed":true},{"id":"agentControlStatusAvailable","passed":true},{"id":"fanControlOwnershipStatusAvailable","passed":true},{"id":"daemonControlPathReady","passed":true},{"id":"supportedHardware","passed":true},{"id":"activeLeaseClear","passed":true},{"id":"manualControlClear","passed":true},{"id":"fanControlProtocolCurrent","passed":true},{"id":"fanControlOwnershipStateValid","passed":true},{"id":"fanControlRecoveryClear","passed":true},{"id":"fanControlOwnershipClear","passed":true},{"id":"fanControlHardwareConsistent","passed":true},{"id":"replacementMaintenanceAttestation","passed":true}],"daemonSnapshotError":null,"agentControlStatusError":null,"fanControlOwnershipStatusError":null,"isAppleSilicon":true,"isMacBookPro":true,"fanCount":1,"fans":[{"id":0,"hardwareMode":"Auto","hardwareModeRawValue":0,"hardwareModeKey":"F0Md","canRestoreOSManagedMode":true,"controlIneligibilityReasons":[]}],"agentControl":{"activeLease":null},"fanControlOwnership":{"protocolVersion":2,"owner":null,"phase":null,"transactionID":null,"expectedFanIDs":[],"confirmedOSManagedFanIDs":[],"recoveryPending":false,"recoveryAttemptCount":0,"errorCode":null,"errorMessage":null},"manualControlActive":false}
        """
        let encodedReport = Data(safeReplacementReport.utf8).base64EncodedString()
        _ = try executableScript(
            root: buildApp,
            name: "Contents/MacOS/viftyctl",
            body: "printf '%s' '\(encodedReport)' | /usr/bin/base64 --decode"
        )
        _ = try executableScript(
            root: destination,
            name: "Contents/MacOS/viftyctl",
            body: "printf '%s' '\(encodedReport)' | /usr/bin/base64 --decode"
        )
        let sentinel = destination.appendingPathComponent("preserve-me")
        try Data("existing".utf8).write(to: sentinel)
        let fakeMake = try executableScript(root: root, name: "make", body: "printf '%s\\n' \"$@\" > \"$VIFTY_TEST_MAKE_ARGS\"\nexit 0")
        let fakeDitto = try executableScript(root: root, name: "ditto", body: "exit 99")
        let replacementLifecycleRoot = URL(fileURLWithPath: try canonicalFilesystemPath(root))
            .appendingPathComponent("root-staged-lifecycle", isDirectory: true)
        let replacementLifecycle = try executableScript(
            root: root,
            name: "replacement-lifecycle",
            body: """
            phase=''
            transaction=''
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --replacement-phase) phase="$2"; shift 2 ;;
                --replacement-transaction-id) transaction="$2"; shift 2 ;;
                *) shift ;;
              esac
            done
            case "$phase" in
              prepare)
                lifecycle_dir="${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}/$transaction"
                /bin/mkdir -p "${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}" "$lifecycle_dir"
                /bin/chmod 755 "${VIFTY_REPLACEMENT_LIFECYCLE_ROOT}" "$lifecycle_dir"
                /bin/cp "$0" "$lifecycle_dir/vifty-helper-lifecycle.sh"
                /bin/chmod 555 "$lifecycle_dir/vifty-helper-lifecycle.sh"
                /usr/bin/chflags uchg "$lifecycle_dir/vifty-helper-lifecycle.sh" "$lifecycle_dir"
                ;;
              finish|release-lock) ;;
              *) exit 64 ;;
            esac
            """
        )
        let makeArgs = root.appendingPathComponent("make-args.txt")

        let result = try run(
            executable: repositoryRoot.appendingPathComponent("scripts/install-vifty.sh"),
            environment: [
                "CONFIGURATION": "debug",
                "VIFTY_ENABLE_ADHOC_XPC": "1",
                "VIFTY_INSTALL_DIR": destination.deletingLastPathComponent().path,
                "VIFTY_BUILD_APP_PATH": buildApp.path,
                "VIFTY_MAKE": fakeMake.path,
                "VIFTY_DITTO": fakeDitto.path,
                "VIFTY_HELPER_LIFECYCLE": replacementLifecycle.path,
                "VIFTY_REPLACEMENT_LIFECYCLE_ROOT": replacementLifecycleRoot.path,
                "VIFTY_HELPER_TARGET": helperTarget.path,
                "VIFTY_TEST_MAKE_ARGS": makeArgs.path,
                "VIFTY_INSTALL_FIXTURE_NO_RUNNING_APP": "1",
                "VIFTY_INSTALL_FIXTURE_PROTOCOL_V2": "1",
                "VIFTY_INSTALL_FIXTURE_UNSIGNED_BUILD": "1",
                "VIFTY_INSTALL_FIXTURE_ROOT": root.path,
                "TMPDIR": root.path,
                "HOME": fixtureHome.path,
                "QUIT_RUNNING_APP": "0",
                "CHECK_HELPER_DAEMON": "0"
            ]
        )

        XCTAssertNotEqual(result.exitCode, 0, result.output)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "existing")
        XCTAssertTrue(result.output.contains("refusing path fallback"), result.output)
        let arguments = try String(contentsOf: makeArgs, encoding: .utf8)
        XCTAssertTrue(arguments.contains("VIFTY_XPC_ADHOC_APP_PATH=\(destination.path)/Contents/MacOS/Vifty"))
        XCTAssertTrue(arguments.contains("VIFTY_XPC_ADHOC_CTL_PATH=\(destination.path)/Contents/MacOS/viftyctl"))
        XCTAssertFalse(arguments.contains("VIFTY_XPC_ADHOC_HELPER_PATH"))
    }

    private func executableScript(root: URL, name: String, body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("#!/bin/bash\nset -eu\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func run(executable: URL, environment: [String: String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
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

private final class XPCPlistFixture {
    let root: URL
    let plist: URL
    private let repositoryRoot: URL

    init() throws {
        repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-xpc-plist-tests-\(UUID().uuidString)", isDirectory: true)
        plist = root.appendingPathComponent("daemon.plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("Resources/tech.reidar.vifty.daemon.plist"),
            to: plist
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func configure(
        configuration: String,
        development: Bool = false,
        uid: String? = nil,
        appPath: String? = nil,
        ctlPath: String? = nil,
        extraArguments: [String] = []
    ) throws -> (exitCode: Int32, output: String) {
        var arguments = ["--plist", plist.path, "--configuration", configuration]
        if development { arguments.append("--enable-adhoc") }
        if let uid { arguments += ["--adhoc-uid", uid] }
        if let appPath { arguments += ["--adhoc-app-path", appPath] }
        if let ctlPath { arguments += ["--adhoc-ctl-path", ctlPath] }
        arguments += extraArguments
        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/configure-daemon-plist.sh")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func environment() throws -> [String: Any] {
        let data = try Data(contentsOf: plist)
        let plistObject = try PropertyListSerialization.propertyList(from: data, format: nil)
        let root = try XCTUnwrap(plistObject as? [String: Any])
        return try XCTUnwrap(root["EnvironmentVariables"] as? [String: Any])
    }
}
