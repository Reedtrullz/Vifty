import XCTest
@testable import Vifty

@MainActor
final class DaemonInstallerTests: XCTestCase {
    func testAdministratorInstallScriptRestrictsDaemonAndPlistPermissionsBeforeBootstrap() {
        let installer = DaemonInstaller()
        let plistTarget = "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        let stdoutLogTarget = "/var/log/tech.reidar.vifty.daemon.out.log"
        let stderrLogTarget = "/var/log/tech.reidar.vifty.daemon.err.log"
        let script = installer.administratorInstallShellScript(
            daemonSource: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            plistSource: "/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: plistTarget,
            stdoutLogTarget: stdoutLogTarget,
            stderrLogTarget: stderrLogTarget
        )

        XCTAssertTrue(script.contains("chmod 755 '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("chown root:wheel '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("chmod 644 '\(plistTarget)'"))
        XCTAssertTrue(script.contains("chown root:wheel '\(plistTarget)'"))
        XCTAssertTrue(script.contains("for log_path in '\(stdoutLogTarget)' '\(stderrLogTarget)'; do"))
        XCTAssertTrue(script.contains("touch \"$log_path\""))
        XCTAssertTrue(script.contains("chmod 600 \"$log_path\""))
        XCTAssertTrue(script.contains("chown root:wheel \"$log_path\""))
        XCTAssertTrue(
            script.contains("chmod 644 '\(plistTarget)'", before: "launchctl bootstrap system '\(plistTarget)'"),
            "LaunchDaemon plist permissions must be fixed before launchd loads it."
        )
        XCTAssertTrue(
            script.contains("chown root:wheel '\(plistTarget)'", before: "launchctl bootstrap system '\(plistTarget)'"),
            "LaunchDaemon plist ownership must be fixed before launchd loads it."
        )
        XCTAssertTrue(
            script.contains("chmod 600 \"$log_path\"", before: "launchctl bootstrap system '\(plistTarget)'"),
            "Daemon logs must be restricted before launchd starts writing to them."
        )
        XCTAssertTrue(
            script.contains("chown root:wheel \"$log_path\"", before: "launchctl bootstrap system '\(plistTarget)'"),
            "Daemon logs must be root-owned before launchd starts writing to them."
        )
    }

    func testAdministratorInstallScriptQuotesPaths() {
        let installer = DaemonInstaller()
        let script = installer.administratorInstallShellScript(
            daemonSource: "/tmp/Vifty Test/ViftyDaemon",
            plistSource: "/tmp/Vifty Test/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )

        XCTAssertTrue(script.contains("cp '/tmp/Vifty Test/ViftyDaemon' '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("cp '/tmp/Vifty Test/tech.reidar.vifty.daemon.plist' '/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist'"))
    }

    func testAdministratorInstallScriptQuotesApostrophesInPathsAndProgramArguments() {
        let installer = DaemonInstaller()
        let script = installer.administratorInstallShellScript(
            daemonSource: "/tmp/Vifty's Test/ViftyDaemon",
            plistSource: "/tmp/Vifty's Test/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )

        XCTAssertTrue(script.contains("cp '/tmp/Vifty'\\''s Test/ViftyDaemon' '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("cp '/tmp/Vifty'\\''s Test/tech.reidar.vifty.daemon.plist' '/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist'"))
        XCTAssertTrue(script.contains("/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("/usr/libexec/PlistBuddy -c 'Set :ProgramArguments:0 /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
    }
}

private extension String {
    func contains(_ firstNeedle: String, before secondNeedle: String) -> Bool {
        guard let firstRange = range(of: firstNeedle),
              let secondRange = range(of: secondNeedle) else {
            return false
        }
        return firstRange.lowerBound < secondRange.lowerBound
    }
}
