import SwiftUI

struct SettingsMenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCategorySection(title: "Menu Bar", systemImage: "menubar.rectangle") {
            Picker("Menu bar", selection: $model.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if model.menuBarDisplayMode == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom fields")
                        .font(.subheadline.weight(.semibold))
                    ForEach(MenuBarField.allCases) { field in
                        Toggle(field.label, isOn: menuBarCustomFieldBinding(field))
                    }
                }
            }

            if model.menuBarDisplaysCodexUsage {
                VStack(alignment: .leading, spacing: 8) {
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
}
