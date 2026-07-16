import SwiftUI
import ViftyCore

struct SensorListView: View {
    let sensors: [TemperatureSensor]
    let selectedSensorID: String?
    let onSelectSensor: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 6) {
            ForEach(sensors) { sensor in
                let accessibility = SensorAccessibilityPresentation.resolve(
                    sensor: sensor,
                    selectedSensorID: selectedSensorID
                )
                Button {
                    onSelectSensor(sensor.id)
                } label: {
                    SensorRowContent(sensor: sensor, selected: sensor.id == selectedSensorID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibility.label)
                .accessibilityValue(accessibility.value)
                .accessibilityAddTraits(accessibility.isSelected ? [.isSelected] : [])
                .accessibilityIdentifier(accessibility.identifier)
                .help("Use \(sensor.name) for the temperature curve.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.sensorList)
    }
}

private struct SensorRowContent: View {
    let sensor: TemperatureSensor
    let selected: Bool

    var body: some View {
        HStack {
            Image(systemName: selected ? "checkmark.circle.fill" : "thermometer.medium")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(sensor.name)
                Text(sensor.source.rawValue)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TemperatureDisplayFormatter.decimal(sensor.celsius))
                .viftyFont(.subheadline, weight: .semibold)
                .monospacedDigit()
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1))
    }
}
