import SwiftUI
import ViftyCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var daemonInstaller = DaemonInstaller()
    @State private var newProfileName = ""
    @State private var showSaveDialog = false
    @State private var selectedProfileID: UUID?
    @State private var helperRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                fanControlPane
                    .frame(minWidth: 360, maxWidth: 420, maxHeight: .infinity)
                Divider()
                sensorsPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            model.start()
        }
    }

    private var helperNeedsAttention: Bool {
        model.helperHealthNeedsAttention
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

    private var helperHealthColor: Color {
        switch model.helperHealthState {
        case .checking:
            return .secondary
        case .healthy:
            return .green
        case .error, .telemetryOnly, .unreachable, .noFanData:
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
            if let error = model.lastError {
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
            modePicker

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

            HStack(spacing: 8) {
                Image(systemName: helperHealthSystemImage)
                    .foregroundStyle(helperHealthColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan Helper")
                        .font(.caption.weight(.semibold))
                    Text(model.helperHealthSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let suggestion = model.helperRecoverySuggestion {
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if let actionDescription = helperNeedsAttention ? daemonInstaller.actionDescription : nil {
                        Text(actionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                Button(daemonInstaller.actionTitle) {
                    performHelperAction()
                }
                .controlSize(.small)
                .disabled(!helperNeedsAttention || !daemonInstaller.canInstall)
                .help(helperNeedsAttention ? daemonInstaller.actionHelp : "Fan helper is healthy")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

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
                    Button("Auto") { model.restoreAuto() }.controlSize(.small)
                }
                .padding(10)
                .background((model.agentCoolingNeedsAttention ? Color.orange : Color.blue).opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            if model.selectedMode == .curve {
                curveEditor
            } else if model.selectedMode == .fixed {
                fixedEditor
            }

            Divider()

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
                    Button {
                        performHelperAction()
                    } label: {
                        Label(daemonInstaller.actionTitle, systemImage: "lock.shield")
                            .frame(maxWidth: 260)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!daemonInstaller.canInstall)
                    .help(daemonInstaller.actionHelp)
                    Text(daemonInstaller.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }

            Spacer()
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

            if let blockedReason = model.manualFanControlBlockedReason {
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
                model.applyModeSelection()
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedMode != .auto && !model.manualFanControlAvailable)
            .help(model.selectedMode != .auto ? (model.manualFanControlBlockedReason ?? "Apply selected fan mode") : "Restore Auto")
        }
    }

    private var fixedEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fixed RPM")
                .font(.headline)
            Slider(value: $model.fixedRPM, in: model.fanRange, step: 50)
                .onChange(of: model.fixedRPM) {
                    model.applyModeSelection()
                }
            Text("\(Int(model.fixedRPM.rounded())) RPM")
                .monospacedDigit()
                .foregroundStyle(.secondary)
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

            if !model.savedProfiles.isEmpty {
                HStack {
                    Picker("Profile", selection: $selectedProfileID) {
                        Text("Unsaved").tag(Optional<UUID>.none)
                        ForEach(model.savedProfiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .onChange(of: selectedProfileID) { _, newID in
                        guard let id = newID,
                              let profile = model.savedProfiles.first(where: { $0.id == id }) else { return }
                        model.loadProfile(profile)
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
                    }
                }
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

            CurvePointEditor(title: "Start", temp: $model.curveStartTemp, rpm: $model.curveStartRPM, rpmRange: model.fanRange)
            CurvePointEditor(title: "Ramp", temp: $model.curveMidTemp, rpm: $model.curveMidRPM, rpmRange: model.fanRange)
            CurvePointEditor(title: "High", temp: $model.curveMaxTemp, rpm: $model.curveMaxRPM, rpmRange: model.fanRange)

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fan \(fan.id): \(fan.name)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            if let override = model.fanOverride(for: fan.id) {
                                HStack {
                                    Text("Start")
                                        .font(.caption)
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { Double(model.fanOverride(for: fan.id)?.startRPM ?? override.startRPM) },
                                            set: { model.setOverrideStartRPM(Int($0.rounded()), for: fan) }
                                        ),
                                        in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                                        step: 50
                                    )
                                    .onChange(of: model.fanOverride(for: fan.id)?.startRPM) { model.applyCurveOverrides() }
                                    Text("\(model.fanOverride(for: fan.id)?.startRPM ?? override.startRPM)")
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 50)
                                }
                                HStack {
                                    Text("Ramp")
                                        .font(.caption)
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { Double(model.fanOverride(for: fan.id)?.midRPM ?? override.midRPM) },
                                            set: { model.setOverrideMidRPM(Int($0.rounded()), for: fan) }
                                        ),
                                        in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                                        step: 50
                                    )
                                    .onChange(of: model.fanOverride(for: fan.id)?.midRPM) { model.applyCurveOverrides() }
                                    Text("\(model.fanOverride(for: fan.id)?.midRPM ?? override.midRPM)")
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 50)
                                }
                                HStack {
                                    Text("High")
                                        .font(.caption)
                                        .frame(width: 40)
                                    Slider(
                                        value: Binding(
                                            get: { Double(model.fanOverride(for: fan.id)?.maxRPM ?? override.maxRPM) },
                                            set: { model.setOverrideMaxRPM(Int($0.rounded()), for: fan) }
                                        ),
                                        in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                                        step: 50
                                    )
                                    .onChange(of: model.fanOverride(for: fan.id)?.maxRPM) { model.applyCurveOverrides() }
                                    Text("\(model.fanOverride(for: fan.id)?.maxRPM ?? override.maxRPM)")
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 50)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        model.ensureFanOverrides(for: fans)
                    }
                }
            }

            if let sensor = model.selectedSensor {
                Text("Live: \(sensor.celsius, specifier: "%.1f") C from \(sensor.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var sensorsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let power = model.powerSnapshot {
                PowerPanel(snapshot: power)
            }

            HistoryPanel(history: model.telemetryHistory)

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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sensors) { sensor in
                            SensorRow(sensor: sensor, selected: sensor.id == model.selectedSensor?.id)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Temperature Sensors", systemImage: "thermometer.slash", description: Text("Vifty needs at least one temperature sensor before fan curves can run."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}

private struct PowerPanel: View {
    let snapshot: PowerSnapshot

    private var insights: PowerInsights { PowerInsights(snapshot: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Power", systemImage: snapshot.isPluggedIn ? "bolt.fill" : "battery.50")
                    .font(.headline)
                    .foregroundStyle(snapshot.isPluggedIn ? .green : .primary)
                Spacer()
                Text(PowerDisplayFormatter.summary(for: snapshot))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                PowerMetric(label: "Battery", value: batteryPercentText, systemImage: "battery.75")
                if let flow = PowerDisplayFormatter.batteryFlow(for: snapshot) {
                    PowerMetric(label: "Battery flow", value: flow.replacingOccurrences(of: "Battery ", with: ""), systemImage: snapshot.batteryIsActivelyCharging ? "arrow.down.circle" : "arrow.up.circle")
                }
                if let adapter = snapshot.adapter, adapter.powerWatts >= 0.5 {
                    PowerMetric(label: "Adapter", value: adapterValue(adapter), systemImage: "powerplug")
                }
                if let health = snapshot.healthPercent {
                    PowerMetric(label: "Health", value: "\(health)%", systemImage: "heart")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let batteryLine {
                    Text(batteryLine)
                }
                if let adapterLine {
                    Text(adapterLine)
                }
                if let profilesLine {
                    Text(profilesLine)
                }
                if let eta = insights.estimatedBatteryText {
                    Text("Estimate: \(eta)")
                }
                if let warning = insights.chargerWarning {
                    Text(warning)
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var batteryPercentText: String {
        snapshot.percent.map { "\($0)%" } ?? "Unknown"
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
        guard let adapter = snapshot.adapter else { return nil }
        var parts: [String] = []
        if let name = adapter.name { parts.append(name) }
        if let manufacturer = adapter.manufacturer { parts.append(manufacturer) }
        if let model = adapter.model { parts.append(model) }
        if let family = adapter.family { parts.append(family) }
        if let voltage = adapter.negotiatedVoltageVolts, let current = adapter.negotiatedCurrentAmps {
            parts.append("\(PowerDisplayFormatter.volts(voltage)) · \(PowerDisplayFormatter.amps(current))")
        }
        return parts.isEmpty ? nil : "Adapter: " + parts.joined(separator: " · ")
    }

    private var profilesLine: String? {
        guard !snapshot.powerDeliveryProfiles.isEmpty else { return nil }
        let profiles = snapshot.powerDeliveryProfiles.map { profile in
            "\(PowerDisplayFormatter.volts(profile.voltageVolts))×\(PowerDisplayFormatter.amps(profile.currentAmps))"
        }
        return "USB-C PD: " + profiles.joined(separator: ", ")
    }

    private func adapterValue(_ adapter: PowerAdapter) -> String {
        if let rated = adapter.ratedWatts { return "\(rated) W" }
        return PowerDisplayFormatter.watts(adapter.powerWatts)
    }
}

private struct HistoryPanel: View {
    let history: TelemetryHistory

    private var sampleCountText: String {
        history.samples.count == 1 ? "1 sample" : "\(history.samples.count) samples"
    }

    private func batteryFlowLabel(for watts: Double) -> String {
        watts < 0 ? "Battery drain" : "Battery charge"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("History", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text(sampleCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let latest = history.samples.last {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    if let temp = latest.highestTemperatureCelsius {
                        PowerMetric(label: "Latest temp", value: String(format: "%.1f C", temp), systemImage: "thermometer.medium")
                    }
                    if let rpm = latest.firstFanRPM {
                        PowerMetric(label: "Latest fan", value: "\(rpm) RPM", systemImage: "fan")
                    }
                    if let watts = latest.batteryPowerWatts {
                        PowerMetric(label: batteryFlowLabel(for: watts), value: PowerDisplayFormatter.watts(abs(watts)), systemImage: watts < 0 ? "arrow.up.circle" : "arrow.down.circle")
                    }
                    PowerMetric(label: "Thermal", value: latest.thermalPressure.displayName, systemImage: "speedometer")
                }
            } else {
                Text("History appears after the first successful poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                .font(.headline)
        }
        .padding(10)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
