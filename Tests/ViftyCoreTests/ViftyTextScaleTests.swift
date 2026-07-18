import AppKit
import SwiftUI
import XCTest
@testable import Vifty

final class ViftyTextScaleTests: XCTestCase {
    func testScalesHaveStableLabelsHelpAndConservativeMultipliers() {
        XCTAssertEqual(ViftyTextScale.allCases, [.standard, .large, .accessibility])
        XCTAssertEqual(ViftyTextScale.standard.label, "Standard")
        XCTAssertEqual(ViftyTextScale.large.label, "Large")
        XCTAssertEqual(ViftyTextScale.accessibility.label, "Accessibility")
        XCTAssertEqual(
            ViftyTextScale.standard.helpText,
            "Use the standard macOS text and control size."
        )
        XCTAssertEqual(
            ViftyTextScale.large.helpText,
            "Make text 20% larger and use larger controls."
        )
        XCTAssertEqual(
            ViftyTextScale.accessibility.helpText,
            "Make text 50% larger and use the largest controls."
        )
        XCTAssertEqual(ViftyTextScale.standard.multiplier, 1.0)
        XCTAssertEqual(ViftyTextScale.large.multiplier, 1.2)
        XCTAssertEqual(ViftyTextScale.accessibility.multiplier, 1.5)
        XCTAssertEqual(ViftyTextScale.standard.controlSize, .regular)
        XCTAssertEqual(ViftyTextScale.large.controlSize, .large)
        XCTAssertEqual(ViftyTextScale.accessibility.controlSize, .extraLarge)
        XCTAssertEqual(ViftyTextScale.standard.lineSpacing, 0)
        XCTAssertEqual(ViftyTextScale.large.lineSpacing, 2)
        XCTAssertEqual(ViftyTextScale.accessibility.lineSpacing, 4)
    }

    func testSemanticStylesMapToExactAppKitPreferredTextStyles() {
        XCTAssertEqual(ViftySemanticTextStyle.largeTitle.appKitTextStyle, .largeTitle)
        XCTAssertEqual(ViftySemanticTextStyle.title.appKitTextStyle, .title1)
        XCTAssertEqual(ViftySemanticTextStyle.title2.appKitTextStyle, .title2)
        XCTAssertEqual(ViftySemanticTextStyle.title3.appKitTextStyle, .title3)
        XCTAssertEqual(ViftySemanticTextStyle.headline.appKitTextStyle, .headline)
        XCTAssertEqual(ViftySemanticTextStyle.subheadline.appKitTextStyle, .subheadline)
        XCTAssertEqual(ViftySemanticTextStyle.body.appKitTextStyle, .body)
        XCTAssertEqual(ViftySemanticTextStyle.callout.appKitTextStyle, .callout)
        XCTAssertEqual(ViftySemanticTextStyle.footnote.appKitTextStyle, .footnote)
        XCTAssertEqual(ViftySemanticTextStyle.caption.appKitTextStyle, .caption1)
        XCTAssertEqual(ViftySemanticTextStyle.caption2.appKitTextStyle, .caption2)
        XCTAssertEqual(ViftySemanticTextStyle.allCases.count, 11)
    }

    func testScaledFontsPreservePreferredSemanticDescriptorsAndExactPointSizes() {
        for style in ViftySemanticTextStyle.allCases {
            let preferred = NSFont.preferredFont(forTextStyle: style.appKitTextStyle)
            for scale in ViftyTextScale.allCases {
                let scaled = style.appKitFont(at: scale)
                XCTAssertEqual(
                    scaled.pointSize,
                    preferred.pointSize * scale.multiplier,
                    accuracy: 0.000_001,
                    "\(style) must use the exact Vifty scale multiplier"
                )
                XCTAssertEqual(
                    scaled.fontName,
                    preferred.fontName,
                    "\(style) must preserve the preferred semantic font face"
                )
                XCTAssertEqual(
                    scaled.fontDescriptor.symbolicTraits,
                    preferred.fontDescriptor.symbolicTraits,
                    "\(style) must preserve native semantic traits"
                )
            }
        }
    }

    func testLegacyPreferencesDecodeToStandardAndNewScaleRoundTrips() throws {
        let legacy = try JSONDecoder().decode(
            AppPreferences.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(legacy.textScale, .standard)

        var updated = AppPreferences.defaults
        updated.textScale = .accessibility
        let decoded = try JSONDecoder().decode(
            AppPreferences.self,
            from: JSONEncoder().encode(updated)
        )
        XCTAssertEqual(decoded.textScale, .accessibility)
    }

    func testReviewedViftyViewsCannotBypassAppOwnedTextScaling() throws {
        let sources = repositoryRoot
            .appendingPathComponent("Sources/Vifty", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: sources,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ViftyTextScale.swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(files.isEmpty)
        let violations = try files.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains(".font(") ? file.lastPathComponent : nil
        }

        XCTAssertEqual(
            violations,
            [],
            "Reviewed Vifty views must use .viftyFont so every persisted text scale remains effective."
        )
    }

    func testProductionWindowSettingsAndPopoverInjectThePersistedScale() throws {
        let appSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Vifty/ViftyApp.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(appSource.components(separatedBy: ".viftyTextScale(model.textScale)").count - 1, 2)
        XCTAssertTrue(appSource.contains(".environmentObject(model)\n                .viftyTextScale(model.textScale)"))
        XCTAssertTrue(appSource.contains("Settings {"))

        let popoverSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Vifty/MenuBarView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(popoverSource.contains(".viftyTextScale(model.textScale)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
