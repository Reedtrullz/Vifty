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

        guard FileManager.default.fileExists(atPath: daemonSource),
              FileManager.default.fileExists(atPath: plistSource) else {
            statusText = "ViftyDaemon or daemon plist is missing from the app bundle"
            return
        }

        let script = """
        set daemonSource to "\(escapeForAppleScript(daemonSource))"
        set plistSource to "\(escapeForAppleScript(plistSource))"
        set helperTarget to "\(helperTarget)"
        set plistTarget to "\(plistTarget)"
        set shellCommand to "mkdir -p /Library/PrivilegedHelperTools && cp " & quoted form of daemonSource & " " & quoted form of helperTarget & " && chmod 755 " & quoted form of helperTarget & " && chown root:wheel " & quoted form of helperTarget & " && cp " & quoted form of plistSource & " " & quoted form of plistTarget & " && /usr/libexec/PlistBuddy -c 'Delete :BundleProgram' " & quoted form of plistTarget & " 2>/dev/null || true && /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' " & quoted form of plistTarget & " 2>/dev/null || true && /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon' " & quoted form of plistTarget & " 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :ProgramArguments:0 /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon' " & quoted form of plistTarget & " && launchctl bootout system " & quoted form of plistTarget & " 2>/dev/null || true && launchctl bootstrap system " & quoted form of plistTarget
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
}
