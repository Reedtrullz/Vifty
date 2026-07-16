#if DEBUG
import AppKit
import CryptoKit
import Foundation
import SwiftUI
import XCTest
@testable import Vifty
@testable import ViftyCore

@MainActor
final class ViftyReviewFixtureTests: XCTestCase {
    func testFixtureRoutesMapEverySurfaceToItsNativeContainer() {
        XCTAssertEqual(ViftyReviewFixtureRoute(surface: .main), .main)
        XCTAssertEqual(
            ViftyReviewFixtureRoute(surface: .settingsGeneral),
            .settings(.general)
        )
        XCTAssertEqual(
            ViftyReviewFixtureRoute(surface: .settingsMenuBar),
            .settings(.menuBar)
        )
        XCTAssertEqual(
            ViftyReviewFixtureRoute(surface: .settingsNotifications),
            .settings(.notifications)
        )
        XCTAssertEqual(
            ViftyReviewFixtureRoute(surface: .settingsAgentWorkflows),
            .settings(.agentWorkflows)
        )
        XCTAssertEqual(ViftyReviewFixtureRoute(surface: .menuPopover), .popover)
    }

    func testLaunchCoordinatorPerformsExactlyOneRequestedContainerLaunch() {
        var settingsTabs: [ViftySettingsTab] = []
        var popoverLaunches = 0
        let settingsCoordinator = ViftyReviewFixtureLaunchCoordinator()

        for _ in 0..<3 {
            settingsCoordinator.launch(
                route: .settings(.notifications),
                openSettings: { settingsTabs.append($0) },
                showPopover: { popoverLaunches += 1 }
            )
        }
        XCTAssertEqual(settingsTabs, [.notifications])
        XCTAssertEqual(popoverLaunches, 0)
        XCTAssertEqual(settingsCoordinator.launchedRoute, .settings(.notifications))

        let popoverCoordinator = ViftyReviewFixtureLaunchCoordinator()
        for _ in 0..<3 {
            popoverCoordinator.launch(
                route: .popover,
                openSettings: { settingsTabs.append($0) },
                showPopover: { popoverLaunches += 1 }
            )
        }
        XCTAssertEqual(settingsTabs, [.notifications])
        XCTAssertEqual(popoverLaunches, 1)
        XCTAssertEqual(popoverCoordinator.launchedRoute, .popover)

        let mainCoordinator = ViftyReviewFixtureLaunchCoordinator()
        mainCoordinator.launch(
            route: .main,
            openSettings: { settingsTabs.append($0) },
            showPopover: { popoverLaunches += 1 }
        )
        XCTAssertEqual(settingsTabs, [.notifications])
        XCTAssertEqual(popoverLaunches, 1)
        XCTAssertEqual(mainCoordinator.launchedRoute, .main)
    }

    func testLauncherUsesSharedNondegenerateNativeFixtureGeometry() throws {
        XCTAssertEqual(
            ViftyReviewFixtureWindow.native.size,
            CGSize(width: 600, height: 420)
        )
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")
        let app = try read("Sources/Vifty/ViftyApp.swift")
        XCTAssertTrue(fixture.contains(
            ".frame(\n"
                + "                width: ViftyReviewFixtureWindow.native.size.width,\n"
                + "                height: ViftyReviewFixtureWindow.native.size.height\n"
                + "            )"
        ))
        XCTAssertTrue(app.contains(
            "case .settings, .popover:\n"
                + "            return ViftyReviewFixtureWindow.native.size.width"
        ))
        XCTAssertTrue(app.contains(
            "case .settings, .popover:\n"
                + "            return ViftyReviewFixtureWindow.native.size.height"
        ))
        XCTAssertFalse(fixture.contains(".frame(width: 1, height: 1)"))
    }

