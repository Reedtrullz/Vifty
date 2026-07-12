import SwiftUI

struct SettingsNotificationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCategorySection(title: "Notifications", systemImage: "bell") {
            Toggle("Helper failure", isOn: $model.notificationSettings.helperFailure)
            Toggle("High thermal pressure", isOn: $model.notificationSettings.elevatedThermalPressure)
            Toggle("Auto restore failure", isOn: $model.notificationSettings.autoRestoreFailure)
            Toggle("Plugged-in battery drain", isOn: $model.notificationSettings.pluggedInBatteryDrain)
            Toggle("Agent cooling attention", isOn: $model.notificationSettings.agentCoolingAttention)
        }
    }
}
