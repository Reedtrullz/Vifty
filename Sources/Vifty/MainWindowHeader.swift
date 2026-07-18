import SwiftUI

struct MainWindowHeader: View {
    let appName: String
    let modelIdentifier: String
    let powerText: String?
    let thermalText: String
    let thermalIsElevated: Bool
    let helperActionTitle: String?
    let helperActionHelp: String?
    let helperActionDisabled: Bool
    let showsDiagnosticsOnly: Bool
    let visibleError: String?
    let statusText: String
    let onHelperAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fan")
                .viftyFont(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .viftyFont(.title3, weight: .semibold)
                Text(modelIdentifier)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let powerText {
                Label(powerText, systemImage: "battery.50")
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Label(thermalText, systemImage: "speedometer")
                .viftyFont(.caption)
                .foregroundStyle(thermalIsElevated ? .orange : .secondary)
            if let helperActionTitle {
                Button(action: onHelperAction) {
                    Label(helperActionTitle, systemImage: "lock.shield")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(helperActionDisabled)
                .help(helperActionHelp ?? "Repair or approve the helper before fan writes.")
            } else if showsDiagnosticsOnly {
                Label("Diagnostics only", systemImage: "doc.text.magnifyingglass")
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if let visibleError {
                Label(visibleError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .viftyFont(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: 340, alignment: .trailing)
            } else {
                Text(statusText)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
