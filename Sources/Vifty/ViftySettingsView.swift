import SwiftUI

struct ViftySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Settings & Tools", systemImage: "gearshape")
                    .font(.title2.weight(.semibold))

                SettingsToolsPanel(model: model)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 620, minHeight: 520)
    }
}
