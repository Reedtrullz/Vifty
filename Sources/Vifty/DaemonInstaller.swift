import Foundation
import ServiceManagement
import ViftyCore

@MainActor
final class DaemonInstaller: ObservableObject {
    @Published var statusText = "Checking helper"
    @Published var canInstall = true

    var service: SMAppService {
        SMAppService.daemon(plistName: ViftyDaemonConstants.plistName)
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
                canInstall = true
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
                canInstall = false
            } else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                statusText = message.isEmpty ? "Fan helper install was cancelled or failed" : message
            }
        } catch {
            statusText = "Fan helper install failed: \(error.localizedDescription)"
        }
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
        return """
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        cp \(shellQuote(daemonSource)) \(shellQuote(helperTarget))
        chmod 755 \(shellQuote(helperTarget))
        chown root:wheel \(shellQuote(helperTarget))
        cp \(shellQuote(plistSource)) \(shellQuote(plistTarget))
        chmod 644 \(shellQuote(plistTarget))
        chown root:wheel \(shellQuote(plistTarget))
        /usr/libexec/PlistBuddy -c 'Delete :BundleProgram' \(shellQuote(plistTarget)) 2>/dev/null || true
        if ! /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' \(shellQuote(plistTarget)) 2>/dev/null; then
          /usr/libexec/PlistBuddy -c 'Delete :ProgramArguments' \(shellQuote(plistTarget)) 2>/dev/null || true
          /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' \(shellQuote(plistTarget))
        fi
        if ! /usr/libexec/PlistBuddy -c \(addProgramArgumentCommand) \(shellQuote(plistTarget)) 2>/dev/null; then
          /usr/libexec/PlistBuddy -c \(setProgramArgumentCommand) \(shellQuote(plistTarget))
        fi
        for log_path in \(shellQuote(stdoutLogTarget)) \(shellQuote(stderrLogTarget)); do
          touch "$log_path"
          chmod 600 "$log_path"
          chown root:wheel "$log_path"
        done
        launchctl bootout system \(shellQuote(plistTarget)) 2>/dev/null || true
        launchctl bootstrap system \(shellQuote(plistTarget))
        """
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
