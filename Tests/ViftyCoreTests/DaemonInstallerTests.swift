import XCTest
@testable import Vifty

@MainActor
final class DaemonInstallerTests: XCTestCase {
    func testHelperActionCopyMatchesInstallerStatus() {
        let installer = DaemonInstaller()
        let installDetail = "Installs the root LaunchDaemon used for fan reads and writes. Fan writes stay blocked until the daemon responds."
        let approveDetail = "Opens Login Items approval. Approve Vifty's fan helper, then return to Vifty. Fan writes stay blocked until the daemon responds."
        let reinstallDetail = "Recopies the daemon, strips quarantine, fixes ownership, and restarts launchd. Fan writes stay blocked until the daemon responds."
        let repairDetail = "Repairs the helper install, fixes ownership, strips quarantine, and restarts launchd. Fan writes stay blocked until the daemon responds."
        let missingBundleDetail = "Vifty is missing its bundled LaunchDaemon plist. Rebuild or reinstall Vifty from source before installing the helper."
        let cases: [(status: String, canInstall: Bool, title: String, help: String, detail: String)] = [
            ("Checking helper", true, "Install Helper", "Install the privileged fan helper", installDetail),
            ("Fan helper not installed", true, "Install Helper", "Install the privileged fan helper", installDetail),
            ("Approve fan helper in Login Items", true, "Approve Helper", "Open Login Items approval for the fan helper", approveDetail),
            ("Fan helper enabled", true, "Reinstall Helper", "Reinstall or repair the privileged fan helper", reinstallDetail),
            ("Fan helper installed", true, "Reinstall Helper", "Reinstall or repair the privileged fan helper", reinstallDetail),
            ("Fan helper installed; waiting for daemon response", true, "Reinstall Helper", "Reinstall or repair the privileged fan helper", reinstallDetail),
            ("Fan helper install failed: denied", true, "Repair Helper", "Repair the privileged fan helper", repairDetail),
            ("Fan helper plist not found in app bundle", false, "Helper Unavailable", missingBundleDetail, missingBundleDetail),
            (
                "macOS 13 or newer is required for bundled daemon install",
                false,
                "Helper Unavailable",
                "macOS 13 or newer is required for bundled daemon install",
                "macOS 13 or newer is required for bundled daemon install"
            )
        ]

        for testCase in cases {
            installer.statusText = testCase.status
            installer.canInstall = testCase.canInstall

            XCTAssertEqual(installer.actionTitle, testCase.title, testCase.status)
            XCTAssertEqual(installer.actionHelp, testCase.help, testCase.status)
            XCTAssertEqual(installer.actionDescription, testCase.detail, testCase.status)
        }
    }

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

        XCTAssertTrue(script.contains("chmod 755 \"$helper_tmp\""))
        XCTAssertTrue(script.contains("chown root:wheel \"$helper_tmp\""))
        XCTAssertTrue(script.contains("chmod 644 \"$plist_tmp\""))
        XCTAssertTrue(script.contains("chown root:wheel \"$plist_tmp\""))
        XCTAssertTrue(script.contains("xattr -cr \"$helper_tmp\" \"$plist_tmp\" 2>/dev/null || true"))
        XCTAssertTrue(script.contains("for log_path in '\(stdoutLogTarget)' '\(stderrLogTarget)'; do"))
        XCTAssertTrue(script.contains("touch \"$log_path\""))
        XCTAssertTrue(script.contains("chmod 600 \"$log_path\""))
        XCTAssertTrue(script.contains("chown root:wheel \"$log_path\""))
        XCTAssertTrue(
            script.contains("chmod 644 \"$plist_tmp\"", before: "launchctl bootstrap system '\(plistTarget)'"),
            "LaunchDaemon plist permissions must be fixed before launchd loads it."
        )
        XCTAssertTrue(
            script.contains("chown root:wheel \"$plist_tmp\"", before: "launchctl bootstrap system '\(plistTarget)'"),
            "LaunchDaemon plist ownership must be fixed before launchd loads it."
        )
        XCTAssertTrue(
            script.contains("xattr -cr \"$helper_tmp\" \"$plist_tmp\"", before: "launchctl bootstrap system '\(plistTarget)'"),
            "Copied ad-hoc source-first helper files must not keep quarantine before launchd loads them."
        )
        XCTAssertTrue(
            script.contains("mv -f \"$helper_tmp\" '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'", before: "launchctl bootstrap system '\(plistTarget)'"),
            "The staged daemon must be moved into place before launchd starts it."
        )
        XCTAssertTrue(
            script.contains("mv -f \"$plist_tmp\" '\(plistTarget)'", before: "launchctl bootstrap system '\(plistTarget)'"),
            "The staged LaunchDaemon plist must be moved into place before launchd loads it."
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

    func testAdministratorInstallScriptBootsOutBeforeReplacingPrivilegedFiles() {
        let installer = DaemonInstaller()
        let plistTarget = "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        let script = installer.administratorInstallShellScript(
            daemonSource: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            plistSource: "/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: plistTarget
        )

        XCTAssertTrue(
            script.contains("launchctl bootout system '\(plistTarget)' 2>/dev/null || true", before: "cp '/Applications/Vifty.app/Contents/MacOS/ViftyDaemon' \"$helper_tmp\""),
            "Repair should stop the existing launchd service before replacing the daemon executable."
        )
        XCTAssertTrue(
            script.contains("launchctl bootout system '\(plistTarget)' 2>/dev/null || true", before: "mv -f \"$plist_tmp\" '\(plistTarget)'"),
            "Repair should stop the existing launchd service before replacing the LaunchDaemon plist."
        )
    }

