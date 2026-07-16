import SwiftUI

struct SettingsGeneralView: View {
    @ObservedObject var model: AppModel

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    var body: some View {
        SettingsPane(accessibilityPane: .general) {
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
}
