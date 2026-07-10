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
    }

    var body: some Scene {
        Window("Vifty", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 480)
                .onAppear {
                    appDelegate.openMainWindowHandler = { openWindow(id: "main") }
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            ViftySettingsView(model: model)
        }
    }
}

@MainActor
final class ViftyAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    var openMainWindowHandler: (() -> Void)? {
        didSet {
            statusItemController?.openMainWindow = { [weak self] in
                self?.openMainWindow()
            }
        }
    }

    private var statusItemController: ViftyStatusItemController?
    private let terminationCoordinator = AppTerminationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        statusItemController = ViftyStatusItemController(
            model: model,
            openMainWindow: { [weak self] in
                self?.openMainWindow()
            }
        )
        statusItemController?.openMainWindow = { [weak self] in
            self?.openMainWindow()
        }
        model.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }

        _ = terminationCoordinator.beginTermination(
            restore: {
                await model.stopAndRestore()
            },
            completion: { [weak self, weak sender] result in
                if !result.canTerminate {
                    self?.openMainWindow()
                }
                sender?.reply(toApplicationShouldTerminate: result.canTerminate)
            }
        )
        return .terminateLater
    }

    private func openMainWindow() {
        if let openMainWindowHandler {
            openMainWindowHandler()
        } else if let window = NSApplication.shared.windows.first(where: { $0.title == "Vifty" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
