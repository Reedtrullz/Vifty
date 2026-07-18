import SwiftUI

struct PerFanCurveOverrideEditor: View {
    let presentation: PerFanCurveOverridePresentation
    let dispatcher: FanControlPanelActionDispatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(presentation.name)
                    .viftyFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(presentation.minimumRPM)-\(presentation.maximumRPM) RPM")
                    .viftyFont(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 6) {
                pointStepper(.start, label: "Start", rpm: presentation.startRPM)
                pointStepper(.ramp, label: "Ramp", rpm: presentation.rampRPM)
                pointStepper(.high, label: "High", rpm: presentation.highRPM)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func pointStepper(
        _ point: FanCurveControlPoint,
        label: String,
        rpm: Int
    ) -> some View {
        Stepper(
            value: Binding(
                get: { rpm },
                set: { value in
                    dispatcher.fanOverrideRPMChanged(
                        fanID: presentation.fanID,
                        point: point,
                        rpm: value
                    )
                }
            ),
            in: presentation.minimumRPM...presentation.maximumRPM,
            step: 50
        ) {
            HStack(spacing: 4) {
                Text(label)
                    .viftyFont(.caption2, weight: .semibold)
                Text("\(rpm)")
                    .viftyFont(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(presentation.name) \(label) RPM")
        .accessibilityValue("\(rpm) RPM")
        .accessibilityHint("Adjusts the \(label.lowercased()) target for \(presentation.name).")
    }
}
