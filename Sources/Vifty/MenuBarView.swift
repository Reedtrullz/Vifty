import SwiftUI
import ViftyCore

struct MenuBarView: View {
    var openMainWindow: (() -> Void)?

    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var helperRefreshTask: Task<Void, Never>?
    @State private var helperDiagnosticsCopied = false
    @State private var agentRuleCopied = false
    @State private var selectedMenuCurveProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fan")
                Text(model.menuPanelTitle)
                    .font(.headline)
            }

            if let error = model.visibleLastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(3)
            }

            if let sensor = model.selectedSensor {
                Label("\(sensor.name): \(sensor.celsius, specifier: "%.1f") C", systemImage: "thermometer.medium")
            }

            Label("Thermal pressure: \(model.thermalPressure.displayName)", systemImage: "speedometer")
                .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)

            if let recentTelemetryTrendSummary = model.recentTelemetryTrendSummary {
                Label(recentTelemetryTrendSummary, systemImage: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let fanWriteBlockedWhileHotSummary = model.fanWriteBlockedWhileHotSummary {
                Label(fanWriteBlockedWhileHotSummary, systemImage: "thermometer.high")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                if let recovery = model.fanWriteBlockedWhileHotRecoverySuggestion {
                    Label(recovery, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            } else if let temperatureAttentionSummary = model.temperatureAttentionSummary {
                Label(temperatureAttentionSummary, systemImage: "thermometer.high")
                    .foregroundStyle(.orange)
            }

            Label(model.controlOwnershipSummary, systemImage: model.controlOwnershipNeedsAttention ? "exclamationmark.triangle" : "person.crop.circle.badge.checkmark")
                .font(.caption)
                .foregroundStyle(model.controlOwnershipNeedsAttention ? .orange : .secondary)
                .lineLimit(2)

            if let power = model.powerSnapshot {
                if let adapter = power.adapter, let adapterDetail = PowerDisplayFormatter.adapterDetail(for: adapter) {
                    Label(adapterDetail, systemImage: "bolt.fill")
                } else {
                    Label(PowerDisplayFormatter.summary(for: power), systemImage: power.isPluggedIn ? "bolt.fill" : "battery.50")
                }
                if let flow = PowerDisplayFormatter.batteryFlow(for: power) {
                    Label(flow, systemImage: power.batteryIsActivelyCharging ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let warning = PowerInsights(snapshot: power).chargerWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(model.snapshot?.fans ?? []) { fan in
                Label("\(fan.name): \(fan.currentRPM) RPM (\(fan.percentage)%)", systemImage: "gauge.with.dots.needle.67percent")
            }

            if let expiresAt = model.manualSessionExpiresAt {
                Label("Auto restore at \(expiresAt.formatted(date: .omitted, time: .shortened))", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let agentCoolingSummary = model.agentCoolingSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.agentCoolingPanelTitle, systemImage: "cpu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.agentCoolingNeedsAttention ? .orange : .blue)
                    Text(agentCoolingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let agentCoolingRecoverySuggestion = model.agentCoolingRecoverySuggestion {
                        Label(agentCoolingRecoverySuggestion, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                    }
                    if model.agentCoolingNeedsAttention, model.agentCoolingRestoreActionAvailable {
                        Button(model.agentCoolingRestoreActionTitle) { model.restoreAuto() }
                        .controlSize(.small)
                        .help(model.agentCoolingRestoreActionHelp)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(model.helperHealthMenuSummary, systemImage: helperHealthSystemImage)
                    .font(.caption.weight(model.helperHealthNeedsAttention ? .semibold : .regular))
                    .foregroundStyle(helperHealthMenuColor)
                Text(daemonInstaller.helperStatusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let context = model.helperInstallRuntimeContext {
                    Text(context)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let helperRecoverySuggestion = model.helperMenuRecoverySuggestion {
                    Text(helperRecoverySuggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.helperRepairActionAvailable || model.helperHealthNeedsAttention {
                    HStack(spacing: 8) {
                        if model.helperRepairActionAvailable {
                            Button(daemonInstaller.actionTitle) {
                                performHelperAction()
                            }
                            .disabled(!daemonInstaller.canInstall)
                            .help(daemonInstaller.actionDescription)
                        }
                        Button {
                            copyHelperDiagnosticsCommand()
                        } label: {
                            Label("Copy Support Evidence", systemImage: "doc.on.doc")
                        }
                        .help(HelperDiagnosticsSupport.copyHelp)
                    }
                }

                if helperDiagnosticsCopied {
                    Text(HelperDiagnosticsSupport.copiedMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.savedProfiles.isEmpty {
                Picker("Curve profile", selection: $selectedMenuCurveProfileID) {
                    Text("Choose profile").tag(Optional<UUID>.none)
                    ForEach(model.savedProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .onChange(of: selectedMenuCurveProfileID) { _, newID in
                    _ = model.selectCurveProfile(id: newID)
                }
            }

            Picker("Default mode", selection: $model.startupMode) {
                ForEach(ModeSelection.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .help("Mode Vifty selects when the app starts")

            Toggle("Start Vifty at startup", isOn: launchAtLoginBinding)
                .controlSize(.small)
                .help("Open Vifty automatically at macOS login")

            if let launchAtLoginStatusMessage = model.launchAtLoginStatusMessage {
                HStack(alignment: .top, spacing: 6) {
                    Label(
                        launchAtLoginStatusMessage,
                        systemImage: model.launchAtLoginStatus == .requiresApproval ? "exclamationmark.triangle" : "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(model.launchAtLoginStatus == .requiresApproval ? .orange : .secondary)
                    .lineLimit(2)
                    if model.launchAtLoginStatus == .requiresApproval {
                        Button("Open Login Items") {
                            model.openLaunchAtLoginSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Picker("Menu bar", selection: $model.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Button {
                copyAgentWorkflowRule()
            } label: {
                Label("Copy Agent Rule", systemImage: "terminal")
            }
            .controlSize(.small)
            .help(AgentWorkflowSupport.copyHelp)

            if agentRuleCopied {
                Text(AgentWorkflowSupport.copiedMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup {
                Toggle("Helper failure", isOn: $model.notificationSettings.helperFailure)
                Toggle("High thermal pressure", isOn: $model.notificationSettings.elevatedThermalPressure)
                Toggle("Auto restore failure", isOn: $model.notificationSettings.autoRestoreFailure)
                Toggle("Plugged-in battery drain", isOn: $model.notificationSettings.pluggedInBatteryDrain)
                Toggle("Agent cooling attention", isOn: $model.notificationSettings.agentCoolingAttention)
            } label: {
                Label("Notifications", systemImage: "bell")
                    .font(.caption.weight(.semibold))
            }
            .font(.caption)

            Divider()

            HStack {
                Button("Open Vifty") {
                    if let openMainWindow {
                        openMainWindow()
                    } else {
                        openWindow(id: "main")
                    }
                }
                Button(model.autoRestoreActionTitle) {
                    model.restoreAuto()
                }
                .keyboardShortcut("a")
                .help(model.autoRestoreActionHelp)
                Button("Quit") {
                    Task { @MainActor in
                        await model.stopAndRestore()
                        NSApplication.shared.terminate(nil)
                    }
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            daemonInstaller.refresh()
            model.refreshLaunchAtLoginStatus()
        }
        .onDisappear {
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
        }
        .task {
            model.start()
        }
    }

    private func performHelperAction() {
        helperRefreshTask?.cancel()
        daemonInstaller.installOrOpenApproval()
        helperRefreshTask = Task { @MainActor in
            await model.pollOnce()
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            daemonInstaller.refresh()
            await model.pollOnce()
        }
    }

    private func copyHelperDiagnosticsCommand() {
        HelperDiagnosticsSupport.copySupportEvidenceCommand(context: model.helperSupportEvidenceContext)
        helperDiagnosticsCopied = true
    }

    private func copyAgentWorkflowRule() {
        AgentWorkflowSupport.copyAgentRule()
        agentRuleCopied = true
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLoginEnabled($0) }
        )
    }

    private var helperHealthSystemImage: String {
        switch model.helperHealthState {
        case .checking:
            "hourglass"
        case .healthy:
            "checkmark.shield"
        case .unreachable:
            "xmark.shield"
        case .unsupported:
            "slash.circle"
        case .error, .telemetryOnly, .noFanData, .noControllableFans:
            "exclamationmark.shield"
        }
    }

    private var helperHealthMenuColor: Color {
        switch model.helperHealthState {
        case .healthy:
            return Color.secondary
        case .checking:
            return Color.secondary
        case .error, .telemetryOnly, .unreachable, .noFanData, .noControllableFans, .unsupported:
            return Color.orange
        }
    }

}
