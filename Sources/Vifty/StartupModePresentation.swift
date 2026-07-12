struct StartupModePresentation: Equatable {
    let detail: String
    let requiresExplicitApply: Bool

    static func resolve(_ mode: ModeSelection) -> StartupModePresentation {
        switch mode {
        case .auto:
            return StartupModePresentation(
                detail: "Starts in macOS Auto control.",
                requiresExplicitApply: false
            )
        case .fixed, .curve:
            return StartupModePresentation(
                detail: "Preselects this mode as a draft; it does not change fan control at launch. Review the targets and choose Apply.",
                requiresExplicitApply: true
            )
        }
    }
}
