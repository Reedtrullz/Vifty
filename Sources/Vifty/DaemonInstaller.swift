import Foundation
import ServiceManagement
import ViftyCore

@MainActor
final class DaemonInstaller: ObservableObject {
    @Published var statusText = "Checking helper"
    @Published var canInstall = true

    private static let missingBundledPlistMessage = "Vifty is missing its bundled LaunchDaemon plist. Rebuild or reinstall Vifty from source before installing the helper."

    var service: SMAppService {
        SMAppService.daemon(plistName: ViftyDaemonConstants.plistName)
    }

    var actionTitle: String {
        guard canInstall else { return "Helper Unavailable" }

        let status = statusText.lowercased()
        if status.contains("approve") {
            return "Approve Helper"
        }
        if status.contains("not installed") || status == "checking helper" {
            return "Install Helper"
        }
        if status.contains("enabled") || status.contains("fan helper installed") {
            return "Reinstall Helper"
        }
        return "Repair Helper"
    }

    var actionHelp: String {
        guard canInstall else { return unavailableActionMessage }

        switch actionTitle {
        case "Approve Helper":
            return "Open Login Items approval for the fan helper"
        case "Install Helper":
            return "Install the privileged fan helper"
        case "Reinstall Helper":
            return "Reinstall or repair the privileged fan helper"
        default:
            return "Repair the privileged fan helper"
        }
    }

    var helperStatusSummary: String {
        let status = statusText.lowercased()
        if !canInstall {
            if status.contains("plist not found") || status.contains("missing its bundled launchdaemon plist") {
                return "macOS helper status: bundled plist missing"
            }
            if status.contains("macos 13") {
                return "macOS helper status: unsupported macOS version"
            }
            return "macOS helper status: \(statusText)"
        }
        if status == "checking helper" {
            return "macOS helper status: checking install state"
        }
        if status.contains("approve") {
            return "macOS helper status: waiting for Login Items approval"
        }
        if status.contains("not installed") {
            return "macOS helper status: not installed"
        }
        if status.contains("install failed")
            || status.contains("repair failed")
            || status.contains("cancelled")
            || status.contains("canceled")
            || status.contains("was denied") {
            return "macOS helper status: last install or repair failed"
        }
        if status.contains("enabled") || status.contains("fan helper installed") {
            return "macOS helper status: installed"
        }
        if status.contains("unknown") {
            return "macOS helper status: unknown"
        }
        return "macOS helper status: \(statusText)"
    }

    var actionDescription: String {
        guard canInstall else { return unavailableActionMessage }

        switch actionTitle {
        case "Approve Helper":
            return "Opens Login Items approval. Approve Vifty's fan helper, then return to Vifty. Fan writes stay blocked until the daemon responds."
        case "Install Helper":
            return "Installs the root LaunchDaemon used for fan reads and writes. Fan writes stay blocked until the daemon responds."
        case "Reinstall Helper":
            return "Recopies the daemon, strips quarantine, fixes ownership, and restarts launchd. Fan writes stay blocked until the daemon responds."
        default:
            return "Repairs the helper install, fixes ownership, strips quarantine, and restarts launchd. Fan writes stay blocked until the daemon responds."
        }
    }

    private var unavailableActionMessage: String {
        let status = statusText.lowercased()
        if status.contains("plist not found") || status.contains("missing its bundled launchdaemon plist") {
            return Self.missingBundledPlistMessage
        }
        return statusText
    }

