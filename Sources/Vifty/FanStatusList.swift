import SwiftUI

struct FanStatusList: View {
    let presentation: FanStatusListPresentation
    let onHelperAction: () -> Void
    let onCopyDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans")
                .viftyFont(.headline)

            if !presentation.fans.isEmpty {
                ForEach(presentation.fans) { fan in
                    FanStatusRow(
                        fanID: fan.fanID,
                        fanName: fan.fanName,
                        presentation: fan.status
                    )
                }
            } else {
                unavailableContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.fanStatus)
    }

    private var unavailableContent: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Fan Access Unavailable",
                systemImage: "fan.slash",
                description: Text(presentation.unavailableDescription)
            )
            if let helperActionTitle = presentation.helperActionTitle {
                Button(action: onHelperAction) {
                    Label(helperActionTitle, systemImage: "lock.shield")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .disabled(presentation.helperActionDisabled)
                .help(presentation.helperActionHelp ?? "Repair or approve the helper before fan writes.")
            } else {
                Button(action: onCopyDiagnostics) {
                    Label("Copy Support Evidence", systemImage: "doc.on.doc")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.bordered)
                .help(HelperDiagnosticsSupport.copyHelp)
            }
            Text(presentation.helperStatusText)
                .viftyFont(.caption)
                .foregroundStyle(.secondary)
            if presentation.helperDiagnosticsCopied {
                Text(HelperDiagnosticsSupport.copiedMessage)
                    .viftyFont(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}
