import SwiftUI

struct SettingsPane<Content: View>: View {
    @Environment(\.viftyTextScale) private var textScale
    private let accessibilityPane: ViftySettingsAccessibilityPane
    private let content: Content

    init(
        accessibilityPane: ViftySettingsAccessibilityPane,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityPane = accessibilityPane
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if let scopeIdentifier = accessibilityPane.scopeIdentifier,
           let scopeLabel = accessibilityPane.scopeLabel {
            VStack(spacing: 0) {
                Text(scopeLabel)
                    .viftyFont(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .accessibilityHeading(.h2)

                scrollArea
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(scopeLabel)
            .accessibilityIdentifier(scopeIdentifier)
        } else {
            scrollArea
        }
    }

    private var scrollArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                Form {
                    content
                }
                .formStyle(.grouped)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if textScale == .accessibility {
                    Spacer(minLength: 1)
                }

                ViftyAccessibilityScrollEndAnchor(
                    identifier: accessibilityPane.endAnchorIdentifier
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: textScale == .accessibility ? 560 : nil,
                alignment: .topLeading
            )
        }
        .scrollIndicators(.visible)
        .accessibilityIdentifier(accessibilityPane.scrollIdentifier)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsMenuBarFieldTogglePresentation: Equatable {
    static let minimumSelectionHelp = "At least one custom menu bar field is required."

    let isSelected: Bool
    let isToggleEnabled: Bool
    let helpText: String

    static func resolve(
        field: MenuBarField,
        selectedFields: [MenuBarField]
    ) -> SettingsMenuBarFieldTogglePresentation {
        let selectedFields = MenuBarField.orderedUnique(selectedFields)
        let isSelected = selectedFields.contains(field)
        let isLastSelectedField = isSelected && selectedFields.count == 1

        return SettingsMenuBarFieldTogglePresentation(
            isSelected: isSelected,
            isToggleEnabled: !isLastSelectedField,
            helpText: isLastSelectedField
                ? minimumSelectionHelp
                : "Show \(field.label) in the custom menu bar display."
        )
    }
}
