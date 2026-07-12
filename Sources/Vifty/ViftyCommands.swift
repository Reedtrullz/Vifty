import SwiftUI

struct ViftyCommands: Commands {
    @ObservedObject var model: AppModel
    let openWindow: OpenWindowAction

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Open Vifty") {
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Control") {
            Button("Restore Auto") {
                model.restoreAuto()
            }
            .disabled(!model.canRequestRestoreAuto)
            .help("Return fan control to macOS Auto. No keyboard shortcut is assigned to avoid accidental activation.")
        }
    }
}
