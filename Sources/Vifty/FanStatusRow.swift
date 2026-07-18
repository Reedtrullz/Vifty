import SwiftUI

struct FanStatusRow: View {
    let fanID: Int
    let fanName: String
    let presentation: FanStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fanName)
                    .viftyFont(.subheadline, weight: .semibold)
                Spacer()
                Text(presentation.currentText)
                    .monospacedDigit()
            }

            Text(presentation.ownershipText)
                .viftyFont(.caption)
                .foregroundStyle(presentation.needsAttention ? .orange : .secondary)

            rpmIndicator

            HStack {
                if let targetText = presentation.targetText {
                    Text(targetText)
                }
                Spacer()
                if let deltaText = presentation.deltaText {
                    Text(deltaText)
                        .foregroundStyle(presentation.needsAttention ? .orange : .secondary)
                }
            }
            .viftyFont(.caption)
            .monospacedDigit()

            if let draft = FanDraftTargetAccessibilityPresentation.resolve(
                fanID: fanID,
                fanName: fanName,
                draftTargetText: presentation.draftTargetText
            ) {
                Text(draft.value)
                    .viftyFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .accessibilityLabel(draft.label)
                    .accessibilityValue(draft.value)
                    .accessibilityIdentifier(draft.identifier)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(fanName)
    }

    private var rpmIndicator: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(presentation.needsAttention ? Color.orange : Color.accentColor)
                    .frame(width: geometry.size.width * presentation.currentFraction)
                if let targetFraction = presentation.targetFraction {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 12)
                        .offset(x: max(0, geometry.size.width * targetFraction - 1))
                }
                if let draftTargetFraction = presentation.draftTargetFraction {
                    Path { path in
                        let x = max(0, geometry.size.width * draftTargetFraction)
                        path.move(to: CGPoint(x: x, y: -2))
                        path.addLine(to: CGPoint(x: x, y: 10))
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
