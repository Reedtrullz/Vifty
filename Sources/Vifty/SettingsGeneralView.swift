import AppKit
import SwiftUI

struct SettingsGeneralView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var softwareUpdates: SoftwareUpdateController

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: {
                softwareUpdates.canCheck && softwareUpdates.automaticChecksEnabled
            },
            set: { softwareUpdates.setAutomaticChecksEnabled($0) }
        )
    }

    var body: some View {
        SettingsPane(accessibilityPane: .general) {
            updatesSection

            Section("Startup") {
                Picker("Default mode", selection: $model.startupMode) {
                    Text("Auto").tag(ModeSelection.auto)
                    Text("Fixed RPM").tag(ModeSelection.fixed)
                    Text("Temperature Curve").tag(ModeSelection.curve)
                }

                Text(StartupModePresentation.resolve(model.startupMode).detail)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Appearance") {
                Picker("Text size", selection: $model.textScale) {
                    ForEach(ViftyTextScale.allCases) { scale in
                        Text(scale.label).tag(scale)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose the text and control size used throughout Vifty.")

                Text(model.textScale.helpText)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Login") {
                Toggle("Start Vifty at startup", isOn: launchAtLoginBinding)
                    .accessibilityLabel("Start Vifty at startup")
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.settingsLaunchAtLogin)
                    .help("Open Vifty automatically at macOS login")

                if let message = model.launchAtLoginStatusMessage {
                    HStack {
                        Label(message, systemImage: model.launchAtLoginStatus == .requiresApproval ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(model.launchAtLoginStatus == .requiresApproval ? .orange : .secondary)
                        if model.launchAtLoginStatus == .requiresApproval {
                            Button("Open Login Items") {
                                model.openLaunchAtLoginSettings()
                            }
                        }
                    }
                    .viftyFont(.caption)
                }
            }

        }
        .onAppear {
            model.refreshLaunchAtLoginStatus()
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        Section("Updates") {
            Toggle(
                "Automatically check for updates",
                isOn: automaticUpdateChecksBinding
            )
            .disabled(!softwareUpdates.canCheck)
            .accessibilityIdentifier(
                ViftyAccessibilityIdentifier.settingsUpdateAutomatic
            )

            Group {
                if softwareUpdateStatusNeedsAttention {
                    Label(
                        softwareUpdates.statusText,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                } else {
                    Text(softwareUpdates.statusText)
                        .foregroundStyle(.secondary)
                }
            }
            .viftyFont(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(
                ViftyAccessibilityIdentifier.settingsUpdateStatus
            )
            .onChange(of: softwareUpdates.statusText) { _, statusText in
                announceSoftwareUpdateStatus(statusText)
            }
            .onChange(of: softwareUpdates.errorAnnouncement?.id) { _, _ in
                if let announcement = softwareUpdates.errorAnnouncement {
                    announceSoftwareUpdateStatus(announcement.message)
                }
            }

            if let errorMessage = softwareUpdates.errorMessage,
               errorMessage != softwareUpdates.statusText {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .viftyFont(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(softwareUpdates.primaryActionTitle) {
                    Task {
                        await softwareUpdates.performPrimaryAction()
                    }
                }
                .disabled(!softwareUpdates.canCheck || softwareUpdates.isChecking)
                .accessibilityIdentifier(
                    softwareUpdates.availableRelease == nil
                        ? ViftyAccessibilityIdentifier.settingsUpdateCheck
                        : ViftyAccessibilityIdentifier.settingsUpdateLatest
                )
                .accessibilityHint(softwareUpdates.primaryActionHint)
                .help(softwareUpdates.primaryActionHint)

                if softwareUpdates.availableRelease != nil {
                    Button("Check now") {
                        Task {
                            await softwareUpdates.checkNow()
                        }
                    }
                    .disabled(softwareUpdates.isChecking)
                    .accessibilityIdentifier(
                        ViftyAccessibilityIdentifier.settingsUpdateCheck
                    )
                    .accessibilityHint(
                        "Refreshes GitHub release availability without downloading or installing."
                    )
                    .help(
                        "Refreshes GitHub release availability without downloading or installing."
                    )
                }
            }

            Text(
                "Automatic checks contact GitHub at most once per day; Check now contacts "
                    + "GitHub when you choose it. GitHub receives your public IP address, request "
                    + "timing, and a Vifty version User-Agent. Vifty sends no fan, sensor, power, "
                    + "Codex, profile, or account payload. Updating opens a fixed GitHub tag page; Vifty "
                    + "never silently replaces itself."
            )
            .viftyFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var softwareUpdateStatusNeedsAttention: Bool {
        if case .failed = softwareUpdates.status {
            return true
        }
        return false
    }

    private func announceSoftwareUpdateStatus(_ statusText: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: statusText,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}
