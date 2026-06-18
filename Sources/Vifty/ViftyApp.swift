import SwiftUI

@main
struct ViftyApp: App {
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    @MainActor
    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarExtraLabel(model: model)
                .onAppear {
                    model.start()
                }
                .task(id: model.menuBarDisplayMode) {
                    await model.primeMenuBarStatusItemTelemetry()
                }
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
