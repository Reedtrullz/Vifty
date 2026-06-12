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
                Text(model.menuTitle)
                    .font(.headline)
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(3)
            }

            if let sensor = model.snapshot?.highestTemperature {
                Label("\(sensor.name): \(sensor.celsius, specifier: "%.1f") C", systemImage: "thermometer.medium")
            }

            Label("Thermal pressure: \(model.thermalPressure.displayName)", systemImage: "speedometer")
                .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)

            Label(model.controlOwnershipSummary, systemImage: model.controlOwnershipNeedsAttention ? "exclamationmark.triangle" : "person.crop.circle.badge.checkmark")
                .font(.caption)
                .foregroundStyle(model.controlOwnershipNeedsAttention ? .orange : .secondary)
                .lineLimit(2)

            if let power = model.powerSnapshot {
                Label(PowerDisplayFormatter.summary(for: power), systemImage: power.isPluggedIn ? "bolt.fill" : "battery.50")
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
                if let adapter = power.adapter, adapter.powerWatts >= 0.5 {
                    Label(adapterDetail(adapter), systemImage: "powerplug")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .lineLimit(3)
            }

            if model.helperHealthNeedsAttention {
                Button(daemonInstaller.actionTitle) {
                    performHelperAction()
                }
                .disabled(!model.helperHealthNeedsAttention || !daemonInstaller.canInstall)
                .help(daemonInstaller.actionHelp)
            }

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
        case .error, .telemetryOnly, .noFanData:
            "exclamationmark.shield"
        }
    }

    private var helperHealthMenuColor: Color {
        switch model.helperHealthState {
        case .healthy:
            return Color.secondary
        case .checking:
            return Color.secondary
        case .error, .telemetryOnly, .unreachable, .noFanData:
            return Color.orange
        }
    }

    private func adapterDetail(_ adapter: PowerAdapter) -> String {
        var parts: [String] = []
        if let ratedWatts = adapter.ratedWatts {
            parts.append("\(ratedWatts) W")
        } else if adapter.powerWatts >= 0.5 {
            parts.append(PowerDisplayFormatter.watts(adapter.powerWatts))
        }
        if let voltage = adapter.negotiatedVoltageVolts, let current = adapter.negotiatedCurrentAmps {
            parts.append("\(PowerDisplayFormatter.volts(voltage)) · \(PowerDisplayFormatter.amps(current))")
        }
        return parts.isEmpty ? "Adapter connected" : parts.joined(separator: " · ")
    }
}
