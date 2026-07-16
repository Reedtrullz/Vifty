import SwiftUI

struct TemperatureCurveEditor: View {
    let presentation: TemperatureCurveEditorPresentation
    let dispatcher: FanControlPanelActionDispatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temperature Curve")
                .viftyFont(.headline)

            CurveProfileToolbar(
                profiles: presentation.profiles,
                selectedProfileID: presentation.selectedProfileID,
                editState: presentation.profileEditState,
                recoveryMessage: presentation.profileRecoveryMessage,
                dispatcher: dispatcher
            )

            if !presentation.sensors.isEmpty {
                Picker("Sensor", selection: sensorBinding) {
                    ForEach(presentation.sensors) { sensor in
                        Text(sensor.name).tag(Optional(sensor.id))
                    }
                }
            }

            if presentation.showsPerFanOverrideToggle {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Separate fan curves", isOn: perFanOverridesBinding)
                        .toggleStyle(.switch)
                        .help("Set separate Start, Ramp, and High RPM targets for each controllable fan.")
                        .accessibilityLabel("Separate fan curves")
                        .accessibilityHint(
                            "When on, each controllable fan has its own labeled curve and RPM point controls."
                        )
                        .accessibilityIdentifier(ViftyAccessibilityIdentifier.curveSeparateFans)
                    Text(
                        curveChartPresentation.statusText
                            ?? "One shared requested curve is used for all fans."
                    )
                        .viftyFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            FanCurveChartEditor(
                startTemp: temperatureBinding(for: .start),
                midTemp: temperatureBinding(for: .ramp),
                maxTemp: temperatureBinding(for: .high),
                startRPM: rpmBinding(for: .start),
                midRPM: rpmBinding(for: .ramp),
                maxRPM: rpmBinding(for: .high),
                rpmRange: presentation.editingRPMRange,
                liveTemperature: presentation.liveTemperature,
                fans: presentation.chartFans,
                fanOverrides: presentation.fanOverrides,
                usePerFanOverrides: presentation.usesPerFanOverrides
            )

            if !curveChartPresentation.effectiveSummaries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(curveChartPresentation.effectiveSummaries) { summary in
                        EffectiveFanCurveSummaryRow(summary: summary)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(ViftyAccessibilityIdentifier.curveEffectiveSummaries)
            }

            DisclosureGroup("Exact point controls") {
                VStack(alignment: .leading, spacing: 10) {
                    CurvePointEditor(
                        title: "Start",
                        temperature: temperatureBinding(for: .start),
                        rpm: rpmBinding(for: .start),
                        rpmRange: presentation.editingRPMRange
                    )
                    CurvePointEditor(
                        title: "Ramp",
                        temperature: temperatureBinding(for: .ramp),
                        rpm: rpmBinding(for: .ramp),
                        rpmRange: presentation.editingRPMRange
                    )
                    CurvePointEditor(
                        title: "High",
                        temperature: temperatureBinding(for: .high),
                        rpm: rpmBinding(for: .high),
                        rpmRange: presentation.editingRPMRange
                    )
                }
                .padding(.top, 6)
            }
            .viftyFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            // The chart's accessibility representation exposes these same six
            // draft bindings exactly once, even while this visual disclosure is closed.
            .accessibilityHidden(true)

            if presentation.showsPerFanOverrideEditors {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.overrideEditors) { override in
                        PerFanCurveOverrideEditor(
                            presentation: override,
                            dispatcher: dispatcher
                        )
                    }
                }
                .onAppear {
                    dispatcher.initializeFanOverrides()
                }
            }
        }
        .disabled(!presentation.isEnabled)
    }

    private var sensorBinding: Binding<String?> {
        Binding(
            get: { presentation.selectedSensorID },
            set: { sensorID in dispatcher.sensorSelected(sensorID) }
        )
    }

    private var perFanOverridesBinding: Binding<Bool> {
        Binding(
            get: { presentation.usesPerFanOverrides },
            set: { value in dispatcher.perFanOverridesChanged(value) }
        )
    }

    private var curveChartPresentation: FanCurveChartPresentation {
        FanCurveChartPresentation.make(
            basePoints: [
                chartValue(for: .start),
                chartValue(for: .ramp),
                chartValue(for: .high)
            ],
            fans: presentation.chartFans,
            overrides: presentation.fanOverrides,
            usePerFanOverrides: presentation.usesPerFanOverrides
        )
    }

    private func chartValue(for point: FanCurveControlPoint) -> FanCurveChartValue {
        let value = presentation.point(point)
        return FanCurveChartValue(temperature: value.temperature, rpm: value.rpm)
    }

    private func temperatureBinding(for point: FanCurveControlPoint) -> Binding<Double> {
        Binding(
            get: { presentation.point(point).temperature },
            set: { dispatcher.curveTemperatureChanged(point: point, value: $0) }
        )
    }

    private func rpmBinding(for point: FanCurveControlPoint) -> Binding<Double> {
        Binding(
            get: { presentation.point(point).rpm },
            set: { dispatcher.curveRPMChanged(point: point, value: $0) }
        )
    }
}

private struct EffectiveFanCurveSummaryRow: View {
    let summary: FanCurveEffectiveSummaryPresentation

    var body: some View {
        Text("\(summary.fanName): \(summary.accessibilityValue)")
            .viftyFont(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(summary.accessibilityLabel)
            .accessibilityValue(summary.accessibilityValue)
            .accessibilityIdentifier(
                ViftyAccessibilityIdentifier.curveEffectiveSummary(fanID: summary.fanID)
            )
    }
}

private struct CurvePointEditor: View {
    let title: String
    @Binding var temperature: Double
    @Binding var rpm: Double
    let rpmRange: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .viftyFont(.subheadline, weight: .semibold)
                Spacer()
                Text("\(TemperatureDisplayFormatter.whole(temperature)) · \(Int(rpm.rounded())) RPM")
                    .viftyFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("°C")
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Slider(value: $temperature, in: 35...105, step: 1)
                    .accessibilityLabel("\(title) temperature")
                    .accessibilityValue("\(Int(temperature.rounded())) degrees Celsius")
                    .accessibilityHint("Sets the \(title.lowercased()) curve temperature.")
            }
            HStack {
                Text("RPM")
                    .viftyFont(.caption)
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
