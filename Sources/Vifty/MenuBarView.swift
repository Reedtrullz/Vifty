import SwiftUI
import ViftyCore

struct MenuBarView: View {
    var openMainWindow: (() -> Void)?

    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var helperRefreshTask: Task<Void, Never>?
    @State private var helperDiagnosticsCopied = false

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

            if let thermalSummary = model.thermalPressure.menuSummary {
                Label(thermalSummary, systemImage: "speedometer")
                    .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)
            }

            if let recentTelemetryTrendSummary = model.recentTelemetryTrendSummary {
                Label(recentTelemetryTrendSummary, systemImage: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if model.menuBarDisplaysCodexUsage {
                Label(model.codexUsageSummary, systemImage: "terminal")
                    .font(.caption)
                    .foregroundStyle(model.codexUsageSnapshot == nil ? .secondary : .primary)
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

            menuReadinessSection

            if let power = model.powerSnapshot {
                if let adapter = power.adapter, let adapterDetail = PowerDisplayFormatter.adapterDetail(for: adapter) {
                    Label(adapterDetail, systemImage: "bolt.fill")
                } else {
                    Label(PowerDisplayFormatter.summary(for: power), systemImage: power.isPluggedIn ? "bolt.fill" : "battery.50")
                }
                if let warning = PowerInsights(snapshot: power).chargerWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(model.snapshot?.fans ?? []) { fan in
                Label {
                    Text(verbatim: "\(fan.name) \(fan.currentRPM) RPM · \(fan.percentage)%")
                } icon: {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                }
            }

            if let expiresAt = model.manualSessionExpiresAt {
                Label("Auto restore at \(expiresAt.formatted(date: .omitted, time: .shortened))", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    NSApplication.shared.terminate(nil)
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

    private var menuReadinessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.compactControlOwnershipSummary, systemImage: model.controlOwnershipNeedsAttention ? "exclamationmark.triangle" : "person.crop.circle.badge.checkmark")
                .font(.caption)
                .foregroundStyle(model.controlOwnershipNeedsAttention ? .orange : .secondary)
                .lineLimit(2)
            menuHelperHealthSection
            menuAgentCoolingSection
        }
    }

    private var menuHelperHealthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.helperHealthMenuSummary, systemImage: helperHealthSystemImage)
                .font(.caption.weight(model.helperHealthNeedsAttention ? .semibold : .regular))
                .foregroundStyle(helperHealthMenuColor)

            if model.helperHealthNeedsAttention {
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
        }
    }

    @ViewBuilder
    private var menuAgentCoolingSection: some View {
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
        case .error, .runtimeMismatch, .telemetryOnly, .noFanData, .noControllableFans:
            "exclamationmark.shield"
        }
    }

    private var helperHealthMenuColor: Color {
        switch model.helperHealthState {
        case .healthy:
            return Color.secondary
        case .checking:
            return Color.secondary
        case .error, .runtimeMismatch, .telemetryOnly, .unreachable, .noFanData, .noControllableFans, .unsupported:
            return Color.orange
        }
    }

}