    func testSchemaV3ReportBindsCanonicalRequestProcessExecutableAndWindow() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try writeExecutableFixture(in: root)
        let request = try fixtureRequest(
            root: root,
            captureID: "capture-schema-v3",
            interaction: .structuralScroll
        )
        let runtime = try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 4_242
        )

        try await runtime.prepare()
        let observation = matchingObservation(for: request)
        XCTAssertFalse(try runtime.recordObservation(observation))
        XCTAssertTrue(try runtime.recordObservation(observation))
        try runtime.finalize()

        let report = runtime.report(phase: "final")
        XCTAssertEqual(report.schemaVersion, 3)
        XCTAssertEqual(report.captureID, "capture-schema-v3")
        XCTAssertEqual(report.request.interaction, "structural-scroll")
        XCTAssertEqual(report.requestSHA256.count, 64)
        let canonicalExecutablePath = executable
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        XCTAssertEqual(report.debugExecutablePath, canonicalExecutablePath)
        XCTAssertEqual(report.debugExecutableSHA256, sha256(try Data(contentsOf: executable)))
        XCTAssertEqual(report.debugBuildProvenance.productRole, "debug-fixture-app")
        XCTAssertEqual(report.debugBuildProvenance.configuration, "debug")
        XCTAssertEqual(report.runtimeIdentity?.processIdentifier, 4_242)
        XCTAssertEqual(report.runtimeIdentity?.executablePath, canonicalExecutablePath)
        XCTAssertEqual(report.runtimeIdentity?.executableSHA256, report.debugExecutableSHA256)
        XCTAssertEqual(report.runtimeIdentity?.provenance, "swiftui-main-window")
        XCTAssertEqual(report.runtimeIdentity?.isVisible, true)
        XCTAssertEqual(
            report.runtimeIdentity?.accessibilityIdentifier,
            "vifty-ui-review-ax-window-capture-schema-v3"
        )
        XCTAssertEqual(report.phase, "final")
        XCTAssertTrue(report.passed)
    }

    func testRuntimeRequiresTwoMatchingVisibleGeometrySamplesBeforeReady() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try fixtureRequest(root: root, captureID: "capture-stability")
        var stabilizer = ViftyReviewGeometryStabilizer()
        let matching = matchingWindowSample(for: request)

        var hidden = matching
        hidden.isVisible = false
        XCTAssertNil(stabilizer.consume(hidden, request: request))

        var empty = matching
        empty.contentWidth = 0
        XCTAssertNil(stabilizer.consume(empty, request: request))

        var unstable = matching
        unstable.contentWidth -= 1
        XCTAssertNil(stabilizer.consume(unstable, request: request))
        XCTAssertNil(stabilizer.consume(matching, request: request))
        XCTAssertEqual(stabilizer.consume(matching, request: request), matching)
    }

    func testWindowConfiguratorOverridesRestoredMainAndSettingsGeometry() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let compactRequest = try fixtureRequest(
            root: root,
            captureID: "capture-compact-window",
            window: .compact
        )
        let autosaveName = "vifty-review-compact-\(UUID().uuidString)"
        let autosaveKey = "NSWindow Frame \(autosaveName)"
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: autosaveKey) }
        let seedWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1_180, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        seedWindow.isReleasedWhenClosed = false
        seedWindow.saveFrame(usingName: autosaveName)
        let seededFrame = try XCTUnwrap(defaults.string(forKey: autosaveKey))
        let compactWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        compactWindow.isReleasedWhenClosed = false
        compactWindow.isRestorable = true
        XCTAssertTrue(compactWindow.setFrameAutosaveName(autosaveName))
        XCTAssertEqual(defaults.string(forKey: autosaveKey), seededFrame)

        ViftyReviewFixtureWindowConfigurator.configure(
            compactWindow,
            for: compactRequest
        )

        XCTAssertEqual(Int(compactWindow.contentLayoutRect.width.rounded()), 780)
        XCTAssertEqual(Int(compactWindow.contentLayoutRect.height.rounded()), 480)
        XCTAssertFalse(compactWindow.isRestorable)
        XCTAssertTrue(compactWindow.frameAutosaveName.isEmpty)
        compactWindow.close()
        XCTAssertEqual(defaults.string(forKey: autosaveKey), seededFrame)
        XCTAssertEqual(
            compactWindow.identifier?.rawValue,
            compactRequest.windowIdentifier
        )
        XCTAssertEqual(
            compactWindow.accessibilityIdentifier(),
            compactRequest.windowAccessibilityIdentifier
        )

        let settingsRequest = try fixtureRequest(
            root: root,
            captureID: "capture-settings-window",
            surface: .settingsGeneral,
            window: .native
        )
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        ViftyReviewFixtureWindowConfigurator.configure(
            settingsWindow,
            for: settingsRequest
        )

        XCTAssertEqual(Int(settingsWindow.contentLayoutRect.width.rounded()), 600)
        XCTAssertEqual(Int(settingsWindow.contentLayoutRect.height.rounded()), 420)
        XCTAssertFalse(settingsWindow.isRestorable)
        XCTAssertTrue(settingsWindow.frameAutosaveName.isEmpty)
    }

    func testWindowConfiguratorPreservesPopoverHeight() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try fixtureRequest(
            root: root,
            captureID: "capture-popover-window",
            surface: .menuPopover,
            window: .popover
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 517),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        ViftyReviewFixtureWindowConfigurator.configure(window, for: request)

        XCTAssertEqual(Int(window.contentLayoutRect.width.rounded()), 320)
        XCTAssertEqual(Int(window.contentLayoutRect.height.rounded()), 517)
        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.frameAutosaveName.isEmpty)
        XCTAssertEqual(window.identifier?.rawValue, request.windowIdentifier)
        XCTAssertEqual(
            window.accessibilityIdentifier(),
            request.windowAccessibilityIdentifier
        )
    }

    func testLauncherIsolationDetachesAutosaveWithoutChangingGeometry() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isRestorable = true
        let initialSize = window.contentLayoutRect.size
        let autosaveName = "vifty-review-launcher-\(UUID().uuidString)"
        let autosaveKey = "NSWindow Frame \(autosaveName)"
        defer { UserDefaults.standard.removeObject(forKey: autosaveKey) }
        XCTAssertTrue(window.setFrameAutosaveName(autosaveName))

        ViftyReviewFixtureWindowConfigurator.isolatePersistentState(window)

        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.frameAutosaveName.isEmpty)
        XCTAssertEqual(window.contentLayoutRect.size, initialSize)
    }

    func testPopoverFixtureDisablesPresentationAnimationBeforeNativeCapture() throws {
        let popover = try read("Sources/Vifty/ViftyReviewPopoverPresenter.swift")
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")

        XCTAssertTrue(
            popover.contains(
                "popover.animates = false\n"
                    + "        popover.behavior = .transient"
            ),
            "Native evidence must not race an in-flight NSPopover scale animation."
        )
        XCTAssertTrue(fixture.contains("@State private var observationEnabled = false"))
        XCTAssertTrue(fixture.contains(
            "if runtime.route == .popover {\n"
                + "                        // A newly ordered _NSPopoverWindow"
        ))
        XCTAssertTrue(fixture.contains("try await Task.sleep(for: .milliseconds(250))"))
        XCTAssertTrue(fixture.contains(
            "observationEnabled = true\n"
                + "                    observationGeneration &+= 1"
        ))
    }

    func testPopoverFixtureAppliesRequestedAppearanceToNativeContainer() throws {
        XCTAssertEqual(ViftyReviewFixtureAppearance.light.nativeAppearance.name, .aqua)
        XCTAssertEqual(ViftyReviewFixtureAppearance.dark.nativeAppearance.name, .darkAqua)

        let popover = try read("Sources/Vifty/ViftyReviewPopoverPresenter.swift")
        XCTAssertTrue(popover.contains("popover.appearance = runtime.request.appearance.nativeAppearance"))
        XCTAssertTrue(popover.contains("window.appearance = runtime.request.appearance.nativeAppearance"))
    }

    func testFixtureAppearancePinsApplicationAgainstOpposingHostAppearance() {
        let application = NSApplication.shared
        let priorAppearance = application.appearance
        defer { application.appearance = priorAppearance }

        for (requested, opposing) in [
            (ViftyReviewFixtureAppearance.light, ViftyReviewFixtureAppearance.dark),
            (ViftyReviewFixtureAppearance.dark, ViftyReviewFixtureAppearance.light)
        ] {
            application.appearance = opposing.nativeAppearance
            XCTAssertEqual(
                application.effectiveAppearance.name,
                opposing.nativeAppearance.name
            )

            requested.apply(to: application)

            XCTAssertEqual(application.appearance?.name, requested.nativeAppearance.name)
            XCTAssertEqual(
                application.effectiveAppearance.name,
                requested.nativeAppearance.name
            )
        }

        application.appearance = priorAppearance
        XCTAssertEqual(application.appearance?.name, priorAppearance?.name)
    }

    func testFixtureAppearanceResolvesOpaqueWindowBackgroundForRequestedScheme() throws {
        let application = NSApplication.shared
        let priorAppearance = application.appearance
        defer { application.appearance = priorAppearance }

        application.appearance = ViftyReviewFixtureAppearance.dark.nativeAppearance
        let light = try XCTUnwrap(
            ViftyReviewFixtureAppearance.light.resolvedWindowBackgroundColor
                .usingColorSpace(.deviceRGB)
        )
        application.appearance = ViftyReviewFixtureAppearance.light.nativeAppearance
        let dark = try XCTUnwrap(
            ViftyReviewFixtureAppearance.dark.resolvedWindowBackgroundColor
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(light.alphaComponent, 1, accuracy: 0.000_001)
        XCTAssertEqual(dark.alphaComponent, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(
            min(light.redComponent, light.greenComponent, light.blueComponent),
            0.9
        )
        XCTAssertLessThan(
            max(dark.redComponent, dark.greenComponent, dark.blueComponent),
            0.25
        )
    }

    func testLayerBackedHostingViewAcceptsOpaqueRequestedBackground() throws {
        let controller = NSHostingController(rootView: EmptyView())
        controller.view.wantsLayer = true
        let layer = try XCTUnwrap(controller.view.layer)

        for appearance in ViftyReviewFixtureAppearance.allCases {
            let expected = appearance.resolvedWindowBackgroundColor.cgColor
            layer.backgroundColor = expected
            layer.isOpaque = true

            let actual = try XCTUnwrap(layer.backgroundColor)
            XCTAssertTrue(layer.isOpaque)
            XCTAssertEqual(actual.colorSpace, expected.colorSpace)
            XCTAssertEqual(actual.components ?? [], expected.components ?? [])
        }
    }

    func testPopoverFixtureInstallsOpaqueResolvedBackgroundBeforePresentation() throws {
        let popover = try read("Sources/Vifty/ViftyReviewPopoverPresenter.swift")
        let controller = try XCTUnwrap(
            popover.range(of: "let controller = NSHostingController(rootView: rootView)")
        )
        let layerBacking = try XCTUnwrap(
            popover.range(
                of: "controller.view.wantsLayer = true",
                range: controller.upperBound..<popover.endIndex
            )
        )
        let background = try XCTUnwrap(
            popover.range(
                of: "controller.view.layer?.backgroundColor = runtime.request.appearance.resolvedWindowBackgroundColor.cgColor",
                range: layerBacking.upperBound..<popover.endIndex
            )
        )
        let opaque = try XCTUnwrap(
            popover.range(
                of: "controller.view.layer?.isOpaque = true",
                range: background.upperBound..<popover.endIndex
            )
        )
        let assignment = try XCTUnwrap(
            popover.range(
                of: "popover.contentViewController = controller",
                range: opaque.upperBound..<popover.endIndex
            )
        )
        let show = try XCTUnwrap(
            popover.range(
                of: "popover.show(relativeTo:",
                range: assignment.upperBound..<popover.endIndex
            )
        )

        XCTAssertLessThan(controller.lowerBound, layerBacking.lowerBound)
        XCTAssertLessThan(layerBacking.lowerBound, background.lowerBound)
        XCTAssertLessThan(background.lowerBound, opaque.lowerBound)
        XCTAssertLessThan(opaque.lowerBound, assignment.lowerBound)
        XCTAssertLessThan(assignment.lowerBound, show.lowerBound)
    }

    func testAppAppliesFixtureAppearanceAfterParsingBeforeModelConstruction() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let parse = try XCTUnwrap(
            app.range(of: "reviewFixtureRuntime = try ViftyReviewFixtureRuntime.parse(")
        )
        let apply = try XCTUnwrap(
            app.range(
                of: "if let reviewFixtureRuntime {\n"
                    + "            reviewFixtureRuntime.request.appearance.apply()\n"
                    + "        }",
                range: parse.upperBound..<app.endIndex
            )
        )
        let model = try XCTUnwrap(
            app.range(
                of: "let model = reviewFixtureRuntime?.model ?? AppModel()",
                range: apply.upperBound..<app.endIndex
            )
        )
        let stateObject = try XCTUnwrap(
            app.range(
                of: "_model = StateObject(wrappedValue: model)",
                range: model.upperBound..<app.endIndex
            )
        )

        XCTAssertLessThan(parse.lowerBound, apply.lowerBound)
        XCTAssertLessThan(apply.lowerBound, model.lowerBound)
        XCTAssertLessThan(model.lowerBound, stateObject.lowerBound)
    }

    func testPopoverRetryDeadlineBoundsRetriesToMonotonicFixtureDeadline() {
        let deadline = ViftyReviewPopoverRetryDeadline(uptime: 12.0)

        XCTAssertEqual(
            deadline.boundedDelay(now: 10.0, preferredDelay: 0.05)!,
            0.05,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            deadline.boundedDelay(now: 11.98, preferredDelay: 0.05)!,
            0.02,
            accuracy: 0.000_001
        )
        XCTAssertNil(deadline.boundedDelay(now: 12.0, preferredDelay: 0.05))
        XCTAssertNil(deadline.boundedDelay(now: 12.01, preferredDelay: 0.05))
        XCTAssertNil(deadline.boundedDelay(now: .nan, preferredDelay: 0.05))
        XCTAssertNil(deadline.boundedDelay(now: 10.0, preferredDelay: -0.01))
    }

    func testFixtureDoesNotInjectSyntheticMacOSDynamicType() throws {
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")
        XCTAssertFalse(fixture.contains(".dynamicTypeSize("))
        XCTAssertFalse(fixture.contains("var dynamicTypeSize:"))

        let settingsPane = try read("Sources/Vifty/SettingsPane.swift")
        XCTAssertTrue(settingsPane.contains("@Environment(\\.viftyTextScale) private var textScale"))
        XCTAssertTrue(settingsPane.contains("textScale == .accessibility"))
        XCTAssertFalse(settingsPane.contains("dynamicTypeSize"))
    }

    func testFixtureProvesAppOwnedTextScaleOutsideItsObservationBackground() throws {
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")
        let background = try XCTUnwrap(fixture.range(of: ".background {"))
        let textScale = try XCTUnwrap(
            fixture.range(
                of: ".viftyTextScale(runtime.model.textScale)",
                range: background.upperBound..<fixture.endIndex
            )
        )

        XCTAssertLessThan(background.lowerBound, textScale.lowerBound)
        XCTAssertTrue(
            fixture[background.upperBound..<textScale.lowerBound]
                .contains("ViftyReviewFixtureObservationBridge("),
            "The Vifty text-scale observer must be inside the app-owned environment modifier it verifies."
        )
        XCTAssertTrue(fixture.contains("@Environment(\\.viftyTextScale) private var textScale"))
        XCTAssertTrue(fixture.contains("fixtureModel.textScale = request.textSize.viftyTextScale"))
    }

    func testConcurrentPreparationCallersAwaitOnePreparation() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try writeExecutableFixture(in: root)
        let request = try fixtureRequest(root: root, captureID: "capture-concurrent-prepare")
        let runtime = try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 6
        )

        async let first: Void = runtime.prepare()
        async let second: Void = runtime.prepare()
        _ = try await (first, second)

        let reads = runtime.recorder.snapshot().readOperations
        XCTAssertEqual(reads.filter { $0 == "hardware-snapshot" }.count, 1)
        XCTAssertEqual(reads.filter { $0 == "notification-authorization" }.count, 1)
        XCTAssertEqual(runtime.report(phase: "prepared").phase, "prepared")
    }

    func testRuntimeRejectsWrongContainerNativeGeometryAndExecutableHash() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try writeExecutableFixture(in: root)
        let request = try fixtureRequest(
            root: root,
            captureID: "capture-settings",
            surface: .settingsNotifications,
            window: .native,
            expectedExecutableSHA256: String(repeating: "0", count: 64)
        )

        XCTAssertThrowsError(try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 7
        )) { error in
            guard case ViftyReviewFixtureError.executableHashMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        var stabilizer = ViftyReviewGeometryStabilizer()
        var wrongContainer = matchingWindowSample(for: request)
        wrongContainer.provenance = "swiftui-main-window"
        wrongContainer.containerKind = "main-window"
        XCTAssertNil(stabilizer.consume(wrongContainer, request: request))

        var wrongNativeGeometry = matchingWindowSample(for: request)
        wrongNativeGeometry.contentWidth = 601
        XCTAssertNil(stabilizer.consume(wrongNativeGeometry, request: request))
    }

    func testCaptureWritesOpaquePNGMatchingObservedScaleAndFinalizesLateSafetyState() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = PatternCaptureView(frame: NSRect(x: 0, y: 0, width: 64, height: 48))
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let screenshotURL = root.appendingPathComponent("capture.png")
        let screenshot = try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: screenshotURL,
            nativeWindowCapture: syntheticNativeWindowCapture
        )
        XCTAssertEqual(screenshot.method, "native-window-screencapture-crop")
        XCTAssertEqual(screenshot.pointWidth, 64)
        XCTAssertEqual(screenshot.pointHeight, 48)
        XCTAssertEqual(
            screenshot.pixelWidth,
            Int((64 * window.backingScaleFactor).rounded())
        )
        XCTAssertEqual(
            screenshot.pixelHeight,
            Int((48 * window.backingScaleFactor).rounded())
        )
        XCTAssertEqual(screenshot.sha256, sha256(try Data(contentsOf: screenshotURL)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: screenshotURL)))
        XCTAssertGreaterThan(bitmap.colorAt(x: 1, y: 1)?.alphaComponent ?? 0, 0)

        let executable = try writeExecutableFixture(in: root)
        let request = try fixtureRequest(root: root, captureID: "capture-late-safety")
        let runtime = try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 8
        )
        try await runtime.prepare()
        let observation = matchingObservation(for: request)
        XCTAssertFalse(try runtime.recordObservation(observation))
        XCTAssertTrue(try runtime.recordObservation(observation))
        runtime.recorder.recordHardwareCommand("late-test-command")
        XCTAssertThrowsError(try runtime.finalize())
        let final = runtime.report(phase: "final")
        XCTAssertEqual(final.phase, "final")
        XCTAssertFalse(final.passed)
        XCTAssertEqual(final.recorder.attemptedHardwareCommands, ["late-test-command"])
    }

    func testCaptureCropsBoundedSymmetricNativeBorderPadding() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = PatternCaptureView(frame: NSRect(x: 0, y: 0, width: 64, height: 48))
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let baselineURL = root.appendingPathComponent("baseline.png")
        let paddedURL = root.appendingPathComponent("padded.png")
        _ = try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: baselineURL,
            nativeWindowCapture: syntheticNativeWindowCapture
        )
        _ = try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: paddedURL,
            nativeWindowCapture: syntheticNativeWindowCaptureWithBorderPadding
        )

        let baseline = try XCTUnwrap(
            NSBitmapImageRep(data: Data(contentsOf: baselineURL))
        )
        let padded = try XCTUnwrap(
            NSBitmapImageRep(data: Data(contentsOf: paddedURL))
        )
        XCTAssertEqual(padded.pixelsWide, baseline.pixelsWide)
        XCTAssertEqual(padded.pixelsHigh, baseline.pixelsHigh)
        XCTAssertEqual(try normalizedRGBA(padded), try normalizedRGBA(baseline))

        let excessivePadding = Int((2 * window.backingScaleFactor).rounded()) + 2
        XCTAssertThrowsError(try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("excessive-horizontal-padding.png"),
            nativeWindowCapture: { window, url in
                try self.syntheticNativeWindowCaptureWithPadding(
                    window,
                    url,
                    horizontalPadding: excessivePadding,
                    verticalPadding: 0
                )
            }
        ))
        XCTAssertThrowsError(try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("vertical-padding.png"),
            nativeWindowCapture: { window, url in
                try self.syntheticNativeWindowCaptureWithPadding(
                    window,
                    url,
                    horizontalPadding: 0,
                    verticalPadding: excessivePadding
                )
            }
        ))
        XCTAssertThrowsError(try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("undersized-frame.png"),
            nativeWindowCapture: { window, url in
                try self.syntheticNativeWindowCaptureWithPadding(
                    window,
                    url,
                    horizontalPadding: -2,
                    verticalPadding: 0
                )
            }
        ))
    }

    func testFixtureStateInventoryIsStableAndComplete() {
        XCTAssertEqual(
            ViftyReviewFixtureState.allCases.map(\.rawValue),
            [
                "healthy-auto",
                "divergent-per-fan-curve-draft",
                "active-manual",
                "recovery-mixed-ownership",
                "helper-blocked",
                "notification-denied",
                "edited-profile",
                "selected-vs-highest-temperature",
                "raw-spike-telemetry"
            ]
        )
    }

    func testFixtureArgumentsAreAbsentWithoutExplicitFlagAndRejectUnknownState() throws {
        XCTAssertNil(try ViftyReviewFixtureRequest.parse(arguments: ["Vifty"]))
        XCTAssertThrowsError(
            try ViftyReviewFixtureRequest.parse(
                arguments: ["Vifty", "--ui-review-fixture", "unknown"]
            )
        ) { error in
            XCTAssertEqual(error as? ViftyReviewFixtureError, .invalidState)
        }
        XCTAssertThrowsError(try ViftyReviewFixtureRequest.parse(arguments: [
            "Vifty", "--ui-review-fixture", "healthy-auto"
        ])) { error in
            XCTAssertEqual(
                error as? ViftyReviewFixtureError,
                .missingOptionValue(flag: "--ui-review-capture-id")
            )
        }
    }

    func testFixtureArgumentsSelectDeterministicSurfaceAndAccessibilityVariants() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshot = root.appendingPathComponent("screenshots/settings.png")
        let completion = root.appendingPathComponent("completion/ax.done")
        let request = try XCTUnwrap(ViftyReviewFixtureRequest.parse(arguments: [
            "Vifty",
            "--ui-review-fixture", "notification-denied",
            "--ui-review-surface", "settings-notifications",
            "--ui-review-window", "native",
            "--ui-review-appearance", "dark",
            "--ui-review-contrast", "increased",
            "--ui-review-transparency", "reduced",
            "--ui-review-text-size", "accessibility",
            "--ui-review-interaction", "structural-scroll",
            "--ui-review-capture-id", "settings-notifications-accessibility",
            "--ui-review-screenshot", screenshot.path,
            "--ui-review-completion-file", completion.path,
            "--ui-review-timeout-seconds", "12.5",
            "--ui-review-readiness-deadline-uptime", "1234.5",
            "--ui-review-output", root.path
        ]))

        XCTAssertEqual(request.state, .notificationDenied)
        XCTAssertEqual(request.surface, .settingsNotifications)
        XCTAssertEqual(request.window, .native)
        XCTAssertEqual(request.appearance, .dark)
        XCTAssertEqual(request.contrast, .increased)
        XCTAssertEqual(request.transparency, .reduced)
        XCTAssertEqual(request.textSize, .accessibility)
        XCTAssertEqual(request.textSize.viftyTextScale, .accessibility)
        XCTAssertEqual(request.interaction, .structuralScroll)
        XCTAssertEqual(request.captureID, "settings-notifications-accessibility")
        XCTAssertEqual(request.screenshotURL, screenshot.standardizedFileURL)
        XCTAssertEqual(request.completionFileURL, completion.standardizedFileURL)
        XCTAssertEqual(request.timeoutSeconds, 12.5)
        XCTAssertEqual(request.readinessDeadlineUptime, 1_234.5)
        XCTAssertEqual(request.screenshotArtifactPath, "screenshots/settings.png")
        XCTAssertEqual(request.outputDirectory.path, root.standardizedFileURL.path)

        let executable = try writeExecutableFixture(in: root)
        let runtime = try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 812
        )
        XCTAssertEqual(runtime.model.textScale, .accessibility)
    }

    func testEveryFixturePreparesAndFinalizesWithoutStartingOrMutatingHardware() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try writeExecutableFixture(in: root)

        for state in ViftyReviewFixtureState.allCases {
            let output = root.appendingPathComponent(state.rawValue, isDirectory: true)
            let runtime = try XCTUnwrap(try ViftyReviewFixtureRuntime.parse(arguments: [
                "Vifty",
                "--ui-review-fixture", state.rawValue,
                "--ui-review-capture-id", "fixture-\(state.rawValue)",
                "--ui-review-output", output.path
            ], executableURL: executable))

            try await runtime.prepare()
            let observation = matchingObservation(for: runtime.request)
            XCTAssertFalse(try runtime.recordObservation(observation))
            XCTAssertTrue(try runtime.recordObservation(observation))
            try runtime.finalize()
            let report = runtime.report(phase: "final")

            XCTAssertEqual(report.schemaVersion, 3, state.rawValue)
            XCTAssertFalse(report.captureID.isEmpty, state.rawValue)
            XCTAssertEqual(report.request.state, state.rawValue)
            XCTAssertEqual(report.observed, matchingObservation(for: runtime.request))
            XCTAssertFalse(runtime.model.isRunning, state.rawValue)
            XCTAssertTrue(report.modelStartSkipped, state.rawValue)
            XCTAssertTrue(report.passed, state.rawValue)
            XCTAssertTrue(report.recorder.attemptedHardwareCommands.isEmpty, state.rawValue)
            XCTAssertTrue(report.recorder.attemptedExternalMutations.isEmpty, state.rawValue)
            XCTAssertTrue(report.recorder.realControlPathConstructions.isEmpty, state.rawValue)
            XCTAssertEqual(report.phase, "final")
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: output.appendingPathComponent("fixture-report.json").path
                ),
                state.rawValue
            )
        }
    }

    func testFinalReportRequiresIndependentEnvironmentAndNSWindowObservation() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try await preparedRuntime(.healthyAuto, root: root)

        let unobserved = runtime.report(phase: "final")
        XCTAssertFalse(unobserved.passed)
        XCTAssertNil(unobserved.observed)
        XCTAssertThrowsError(try runtime.finalize()) { error in
            XCTAssertEqual(error as? ViftyReviewFixtureError, .unsafeReport)
        }

        var mismatched = matchingObservation(for: runtime.request)
        mismatched.environment.appearance = "dark"
        XCTAssertFalse(try runtime.recordObservation(mismatched))
        XCTAssertFalse(runtime.report(phase: "final").passed)

        mismatched = matchingObservation(for: runtime.request)
        mismatched.environment.contrast = "increased"
        XCTAssertFalse(try runtime.recordObservation(mismatched))
        XCTAssertFalse(runtime.report(phase: "final").passed)

        mismatched = matchingObservation(for: runtime.request)
        mismatched.environment.transparency = "reduced"
        XCTAssertFalse(try runtime.recordObservation(mismatched))
        XCTAssertFalse(runtime.report(phase: "final").passed)

        mismatched = matchingObservation(for: runtime.request)
        mismatched.window.containerKind = "settings-window"
        XCTAssertFalse(try runtime.recordObservation(mismatched))
        XCTAssertFalse(runtime.report(phase: "final").passed)

        let matching = matchingObservation(for: runtime.request)
        XCTAssertFalse(try runtime.recordObservation(matching))
        XCTAssertTrue(try runtime.recordObservation(matching))
        let report = runtime.report(phase: "final")
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.observed?.environment.source, "swiftui-environment")
        XCTAssertEqual(report.observed?.window.source, "nswindow-content-layout-rect")
        XCTAssertEqual(report.observed?.window.containerKind, "main-window")
        XCTAssertEqual(report.observed?.window.contentWidth, 1_180)
        XCTAssertEqual(report.observed?.window.contentHeight, 820)
        XCTAssertEqual(report.observed?.window.backingScaleFactor, 2)
    }

    func testFixtureStatesExposeTheReviewRegressionsWithoutControlCommands() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let curve = try await preparedRuntime(.divergentPerFanCurveDraft, root: root)
        XCTAssertEqual(curve.model.selectedMode, .curve)
        XCTAssertEqual(curve.model.fanOverrides.map(\.maxRPM), [5_700, 6_400])
        XCTAssertTrue(curve.model.hasPendingFanControlChanges)

        let manual = try await preparedRuntime(.activeManual, root: root)
        XCTAssertEqual(manual.model.controlSessionPresentation.summary, "Owner: Vifty manual control")
        XCTAssertEqual(manual.model.controlSessionPresentation.title, "Vifty manual control active")
        XCTAssertEqual(manual.model.fanControlApplyState, .applied)
        XCTAssertFalse(manual.model.hasPendingFanControlChanges)
        XCTAssertEqual(manual.model.snapshot?.fans.map(\.targetRPM), [3_800, 4_400])

        let recovery = try await preparedRuntime(.recoveryMixedOwnership, root: root)
        XCTAssertEqual(recovery.model.controlSessionPresentation.title, "Fan recovery pending")
        XCTAssertEqual(recovery.model.snapshot?.fans.map(\.hardwareMode), [.automatic, .forced])

        let blocked = try await preparedRuntime(.helperBlocked, root: root)
        XCTAssertFalse(blocked.model.daemonResponding)
        XCTAssertEqual(blocked.model.helperHealthState, .telemetryOnly)

        let denied = try await preparedRuntime(.notificationDenied, root: root)
        XCTAssertEqual(denied.model.notificationAuthorization, .denied)
        XCTAssertTrue(denied.model.notificationSettings.helperFailure)

        let profile = try await preparedRuntime(.editedProfile, root: root)
        XCTAssertEqual(profile.model.savedProfiles.map(\.name), ["Quiet Build"])
        XCTAssertEqual(profile.model.curveProfileEditState.suffix, "Edited")
        XCTAssertEqual(profile.model.snapshot?.fans.map(\.maximumRPM), [4_296, 4_744])
        let profileChart = FanCurveChartPresentation.make(
            basePoints: [
                FanCurveChartValue(temperature: profile.model.curveStartTemp, rpm: profile.model.curveStartRPM),
                FanCurveChartValue(temperature: profile.model.curveMidTemp, rpm: profile.model.curveMidRPM),
                FanCurveChartValue(temperature: profile.model.curveMaxTemp, rpm: profile.model.curveMaxRPM)
            ],
            fans: try XCTUnwrap(profile.model.snapshot).fans,
            overrides: profile.model.fanOverrides,
            usePerFanOverrides: profile.model.usePerFanOverrides
        )
        XCTAssertFalse(profileChart.usesPerFanOverrides)
        XCTAssertEqual(profileChart.basePoints.map(\.rpm), [1_750, 3_600, 6_000])
        XCTAssertEqual(profileChart.series.map { $0.points.last?.rpm }, [4_296, 4_744])

        let selected = try await preparedRuntime(.selectedVersusHighestTemperature, root: root)
        XCTAssertEqual(selected.model.selectedSensor?.id, "cpu-efficiency")
        XCTAssertEqual(selected.model.snapshot?.highestTemperature?.id, "gpu-hotspot")
        XCTAssertEqual(selected.model.telemetryHistory.latestSample?.temperatureRole, .curveSensor)

        let spike = try await preparedRuntime(.rawSpikeTelemetry, root: root)
        XCTAssertEqual(spike.model.telemetryOverviewSummary.temperatureValues, [50, 50, 100, 50, 50])
        let spikeLatest = try XCTUnwrap(spike.model.telemetryHistory.latestSample)
        let spikeSnapshot = try XCTUnwrap(spike.model.snapshot)
        XCTAssertEqual(
            spikeSnapshot.temperatureSensors.first { $0.id == spikeLatest.selectedTemperatureID }?.celsius,
            spikeLatest.selectedTemperatureCelsius,
            "The raw-spike fixture's visible current sensor must equal the history endpoint."
        )
        XCTAssertEqual(
            Double(spikeSnapshot.fans.reduce(0) { $0 + $1.currentRPM })
                / Double(spikeSnapshot.fans.count),
            spikeLatest.averageFanRPM,
            "The raw-spike fixture's visible fan rows must equal the latest history average."
        )
        XCTAssertEqual(
            spike.model.telemetryOverviewSummary.temperatureChangeText,
            "returned to start"
        )
        XCTAssertEqual(spikeLatest.capturedAt, spikeSnapshot.capturedAt)
        XCTAssertEqual(
            spikeLatest.highestTemperatureCelsius,
            spikeSnapshot.highestTemperature?.celsius
        )
        XCTAssertEqual(
            spikeLatest.batteryPowerWatts,
            spike.model.powerSnapshot?.batteryPowerWatts
        )
        XCTAssertEqual(spikeLatest.firstFanRPM, spikeSnapshot.fans.first?.currentRPM)
    }

    func testFixtureHardwareAttemptMakesFinalReportFailClosed() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try await preparedRuntime(.healthyAuto, root: root)
        let observation = matchingObservation(for: runtime.request)
        XCTAssertFalse(try runtime.recordObservation(observation))
        XCTAssertTrue(try runtime.recordObservation(observation))

        runtime.model.selectedMode = .fixed
        runtime.model.fixedRPM = 3_600
        _ = await runtime.model.applyCurrentModeSelection()

        let report = runtime.report(phase: "final")
        XCTAssertFalse(report.passed)
        XCTAssertFalse(report.recorder.attemptedHardwareCommands.isEmpty)
        XCTAssertThrowsError(try runtime.finalize()) { error in
            XCTAssertEqual(error as? ViftyReviewFixtureError, .unsafeReport)
        }
    }

    func testCaptureCropsAFullSizeContentViewToTheNativeContentLayoutRect() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 72),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let view = VerticalBandCaptureView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let expectedWidth = Int(window.contentLayoutRect.width.rounded())
        let expectedHeight = Int(window.contentLayoutRect.height.rounded())
        XCTAssertGreaterThan(Int(view.bounds.height.rounded()), expectedHeight)

        let screenshot = try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("full-size-content.png"),
            nativeWindowCapture: syntheticNativeWindowCapture
        )

        XCTAssertEqual(screenshot.pointWidth, expectedWidth)
        XCTAssertEqual(screenshot.pointHeight, expectedHeight)
        XCTAssertEqual(
            screenshot.pixelHeight,
            Int((Double(expectedHeight) * window.backingScaleFactor).rounded())
        )
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(data: Data(contentsOf: root.appendingPathComponent("full-size-content.png")))
        )
        let x = bitmap.pixelsWide / 2
        let samples = [
            try XCTUnwrap(bitmap.colorAt(x: x, y: max(1, bitmap.pixelsHigh / 6))?.usingColorSpace(.sRGB)),
            try XCTUnwrap(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)),
            try XCTUnwrap(bitmap.colorAt(x: x, y: min(bitmap.pixelsHigh - 2, bitmap.pixelsHigh * 5 / 6))?.usingColorSpace(.sRGB))
        ]
        let dominantChannels = Set(samples.map { color in
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
            return channels.firstIndex(of: channels.max()!)!
        })
        XCTAssertEqual(
            dominantChannels,
            Set([0, 1, 2]),
            "The crop did not preserve all three distinct content bands: \(samples)"
        )
        XCTAssertFalse(
            samples.contains {
                $0.redComponent > 0.75
                    && $0.greenComponent < 0.35
                    && $0.blueComponent > 0.75
            },
            "The content crop retained pixels outside contentLayoutRect: \(samples)"
        )
    }

    func testCaptureCompositesTheNativeWindowBackgroundBehindTransparentContent() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .systemBlue
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let screenshotURL = root.appendingPathComponent("transparent-content.png")
        _ = try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: screenshotURL,
            nativeWindowCapture: syntheticNativeWindowCapture
        )

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: screenshotURL)))
        let color = try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
        XCTAssertGreaterThan(color.blueComponent, 0.5)
    }

    func testCaptureRemovesTransientFullWindowFileOnEveryFailurePath() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = PatternCaptureView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        XCTAssertThrowsError(try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("invalid-capture.png"),
            nativeWindowCapture: { _, rawURL in
                try Data("not a PNG".utf8).write(to: rawURL)
            }
        ))
        XCTAssertEqual(try transientWindowCaptureFiles(in: root), [])

        XCTAssertThrowsError(try ViftyReviewPNGWriter.capture(
            contentView: view,
            window: window,
            to: root.appendingPathComponent("failed-capture.png"),
            nativeWindowCapture: { _, rawURL in
                try Data("partial native capture".utf8).write(to: rawURL)
                throw CocoaError(.fileReadCorruptFile)
            }
        ))
        XCTAssertEqual(try transientWindowCaptureFiles(in: root), [])
    }

    func testTimedOutNativeCaptureProcessIsForceKilledAndReaped() throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readyURL = root.appendingPathComponent("ready")

        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "trap '' TERM; : > \"$1\"; while :; do :; done",
            "vifty-capture-timeout-test",
            readyURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }
        try process.run()

        let readyDeadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: readyURL.path), Date() < readyDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: readyURL.path))
        XCTAssertTrue(process.isRunning)

        ViftyReviewPNGWriter.stopTimedOutCaptureProcess(
            process,
            completion: completion,
            terminationGracePeriod: .milliseconds(50)
        )

        XCTAssertFalse(process.isRunning)
        XCTAssertNotEqual(process.terminationStatus, 0)
    }

    func testFixtureSelectsInertHelperBackendAndRecordsAnyMutation() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try await preparedRuntime(.healthyAuto, root: root)

        runtime.daemonInstaller.refresh()
        XCTAssertEqual(runtime.daemonInstaller.statusText, "Fan helper enabled")
        XCTAssertTrue(runtime.recorder.snapshot().attemptedExternalMutations.isEmpty)

        await runtime.daemonInstaller.installOrOpenApproval()
        XCTAssertEqual(
            runtime.recorder.snapshot().attemptedExternalMutations,
            ["helper-lifecycle-repair"]
        )
    }

    func testFixtureSourceBoundaryExcludesRealControlPathsAndFixtureLifecycleSkipsRestore() throws {
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")
        let capture = try read("Sources/Vifty/ViftyReviewCapture.swift")
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let content = try read("Sources/Vifty/ContentView.swift")
        let popover = try read("Sources/Vifty/ViftyReviewPopoverPresenter.swift")
        let settings = try read("Sources/Vifty/ViftySettingsView.swift")

        XCTAssertTrue(fixture.hasPrefix("#if DEBUG"))
        XCTAssertTrue(fixture.hasSuffix("#endif\n"))
        for forbiddenConstructor in [
            "RealMacHardwareService(",
            "ViftyDaemonClient(",
            "SMCClient(",
            "LocalFanHelperClient(",
            "SystemDaemonInstallerBackend("
        ] {
            XCTAssertFalse(fixture.contains(forbiddenConstructor), forbiddenConstructor)
        }
        XCTAssertTrue(app.contains("guard reviewFixtureRuntime == nil else { return }"))
        XCTAssertTrue(app.contains("guard reviewFixtureRuntime == nil else { return }"))
        XCTAssertTrue(app.contains("try reviewFixtureRuntime.finalize()"))
        XCTAssertTrue(app.contains("return .terminateNow"))
        XCTAssertFalse(
            fixture.contains("stopAndRestore()"),
            "Fixture termination must never run production Auto restoration."
        )
        XCTAssertTrue(content.contains("daemonInstaller: DaemonInstaller = DaemonInstaller(),"))
        XCTAssertFalse(content.contains("@StateObject private var daemonInstaller = DaemonInstaller()"))
        XCTAssertTrue(fixture.contains("NSViewRepresentable"))
        XCTAssertTrue(capture.contains("native-window-screencapture-crop"))
        XCTAssertTrue(capture.contains("/usr/sbin/screencapture"))
        XCTAssertTrue(capture.contains("ownerAccountID"))
        XCTAssertTrue(
            fixture.contains(".id(observationGeneration)"),
            "Preparation must install a fresh observer generation even when the pre-prepare pair is still coalesced."
        )
        XCTAssertTrue(fixture.contains("@Environment(\\.colorScheme)"))
        XCTAssertTrue(fixture.contains("window.contentLayoutRect.size"))
        XCTAssertTrue(
            fixture.contains(
                ".accessibilityElement(children: .contain)\n" +
                    "            .accessibilityIdentifier(runtime.request.rootAccessibilityIdentifier)"
            )
        )
        XCTAssertEqual(
            fixture.components(
                separatedBy: ".accessibilityIdentifier(runtime.request.rootAccessibilityIdentifier)"
            ).count - 1,
            1
        )
        XCTAssertFalse(fixture.contains("MenuBarView("))
        XCTAssertFalse(fixture.contains("ViftySettingsView("))
        XCTAssertTrue(app.contains("ViftyReviewFixtureSceneHost("))
        XCTAssertTrue(app.contains("ViftyReviewFixtureLaunchBridge(runtime:"))
        XCTAssertTrue(app.contains("if reviewFixtureRuntime == nil"))
        XCTAssertEqual(
            app.components(
                separatedBy: ".restorationBehavior(reviewFixtureRuntime == nil ? .automatic : .disabled)"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            app.components(
                separatedBy: ".defaultLaunchBehavior(reviewFixtureRuntime == nil ? .automatic : .presented)"
            ).count - 1,
            1
        )
        XCTAssertTrue(popover.hasPrefix("#if DEBUG\n"))
        XCTAssertTrue(popover.contains("NSStatusBar.system.statusItem"))
        XCTAssertTrue(popover.contains("private let popover = NSPopover()"))
        XCTAssertTrue(popover.contains("MenuBarView("))
        XCTAssertFalse(popover.contains("ViftyStatusItemController"))
        XCTAssertTrue(popover.contains("let window = button.window"))
        XCTAssertTrue(popover.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(popover.contains("anchorStableSampleCount >= 5"))
        XCTAssertTrue(popover.contains("schedulePostShowVerification"))
        XCTAssertTrue(popover.contains("!runtime.hasReadyObservation"))
        XCTAssertTrue(popover.contains(
            "runtime.recordFailure(ViftyReviewFixtureError.observationUnavailable)"
        ))
        XCTAssertTrue(settings.contains(".scenePadding()\n        .frame(width: 600, height: 420)"))
    }

    private func fixtureRequest(
        root: URL,
        captureID: String,
        state: ViftyReviewFixtureState = .healthyAuto,
        surface: ViftyReviewFixtureSurface = .main,
        window: ViftyReviewFixtureWindow = .standard,
        interaction: ViftyReviewFixtureInteraction = .none,
        expectedExecutableSHA256: String? = nil
    ) throws -> ViftyReviewFixtureRequest {
        var arguments = [
            "Vifty",
            "--ui-review-fixture", state.rawValue,
            "--ui-review-surface", surface.rawValue,
            "--ui-review-window", window.rawValue,
            "--ui-review-interaction", interaction.rawValue,
            "--ui-review-capture-id", captureID,
            "--ui-review-output", root.path
        ]
        if let expectedExecutableSHA256 {
            arguments.append(contentsOf: [
                "--ui-review-executable-sha256", expectedExecutableSHA256
            ])
        }
        return try XCTUnwrap(ViftyReviewFixtureRequest.parse(arguments: arguments))
    }

    private func matchingWindowSample(
        for request: ViftyReviewFixtureRequest
    ) -> ViftyReviewWindowSample {
        let geometry = request.window.expectedContentSize
            ?? CGSize(width: request.window == .native ? 600 : 320, height: request.window == .native ? 420 : 360)
        return ViftyReviewWindowSample(
            source: "nswindow-content-layout-rect",
            provenance: request.surface.provenance,
            windowIdentifier: "vifty-ui-review-window-\(request.captureID)",
            accessibilityIdentifier: "vifty-ui-review-ax-window-\(request.captureID)",
            windowNumber: 91,
            windowClass: "NSWindow",
            containerKind: request.surface.expectedContainerKind,
            isVisible: true,
            contentWidth: Int(geometry.width),
            contentHeight: Int(geometry.height),
            backingScaleFactor: 2
        )
    }

    private func writeExecutableFixture(in root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("Vifty-debug-fixture")
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: url, options: .atomic)
        return url
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func transientWindowCaptureFiles(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("window-capture-") }
            .sorted()
    }

    @MainActor
    private func syntheticNativeWindowCapture(_ window: NSWindow, _ url: URL) throws {
        let view = try XCTUnwrap(window.contentView)
        let bounds = view.bounds
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
        bitmap.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            window.backgroundColor.setFill()
            NSBezierPath(rect: bounds).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private func syntheticNativeWindowCaptureWithBorderPadding(
        _ window: NSWindow,
        _ url: URL
    ) throws {
        let sidePadding = max(1, Int(window.backingScaleFactor.rounded()))
        try syntheticNativeWindowCaptureWithPadding(
            window,
            url,
            horizontalPadding: sidePadding * 2,
            verticalPadding: sidePadding * 2
        )
    }

    @MainActor
    private func syntheticNativeWindowCaptureWithPadding(
        _ window: NSWindow,
        _ url: URL,
        horizontalPadding: Int,
        verticalPadding: Int
    ) throws {
        let unpaddedURL = url.deletingLastPathComponent().appendingPathComponent(
            "unpadded-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: unpaddedURL) }
        try syntheticNativeWindowCapture(window, unpaddedURL)
        let sourceData = try Data(contentsOf: unpaddedURL)
        let sourceBitmap = try XCTUnwrap(NSBitmapImageRep(data: sourceData))
        let sourceImage = try XCTUnwrap(sourceBitmap.cgImage)
        let paddedWidth = sourceBitmap.pixelsWide + horizontalPadding
        let paddedHeight = sourceBitmap.pixelsHigh + verticalPadding
        XCTAssertGreaterThan(paddedWidth, 0)
        XCTAssertGreaterThan(paddedHeight, 0)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: paddedWidth,
            height: paddedHeight,
            bitsPerComponent: 8,
            bytesPerRow: paddedWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(NSColor.systemPink.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: paddedWidth, height: paddedHeight))
        context.draw(
            sourceImage,
            in: CGRect(
                x: horizontalPadding / 2,
                y: verticalPadding / 2,
                width: sourceBitmap.pixelsWide,
                height: sourceBitmap.pixelsHigh
            )
        )
        let paddedImage = try XCTUnwrap(context.makeImage())
        let paddedBitmap = NSBitmapImageRep(cgImage: paddedImage)
        let data = try XCTUnwrap(paddedBitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    private func normalizedRGBA(_ bitmap: NSBitmapImageRep) throws -> Data {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var data = Data(count: width * height * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(
                try XCTUnwrap(bitmap.cgImage),
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
        }
        return data
    }

    private func preparedRuntime(
        _ state: ViftyReviewFixtureState,
        root: URL
    ) async throws -> ViftyReviewFixtureRuntime {
        let output = root.appendingPathComponent(state.rawValue, isDirectory: true)
        let executable = try writeExecutableFixture(in: root)
        let runtime = try XCTUnwrap(try ViftyReviewFixtureRuntime.parse(arguments: [
            "Vifty",
            "--ui-review-fixture", state.rawValue,
            "--ui-review-capture-id", "prepared-\(state.rawValue)",
            "--ui-review-output", output.path
        ], executableURL: executable))
        try await runtime.prepare()
        return runtime
    }

    private func fixtureRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-ui-review-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func matchingObservation(
        for request: ViftyReviewFixtureRequest
    ) -> ViftyReviewFixtureObservation {
        ViftyReviewFixtureObservation(
            environment: ViftyReviewFixtureEnvironmentObservation(
                source: "swiftui-environment",
                appearance: request.appearance.rawValue,
                contrast: request.contrast.rawValue,
                transparency: request.transparency.rawValue,
                textSize: request.textSize.rawValue
            ),
            window: matchingWindowSample(for: request)
        )
    }

    private func read(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class PatternCaptureView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.systemBlue.setFill()
        NSRect(x: 8, y: 8, width: 24, height: 20).fill()
    }
}

@MainActor
private final class VerticalBandCaptureView: NSView {
    static let outsideColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    static let contentBandColors = [
        NSColor(srgbRed: 0.05, green: 0.2, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.05, green: 0.85, blue: 0.2, alpha: 1),
        NSColor(srgbRed: 1, green: 0.45, blue: 0.05, alpha: 1)
    ]

    override func draw(_ dirtyRect: NSRect) {
        Self.outsideColor.setFill()
        bounds.fill()
        guard let window else { return }
        let content = convert(window.contentLayoutRect, from: nil).intersection(bounds)
        let bandHeight = content.height / CGFloat(Self.contentBandColors.count)
        for (index, color) in Self.contentBandColors.enumerated() {
            color.setFill()
            NSRect(
                x: content.minX,
                y: content.minY + CGFloat(index) * bandHeight,
                width: content.width,
                height: index == Self.contentBandColors.count - 1
                    ? content.maxY - (content.minY + CGFloat(index) * bandHeight)
                    : bandHeight
            ).fill()
        }
    }
}
#endif
