import SwiftUI

@MainActor
enum ModeSelectionInteraction {
    static func userInitiatedBinding(
        selection: Binding<ModeSelection>,
        onUserSelection: @escaping (ModeSelection) -> Void
    ) -> Binding<ModeSelection> {
        Binding(
            get: { selection.wrappedValue },
            set: { mode in
                selection.wrappedValue = mode
                onUserSelection(mode)
            }
        )
    }
}

struct ReadinessModePanel: View {
    @Binding var selectedMode: ModeSelection
    @Binding var manualRunLimit: ManualRunLimit
    let manualFanControlAvailable: Bool
    let fanWriteBlockedWhileHotSummary: String?
    let fanWriteBlockedWhileHotRecoverySuggestion: String?
    let manualControlAttentionSummary: String?
    let manualControlAttentionRecoverySuggestion: String?
    let manualFanControlBlockedReason: String?
    let presentation: ControlSessionPresentation
    let onModeChange: (ModeSelection) -> Void
    let onManualRunLimitChange: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Safety & Mode", systemImage: "shield.lefthalf.filled")
                .viftyFont(.headline)

            if let fanWriteBlockedWhileHotSummary {
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.high")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fanWriteBlockedWhileHotSummary)
                            .viftyFont(.caption, weight: .semibold)
                        if let fanWriteBlockedWhileHotRecoverySuggestion {
                            Text(fanWriteBlockedWhileHotRecoverySuggestion)
                                .viftyFont(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            ControlSessionCard(
                presentation: presentation,
                onPrimaryAction: onPrimaryAction
            )

            Picker(selection: ModeSelectionInteraction.userInitiatedBinding(
                selection: $selectedMode,
                onUserSelection: onModeChange
            )) {
                Text("Auto").tag(ModeSelection.auto)
                Text("Fixed RPM").tag(ModeSelection.fixed)
                Text("Temperature Curve").tag(ModeSelection.curve)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Mode")

            if selectedMode != .auto {
                Picker("Manual run", selection: $manualRunLimit) {
                    ForEach(ManualRunLimit.presets) { limit in
                        Text(limit.label).tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!manualFanControlAvailable)
                .onChange(of: manualRunLimit) {
                    onManualRunLimitChange()
                }
            }

            if let manualControlAttentionSummary {
                Label(manualControlAttentionSummary, systemImage: "hourglass.badge.exclamationmark")
                    .viftyFont(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                if let manualControlAttentionRecoverySuggestion {
                    Text(manualControlAttentionRecoverySuggestion)
                        .viftyFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else if let manualFanControlBlockedReason {
                Label(manualFanControlBlockedReason, systemImage: "lock.shield")
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}
