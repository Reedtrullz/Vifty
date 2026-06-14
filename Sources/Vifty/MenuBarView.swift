import SwiftUI
import ViftyCore

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var helperRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "fan")
                Text(model.menuPanelTitle)
                    .font(.headline)
            }

            if let error = model.lastError {
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

            if let temperatureAttentionSummary = model.temperatureAttentionSummary {
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
                    if model.agentCoolingNeedsAttention {
                        Button("Auto") { model.restoreAuto() }
                        .controlSize(.small)
                        .help("Restore Auto before starting another agent workload")
                    }
                }
            }

            Label(model.helperHealthSummary, systemImage: helperHealthSystemImage)
                .font(.caption)
                .foregroundStyle(helperHealthMenuColor)

            if let helperRecoverySuggestion = model.helperRecoverySuggestion {
                Label(helperRecoverySuggestion, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if model.helperRepairActionAvailable {
                Label(daemonInstaller.actionDescription, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button(daemonInstaller.actionTitle) {
                    performHelperAction()
                }
                .disabled(!daemonInstaller.canInstall)
                .help(daemonInstaller.actionHelp)
            }

            Picker("Menu bar", selection: $model.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)

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
                    openWindow(id: "main")
                }
                Button("Auto") {
                    model.restoreAuto()
                }
                .keyboardShortcut("a")
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
