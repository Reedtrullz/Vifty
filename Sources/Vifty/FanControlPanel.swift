import SwiftUI

struct FanControlPanel: View {
    let presentation: FanControlPanelPresentation
    let dispatcher: FanControlPanelActionDispatcher
    let onHelperAction: () -> Void
    let onCopyDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Fan Control", systemImage: "fan")
                .viftyFont(.headline)

            switch presentation.selectedMode {
            case .curve:
                TemperatureCurveEditor(
                    presentation: presentation.temperatureCurveEditor,
                    dispatcher: dispatcher
                )
                Divider()
            case .fixed:
                FixedRPMEditor(
                    presentation: presentation.fixedRPMEditor,
                    dispatcher: dispatcher
                )
                Divider()
            case .auto:
                EmptyView()
            }

            FanStatusList(
                presentation: presentation.fanStatusList,
                onHelperAction: onHelperAction,
                onCopyDiagnostics: onCopyDiagnostics
            )
        }
    }
}
