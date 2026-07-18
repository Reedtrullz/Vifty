import SwiftUI

enum ViftySettingsTabLayout: Equatable {
    case singleRow
    case twoRows

    static func resolve(textScale: ViftyTextScale) -> ViftySettingsTabLayout {
        textScale == .accessibility ? .twoRows : .singleRow
    }

    var columnCount: Int {
        switch self {
        case .singleRow: 4
        case .twoRows: 2
        }
    }
}

enum ViftySettingsTabWidthAllocation {
    static func resolve(
        idealWidths: [CGFloat],
        availableWidth: CGFloat,
        spacing: CGFloat,
        arrangement: ViftySettingsTabLayout
    ) -> [CGFloat] {
        guard !idealWidths.isEmpty else { return [] }

        let safeAvailableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let safeSpacing = spacing.isFinite ? max(0, spacing) : 0

        switch arrangement {
        case .singleRow:
            let widths = idealWidths.map { width in
                width.isFinite ? max(0, width) : 0
            }
            let contentWidth = max(
                0,
                safeAvailableWidth - safeSpacing * CGFloat(max(0, widths.count - 1))
            )
            let idealTotal = widths.reduce(0, +)

            guard idealTotal > 0 else {
                return Array(
                    repeating: contentWidth / CGFloat(widths.count),
                    count: widths.count
                )
            }

            if idealTotal <= contentWidth {
                let remainingWidth = contentWidth - idealTotal
                let additionalWidth = remainingWidth / CGFloat(widths.count)
                return widths.map { $0 + additionalWidth }
            }

            let scale = contentWidth / idealTotal
            return widths.map { $0 * scale }

        case .twoRows:
            let columnCount = min(arrangement.columnCount, idealWidths.count)
            let contentWidth = max(
                0,
                safeAvailableWidth - safeSpacing * CGFloat(max(0, columnCount - 1))
            )
            return Array(
                repeating: contentWidth / CGFloat(columnCount),
                count: columnCount
            )
        }
    }
}

private struct ViftySettingsTabStripLayout: Layout {
    let arrangement: ViftySettingsTabLayout
    var spacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? naturalWidth(subviews)
        let measurements = measurements(for: subviews, width: width)
        return CGSize(width: width, height: measurements.rowHeights.reduce(0, +)
            + spacing * CGFloat(max(0, measurements.rowHeights.count - 1)))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let measurements = measurements(for: subviews, width: bounds.width)
        var rowOrigins: [CGFloat] = []
        var nextY = bounds.minY
        for height in measurements.rowHeights {
            rowOrigins.append(nextY)
            nextY += height + spacing
        }

        var columnOrigins: [CGFloat] = []
        var nextX = bounds.minX
        for width in measurements.columnWidths {
            columnOrigins.append(nextX)
            nextX += width + spacing
        }

        for (index, subview) in subviews.enumerated() {
            let row = index / arrangement.columnCount
            let column = index % arrangement.columnCount
            subview.place(
                at: CGPoint(
                    x: columnOrigins[column],
                    y: rowOrigins[row]
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: measurements.columnWidths[column],
                    height: measurements.rowHeights[row]
                )
            )
        }
    }

    private func naturalWidth(_ subviews: Subviews) -> CGFloat {
        let widths = idealWidths(for: subviews)
        switch arrangement {
        case .singleRow:
            return widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        case .twoRows:
            let widestColumn = widths.max() ?? 0
            return widestColumn * CGFloat(arrangement.columnCount)
                + spacing * CGFloat(arrangement.columnCount - 1)
        }
    }

    private func measurements(
        for subviews: Subviews,
        width: CGFloat
    ) -> (columnWidths: [CGFloat], rowHeights: [CGFloat]) {
        let columns = arrangement.columnCount
        let columnWidths = ViftySettingsTabWidthAllocation.resolve(
            idealWidths: idealWidths(for: subviews),
            availableWidth: width,
            spacing: spacing,
            arrangement: arrangement
        )
        let rowCount = Int(ceil(Double(subviews.count) / Double(columns)))
        var rowHeights = Array(repeating: CGFloat.zero, count: rowCount)
        for (index, subview) in subviews.enumerated() {
            let column = index % columns
            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidths[column], height: nil)
            )
            rowHeights[index / columns] = max(rowHeights[index / columns], size.height)
        }
        return (columnWidths, rowHeights)
    }

    private func idealWidths(for subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }
}

enum ViftySettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case menuBar
    case notifications
    case agentWorkflows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .notifications: "Notifications"
        case .agentWorkflows: "Agent Workflows"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell"
        case .agentWorkflows: "terminal"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .general: ViftyAccessibilityIdentifier.settingsTabGeneral
        case .menuBar: ViftyAccessibilityIdentifier.settingsTabMenuBar
        case .notifications: ViftyAccessibilityIdentifier.settingsTabNotifications
        case .agentWorkflows: ViftyAccessibilityIdentifier.settingsTabAgentWorkflows
        }
    }
}

struct ViftySettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var softwareUpdates: SoftwareUpdateController
    @Environment(\.viftyTextScale) private var textScale
    @State private var selectedTab: ViftySettingsTab

    init(
        model: AppModel,
        softwareUpdates: SoftwareUpdateController,
        initialTab: ViftySettingsTab = .general
    ) {
        self.model = model
        self.softwareUpdates = softwareUpdates
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsSectionPicker

            Divider()

            selectedPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.settings)
        .scenePadding()
        .frame(width: 600, height: 420)
    }

    private var settingsSectionPicker: some View {
        ViftySettingsTabStripLayout(arrangement: settingsTabLayout) {
            ForEach(ViftySettingsTab.allCases) { tab in
                settingsSectionButton(tab)
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
        .accessibilityIdentifier(ViftyAccessibilityIdentifier.settingsTabs)
    }

    private var settingsTabLayout: ViftySettingsTabLayout {
        ViftySettingsTabLayout.resolve(textScale: textScale)
    }

    private func settingsSectionButton(_ tab: ViftySettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .viftyFont(.subheadline, weight: .semibold)
                .lineLimit(settingsTabLayout == .singleRow ? 1 : 2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
        }
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
        .help("Show \(tab.title) settings")
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedTab {
        case .general:
            SettingsGeneralView(model: model, softwareUpdates: softwareUpdates)
        case .menuBar:
            SettingsMenuBarView(model: model)
        case .notifications:
            SettingsNotificationsView(model: model)
        case .agentWorkflows:
            SettingsAgentWorkflowView(model: model)
        }
    }
}