    func refresh() {
        if #available(macOS 13.0, *) {
            switch service.status {
            case .enabled:
                statusText = "Fan helper enabled"
                canInstall = true
            case .notRegistered:
                statusText = "Fan helper not installed"
                canInstall = true
            case .notFound:
                statusText = "Fan helper plist not found in app bundle"
                canInstall = false
            case .requiresApproval:
                statusText = "Approve fan helper in Login Items"
                canInstall = true
            @unknown default:
                statusText = "Fan helper status unknown"
                canInstall = true
            }
        } else {
            statusText = "macOS 13 or newer is required for bundled daemon install"
            canInstall = false
        }
    }

    func installOrOpenApproval() {
        guard #available(macOS 13.0, *) else {
            installWithAdministratorPrompt()
            return
        }

        do {
            switch service.status {
            case .enabled:
                installWithAdministratorPrompt()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                refresh()
            case .notRegistered, .notFound:
                do {
                    try service.register()
                    refresh()
                    if service.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } catch {
                    installWithAdministratorPrompt()
                }
            @unknown default:
                try service.register()
                refresh()
            }
        } catch {
            statusText = "Fan helper install failed: \(error.localizedDescription)"
            installWithAdministratorPrompt()
        }
    }

    func installWithAdministratorPrompt() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            statusText = "Could not locate Vifty app bundle"
            return
        }

        let daemonSource = bundleURL
            .appendingPathComponent("Contents/MacOS/ViftyDaemon")
            .path
        let plistSource = bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(ViftyDaemonConstants.plistName)")
            .path
        let helperTarget = "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon"
        let plistTarget = "/Library/LaunchDaemons/\(ViftyDaemonConstants.plistName)"
        let stdoutLogTarget = "/var/log/tech.reidar.vifty.daemon.out.log"
        let stderrLogTarget = "/var/log/tech.reidar.vifty.daemon.err.log"

        guard FileManager.default.fileExists(atPath: daemonSource),
              FileManager.default.fileExists(atPath: plistSource) else {
            statusText = "ViftyDaemon or daemon plist is missing from the app bundle"
            return
        }

        let shellScript = administratorInstallShellScript(
            daemonSource: daemonSource,
            plistSource: plistSource,
            helperTarget: helperTarget,
            plistTarget: plistTarget,
            stdoutLogTarget: stdoutLogTarget,
            stderrLogTarget: stderrLogTarget
        )
        let script = """
        set shellCommand to \(appleScriptMultilineString(shellScript))
        do shell script shellCommand with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                statusText = "Fan helper installed"
                canInstall = true
            } else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                statusText = administratorInstallFailureStatus(stderr: message)
            }
        } catch {
            statusText = "Fan helper install failed: \(error.localizedDescription)"
        }
    }

    func administratorInstallFailureStatus(stderr: String) -> String {
        let normalized = stderr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return "Fan helper repair was canceled or failed; fan writes stay blocked until the helper is installed."
        }
        if normalized.contains("cancelled") || normalized.contains("canceled") {
            return "Fan helper repair was canceled; fan writes stay blocked until the helper is installed."
        }
        if normalized.contains("denied") || normalized.contains("authorization") {
            return "Fan helper repair was denied; fan writes stay blocked until the helper is installed."
        }
        return "Fan helper repair failed; fan writes stay blocked. Copy support evidence if it keeps failing."
    }

    private func escapeForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func appleScriptMultilineString(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\"\(escapeForAppleScript(String($0)))\"" }
            .joined(separator: " & linefeed & ")
    }

    func administratorInstallShellScript(
        daemonSource: String,
        plistSource: String,
        helperTarget: String,
        plistTarget: String,
        stdoutLogTarget: String = "/var/log/tech.reidar.vifty.daemon.out.log",
        stderrLogTarget: String = "/var/log/tech.reidar.vifty.daemon.err.log"
    ) -> String {
        let addProgramArgumentCommand = shellQuote("Add :ProgramArguments:0 string \(helperTarget)")
        let setProgramArgumentCommand = shellQuote("Set :ProgramArguments:0 \(helperTarget)")
        let helperTempTemplate = "\(helperTarget).XXXXXX"
        let plistTempTemplate = "\(plistTarget).XXXXXX"
        let serviceTarget = "system/\(ViftyDaemonConstants.machServiceName)"
        return """
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        launchctl bootout system \(shellQuote(plistTarget)) 2>/dev/null || true
        helper_tmp="$(mktemp \(shellQuote(helperTempTemplate)))"
        plist_tmp="$(mktemp \(shellQuote(plistTempTemplate)))"
        trap 'rm -f "$helper_tmp" "$plist_tmp"' EXIT
        cp \(shellQuote(daemonSource)) "$helper_tmp"
        chmod 755 "$helper_tmp"
        chown root:wheel "$helper_tmp"
        cp \(shellQuote(plistSource)) "$plist_tmp"
        chmod 644 "$plist_tmp"
        chown root:wheel "$plist_tmp"
        xattr -cr "$helper_tmp" "$plist_tmp" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c 'Delete :BundleProgram' "$plist_tmp" 2>/dev/null || true
        if ! /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$plist_tmp" 2>/dev/null; then
          /usr/libexec/PlistBuddy -c 'Delete :ProgramArguments' "$plist_tmp" 2>/dev/null || true
          /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$plist_tmp"
        fi
        if ! /usr/libexec/PlistBuddy -c \(addProgramArgumentCommand) "$plist_tmp" 2>/dev/null; then
          /usr/libexec/PlistBuddy -c \(setProgramArgumentCommand) "$plist_tmp"
        fi
        mv -f "$helper_tmp" \(shellQuote(helperTarget))
        mv -f "$plist_tmp" \(shellQuote(plistTarget))
        for log_path in \(shellQuote(stdoutLogTarget)) \(shellQuote(stderrLogTarget)); do
          touch "$log_path"
          chmod 600 "$log_path"
          chown root:wheel "$log_path"
        done
        launchctl bootstrap system \(shellQuote(plistTarget))
        launchctl kickstart -k \(shellQuote(serviceTarget))
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
