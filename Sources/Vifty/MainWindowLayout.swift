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
    let telemetryPaneMaxWidth: CGFloat

    static func resolve(width: CGFloat, height: CGFloat) -> MainWindowLayout {
        if width >= 1280, height >= 640 {
            return MainWindowLayout(
                mode: .workbench,
                compactTelemetry: false,
                controlPaneWidth: 320,
                editorPaneMinWidth: 460,
                editorPaneIdealWidth: 600,
                editorPaneMaxWidth: 760,
                telemetryPaneMaxWidth: 1000
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
            telemetryPaneMaxWidth: .infinity
        )
    }
}
