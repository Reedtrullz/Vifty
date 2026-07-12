import SwiftUI
import ViftyCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var helperRefreshTask: Task<Void, Never>?
    @State private var helperDiagnosticsCopied = false

    var body: some View {
        VStack(spacing: 0) {
            MainWindowHeader(
                appName: "Vifty",
                modelIdentifier: model.snapshot?.modelIdentifier ?? "Detecting hardware",
                powerText: model.powerSnapshot.map { PowerDisplayFormatter.summary(for: $0) },
                thermalText: "Thermal \(model.thermalPressure.displayName)",
                thermalIsElevated: model.thermalPressure == .serious || model.thermalPressure == .critical,
                helperActionTitle: model.helperRepairActionAvailable ? daemonInstaller.actionTitle : nil,
                helperActionHelp: model.helperRepairActionAvailable ? daemonInstaller.actionHelp : nil,
                helperActionDisabled: !daemonInstaller.canInstall,
                showsDiagnosticsOnly: !model.helperRepairActionAvailable && model.helperHealthNeedsAttention,
                visibleError: model.visibleLastError,
                statusText: model.controlState.statusMessage,
                onHelperAction: performHelperAction
            )
            Divider()
            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            model.start()
        }
    }

    private var mainContent: some View {
        GeometryReader { proxy in
            let layout = MainWindowLayout.resolve(width: proxy.size.width, height: proxy.size.height)
            let placement = MainWindowSectionPlacement.resolve(layout: layout)

            Group {
                switch layout.mode {
                case .stacked:
                    let stackedSections = placement.sections(in: .stackedFlow)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            paneSectionsView(
                                stackedSections.filter { $0 != .telemetryEvidence },
                                compactTelemetry: layout.compactTelemetry,
                                minHeight: nil
                            )
                            if stackedSections.contains(.telemetryEvidence) {
                                Divider()
                                sectionView(.telemetryEvidence, compactTelemetry: layout.compactTelemetry)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .background(Color.secondary.opacity(0.035))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                case .split:
                    let controlSections = placement.sections(in: .splitControl)
                    let telemetrySections = placement.sections(in: .splitTelemetry)
                    HStack(alignment: .top, spacing: 0) {
                        paneScrollView(
                            sections: controlSections,
                            compactTelemetry: layout.compactTelemetry,
                            minHeight: proxy.size.height
                        )
                        .frame(width: layout.controlPaneWidth)
                        .frame(minHeight: proxy.size.height, maxHeight: proxy.size.height)

                        Divider().frame(height: proxy.size.height)

                        paneScrollView(
                            sections: telemetrySections,
                            compactTelemetry: layout.compactTelemetry,
                            minHeight: proxy.size.height,
                            outerPadding: 0
                        )
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, maxHeight: proxy.size.height)
                        .background(Color.secondary.opacity(0.035))
                    }
                case .workbench:
                    let controlSections = placement.sections(in: .workbenchControlRail)
                    let editorSections = placement.sections(in: .workbenchEditor)
                    let telemetrySections = placement.sections(in: .workbenchTelemetry)
                    HStack(alignment: .top, spacing: 0) {
                        paneScrollView(
                            sections: controlSections,
                            compactTelemetry: layout.compactTelemetry,
                            minHeight: proxy.size.height
                        )
                        .frame(width: layout.controlPaneWidth)
                        .frame(minHeight: proxy.size.height, maxHeight: proxy.size.height)

                        Divider().frame(height: proxy.size.height)

                        paneScrollView(
                            sections: editorSections,
                            compactTelemetry: layout.compactTelemetry,
                            minHeight: proxy.size.height
                        )
                        .frame(
                            minWidth: layout.editorPaneMinWidth,
                            idealWidth: layout.editorPaneIdealWidth,
                            maxWidth: layout.editorPaneMaxWidth,
                            minHeight: proxy.size.height,
                            maxHeight: proxy.size.height
                        )

                        Divider().frame(height: proxy.size.height)

                        paneScrollView(
                            sections: telemetrySections,
                            compactTelemetry: layout.compactTelemetry,
                            minHeight: proxy.size.height,
                            outerPadding: 0
                        )
                        .frame(
                            minWidth: layout.telemetryPaneMinWidth,
                            idealWidth: layout.telemetryPaneIdealWidth,
                            maxWidth: layout.telemetryPaneMaxWidth,
                            minHeight: proxy.size.height,
                            maxHeight: proxy.size.height
                        )
                        .background(Color.secondary.opacity(0.035))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func paneScrollView(
        sections: [MainWindowSection],
        compactTelemetry: Bool,
        minHeight: CGFloat,
        outerPadding: CGFloat = 16
    ) -> some View {
        ScrollView(.vertical) {
            paneSectionsView(
                sections,
                compactTelemetry: compactTelemetry,
                minHeight: minHeight,
                outerPadding: outerPadding
            )
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
    }

    private func paneSectionsView(
        _ sections: [MainWindowSection],
        compactTelemetry: Bool,
        minHeight: CGFloat?,
        outerPadding: CGFloat = 16
    ) -> some View {
        let needsHelperLifecycle = sections.contains(.safetyMode) || sections.contains(.settingsAndTools)

        return VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    Divider()
                }
                sectionView(section, compactTelemetry: compactTelemetry)
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .onAppear {
            guard needsHelperLifecycle else { return }
            daemonInstaller.refresh()
        }
        .onDisappear {
            guard needsHelperLifecycle else { return }
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
        }
    }

    @ViewBuilder
    private func sectionView(
        _ section: MainWindowSection,
        compactTelemetry: Bool
    ) -> some View {
        switch section {
        case .safetyMode:
            ReadinessModePanel(
                selectedMode: $model.selectedMode,
                manualRunLimit: $model.manualRunLimit,
                manualFanControlAvailable: model.manualFanControlAvailable,
                fanWriteBlockedWhileHotSummary: model.fanWriteBlockedWhileHotSummary,
                fanWriteBlockedWhileHotRecoverySuggestion: model.fanWriteBlockedWhileHotRecoverySuggestion,
                manualControlAttentionSummary: model.manualControlAttentionSummary,
                manualControlAttentionRecoverySuggestion: model.manualControlAttentionRecoverySuggestion,
                manualFanControlBlockedReason: model.manualFanControlBlockedReason,
                presentation: model.controlSessionPresentation,
                onModeChange: handleModeChange,
                onManualRunLimitChange: model.markFanControlDraftPending,
                onPrimaryAction: { performControlSessionPrimaryAction(model.controlSessionPresentation) }
            )
        case .fanControl:
            FanControlPanel(
                snapshot: model.snapshot,
                selectedMode: model.selectedMode,
                fixedRPM: $model.fixedRPM,
                usePerFanFixedRPM: $model.usePerFanFixedRPM,
                curveStartTemp: $model.curveStartTemp,
                curveMidTemp: $model.curveMidTemp,
                curveMaxTemp: $model.curveMaxTemp,
                curveStartRPM: $model.curveStartRPM,
                curveMidRPM: $model.curveMidRPM,
                curveMaxRPM: $model.curveMaxRPM,
                selectedSensorID: $model.selectedSensorID,
                effectiveSensor: model.selectedSensor,
                effectiveSensorID: model.effectiveSelectedSensorID,
                usePerFanOverrides: $model.usePerFanOverrides,
                savedProfiles: model.savedProfiles,
                selectedCurveProfileID: $model.selectedCurveProfileID,
                fanRange: model.fanRange,
                fanOverrides: model.fanOverrides,
                manualFanControlAvailable: model.manualFanControlAvailable,
                helperRecoverySuggestion: model.helperRecoverySuggestion,
                fanAccessMessage: model.fanAccessMessage,
                helperActionTitle: model.helperRepairActionAvailable ? daemonInstaller.actionTitle : nil,
                helperActionHelp: model.helperRepairActionAvailable ? daemonInstaller.actionHelp : nil,
                helperActionDisabled: !daemonInstaller.canInstall,
                helperStatusText: daemonInstaller.statusText,
                helperDiagnosticsCopied: helperDiagnosticsCopied,
                appliedTargetRPM: model.appliedTargetRPM,
                draftTargetRPMPreview: model.draftTargetRPMPreview,
                fixedFanSliderRPM: model.fixedFanSliderRPM,
                fixedFanTargetRPM: model.fixedFanTargetRPM,
                fixedFanTargetPercent: model.fixedFanTargetPercent,
                ensureFixedFanTargets: model.ensureFixedFanTargets,
                setFixedFanRPM: { rpm, fan in model.setFixedFanRPM(rpm, for: fan, persist: false) },
                commitFixedFanTargets: model.commitFixedFanTargetsAndApply,
                loadDeveloperPreset: model.loadDeveloperPreset,
                selectCurveProfile: { _ = model.selectCurveProfile(id: $0) },
                deleteProfile: model.deleteProfile,
                ensureFanOverrides: model.ensureFanOverrides,
                fanOverride: model.fanOverride,
                setOverrideStartRPM: model.setOverrideStartRPM,
                setOverrideMidRPM: model.setOverrideMidRPM,
                setOverrideMaxRPM: model.setOverrideMaxRPM,
                saveProfile: model.saveCurrentProfile,
                markDraftPending: model.markFanControlDraftPending,
                onHelperAction: performHelperAction,
                onCopyDiagnostics: copyHelperDiagnosticsCommand
            )
        case .settingsAndTools:
            settingsAndToolsLauncher
        case .telemetryEvidence:
            TelemetryEvidencePanel(
                power: model.powerSnapshot,
                summary: compactTelemetry ? model.compactTelemetryOverviewSummary : model.telemetryOverviewSummary,
                sensors: model.snapshot?.temperatureSensors ?? [],
                effectiveSensorID: model.effectiveSelectedSensorID,
                compact: compactTelemetry,
                onSelectSensor: selectSensor
            )
        }
    }

    private var settingsAndToolsLauncher: some View {
        SettingsLink {
            HStack(spacing: 8) {
                Label("Settings & Tools", systemImage: "gearshape")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Vifty settings")
    }

    private func handleModeChange(_ mode: ModeSelection) {
        if mode == .auto {
            model.restoreAuto()
        } else {
            model.markFanControlDraftPending()
        }
    }

    private func selectSensor(_ sensorID: String) {
        model.selectedSensorID = sensorID
        if model.selectedMode == .curve {
            model.markFanControlDraftPending()
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

    private func performControlSessionPrimaryAction(_ presentation: ControlSessionPresentation) {
        switch presentation.primaryAction {
        case .repairHelper:
            performHelperAction()
        case .copyDiagnostics:
            copyHelperDiagnosticsCommand()
        case .apply, .restoreAuto:
            model.performModeSelectionAction()
        case .none:
            break
        }
    }
}
