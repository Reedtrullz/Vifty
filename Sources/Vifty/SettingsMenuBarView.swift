import SwiftUI

struct SettingsMenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPane(accessibilityPane: .menuBar) {
            Section("Display") {
                Picker("Menu bar", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }

            if model.menuBarDisplayMode == .custom {
                Section {
                    ForEach(MenuBarField.allCases) { field in
                        let presentation = menuBarFieldPresentation(field)
                        Toggle(field.label, isOn: menuBarCustomFieldBinding(field))
                            .disabled(!presentation.isToggleEnabled)
                            .help(presentation.helpText)
                    }
                } header: {
                    Text("Custom Fields")
                } footer: {
                    Text(SettingsMenuBarFieldTogglePresentation.minimumSelectionHelp)
                }
            }

            if model.menuBarDisplaysCodexUsage {
                Section("Codex Usage") {
                    Picker("Codex display", selection: $model.codexUsageDisplayStyle) {
                        ForEach(CodexUsageDisplayStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    Picker("Codex metric", selection: $model.codexUsageMetricMode) {
                        ForEach(CodexUsageMetricMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("Reset", selection: $model.codexUsageResetMode) {
                        ForEach(CodexUsageResetMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("Refresh", selection: $model.codexUsageRefreshCadence) {
                        ForEach(CodexUsageRefreshCadence.allCases) { cadence in
                            Text(cadence.label).tag(cadence)
                        }
                    }
                }
            }
        }
    }

    private func menuBarCustomFieldBinding(_ field: MenuBarField) -> Binding<Bool> {
        Binding(
            get: { model.isMenuBarCustomFieldEnabled(field) },
            set: { model.setMenuBarCustomField(field, enabled: $0) }
        )
    }

    private func menuBarFieldPresentation(
        _ field: MenuBarField
    ) -> SettingsMenuBarFieldTogglePresentation {
        SettingsMenuBarFieldTogglePresentation.resolve(
            field: field,
            selectedFields: model.menuBarCustomFields
        )
    }
}
