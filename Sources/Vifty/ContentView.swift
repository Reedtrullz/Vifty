import SwiftUI
import ViftyCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var newProfileName = ""
    @State private var showSaveDialog = false
    @State private var selectedProfileID: UUID?
    @State private var helperRefreshTask: Task<Void, Never>?
    @State private var helperDiagnosticsCopied = false
    @State private var agentRuleCopied = false
    @State private var agentCommandCopied = false

    var body: some View {
        VStack(spacing: 0) {
            header
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
            let _ = placement

            Group {
                switch layout.mode {
                case .stacked:
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            fanControlPane
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            Divider()

                            sensorsPane(compact: layout.compactTelemetry)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(Color.secondary.opacity(0.035))
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                case .split:
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView(.vertical) {
                            fanControlPane
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .scrollIndicators(.visible)
                        .frame(width: layout.controlPaneWidth)
                        .frame(minHeight: proxy.size.height, maxHeight: proxy.size.height)

                        Divider()
                            .frame(height: proxy.size.height)

                        ScrollView(.vertical) {
                            sensorsPane(compact: layout.compactTelemetry)
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .scrollIndicators(.visible)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, maxHeight: proxy.size.height)
                        .background(Color.secondary.opacity(0.035))
                    }
                case .workbench:
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView(.vertical) {
                            controlRailPane
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .scrollIndicators(.visible)
                        .frame(width: layout.controlPaneWidth)
                        .frame(minHeight: proxy.size.height, maxHeight: proxy.size.height)

                        Divider()
                            .frame(height: proxy.size.height)

                        ScrollView(.vertical) {
                            primaryEditorPane
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .scrollIndicators(.visible)
                        .frame(minWidth: layout.editorPaneMinWidth, idealWidth: layout.editorPaneIdealWidth, maxWidth: layout.editorPaneMaxWidth, minHeight: proxy.size.height, maxHeight: proxy.size.height)

                        Divider()
                            .frame(height: proxy.size.height)

                        ScrollView(.vertical) {
                            sensorsPane(compact: layout.compactTelemetry)
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        }
                        .scrollIndicators(.visible)
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

    private var helperHealthColor: Color {
        switch model.helperHealthState {
        case .checking:
            return .secondary
        case .healthy:
            return .green
        case .error, .runtimeMismatch, .telemetryOnly, .unreachable, .noFanData, .noControllableFans, .unsupported:
            return .orange
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "fan")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vifty")
                    .font(.title3.weight(.semibold))
                Text(model.snapshot?.modelIdentifier ?? "Detecting hardware")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let power = model.powerSnapshot {
                Label(PowerDisplayFormatter.summary(for: power), systemImage: power.isPluggedIn ? "bolt.fill" : "battery.50")
                    .font(.caption)
                    .foregroundStyle(power.isPluggedIn ? .green : .secondary)
                    .monospacedDigit()
            }
            Label("Thermal \(model.thermalPressure.displayName)", systemImage: "speedometer")
                .font(.caption)
                .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)
            if model.helperRepairActionAvailable {
                Button {
                    performHelperAction()
                } label: {
                    Label(daemonInstaller.actionTitle, systemImage: "lock.shield")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!daemonInstaller.canInstall)
                .help(daemonInstaller.actionHelp)
            } else if model.helperHealthNeedsAttention {
                Label("Diagnostics only", systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.visibleLastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: 340, alignment: .trailing)
            } else {
                Text(model.controlState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var fanControlPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            safetyModeSection

            Divider()

            fanControlWorkspace

            Divider()

            settingsAndToolsPanel
        }
        .padding(16)
        .onAppear {
            daemonInstaller.refresh()
        }
        .onDisappear {
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
        }
    }

    private var controlRailPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            safetyModeSection

            Spacer(minLength: 24)

            Divider()

            settingsAndToolsPanel
        }
        .padding(16)
        .onAppear {
            daemonInstaller.refresh()
        }
        .onDisappear {
            helperRefreshTask?.cancel()
            helperRefreshTask = nil
        }
    }

    private var primaryEditorPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            fanControlWorkspace
        }
        .padding(16)
    }

    private var safetyModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Safety & Mode", systemImage: "shield.lefthalf.filled")
                .font(.headline)
            readinessStatusGroup
            modePicker
        }
    }

    private var fanControlWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Fan Control", systemImage: "fan")
                .font(.headline)

            if model.selectedMode == .curve {
                curveEditor
                Divider()
            } else if model.selectedMode == .fixed {
                fixedEditor
                Divider()
            }

            fansSection
        }
    }

    private var settingsAndToolsPanel: some View {
        SettingsToolsPanel(
            model: model,
            selectedProfileID: $selectedProfileID,
            agentRuleCopied: $agentRuleCopied,
            agentCommandCopied: $agentCommandCopied,
            menuBarCustomFieldBinding: menuBarCustomFieldBinding(_:),
            copyAgentWorkflowCommand: copyAgentWorkflowCommand(_:mode:),
            copyAgentWorkflowRule: copyAgentWorkflowRule
        )
    }

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans")
                .font(.headline)

            if let fans = model.snapshot?.fans, !fans.isEmpty {
                ForEach(fans) { fan in
                    FanRow(fan: fan, targetRPM: model.targetRPMPreview(for: fan))
                }
            } else {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Fan Access Unavailable",
                        systemImage: "fan.slash",
                        description: Text(model.helperRecoverySuggestion ?? model.fanAccessMessage ?? daemonInstaller.statusText)
                    )
                    if model.helperRepairActionAvailable {
                        Button {
                            performHelperAction()
                        } label: {
                            Label(daemonInstaller.actionTitle, systemImage: "lock.shield")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!daemonInstaller.canInstall)
                        .help(daemonInstaller.actionHelp)
                    } else {
                        Button {
                            copyHelperDiagnosticsCommand()
                        } label: {
                            Label("Copy Support Evidence", systemImage: "doc.on.doc")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .help(HelperDiagnosticsSupport.copyHelp)
                    }
                    Text(daemonInstaller.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if helperDiagnosticsCopied {
                        Text(HelperDiagnosticsSupport.copiedMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
    }

    private var readinessStatusGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Readiness")
                .font(.headline)
            fanWriteBlockedWhileHotCard
            helperHealthCard
            controlOwnerCard
            agentCoolingCard
        }
    }

    @ViewBuilder
    private var fanWriteBlockedWhileHotCard: some View {
        if let fanWriteBlockedWhileHotSummary = model.fanWriteBlockedWhileHotSummary {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.high")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fanWriteBlockedWhileHotSummary)
                        .font(.caption.weight(.semibold))
                    if let recovery = model.fanWriteBlockedWhileHotRecoverySuggestion {
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var helperHealthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: helperHealthSystemImage)
                    .foregroundStyle(helperHealthColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan Helper")
                        .font(.caption.weight(.semibold))
                    Text(model.helperHealthSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    if let suggestion = model.helperRecoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            if model.helperRepairActionAvailable || model.helperHealthNeedsAttention {
                HStack(spacing: 8) {
                    if model.helperRepairActionAvailable {
                        Button(daemonInstaller.actionTitle) {
                            performHelperAction()
                        }
                        .controlSize(.small)
                        .disabled(!daemonInstaller.canInstall)
                        .help(daemonInstaller.actionDescription)
                    }
                    Button {
                        copyHelperDiagnosticsCommand()
                    } label: {
                        Label("Copy Support Evidence", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .help(HelperDiagnosticsSupport.copyHelp)
                    if helperDiagnosticsCopied {
                        Text(HelperDiagnosticsSupport.copiedMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controlOwnerCard: some View {
        HStack(spacing: 8) {
            Image(systemName: model.controlOwnershipNeedsAttention ? "exclamationmark.triangle" : "person.crop.circle.badge.checkmark")
                .foregroundStyle(model.controlOwnershipNeedsAttention ? .orange : .green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fan Control Owner")
                    .font(.caption.weight(.semibold))
                Text(model.controlOwnershipSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(10)
        .background((model.controlOwnershipNeedsAttention ? Color.orange : Color.green).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var agentCoolingCard: some View {
        if let agentCoolingSummary = model.agentCoolingSummary {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundStyle(model.agentCoolingNeedsAttention ? .orange : .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.agentCoolingPanelTitle)
                        .font(.caption.weight(.semibold))
                    Text(agentCoolingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let agentCoolingRecoverySuggestion = model.agentCoolingRecoverySuggestion {
                        Text(agentCoolingRecoverySuggestion)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                    }
                }
                Spacer()
                if model.agentCoolingRestoreActionAvailable {
                    Button(model.agentCoolingRestoreActionTitle) { model.restoreAuto() }
                        .controlSize(.small)
                        .help(model.agentCoolingRestoreActionHelp)
                }
            }
            .padding(10)
            .background((model.agentCoolingNeedsAttention ? Color.orange : Color.blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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
        agentCommandCopied = false
    }

    private func copyAgentWorkflowCommand(
        _ template: AgentWorkflowSupport.WorkloadCommandTemplate,
        mode: AgentWorkflowSupport.WorkloadCommandMode
    ) {
        AgentWorkflowSupport.copyWorkloadCommand(template, mode: mode)
        agentRuleCopied = false
        agentCommandCopied = true
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $model.selectedMode) {
                ForEach(ModeSelection.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.selectedMode) {
                model.applyModeSelection()
            }

            Picker("Manual run", selection: $model.manualRunLimit) {
                ForEach(ManualRunLimit.presets) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.selectedMode != .auto && !model.manualFanControlAvailable)

            if let manualControlAttentionSummary = model.manualControlAttentionSummary {
                Label(manualControlAttentionSummary, systemImage: "hourglass.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                if let recovery = model.manualControlAttentionRecoverySuggestion {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else if let blockedReason = model.manualFanControlBlockedReason {
                Label(blockedReason, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let expiresAt = model.manualSessionExpiresAt {
                Text("Auto restore scheduled at \(expiresAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.performModeSelectionAction()
            } label: {
                Label(model.modeSelectionActionTitle, systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.modeSelectionActionDisabled)
            .help(model.modeSelectionActionHelp)
        }
    }

    private func menuBarCustomFieldBinding(_ field: MenuBarField) -> Binding<Bool> {
        Binding(
            get: { model.isMenuBarCustomFieldEnabled(field) },
            set: { model.setMenuBarCustomField(field, enabled: $0) }
        )
    }

    private var fixedEditor: some View {
        let fans = model.snapshot?.fans ?? []
        let controllableFans = fans.filter(\.controllable)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fixed RPM")
                    .font(.headline)
                Spacer()
                if controllableFans.count > 1 {
                    Toggle("Per-fan targets", isOn: $model.usePerFanFixedRPM)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: model.usePerFanFixedRPM) {
                            if model.usePerFanFixedRPM {
                                model.ensureFixedFanTargets(for: controllableFans)
                            }
                            model.applyModeSelection()
                        }
                        .help("Set different fixed RPM targets for fans with different speed ranges")
                        .accessibilityLabel("Per-fan fixed RPM targets")
                        .accessibilityHint("Set separate fixed RPM targets for each fan.")
                }
            }

            if model.usePerFanFixedRPM, controllableFans.count > 1 {
                ForEach(controllableFans) { fan in
                    let targetRPM = model.fixedFanTargetRPM(for: fan)
                    let targetPercent = model.fixedFanTargetPercent(for: fan)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fan.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(targetRPM) RPM · \(targetPercent)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(model.fixedFanSliderRPM(for: fan)) },
                                set: { value in
                                    model.setFixedFanRPM(Int(value.rounded()), for: fan, persist: false)
                                }
                            ),
                            in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                            step: 50,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    model.commitFixedFanTargetsAndApply()
                                }
                            }
                        )
                        .help("\(fan.name) fixed target. Range \(fan.minimumRPM)-\(fan.maximumRPM) RPM; currently \(targetPercent)% of that fan's range.")
                        .accessibilityLabel("\(fan.name) fixed RPM target")
                        .accessibilityValue("\(targetRPM) RPM, \(targetPercent)%")
                        .accessibilityHint("\(fan.name) target is clamped to \(fan.minimumRPM)-\(fan.maximumRPM) RPM.")
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    model.ensureFixedFanTargets(for: controllableFans)
                }
            } else {
                Slider(
                    value: $model.fixedRPM,
                    in: model.fanRange,
                    step: 50,
                    onEditingChanged: { isEditing in
                        guard !isEditing else { return }
                        model.applyModeSelection()
                    }
                )
                .accessibilityLabel("Fixed RPM target")
                .accessibilityValue("\(Int(model.fixedRPM.rounded())) RPM")
                .accessibilityHint("Sets one fixed target for every controllable fan.")
                Text("\(Int(model.fixedRPM.rounded())) RPM")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!model.manualFanControlAvailable)
    }

    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperature Curve")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(DeveloperFanPreset.allCases) { preset in
                        Button {
                            model.loadDeveloperPreset(preset)
                            selectedProfileID = nil
                            model.applyModeSelection()
                        } label: {
                            Label(preset.displayName, systemImage: preset.systemImage)
                        }
                    }
                } label: {
                    Label("Developer Presets", systemImage: "slider.horizontal.3")
                }
                .controlSize(.small)
                .help("Apply a conservative fan curve for common developer workloads")
            }

            if let sensors = model.snapshot?.temperatureSensors, !sensors.isEmpty {
                Picker("Sensor", selection: $model.selectedSensorID) {
                    ForEach(sensors) { sensor in
                        Text(sensor.name).tag(Optional(sensor.id))
                    }
                }
                .onChange(of: model.selectedSensorID) {
                    model.applyModeSelection()
                }
            }

            FanCurveChartEditor(
                startTemp: $model.curveStartTemp,
                midTemp: $model.curveMidTemp,
                maxTemp: $model.curveMaxTemp,
                startRPM: $model.curveStartRPM,
                midRPM: $model.curveMidRPM,
                maxRPM: $model.curveMaxRPM,
                rpmRange: model.fanRange,
                liveTemperature: model.selectedSensor?.celsius,
                fans: model.snapshot?.fans ?? [],
                fanOverrides: model.fanOverrides,
                usePerFanOverrides: model.usePerFanOverrides
            )

            DisclosureGroup("Exact points") {
                VStack(alignment: .leading, spacing: 10) {
                    CurvePointEditor(title: "Start", temp: $model.curveStartTemp, rpm: $model.curveStartRPM, rpmRange: model.fanRange)
                    CurvePointEditor(title: "Ramp", temp: $model.curveMidTemp, rpm: $model.curveMidRPM, rpmRange: model.fanRange)
                    CurvePointEditor(title: "High", temp: $model.curveMaxTemp, rpm: $model.curveMaxRPM, rpmRange: model.fanRange)
                }
                .padding(.top, 6)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if let fans = model.snapshot?.fans, fans.count > 1 {
                Toggle("Per-fan overrides", isOn: $model.usePerFanOverrides)
                    .onChange(of: model.usePerFanOverrides) {
                        if model.usePerFanOverrides {
                            model.ensureFanOverrides(for: fans)
                        }
                        model.applyCurveOverrides()
                    }

                if model.usePerFanOverrides {
                    ForEach(fans) { fan in
                        if let override = model.fanOverride(for: fan.id) {
                            CompactFanOverrideEditor(
                                fan: fan,
                                startRPM: model.fanOverride(for: fan.id)?.startRPM ?? override.startRPM,
                                midRPM: model.fanOverride(for: fan.id)?.midRPM ?? override.midRPM,
                                maxRPM: model.fanOverride(for: fan.id)?.maxRPM ?? override.maxRPM,
                                setStartRPM: { rpm in
                                    model.setOverrideStartRPM(rpm, for: fan)
                                    model.applyCurveOverrides()
                                },
                                setMidRPM: { rpm in
                                    model.setOverrideMidRPM(rpm, for: fan)
                                    model.applyCurveOverrides()
                                },
                                setMaxRPM: { rpm in
                                    model.setOverrideMaxRPM(rpm, for: fan)
                                    model.applyCurveOverrides()
                                }
                            )
                        }
                    }
                    .onAppear {
                        model.ensureFanOverrides(for: fans)
                    }
                }
            }

            HStack {
                if showSaveDialog {
                    TextField("Profile name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button("Save") {
                        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        model.saveCurrentProfile(name: name)
                        selectedProfileID = model.savedProfiles.last?.id
                        newProfileName = ""
                        showSaveDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Cancel") {
                        newProfileName = ""
                        showSaveDialog = false
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else {
                    Button {
                        showSaveDialog = true
                    } label: {
                        Label("Save Profile", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .disabled(!model.manualFanControlAvailable)
    }

    private func sensorsPane(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Telemetry & Evidence", systemImage: "waveform.path.ecg")
                .font(.headline)

            TelemetryOverviewPanel(
                power: model.powerSnapshot,
                summary: compact ? model.compactTelemetryOverviewSummary : model.telemetryOverviewSummary,
                compact: compact
            )

            HStack {
                Text("Temperatures")
                    .font(.headline)
                Spacer()
                if let highest = model.snapshot?.highestTemperature {
                    Text("Highest \(highest.celsius, specifier: "%.1f") C")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let sensors = model.snapshot?.temperatureSensors, !sensors.isEmpty {
                DisclosureGroup("All sensors") {
                    LazyVStack(spacing: 6) {
                        ForEach(sensors) { sensor in
                            SensorRow(sensor: sensor, selected: sensor.id == model.selectedSensor?.id, compact: true)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No Temperature Sensors", systemImage: "thermometer.slash", description: Text("Vifty needs at least one temperature sensor before fan curves can run."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TelemetryOverviewPanel: View {
    let power: PowerSnapshot?
    let summary: TelemetryHistorySummary
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                Label("Power & History", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(power?.isPluggedIn == true ? .green : .primary)
                Spacer()
                Text(summaryHeaderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 104 : 118), spacing: compact ? 8 : 10)], spacing: compact ? 8 : 10) {
                if let power {
                    PowerMetric(label: "Battery", value: batteryPercentText(for: power), systemImage: "battery.75")
                    if let adapter = power.adapter, adapter.powerWatts >= 0.5 {
                        PowerMetric(label: "Adapter", value: adapterValue(adapter), systemImage: "powerplug")
                    }
                    if let health = power.healthPercent {
                        PowerMetric(label: "Health", value: "\(health)%", systemImage: "heart")
                    }
                }
                if summary.sampleCount > 0, let fanRPMText = summary.latestFanRPMText {
                    PowerMetric(label: summary.latestFanRPMLabel, value: fanRPMText, systemImage: "fan")
                }
                if let batteryPowerLabel = summary.latestBatteryPowerLabel,
                   let batteryPowerText = summary.latestBatteryPowerText,
                   let watts = summary.latestBatteryPowerWatts {
                    PowerMetric(label: batteryPowerLabel, value: batteryPowerText, systemImage: watts < 0 ? "arrow.up.circle" : "arrow.down.circle")
                }
                if summary.sampleCount > 0 {
                    PowerMetric(label: "Thermal", value: summary.latestThermalPressureText, systemImage: "speedometer")
                }
            }

            if let power,
               let warning = PowerInsights(snapshot: power).chargerWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if summary.sampleCount > 1 {
                TelemetryHistoryChart(summary: summary, compact: compact)
            } else {
                Text("History appears after the first successful poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let power {
                PowerDetailDisclosure(snapshot: power, compact: compact)
            }
        }
        .padding(compact ? 10 : 12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryHeaderText: String {
        var parts: [String] = []
        if let power {
            parts.append(PowerDisplayFormatter.panelHeadline(for: power))
        }
        if let sampleWindowText = summary.sampleWindowText {
            parts.append("\(summary.sampleCountText) · last \(sampleWindowText)")
        } else {
            parts.append(summary.sampleCountText)
        }
        return parts.joined(separator: " · ")
    }

    private func batteryPercentText(for snapshot: PowerSnapshot) -> String {
        snapshot.percent.map { "\($0)%" } ?? "Unknown"
    }

    private func adapterValue(_ adapter: PowerAdapter) -> String {
        if let rated = adapter.ratedWatts { return "\(rated) W" }
        return PowerDisplayFormatter.watts(adapter.powerWatts)
    }
}

private struct PowerDetailDisclosure: View {
    let snapshot: PowerSnapshot
    let compact: Bool

    private var insights: PowerInsights { PowerInsights(snapshot: snapshot) }

    var body: some View {
        DisclosureGroup("Power details") {
            VStack(alignment: .leading, spacing: 6) {
                if let batteryLine {
                    Text(batteryLine)
                        .lineLimit(compact ? 1 : 2)
                }
                if let adapterLine {
                    Text(adapterLine)
                        .lineLimit(compact ? 1 : 2)
                        .truncationMode(.middle)
                }
                if !compact, let profilesLine {
                    Text(profilesLine)
                }
                if let eta = insights.estimatedBatteryText {
                    Text("Estimate: \(eta)")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, compact ? 0 : 2)
    }

    private var batteryLine: String? {
        var parts: [String] = []
        if let voltage = snapshot.batteryVoltageVolts {
            parts.append(PowerDisplayFormatter.volts(voltage))
        }
        if let current = snapshot.batteryCurrentAmps {
            let sign = current >= 0 ? "+" : "−"
            parts.append("\(sign)\(PowerDisplayFormatter.amps(abs(current)))")
        }
        if let temperature = snapshot.temperatureCelsius {
            parts.append(PowerDisplayFormatter.temperature(temperature))
        }
        if let cycles = snapshot.cycleCount {
            parts.append("\(cycles) cycles")
        }
        return parts.isEmpty ? nil : "Battery: " + parts.joined(separator: " · ")
    }

    private var adapterLine: String? {
        guard let adapter = snapshot.adapter,
              let description = PowerDisplayFormatter.adapterDescription(for: adapter)
        else { return nil }
        return "Adapter: " + description
    }

    private var profilesLine: String? {
        guard !snapshot.powerDeliveryProfiles.isEmpty else { return nil }
        let profiles = snapshot.powerDeliveryProfiles.map { profile in
            "\(PowerDisplayFormatter.volts(profile.voltageVolts))×\(PowerDisplayFormatter.amps(profile.currentAmps))"
        }
        return "USB-C PD: " + profiles.joined(separator: ", ")
    }
}

private struct TelemetryHistoryChart: View {
    let summary: TelemetryHistorySummary
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if summary.temperatureValues.count > 1 {
                HistorySparkline(
                    title: "Temp",
                    values: summary.temperatureValues,
                    color: .orange,
                    startValueText: summary.temperatureValues.first.map(TelemetryHistorySummary.temperatureText),
                    currentValueText: summary.latestTemperatureText,
                    rangeText: summary.temperatureRangeText,
                    changeText: summary.temperatureChangeText,
                    compact: compact
                )
            }
            if summary.fanRPMValues.count > 1 {
                HistorySparkline(
                    title: summary.fanRPMSparklineTitle,
                    values: summary.fanRPMValues,
                    color: .blue,
                    startValueText: summary.fanRPMValues.first.map(TelemetryHistorySummary.fanRPMText),
                    currentValueText: summary.latestFanRPMText,
                    rangeText: summary.fanRPMRangeText,
                    changeText: summary.fanRPMChangeText,
                    compact: compact
                )
            }
            if summary.batteryPowerValues.count > 1 {
                HistorySparkline(
                    title: "Power",
                    values: summary.batteryPowerValues,
                    color: .green,
                    startValueText: nil,
                    currentValueText: nil,
                    rangeText: summary.batteryPowerRangeText,
                    changeText: summary.batteryPowerChangeText,
                    compact: compact
                )
            }
            ThermalPressureTrail(
                pressures: summary.thermalPressureSamples,
                summaryText: summary.thermalPressureSummaryText,
                compact: compact
            )
        }
        .padding(.top, compact ? 2 : 4)
    }
}

private struct HistorySparkline: View {
    let title: String
    let values: [Double]
    let color: Color
    let startValueText: String?
    let currentValueText: String?
    let rangeText: String
    let changeText: String?
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 34 : 42, alignment: .leading)
            SparklinePath(
                values: values,
                color: color,
                startValueLabelText: startValueText,
                valueLabelText: currentValueText
            )
                .frame(height: compact ? 20 : 24)
            VStack(alignment: .trailing, spacing: 1) {
                Text(rangeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let changeText {
                    Text(changeText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: compact ? 86 : 104, alignment: .trailing)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let valueText: String
        if let startValueText, let currentValueText, startValueText != currentValueText {
            valueText = ", from \(startValueText) to \(currentValueText)"
        } else if let currentValueText {
            valueText = ", current \(currentValueText)"
        } else {
            valueText = ""
        }
        if let changeText {
            return "\(title) history \(rangeText)\(valueText), change \(changeText)"
        }
        return "\(title) history \(rangeText)\(valueText)"
    }
}

private struct SparklinePath: View {
    let values: [Double]
    let color: Color
    let startValueLabelText: String?
    let valueLabelText: String?

    var body: some View {
        GeometryReader { geometry in
            let plottedValues = smoothedValues(values)
            let points = points(for: plottedValues, in: geometry.size)
            ZStack {
                Path { path in
                    addSmoothedLine(to: &path, points: points)
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                if let startValueLabelText, let startPoint = points.first {
                    SparklineValueBadge(text: startValueLabelText, color: color)
                        .position(startLabelPosition(near: startPoint, in: geometry.size))
                }

                if let valueLabelText, let endpoint = points.last {
                    SparklineValueBadge(text: valueLabelText, color: color)
                        .position(labelPosition(near: endpoint, in: geometry.size))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(for plottedValues: [Double], in size: CGSize) -> [CGPoint] {
        guard plottedValues.count > 1,
              let minValue = plottedValues.min(),
              let maxValue = plottedValues.max() else { return [] }

        let isFlat = abs(maxValue - minValue) < 0.0001
        let valueRange = max(maxValue - minValue, 0.0001)
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let xStep = width / CGFloat(plottedValues.count - 1)

        return plottedValues.enumerated().map { index, value in
            let normalized = isFlat ? 0.5 : (value - minValue) / valueRange
            return CGPoint(
                x: CGFloat(index) * xStep,
                y: height - (CGFloat(normalized) * height)
            )
        }
    }

    private func addSmoothedLine(to path: inout Path, points: [CGPoint]) {
        var previousPoint: CGPoint?
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else if let previousPoint {
                let midPoint = CGPoint(
                    x: (previousPoint.x + point.x) / 2,
                    y: (previousPoint.y + point.y) / 2
                )
                path.addQuadCurve(to: midPoint, control: previousPoint)
                if index == points.count - 1 {
                    path.addQuadCurve(to: point, control: point)
                }
            } else {
                path.addLine(to: point)
            }
            previousPoint = point
        }
    }

    private func startLabelPosition(near point: CGPoint, in size: CGSize) -> CGPoint {
        let horizontalInset: CGFloat = 44
        let verticalInset: CGFloat = 9
        let x = min(max(point.x + 40, horizontalInset), max(size.width - horizontalInset, horizontalInset))
        let y = min(max(point.y - 10, verticalInset), max(size.height - verticalInset, verticalInset))
        return CGPoint(x: x, y: y)
    }

    private func labelPosition(near point: CGPoint, in size: CGSize) -> CGPoint {
        let horizontalInset: CGFloat = 44
        let verticalInset: CGFloat = 9
        let x = min(max(point.x - 40, horizontalInset), max(size.width - horizontalInset, horizontalInset))
        let y = min(max(point.y - 10, verticalInset), max(size.height - verticalInset, verticalInset))
        return CGPoint(x: x, y: y)
    }

    private func smoothedValues(_ rawValues: [Double]) -> [Double] {
        guard rawValues.count > 4 else { return rawValues }
        return rawValues.indices.map { index in
            let lowerBound = max(rawValues.startIndex, index - 2)
            let upperBound = min(rawValues.index(before: rawValues.endIndex), index + 2)
            let window = rawValues[lowerBound...upperBound]
            return window.reduce(0, +) / Double(window.count)
        }
    }
}

private struct SparklineValueBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.75))
            .allowsHitTesting(false)
    }
}

private struct ThermalPressureTrail: View {
    let pressures: [ThermalPressure]
    let summaryText: String
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("Thermal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 34 : 42, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(Array(pressures.enumerated()), id: \.offset) { pair in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: pair.element))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: compact ? 6 : 8)
            Text(summaryText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: compact ? 86 : 104, alignment: .trailing)
        }
        .accessibilityLabel("Thermal pressure history \(summaryText)")
    }

    private func color(for pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal:
            return .green.opacity(0.7)
        case .fair:
            return .yellow.opacity(0.8)
        case .serious:
            return .orange.opacity(0.9)
        case .critical:
            return .red
        case .unknown:
            return .secondary.opacity(0.4)
        }
    }
}

private struct PowerMetric: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FanRow: View {
    let fan: Fan
    let targetRPM: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fan.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(fan.currentRPM) RPM")
                    .monospacedDigit()
            }
            Text(FanDisplayFormatter.subtitle(for: fan))
                .font(.caption)
                .foregroundStyle(fan.hardwareMode == .forced ? .orange : .secondary)
            ProgressView(value: Double(fan.percentage), total: 100)
            HStack {
                Text("\(fan.minimumRPM) min")
                Spacer()
                if let targetRPM {
                    Text("Target \(targetRPM) RPM")
                }
                Spacer()
                Text("\(fan.maximumRPM) max")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SensorRow: View {
    let sensor: TemperatureSensor
    let selected: Bool
    let compact: Bool

    var body: some View {
        HStack {
            Image(systemName: selected ? "checkmark.circle.fill" : "thermometer.medium")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(sensor.name)
                Text(sensor.source.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(sensor.celsius, specifier: "%.1f") C")
                .monospacedDigit()
                .font(compact ? .subheadline.weight(.semibold) : .headline)
        }
        .padding(compact ? 8 : 10)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompactFanOverrideEditor: View {
    let fan: Fan
    let startRPM: Int
    let midRPM: Int
    let maxRPM: Int
    let setStartRPM: (Int) -> Void
    let setMidRPM: (Int) -> Void
    let setMaxRPM: (Int) -> Void

    var body: some View {
        let startBinding = Binding<Int>(
            get: { startRPM },
            set: { newValue in setStartRPM(newValue) }
        )
        let midBinding = Binding<Int>(
            get: { midRPM },
            set: { newValue in setMidRPM(newValue) }
        )
        let maxBinding = Binding<Int>(
            get: { maxRPM },
            set: { newValue in setMaxRPM(newValue) }
        )

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fan.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(fan.minimumRPM)-\(fan.maximumRPM) RPM")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 6) {
                Stepper(value: startBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50) {
                    fanOverrideValueLabel("Start", rpm: startRPM)
                }
                Stepper(value: midBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50) {
                    fanOverrideValueLabel("Ramp", rpm: midRPM)
                }
                Stepper(value: maxBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50) {
                    fanOverrideValueLabel("High", rpm: maxRPM)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func fanOverrideValueLabel(_ label: String, rpm: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
            Text("\(rpm)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct CurvePointEditor: View {
    let title: String
    @Binding var temp: Double
    @Binding var rpm: Double
    let rpmRange: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(temp.rounded())) C -> \(Int(rpm.rounded())) RPM")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Slider(value: $temp, in: 35...105, step: 1)
            }
            HStack {
                Text("RPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Slider(value: $rpm, in: rpmRange, step: 50)
            }
        }
    }
}
