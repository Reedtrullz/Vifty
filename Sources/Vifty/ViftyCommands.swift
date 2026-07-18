import SwiftUI

struct ViftyCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var softwareUpdates: SoftwareUpdateController
    let openWindow: OpenWindowAction
    let openSettings: OpenSettingsAction

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Open Vifty") {
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: .command)

            Button(softwareUpdates.menuActionTitle) {
                openSettings()
                Task {
                    await softwareUpdates.performPrimaryAction()
                }
            }
            .disabled(!softwareUpdates.canCheck || softwareUpdates.isChecking)
            .help(softwareUpdates.primaryActionHint)
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
