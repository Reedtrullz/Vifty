import SwiftUI

struct ControlSessionCard: View {
    let presentation: ControlSessionPresentation
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let expiryText = presentation.expiryText {
                    Text(expiryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if presentation.primaryAction != .none {
                    Button(action: onPrimaryAction) {
                        Label(presentation.primaryActionTitle, systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(presentation.primaryActionDisabled)
                    .help(presentation.primaryActionHelp)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accentColor.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var accentColor: Color {
        switch presentation.state {
        case .ready:
            .green
        case .attention, .blocked:
            .orange
        case .agentCooling:
            .blue
        case .checking, .manual:
            .accentColor
        }
    }

    private var systemImage: String {
        switch presentation.state {
        case .checking:
            "hourglass"
        case .ready:
            "checkmark.shield"
        case .attention, .blocked:
            "exclamationmark.shield"
        case .manual:
            "fan"
        case .agentCooling:
            "cpu"
        }
    }
}
