import Foundation

struct MainWindowLayout: Equatable {
    enum Mode: Equatable {
        case split
        case stacked
    }

    let mode: Mode
    let compactTelemetry: Bool

    static func resolve(width: CGFloat, height: CGFloat) -> MainWindowLayout {
        let compactTelemetry = height < 640 || width < 920
        let mode: Mode = width < 920 || height < 560 ? .stacked : .split
        return MainWindowLayout(mode: mode, compactTelemetry: compactTelemetry)
    }
}
