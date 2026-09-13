enum StartupModePresentation {
    static func detail(for mode: ModeSelection) -> String {
        switch mode {
        case .auto:
            "Starts in macOS Auto control."
        case .fixed, .curve:
            "Preselects this mode as a draft; it does not change fan control at launch. Review the targets and choose Apply."
        }
    }
}