    func testAdministratorInstallScriptKickstartsDaemonAfterBootstrap() {
        let installer = DaemonInstaller()
        let plistTarget = "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        let script = installer.administratorInstallShellScript(
            daemonSource: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            plistSource: "/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: plistTarget
        )

        XCTAssertTrue(script.contains("launchctl kickstart -k 'system/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(
            script.contains("launchctl bootstrap system '\(plistTarget)'", before: "launchctl kickstart -k 'system/tech.reidar.vifty.daemon'"),
            "Repair should load the LaunchDaemon before kickstarting it so the daemon responds immediately after install."
        )
    }

    func testAdministratorInstallScriptStagesPrivilegedFilesBeforeMovingIntoPlace() {
        let installer = DaemonInstaller()
        let script = installer.administratorInstallShellScript(
            daemonSource: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            plistSource: "/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )

        XCTAssertTrue(script.contains("helper_tmp=\"$(mktemp '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon.XXXXXX')\""))
        XCTAssertTrue(script.contains("plist_tmp=\"$(mktemp '/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist.XXXXXX')\""))
        XCTAssertTrue(script.contains("trap 'rm -f \"$helper_tmp\" \"$plist_tmp\"' EXIT"))
        XCTAssertTrue(script.contains("cp '/Applications/Vifty.app/Contents/MacOS/ViftyDaemon' \"$helper_tmp\""))
        XCTAssertTrue(script.contains("cp '/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist' \"$plist_tmp\""))
        XCTAssertTrue(script.contains("mv -f \"$helper_tmp\" '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertTrue(script.contains("mv -f \"$plist_tmp\" '/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist'"))
        XCTAssertFalse(script.contains("cp '/Applications/Vifty.app/Contents/MacOS/ViftyDaemon' '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon'"))
        XCTAssertFalse(script.contains("cp '/Applications/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist' '/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist'"))
    }

    func testAdministratorInstallScriptQuotesPaths() {
        let installer = DaemonInstaller()
        let script = installer.administratorInstallShellScript(
            daemonSource: "/tmp/Vifty Test/ViftyDaemon",
            plistSource: "/tmp/Vifty Test/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )

        XCTAssertTrue(script.contains("cp '/tmp/Vifty Test/ViftyDaemon' \"$helper_tmp\""))
        XCTAssertTrue(script.contains("cp '/tmp/Vifty Test/tech.reidar.vifty.daemon.plist' \"$plist_tmp\""))
    }

    func testAdministratorInstallScriptQuotesApostrophesInPathsAndProgramArguments() {
        let installer = DaemonInstaller()
        let script = installer.administratorInstallShellScript(
            daemonSource: "/tmp/Vifty's Test/ViftyDaemon",
            plistSource: "/tmp/Vifty's Test/tech.reidar.vifty.daemon.plist",
            helperTarget: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            plistTarget: "/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
        )

        XCTAssertTrue(script.contains("cp '/tmp/Vifty'\\''s Test/ViftyDaemon' \"$helper_tmp\""))
        XCTAssertTrue(script.contains("cp '/tmp/Vifty'\\''s Test/tech.reidar.vifty.daemon.plist' \"$plist_tmp\""))
        XCTAssertTrue(script.contains("/usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon' \"$plist_tmp\""))
        XCTAssertTrue(script.contains("/usr/libexec/PlistBuddy -c 'Set :ProgramArguments:0 /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon' \"$plist_tmp\""))
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
