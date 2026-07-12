import SwiftUI

struct ViftySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            SettingsGeneralView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            SettingsMenuBarView(model: model)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            SettingsNotificationsView(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
            SettingsAgentWorkflowView(model: model)
                .tabItem { Label("Agent Workflows", systemImage: "terminal") }
        }
        .frame(minWidth: 620, minHeight: 420)
        .scenePadding()
    }
}
