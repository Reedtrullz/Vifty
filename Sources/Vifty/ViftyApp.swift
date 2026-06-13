import SwiftUI

@main
struct ViftyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarExtraLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Vifty", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
    }
}

struct MenuBarExtraLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.menuBarLabelUsesFanIcon {
            Image(systemName: "fan")
                .accessibilityLabel(model.menuBarLabelText)
        } else {
            Text(model.menuBarLabelText)
                .monospacedDigit()
        }
    }
}
