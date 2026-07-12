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
        SettingsCategorySection(title: "General", systemImage: "gearshape") {
            Picker("Default mode", selection: $model.startupMode) {
                Text("Auto").tag(ModeSelection.auto)
                Text("Fixed RPM").tag(ModeSelection.fixed)
                Text("Temperature Curve").tag(ModeSelection.curve)
            }

            Text(StartupModePresentation.resolve(model.startupMode).detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Start Vifty at startup", isOn: launchAtLoginBinding)
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
                .font(.caption)
            }
        }
        .onAppear {
            model.refreshLaunchAtLoginStatus()
        }
    }
}
