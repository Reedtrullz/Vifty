import AppKit
import SwiftUI

enum ViftyTextScale: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case large
    case accessibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            "Standard"
        case .large:
            "Large"
        case .accessibility:
            "Accessibility"
        }
    }

    var helpText: String {
        switch self {
        case .standard:
            "Use the standard macOS text and control size."
        case .large:
            "Make text 20% larger and use larger controls."
        case .accessibility:
            "Make text 50% larger and use the largest controls."
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .standard:
            1.0
        case .large:
            1.2
        case .accessibility:
            1.5
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .standard:
            .regular
        case .large:
            .large
        case .accessibility:
            .extraLarge
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .standard:
            0
        case .large:
            2
        case .accessibility:
            4
        }
    }
}

enum ViftySemanticTextStyle: CaseIterable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case footnote
    case caption
    case caption2

    var appKitTextStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle:
            .largeTitle
        case .title:
            .title1
        case .title2:
            .title2
        case .title3:
            .title3
        case .headline:
            .headline
        case .subheadline:
            .subheadline
        case .body:
            .body
        case .callout:
            .callout
        case .footnote:
            .footnote
        case .caption:
            .caption1
        case .caption2:
            .caption2
        }
    }

    func pointSize(at scale: ViftyTextScale) -> CGFloat {
        NSFont.preferredFont(forTextStyle: appKitTextStyle).pointSize * scale.multiplier
    }

    func appKitFont(at scale: ViftyTextScale) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: appKitTextStyle)
        return NSFont(
            descriptor: preferred.fontDescriptor,
            size: preferred.pointSize * scale.multiplier
        ) ?? NSFont.systemFont(ofSize: preferred.pointSize * scale.multiplier)
    }

    func font(
        at scale: ViftyTextScale,
        weight: Font.Weight? = nil
    ) -> Font {
        let semanticFont = Font(appKitFont(at: scale))
        return weight.map { semanticFont.weight($0) } ?? semanticFont
    }
}

private struct ViftyTextScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue = ViftyTextScale.standard
}

extension EnvironmentValues {
    var viftyTextScale: ViftyTextScale {
        get { self[ViftyTextScaleEnvironmentKey.self] }
        set { self[ViftyTextScaleEnvironmentKey.self] = newValue }
    }
}

private struct ViftyFontModifier: ViewModifier {
    @Environment(\.viftyTextScale) private var textScale

    let style: ViftySemanticTextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(style.font(at: textScale, weight: weight))
    }
}

private struct ViftyTextScaleModifier: ViewModifier {
    let scale: ViftyTextScale

    func body(content: Content) -> some View {
        content
            .environment(\.viftyTextScale, scale)
            .font(ViftySemanticTextStyle.body.font(at: scale))
            .controlSize(scale.controlSize)
            .lineSpacing(scale.lineSpacing)
    }
}

extension View {
    func viftyFont(
        _ style: ViftySemanticTextStyle,
        weight: Font.Weight? = nil
    ) -> some View {
        modifier(ViftyFontModifier(style: style, weight: weight))
    }

    func viftyTextScale(_ scale: ViftyTextScale) -> some View {
        modifier(ViftyTextScaleModifier(scale: scale))
    }
}
