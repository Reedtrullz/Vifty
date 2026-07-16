import SwiftUI

struct FixedRPMEditor: View {
    let presentation: FixedRPMEditorPresentation
    let dispatcher: FanControlPanelActionDispatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fixed RPM")
                    .viftyFont(.headline)
                Spacer()
                if presentation.showsPerFanToggle {
                    Toggle("Per-fan targets", isOn: perFanTargetsBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Set different fixed RPM targets for fans with different speed ranges")
                        .accessibilityLabel("Per-fan fixed RPM targets")
                        .accessibilityHint("Set separate fixed RPM targets for each fan.")
                }
            }

            if presentation.showsPerFanEditors {
                perFanEditors
            } else {
                sharedTargetEditor
            }
        }
        .disabled(!presentation.isEnabled)
    }

    private var perFanTargetsBinding: Binding<Bool> {
        Binding(
            get: { presentation.usesPerFanTargets },
            set: { value in dispatcher.perFanFixedRPMChanged(value) }
        )
    }

    private var perFanEditors: some View {
        ForEach(presentation.fans) { fan in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(fan.name)
                        .viftyFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(fan.targetRPM) RPM · \(fan.targetPercent)%")
                        .viftyFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(fan.sliderRPM) },
                        set: { value in
                            dispatcher.fixedFanRPMChanged(
                                fanID: fan.fanID,
                                rpm: Int(value.rounded())
                            )
                        }
                    ),
                    in: Double(fan.minimumRPM)...Double(fan.maximumRPM),
                    step: 50,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            dispatcher.fixedFanEditingEnded()
                        }
                    }
                )
                .help("\(fan.name) fixed target. Range \(fan.minimumRPM)-\(fan.maximumRPM) RPM; currently \(fan.targetPercent)% of that fan's range.")
                .accessibilityLabel("\(fan.name) fixed RPM target")
                .accessibilityValue("\(fan.targetRPM) RPM, \(fan.targetPercent)%")
                .accessibilityHint("\(fan.name) target is clamped to \(fan.minimumRPM)-\(fan.maximumRPM) RPM.")
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            dispatcher.initializeFixedFanTargets()
        }
    }

    private var sharedTargetEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(
                value: Binding(
                    get: { presentation.fixedRPM },
                    set: { value in dispatcher.fixedRPMChanged(value) }
                ),
                in: presentation.fanRange,
                step: 50,
                onEditingChanged: { isEditing in
                    guard !isEditing else { return }
                    dispatcher.fixedRPMEditingEnded()
                }
            )
            .accessibilityLabel("Fixed RPM target")
            .accessibilityValue("\(Int(presentation.fixedRPM.rounded())) RPM")
            .accessibilityHint("Sets one fixed target for every controllable fan.")
            Text("\(Int(presentation.fixedRPM.rounded())) RPM")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
