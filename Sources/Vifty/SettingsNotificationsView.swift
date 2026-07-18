import SwiftUI

enum SettingsNotificationAuthorizationIconTone: Equatable {
    case neutral
    case positive
    case warning
}

struct SettingsNotificationAuthorizationPresentation: Equatable {
    let statusText: String
    let systemImage: String
    let iconTone: SettingsNotificationAuthorizationIconTone
    let usesPrimaryStatusText: Bool

    static func resolve(
        _ authorization: LocalNotificationAuthorization
    ) -> SettingsNotificationAuthorizationPresentation {
        let symbol: String
        let tone: SettingsNotificationAuthorizationIconTone
        switch authorization {
        case .authorized:
            symbol = "checkmark.circle.fill"
            tone = .positive
        case .denied:
            symbol = "exclamationmark.triangle.fill"
            tone = .warning
        case .checking:
            symbol = "hourglass"
            tone = .neutral
        case .notDetermined:
            symbol = "questionmark.circle"
            tone = .neutral
        case .unavailable:
            symbol = "minus.circle"
            tone = .neutral
        }
        return SettingsNotificationAuthorizationPresentation(
            statusText: authorization.displayName,
            systemImage: symbol,
            iconTone: tone,
            usesPrimaryStatusText: true
        )
    }
}

struct SettingsNotificationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane(accessibilityPane: .notifications) {
            Section("Authorization") {
                LabeledContent("Permission") {
                    HStack(spacing: 5) {
                        Image(systemName: authorizationPresentation.systemImage)
                            .foregroundStyle(authorizationIconColor)
                            .accessibilityHidden(true)
                        Text(authorizationPresentation.statusText)
                            .foregroundStyle(.primary)
                    }
                }

                Text(authorizationDetail)
                    .viftyFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if model.notificationAuthorization == .denied {
                    Button {
                        Task { await model.openNotificationSettings() }
                    } label: {
                        Label("Open Notification Settings", systemImage: "gearshape.arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Open Notification Settings")
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationOpenSettings)
                }

                if model.notificationAuthorization == .authorized {
                    Button {
                        Task { await model.sendTestNotification() }
                    } label: {
                        Label("Send Test Notification", systemImage: "bell.badge")
                    }
                    .accessibilityLabel("Send Test Notification")
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationSendTest)
                    if let notificationTestMessage = model.notificationTestMessage {
                        Text(notificationTestMessage)
                            .viftyFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Events") {
                Toggle("Helper failure", isOn: notificationBinding(.helperFailure))
                    .accessibilityLabel("Helper failure")
                    .accessibilityAddTraits(
                        model.notificationSettings.isEnabled(.helperFailure) ? [.isSelected] : []
                    )
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationHelperFailure)
                Toggle("High thermal pressure", isOn: notificationBinding(.elevatedThermalPressure))
                    .accessibilityLabel("High thermal pressure")
                    .accessibilityAddTraits(
                        model.notificationSettings.isEnabled(.elevatedThermalPressure) ? [.isSelected] : []
                    )
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationThermalPressure)
                Toggle("Auto restore failure", isOn: notificationBinding(.autoRestoreFailure))
                    .accessibilityLabel("Auto restore failure")
                    .accessibilityAddTraits(
                        model.notificationSettings.isEnabled(.autoRestoreFailure) ? [.isSelected] : []
                    )
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationAutoRestore)
                Toggle("Plugged-in battery drain", isOn: notificationBinding(.pluggedInBatteryDrain))
                    .accessibilityLabel("Plugged-in battery drain")
                    .accessibilityAddTraits(
                        model.notificationSettings.isEnabled(.pluggedInBatteryDrain) ? [.isSelected] : []
                    )
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationBatteryDrain)
                Toggle("Agent cooling attention", isOn: notificationBinding(.agentCoolingAttention))
                    .accessibilityLabel("Agent cooling attention")
                    .accessibilityAddTraits(
                        model.notificationSettings.isEnabled(.agentCoolingAttention) ? [.isSelected] : []
                    )
                    .accessibilityIdentifier(ViftyAccessibilityIdentifier.notificationAgentCooling)
            }
        }
        .task {
            await model.refreshNotificationAuthorization()
        }
    }

    private func notificationBinding(_ kind: LocalNotificationKind) -> Binding<Bool> {
        Binding(
            get: { model.notificationSettings.isEnabled(kind) },
            set: { model.setNotificationEnabled(kind, isEnabled: $0) }
        )
    }

    private var authorizationDetail: String {
        switch model.notificationAuthorization {
        case .checking:
            "Checking the current macOS notification permission."
        case .notDetermined:
            "Turning on an event asks macOS for notification permission once. Your event choices remain selected if permission is denied."
        case .authorized:
            "Notifications are allowed. A test does not consume event cooldown history."
        case .denied:
            "Event choices remain saved, but delivery is blocked until Vifty is allowed in System Settings."
        case .unavailable:
            "Notification permission is unavailable in this environment. Event choices remain saved."
        }
    }

    private var authorizationPresentation: SettingsNotificationAuthorizationPresentation {
        SettingsNotificationAuthorizationPresentation.resolve(model.notificationAuthorization)
    }

    private var authorizationIconColor: Color {
        switch authorizationPresentation.iconTone {
        case .positive:
            .green
        case .warning:
            .orange
        case .neutral:
            .secondary
        }
    }
}
