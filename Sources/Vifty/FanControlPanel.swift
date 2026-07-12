import SwiftUI
import ViftyCore

struct FanControlPanel: View {
    let snapshot: HardwareSnapshot?
    let selectedMode: ModeSelection
    @Binding var fixedRPM: Double
    @Binding var usePerFanFixedRPM: Bool
    @Binding var curveStartTemp: Double
    @Binding var curveMidTemp: Double
    @Binding var curveMaxTemp: Double
    @Binding var curveStartRPM: Double
    @Binding var curveMidRPM: Double
    @Binding var curveMaxRPM: Double
    @Binding var selectedSensorID: String?
    let effectiveSensor: TemperatureSensor?
    let effectiveSensorID: String?
    @Binding var usePerFanOverrides: Bool
    let savedProfiles: [CurveProfile]
    @Binding var selectedCurveProfileID: CurveProfile.ID?
    let fanRange: ClosedRange<Double>
    let fanOverrides: [FanCurveOverride]
    let manualFanControlAvailable: Bool
    let helperRecoverySuggestion: String?
    let fanAccessMessage: String?
    let helperActionTitle: String?
    let helperActionHelp: String?
    let helperActionDisabled: Bool
    let helperStatusText: String
    let helperDiagnosticsCopied: Bool
    let appliedTargetRPM: (Fan) -> Int?
    let draftTargetRPMPreview: (Fan) -> Int?
    let fixedFanSliderRPM: (Fan) -> Int
    let fixedFanTargetRPM: (Fan) -> Int
    let fixedFanTargetPercent: (Fan) -> Int
    let ensureFixedFanTargets: ([Fan]) -> Void
    let setFixedFanRPM: (Int, Fan) -> Void
    let commitFixedFanTargets: () -> Void
    let loadDeveloperPreset: (DeveloperFanPreset) -> Void
    let selectCurveProfile: (CurveProfile.ID?) -> Void
    let deleteProfile: (CurveProfile) -> Void
    let ensureFanOverrides: ([Fan]) -> Void
    let fanOverride: (Int) -> FanCurveOverride?
    let setOverrideStartRPM: (Int, Fan) -> Void
    let setOverrideMidRPM: (Int, Fan) -> Void
    let setOverrideMaxRPM: (Int, Fan) -> Void
    let saveProfile: (String) -> Void
    let markDraftPending: () -> Void
    let onHelperAction: () -> Void
    let onCopyDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Fan Control", systemImage: "fan")
                .font(.headline)

            if selectedMode == .curve {
                curveEditor
                Divider()
            } else if selectedMode == .fixed {
                fixedEditor
                Divider()
            }

