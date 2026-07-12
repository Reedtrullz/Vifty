import AppKit
import SwiftUI

struct MenuBarView: View {
    let openMainWindow: () -> Void
    let onRestoreAuto: () -> Void
    let onQuit: () -> Void

    @EnvironmentObject private var model: AppModel

    var body: some View {
        let presentation = model.menuBarPanelPresentation

        VStack(alignment: .leading, spacing: 10) {
            MenuBarStatusSummary(presentation: presentation)
            if let attentionText = presentation.attentionText {
                MenuBarAttentionRow(text: attentionText)
            }
            MenuBarFanLines(lines: presentation.fanLines)
            Divider()
            HStack {
                Button(presentation.primaryActionTitle) {
                    perform(presentation.primaryAction)
                }
                .help(presentation.primaryActionHelp)
                if presentation.showsRestoreAuto {
                    Button("Restore Auto", action: onRestoreAuto)
                        .help("Restore automatic macOS fan control.")
                }
                Button("Quit", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 320)
        .task {
            model.start()
        }
    }

    private func perform(_ action: MenuBarPanelAction) {
        switch action {
        case .openMainWindow:
            openMainWindow()
        case .restoreAuto:
            onRestoreAuto()
        case .quit:
            onQuit()
        }
    }

    private struct MenuBarStatusSummary: View {
        let presentation: MenuBarPanelPresentation

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Label(presentation.stateTitle, systemImage: "fan")
                    .font(.headline)
                Text(presentation.headline)
                    .font(.caption)
                Text(presentation.ownerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct MenuBarAttentionRow: View {
        let text: String

        var body: some View {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private struct MenuBarFanLines: View {
        let lines: [MenuBarFanLine]

        var body: some View {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.title)
                    Spacer()
                    Text(line.detail)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
