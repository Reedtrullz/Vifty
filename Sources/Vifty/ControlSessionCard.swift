import SwiftUI

struct ControlSessionCard: View {
    let presentation: ControlSessionPresentation
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(accentColor)
                .viftyFont(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .viftyFont(.subheadline, weight: .semibold)
                    .accessibilityLabel(presentation.title)
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.controlSessionTitle)
                Text(presentation.summary)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(presentation.summary)
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.controlSessionSummary)
                if let detail = presentation.detail {
                    Text(detail)
                        .viftyFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let expiryText = presentation.expiryText {
                    Text(expiryText)
                        .viftyFont(.caption)
                        .foregroundStyle(.secondary)
                }
                if presentation.primaryAction != .none {
                    Button(action: onPrimaryAction) {
                        Label(presentation.primaryActionTitle, systemImage: primaryActionSystemImage)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.controlSession)
    }

    private var accentColor: Color {
        switch presentation.state {
        case .ready:
            .green
        case .attention, .blocked:
            .orange
        case .agentCooling:
            .blue
        case .checking, .draft, .manual:
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
        case .draft:
            "slider.horizontal.3"
        case .manual:
            "fan"
        case .agentCooling:
            "cpu"
        }
    }

    private var primaryActionSystemImage: String {
        switch presentation.primaryAction {
        case .none:
            "circle"
        case .apply:
            "checkmark.circle"
        case .restoreAuto:
            "arrow.counterclockwise.circle"
        case .repairHelper:
            "wrench.and.screwdriver"
        case .copyDiagnostics:
            "doc.on.doc"
        }
    }
}