            fansSection
        }
    }

    private var fans: [Fan] {
        snapshot?.fans ?? []
    }

    private var fixedEditor: some View {
        let controllableFans = fans.filter(\.controllable)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fixed RPM")
                    .font(.headline)
                Spacer()
                if controllableFans.count > 1 {
                    Toggle("Per-fan targets", isOn: $usePerFanFixedRPM)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: usePerFanFixedRPM) {
                            if usePerFanFixedRPM {
                                ensureFixedFanTargets(controllableFans)
                            }
                            markDraftPending()
                        }
                        .help("Set different fixed RPM targets for fans with different speed ranges")
                        .accessibilityLabel("Per-fan fixed RPM targets")
                        .accessibilityHint("Set separate fixed RPM targets for each fan.")
                }
            }

            if usePerFanFixedRPM, controllableFans.count > 1 {
                ForEach(controllableFans) { fan in
                    let targetRPM = fixedFanTargetRPM(fan)
                    let targetPercent = fixedFanTargetPercent(fan)
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
                                get: { Double(fixedFanSliderRPM(fan)) },
                                set: { value in setFixedFanRPM(Int(value.rounded()), fan) }
                            ),
                            in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                            step: 50,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    commitFixedFanTargets()
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
                    ensureFixedFanTargets(controllableFans)
                }
            } else {
                Slider(
                    value: $fixedRPM,
                    in: fanRange,
                    step: 50,
                    onEditingChanged: { isEditing in
                        guard !isEditing else { return }
                        markDraftPending()
                    }
                )
                .accessibilityLabel("Fixed RPM target")
                .accessibilityValue("\(Int(fixedRPM.rounded())) RPM")
                .accessibilityHint("Sets one fixed target for every controllable fan.")
                Text("\(Int(fixedRPM.rounded())) RPM")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!manualFanControlAvailable)
    }

    private var curveEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Temperature Curve")
                    .font(.headline)
                Spacer()
                CurveProfileToolbar(
                    profiles: savedProfiles,
                    selectedProfileID: $selectedCurveProfileID,
                    selectProfile: selectCurveProfile,
                    loadPreset: loadDeveloperPreset,
                    saveProfile: saveProfile,
                    deleteProfile: deleteProfile
                )
            }

            if let sensors = snapshot?.temperatureSensors, !sensors.isEmpty {
                Picker("Sensor", selection: displayedSensorSelection) {
                    ForEach(sensors) { sensor in
                        Text(sensor.name).tag(Optional(sensor.id))
                    }
                }
                .onChange(of: selectedSensorID) {
                    markDraftPending()
                }
            }

            FanCurveChartEditor(
                startTemp: $curveStartTemp,
                midTemp: $curveMidTemp,
                maxTemp: $curveMaxTemp,
                startRPM: $curveStartRPM,
                midRPM: $curveMidRPM,
                maxRPM: $curveMaxRPM,
                rpmRange: fanRange,
                liveTemperature: effectiveSensor?.celsius,
                fans: fans,
                fanOverrides: fanOverrides,
                usePerFanOverrides: usePerFanOverrides
            )
            .onChange(of: curveStartTemp) { markDraftPending() }
            .onChange(of: curveMidTemp) { markDraftPending() }
            .onChange(of: curveMaxTemp) { markDraftPending() }
            .onChange(of: curveStartRPM) { markDraftPending() }
            .onChange(of: curveMidRPM) { markDraftPending() }
            .onChange(of: curveMaxRPM) { markDraftPending() }

            DisclosureGroup("Exact points") {
                VStack(alignment: .leading, spacing: 10) {
                    CurvePointEditor(title: "Start", temp: $curveStartTemp, rpm: $curveStartRPM, rpmRange: fanRange)
                    CurvePointEditor(title: "Ramp", temp: $curveMidTemp, rpm: $curveMidRPM, rpmRange: fanRange)
                    CurvePointEditor(title: "High", temp: $curveMaxTemp, rpm: $curveMaxRPM, rpmRange: fanRange)
                }
                .padding(.top, 6)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if fans.count > 1 {
                Toggle("Per-fan overrides", isOn: $usePerFanOverrides)
                    .onChange(of: usePerFanOverrides) {
                        if usePerFanOverrides {
                            ensureFanOverrides(fans)
                        }
                        markDraftPending()
                    }

                if usePerFanOverrides {
                    ForEach(fans) { fan in
                        if let override = fanOverride(fan.id) {
                            CompactFanOverrideEditor(
                                fan: fan,
                                startRPM: fanOverride(fan.id)?.startRPM ?? override.startRPM,
                                midRPM: fanOverride(fan.id)?.midRPM ?? override.midRPM,
                                maxRPM: fanOverride(fan.id)?.maxRPM ?? override.maxRPM,
                                setStartRPM: { rpm in
                                    setOverrideStartRPM(rpm, fan)
                                    markDraftPending()
                                },
                                setMidRPM: { rpm in
                                    setOverrideMidRPM(rpm, fan)
                                    markDraftPending()
                                },
                                setMaxRPM: { rpm in
                                    setOverrideMaxRPM(rpm, fan)
                                    markDraftPending()
                                }
                            )
                        }
                    }
                    .onAppear {
                        ensureFanOverrides(fans)
                    }
                }
            }
        }
        .disabled(!manualFanControlAvailable)
    }

    private var displayedSensorSelection: Binding<String?> {
        Binding(
            get: { effectiveSensorID },
            set: { selectedSensorID = $0 }
        )
    }

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans")
                .font(.headline)

            if !fans.isEmpty {
                ForEach(fans) { fan in
                    FanStatusRow(
                        fanName: fan.name,
                        presentation: FanStatusPresentation.make(
                            fan: fan,
                            appliedTargetRPM: appliedTargetRPM(fan),
                            draftTargetRPM: draftTargetRPMPreview(fan)
                        )
                    )
                }
            } else {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Fan Access Unavailable",
                        systemImage: "fan.slash",
                        description: Text(helperRecoverySuggestion ?? fanAccessMessage ?? helperStatusText)
                    )
                    if let helperActionTitle {
                        Button(action: onHelperAction) {
                            Label(helperActionTitle, systemImage: "lock.shield")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(helperActionDisabled)
                        .help(helperActionHelp ?? "Repair or approve the helper before fan writes.")
                    } else {
                        Button(action: onCopyDiagnostics) {
                            Label("Copy Support Evidence", systemImage: "doc.on.doc")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .help(HelperDiagnosticsSupport.copyHelp)
                    }
                    Text(helperStatusText)
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
        let startBinding = Binding<Int>(get: { startRPM }, set: { newValue in setStartRPM(newValue) })
        let midBinding = Binding<Int>(get: { midRPM }, set: { newValue in setMidRPM(newValue) })
        let maxBinding = Binding<Int>(get: { maxRPM }, set: { newValue in setMaxRPM(newValue) })

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
                    valueLabel("Start", rpm: startRPM)
                }
                Stepper(value: midBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50) {
                    valueLabel("Ramp", rpm: midRPM)
                }
                Stepper(value: maxBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50) {
                    valueLabel("High", rpm: maxRPM)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func valueLabel(_ label: String, rpm: Int) -> some View {
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
                Text("\(TemperatureDisplayFormatter.whole(temp)) · \(Int(rpm.rounded())) RPM")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("°C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Slider(value: $temp, in: 35...105, step: 1)
                    .accessibilityLabel("\(title) temperature")
                    .accessibilityValue("\(Int(temp.rounded())) degrees Celsius")
                    .accessibilityHint("Sets the \(title.lowercased()) curve temperature.")
            }
            HStack {
                Text("RPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Slider(value: $rpm, in: rpmRange, step: 50)
                    .accessibilityLabel("\(title) RPM")
                    .accessibilityValue("\(Int(rpm.rounded())) RPM")
                    .accessibilityHint("Sets the \(title.lowercased()) curve fan speed.")
            }
        }
    }
}
