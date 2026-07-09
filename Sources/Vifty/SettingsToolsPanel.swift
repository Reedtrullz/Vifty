import SwiftUI
import ViftyCore

struct SettingsToolsPanel: View {
    @ObservedObject var model: AppModel
    @Binding var selectedProfileID: UUID?
    @Binding var agentRuleCopied: Bool
    @Binding var agentCommandCopied: Bool

    let menuBarCustomFieldBinding: (MenuBarField) -> Binding<Bool>
    let copyAgentWorkflowCommand: (AgentWorkflowSupport.WorkloadCommandTemplate, AgentWorkflowSupport.WorkloadCommandMode) -> Void
    let copyAgentWorkflowRule: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                quickSettingsStrip
                menuBarDisplaySettings
                notificationSettings
                agentWorkflowSettings
            }
            .padding(.top, 6)
        } label: {
            Label("Settings & Tools", systemImage: "gearshape")
                .font(.headline)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    private var quickSettingsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    curveProfileSettings
                    Divider()
                        .frame(height: 22)
                    startupModeSettings
                    Divider()
                        .frame(height: 22)
                    launchAtLoginSettings
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    curveProfileSettings
                    startupModeSettings
                    launchAtLoginSettings
                }
            }

            launchAtLoginStatusMessage
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            model.refreshLaunchAtLoginStatus()
        }
    }

    private var curveProfileSettings: some View {
        HStack(spacing: 8) {
            Label("Curve profile", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Curve profile", selection: $selectedProfileID) {
                Text("Unsaved").tag(Optional<UUID>.none)
                ForEach(model.savedProfiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .onChange(of: selectedProfileID) { _, newID in
                _ = model.selectCurveProfile(id: newID)
            }

            if selectedProfileID != nil {
                Button {
                    if let id = selectedProfileID,
                       let profile = model.savedProfiles.first(where: { $0.id == id }) {
                        model.deleteProfile(profile)
                        selectedProfileID = nil
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete selected curve profile")
            }
        }
    }

    private var startupModeSettings: some View {
        HStack(spacing: 8) {
            Label("Default mode", systemImage: "poweron")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Default mode", selection: $model.startupMode) {
                ForEach(ModeSelection.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .help("Mode Vifty selects when the app starts")
        }
    }

    private var launchAtLoginSettings: some View {
        Toggle(isOn: launchAtLoginBinding) {
            Label("Start Vifty at startup", systemImage: "power")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Open Vifty automatically at macOS login")
    }

    @ViewBuilder
    private var launchAtLoginStatusMessage: some View {
        if let message = model.launchAtLoginStatusMessage {
            HStack(spacing: 8) {
                Label(message, systemImage: model.launchAtLoginStatus == .requiresApproval ? "exclamationmark.triangle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(model.launchAtLoginStatus == .requiresApproval ? .orange : .secondary)
                    .lineLimit(2)
                Spacer()
                if model.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items") {
                        model.openLaunchAtLoginSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var menuBarDisplaySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Menu bar", systemImage: "menubar.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Menu bar", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                Spacer()
            }
            if model.menuBarDisplayMode == .custom {
                menuBarCustomFieldControls
            }
            if model.menuBarDisplaysCodexUsage {
                codexUsageDisplayControls
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var menuBarCustomFieldControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Custom fields", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 126), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(MenuBarField.allCases) { field in
                    Toggle(field.label, isOn: menuBarCustomFieldBinding(field))
                        .controlSize(.small)
                }
            }
        }
    }

    private var codexUsageDisplayControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Codex display", selection: $model.codexUsageDisplayStyle) {
                ForEach(CodexUsageDisplayStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker("Codex metric", selection: $model.codexUsageMetricMode) {
                ForEach(CodexUsageMetricMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker("Reset", selection: $model.codexUsageResetMode) {
                ForEach(CodexUsageResetMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker("Refresh", selection: $model.codexUsageRefreshCadence) {
                ForEach(CodexUsageRefreshCadence.allCases) { cadence in
                    Text(cadence.label).tag(cadence)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private var notificationSettings: some View {
        DisclosureGroup {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 172), alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                Toggle("Helper failure", isOn: $model.notificationSettings.helperFailure)
                Toggle("High thermal pressure", isOn: $model.notificationSettings.elevatedThermalPressure)
                Toggle("Auto restore failure", isOn: $model.notificationSettings.autoRestoreFailure)
                Toggle("Plugged-in battery drain", isOn: $model.notificationSettings.pluggedInBatteryDrain)
                Toggle("Agent cooling attention", isOn: $model.notificationSettings.agentCoolingAttention)
            }
            .controlSize(.small)
            .padding(.top, 4)
        } label: {
            Label("Notifications", systemImage: "bell")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var agentWorkflowSettings: some View {
        HStack(spacing: 8) {
            Label("Agent workflows", systemImage: "terminal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(AgentWorkflowSupport.WorkloadCommandMode.allCases) { mode in
                    Section(mode.menuTitle) {
                        ForEach(AgentWorkflowSupport.safeWorkloadCommandTemplates) { template in
                            Button(template.title) {
                                copyAgentWorkflowCommand(template, mode)
                            }
                        }
                    }
                }
            } label: {
                Label("Copy Command", systemImage: "terminal")
            }
            .controlSize(.small)
            .help(AgentWorkflowSupport.copyCommandHelp)
            Button {
                copyAgentWorkflowRule()
            } label: {
                Label("Copy Agent Rule", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help(AgentWorkflowSupport.copyHelp)
            if agentRuleCopied {
                Text(AgentWorkflowSupport.copiedMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if agentCommandCopied {
                Text(AgentWorkflowSupport.copiedCommandMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
