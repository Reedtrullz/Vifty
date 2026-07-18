import SwiftUI

struct SettingsCategorySection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
        } header: {
            Label(title, systemImage: systemImage)
        }
    }
}
