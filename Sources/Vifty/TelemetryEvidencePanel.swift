import SwiftUI
import ViftyCore

struct TelemetryEvidencePanel: View {
    let power: PowerSnapshot?
    let summary: TelemetryHistorySummary
    let sensors: [TemperatureSensor]
    let effectiveSensorID: String?
    let compact: Bool
    let onSelectSensor: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Telemetry & Evidence", systemImage: "waveform.path.ecg")
                .viftyFont(.headline)

            TelemetryOverviewPanel(
                power: power,
                summary: summary,
                compact: compact
            )

            HStack {
                Text("Temperatures")
                    .viftyFont(.headline)
                Spacer()
                if let metrics = TemperatureMetricAccessibilityPresentation.resolve(
                    sensors: sensors,
                    effectiveSensorID: effectiveSensorID
                ) {
                    HStack(spacing: 10) {
                        Text(metrics.curveSensorValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityLabel(metrics.curveSensorLabel)
                            .accessibilityValue(metrics.curveSensorValue)
                            .accessibilityIdentifier(
                                ViftyAccessibilityIdentifier.curveSensorMetric
                            )
                        Text(metrics.highestTemperatureValue)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityLabel(metrics.highestTemperatureLabel)
                            .accessibilityValue(metrics.highestTemperatureValue)
                            .accessibilityIdentifier(
                                ViftyAccessibilityIdentifier.highestTemperatureMetric
                            )
                    }
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.temperatureMetrics)
                }
            }

            if sensors.isEmpty {
                ContentUnavailableView(
                    "No Temperature Sensors",
                    systemImage: "thermometer.medium",
                    description: Text("Vifty needs at least one temperature sensor before fan curves can run.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SensorListView(
                    sensors: sensors,
                    selectedSensorID: effectiveSensorID,
                    onSelectSensor: onSelectSensor
                )
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
    @State private var metricContainerWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack {
                Label("Power & History", systemImage: "chart.xyaxis.line")
                    .viftyFont(.headline)
                    .foregroundStyle(power?.isPluggedIn == true ? .green : .primary)
                Spacer()
                Text(summaryHeaderText)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: metricColumns, spacing: metricSpacing) {
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width.rounded(.down)
            } action: { width in
                metricContainerWidth = width
            }

            if let power, let warning = PowerInsights(snapshot: power).chargerWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .viftyFont(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if summary.sampleCount > 1 {
                TelemetryHistoryChart(summary: summary, compact: compact)
            } else if let historyReadinessText = TelemetryHistorySummary.historyReadinessText(
                sampleCount: summary.sampleCount
            ) {
                Text(historyReadinessText)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
            }

            if let power {
                PowerDetailDisclosure(snapshot: power, compact: compact)
            }
        }
        .padding(compact ? 10 : 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var metricSpacing: CGFloat {
        compact ? 8 : 10
    }

    private var metricColumns: [GridItem] {
        let count = TelemetryLayoutPolicy.metricColumnCount(for: metricContainerWidth)
        return Array(
            repeating: GridItem(.flexible(minimum: compact ? 104 : 118), spacing: metricSpacing, alignment: .topLeading),
            count: count
        )
    }

    private var summaryHeaderText: String {
        var parts: [String] = []
        if let power {
            parts.append(PowerDisplayFormatter.panelHeadline(for: power))
        }
        parts.append(summary.plottedSeriesCountText)
        if let sampleWindowText = summary.sampleWindowText {
            parts.append("retained window \(sampleWindowText)")
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
                .viftyFont(.caption2, weight: .semibold)
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
                    .viftyFont(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let changeText {
                    Text(changeText)
                        .viftyFont(.caption2, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: compact ? 86 : 104, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
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
            let points = SparklineGeometry.points(
                for: values,
                width: geometry.size.width,
                height: geometry.size.height
            ).map { CGPoint(x: $0.x, y: $0.y) }
            ZStack {
                Path { path in
                    addRawLine(to: &path, points: points)
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

    private func addRawLine(to path: inout Path, points: [CGPoint]) {
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
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

}

private struct SparklineValueBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .viftyFont(.caption2, weight: .semibold)
            .monospacedDigit()
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
                .viftyFont(.caption2, weight: .semibold)
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
                .viftyFont(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: compact ? 86 : 104, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
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

private struct PowerDetailDisclosure: View {
    let snapshot: PowerSnapshot
    let compact: Bool

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
                if let eta = PowerInsights(snapshot: snapshot).estimatedBatteryText {
                    Text("Estimate: \(eta)")
                        .lineLimit(1)
                }
            }
            .viftyFont(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .viftyFont(.caption, weight: .semibold)
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
                    .viftyFont(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .viftyFont(.subheadline, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
