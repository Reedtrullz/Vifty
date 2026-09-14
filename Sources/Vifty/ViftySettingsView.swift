import SwiftUI

enum ViftySettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case menuBar
    case notifications
    case agentWorkflows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .agentWorkflows: "Agent Workflows"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell"
        case .agentWorkflows: "terminal"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .general: ViftyAccessibilityIdentifier.settingsTabGeneral
        case .menuBar: ViftyAccessibilityIdentifier.settingsTabMenuBar
        case .notifications: ViftyAccessibilityIdentifier.settingsTabNotifications
        case .agentWorkflows: ViftyAccessibilityIdentifier.settingsTabAgentWorkflows
        }
    }
}

struct ViftySettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var softwareUpdates: SoftwareUpdateController
    @State private var selectedTab: ViftySettingsTab

    init(
        model: AppModel,
        softwareUpdates: SoftwareUpdateController,
        initialTab: ViftySettingsTab = .general
    ) {
        self.model = model
        self.softwareUpdates = softwareUpdates
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                VStack(spacing: 0) {
                    SettingsGeneralView(model: model, softwareUpdates: softwareUpdates)
                }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ViftySettingsTab.general.accessibilityIdentifier)
                    .tabItem {
                        Label(ViftySettingsTab.general.title, systemImage: ViftySettingsTab.general.systemImage)
                            .accessibilityIdentifier(ViftySettingsTab.general.accessibilityIdentifier)
                    }
                    .tag(ViftySettingsTab.general)
                VStack(spacing: 0) {
                    SettingsMenuBarView(model: model)
                }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ViftySettingsTab.menuBar.accessibilityIdentifier)
                    .tabItem {
                        Label(ViftySettingsTab.menuBar.title, systemImage: ViftySettingsTab.menuBar.systemImage)
                            .accessibilityIdentifier(ViftySettingsTab.menuBar.accessibilityIdentifier)
                    }
                    .tag(ViftySettingsTab.menuBar)
                VStack(spacing: 0) {
                    SettingsNotificationsView(model: model)
                }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ViftySettingsTab.notifications.accessibilityIdentifier)
                    .tabItem {
                        Label(ViftySettingsTab.notifications.title, systemImage: ViftySettingsTab.notifications.systemImage)
                            .accessibilityIdentifier(ViftySettingsTab.notifications.accessibilityIdentifier)
                    }
                    .tag(ViftySettingsTab.notifications)
                VStack(spacing: 0) {
                    SettingsAgentWorkflowView(model: model)
                }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(ViftySettingsTab.agentWorkflows.accessibilityIdentifier)
                    .tabItem {
                        Label(ViftySettingsTab.agentWorkflows.title, systemImage: ViftySettingsTab.agentWorkflows.systemImage)
                            .accessibilityIdentifier(ViftySettingsTab.agentWorkflows.accessibilityIdentifier)
                    }
                    .tag(ViftySettingsTab.agentWorkflows)
            }
            .accessibilityIdentifier(ViftyAccessibilityIdentifier.settingsTabs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.settings)
        .scenePadding()
        .frame(minWidth: 600, minHeight: 420)
    }
}
