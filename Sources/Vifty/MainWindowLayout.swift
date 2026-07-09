import Foundation

struct MainWindowLayout: Equatable {
    enum Mode: Equatable {
        case split
        case stacked
        case workbench
    }

    let mode: Mode
    let compactTelemetry: Bool
    let controlPaneWidth: CGFloat
    let editorPaneMinWidth: CGFloat
    let editorPaneIdealWidth: CGFloat
    let editorPaneMaxWidth: CGFloat
    let telemetryPaneMinWidth: CGFloat
    let telemetryPaneIdealWidth: CGFloat
    let telemetryPaneMaxWidth: CGFloat

    static func resolve(width: CGFloat, height: CGFloat) -> MainWindowLayout {
        if width >= 1280, height >= 640 {
            let editorIdealWidth = min(max((width * 0.30).rounded(), 620), 860)
            let telemetryIdealWidth = max(520, (width - 320 - editorIdealWidth).rounded(.down))
            return MainWindowLayout(
                mode: .workbench,
                compactTelemetry: false,
                controlPaneWidth: 320,
                editorPaneMinWidth: 460,
                editorPaneIdealWidth: editorIdealWidth,
                editorPaneMaxWidth: 900,
                telemetryPaneMinWidth: 420,
                telemetryPaneIdealWidth: telemetryIdealWidth,
                telemetryPaneMaxWidth: .infinity
            )
        }

        if width < 980 || height < 560 {
            return MainWindowLayout(
                mode: .stacked,
                compactTelemetry: true,
                controlPaneWidth: min(max(width, 360), 460),
                editorPaneMinWidth: 360,
                editorPaneIdealWidth: 420,
                editorPaneMaxWidth: 560,
                telemetryPaneMinWidth: 360,
                telemetryPaneIdealWidth: min(max(width, 360), 560),
                telemetryPaneMaxWidth: .infinity
            )
        }

        return MainWindowLayout(
            mode: .split,
            compactTelemetry: height < 640 || width < 1120,
            controlPaneWidth: min(max((width * 0.42).rounded(), 420), 500),
            editorPaneMinWidth: 420,
            editorPaneIdealWidth: 560,
            editorPaneMaxWidth: 640,
            telemetryPaneMinWidth: 420,
            telemetryPaneIdealWidth: max(520, (width * 0.52).rounded()),
            telemetryPaneMaxWidth: .infinity
        )
    }
}
