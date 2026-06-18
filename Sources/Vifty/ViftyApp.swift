import AppKit
import SwiftUI

@main
struct ViftyApp: App {
    @NSApplicationDelegateAdaptor(ViftyAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    @MainActor
    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model
        model.start()
        Task { @MainActor in
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarExtraLabel(model: model)
                .id(model.menuBarStatusItemRevision)
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
        label
            .onAppear {
                refreshMenuBarStatusItemTelemetry()
            }
            .task(id: model.menuBarDisplayMode) {
                await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
            }
    }

    @ViewBuilder
    private var label: some View {
        if model.menuBarLabelUsesFanIcon {
            Image(systemName: "fan")
                .accessibilityLabel(model.menuBarLabelText)
        } else {
            Text(model.menuBarLabelText)
                .monospacedDigit()
                .id(model.menuBarStatusItemRevision)
        }
    }

    private func refreshMenuBarStatusItemTelemetry() {
        model.start()
        Task { @MainActor in
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
        }
    }
}

@MainActor
final class ViftyAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        model.start()
        Task { @MainActor in
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
        }
    }
}
