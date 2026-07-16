import Foundation
import XCTest

/// Source inspection is intentionally limited to boundaries that cannot be
/// expressed reliably through behavior tests. Presentation text, layout, and
/// state transitions belong in focused model/view-policy tests instead.
final class AppArchitectureBoundaryTests: XCTestCase {
    func testNativeScenesOwnStartupAndSettingsComposition() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let content = try read("Sources/Vifty/ContentView.swift")
        let menu = try read("Sources/Vifty/MenuBarView.swift")

        XCTAssertTrue(app.contains("Window(\"Vifty\", id: \"main\")"))
        XCTAssertTrue(app.contains("Settings {"))
        XCTAssertTrue(app.contains("ViftySettingsView(model: model)"))
        XCTAssertEqual(app.components(separatedBy: "model.start()").count - 1, 1)
        XCTAssertFalse(content.contains("model.start()"))
        XCTAssertFalse(menu.contains("model.start()"))
    }

    func testAppActivationRefreshesExternalSettingsWithoutRunningInFixtureMode() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")

        XCTAssertTrue(app.contains("func applicationDidBecomeActive"))
        XCTAssertTrue(app.contains("await model.refreshSystemSettingsStateOnActivation()"))
        XCTAssertTrue(app.contains("guard reviewFixtureRuntime == nil else { return }"))
    }

    func testViewSurfacesDoNotConstructHardwareOrXPCControlClients() throws {
        let viewPaths = [
            "Sources/Vifty/ContentView.swift",
            "Sources/Vifty/ControlSessionCard.swift",
            "Sources/Vifty/CurveProfileToolbar.swift",
            "Sources/Vifty/FanControlPanel.swift",
            "Sources/Vifty/FanCurveChartEditor.swift",
            "Sources/Vifty/FanStatusList.swift",
            "Sources/Vifty/FixedRPMEditor.swift",
            "Sources/Vifty/MenuBarView.swift",
            "Sources/Vifty/PerFanCurveOverrideEditor.swift",
            "Sources/Vifty/ReadinessModePanel.swift",
            "Sources/Vifty/SettingsAgentWorkflowView.swift",
            "Sources/Vifty/SettingsGeneralView.swift",
            "Sources/Vifty/SettingsMenuBarView.swift",
            "Sources/Vifty/SettingsNotificationsView.swift",
            "Sources/Vifty/TelemetryEvidencePanel.swift",
            "Sources/Vifty/TemperatureCurveEditor.swift",
            "Sources/Vifty/ViftyReviewPopoverPresenter.swift",
            "Sources/Vifty/ViftySettingsView.swift"
        ]
        let forbiddenConstructions = [
            "SMCClient(",
            "RealMacHardwareService(",
            "ViftyDaemonClient(",
            "FanControlCoordinator(",
            "LocalFanHelperClient("
        ]

        for path in viewPaths {
            let source = try read(path)
            for forbidden in forbiddenConstructions {
                XCTAssertFalse(source.contains(forbidden), "\(path) constructs \(forbidden)")
            }
        }
    }

    func testViewSurfacesContainNoRawFanWriteCommands() throws {
        let viewPaths = [
            "Sources/Vifty/ContentView.swift",
            "Sources/Vifty/CurveProfileToolbar.swift",
            "Sources/Vifty/FanControlPanel.swift",
            "Sources/Vifty/FanStatusList.swift",
            "Sources/Vifty/FixedRPMEditor.swift",
            "Sources/Vifty/MenuBarView.swift",
            "Sources/Vifty/PerFanCurveOverrideEditor.swift",
            "Sources/Vifty/SettingsAgentWorkflowView.swift",
            "Sources/Vifty/SettingsToolsPanel.swift",
            "Sources/Vifty/TemperatureCurveEditor.swift",
            "Sources/Vifty/ViftyReviewPopoverPresenter.swift"
        ]
        let forbidden = [
            "FanCommand(",
            "setFixedRPM(",
            "applyManualFanControl(",
            "applyAgentFanControl(",
            "restoreAllAuto("
        ]

        for path in viewPaths {
            let source = try read(path)
            for command in forbidden {
                XCTAssertFalse(source.contains(command), "\(path) contains raw control call \(command)")
            }
        }
    }

    func testAppModelControlTestsInjectAHostFreeCoordinator() throws {
        let testPaths = try swiftSources(under: "Tests/ViftyCoreTests").filter { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.hasPrefix("AppModel") && name.hasSuffix("Tests.swift")
        }
        let controlCalls = [
            ".start()",
            ".pollOnce()",
            ".primeMenuBarStatusItemTelemetry(",
            ".applyStartupModePreferenceIfNeeded()",
            ".applyCurrentModeSelection()",
            ".performModeSelectionActionNow()",
            ".restoreAutoNow()",
            ".stopAndRestore()"
        ]

        for path in testPaths {
            let source = try read(path)
            for section in source.components(separatedBy: "\n    func test").dropFirst() {
                guard controlCalls.contains(where: section.contains) else { continue }
                XCTAssertTrue(
                    section.contains("coordinator:"),
                    "\(path) has an AppModel control-path test without an injected coordinator"
                )
            }
        }

        let appModel = try read("Sources/Vifty/AppModel.swift")
        let start = try XCTUnwrap(appModel.range(of: "    func start() {"))
        let end = try XCTUnwrap(appModel.range(of: "    func primeMenuBarStatusItemTelemetry("))
        let startupSource = String(appModel[start.lowerBound..<end.lowerBound])
        let recovery = try XCTUnwrap(startupSource.range(of: "await coordinator.recoverIfNeeded()"))
        let firstPoll = try XCTUnwrap(startupSource.range(of: "await pollOnce()"))
        let notifications = try XCTUnwrap(startupSource.range(of: "await refreshNotificationAuthorization()"))
        XCTAssertLessThan(recovery.lowerBound, firstPoll.lowerBound)
        XCTAssertLessThan(firstPoll.lowerBound, notifications.lowerBound)
    }

    func testContentViewDelegatesFanControlActionsToTestableHandler() throws {
        let content = try read("Sources/Vifty/ContentView.swift")
        let handler = try read("Sources/Vifty/FanControlPanelActionHandler.swift")

        XCTAssertTrue(content.contains("FanControlPanelActionHandler(model: model).handle(action)"))
        XCTAssertTrue(content.contains("helperRefreshSleeper.sleep(for: .milliseconds(750))"))
        XCTAssertFalse(content.contains("Task.sleep"))
        XCTAssertFalse(content.contains("case .fixedRPMChanged"))
        XCTAssertTrue(handler.contains("struct FanControlPanelActionHandler"))
        XCTAssertTrue(handler.contains("guard let fan = fan(withID: fanID), fan.controllable"))
    }

    func testPrivilegedSMCWritesStayInsideSafetyTarget() throws {
        let sources = try swiftSources(under: "Sources")
        let directWriteCallers = try sources.filter { path in
            let source = try read(path)
            return source.contains("smc.write(write.key")
        }

        XCTAssertEqual(
            directWriteCallers,
            ["Sources/ViftyFanControlSafety/LocalFanHelperClient.swift"]
        )
        XCTAssertFalse(try read("Sources/ViftyCore/RealMacHardwareService.swift").contains("LocalFanHelperClient"))
    }

    func testReviewFixtureIsDebugOnlyAndCannotStartProductionRuntime() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")

        XCTAssertTrue(fixture.hasPrefix("#if DEBUG\n"))
        XCTAssertTrue(fixture.hasSuffix("#endif\n"))
        XCTAssertTrue(app.contains("let model = reviewFixtureRuntime?.model ?? AppModel()"))
        XCTAssertTrue(app.contains("guard reviewFixtureRuntime == nil else { return }\n#endif\n        model.start()"))
        XCTAssertTrue(app.contains("guard reviewFixtureRuntime == nil else { return }"))
        XCTAssertTrue(app.contains("try reviewFixtureRuntime.finalize()"))
    }

    func testReviewFixtureRoutesOnlyThroughNativeSceneAndDebugPopoverContainers() throws {
        let app = try read("Sources/Vifty/ViftyApp.swift")
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")
        let popover = try read("Sources/Vifty/ViftyReviewPopoverPresenter.swift")
        let settings = try read("Sources/Vifty/ViftySettingsView.swift")

        XCTAssertTrue(app.contains("ViftyReviewFixtureSceneHost("))
        XCTAssertTrue(app.contains("ViftyReviewFixtureLaunchBridge(runtime:"))
        XCTAssertTrue(app.contains("initialTab: settingsTab"))
        XCTAssertTrue(app.contains("if reviewFixtureRuntime == nil"))
        XCTAssertFalse(fixture.contains("struct ViftyReviewFixtureRootView"))
        XCTAssertFalse(fixture.contains("MenuBarView("))
        XCTAssertFalse(fixture.contains("ViftySettingsView("))
        XCTAssertTrue(popover.hasPrefix("#if DEBUG\n"))
        XCTAssertTrue(popover.hasSuffix("#endif\n"))
        XCTAssertTrue(popover.contains("NSStatusBar.system.statusItem"))
        XCTAssertTrue(popover.contains("NSPopover()"))
        XCTAssertTrue(popover.contains("MenuBarView("))
        XCTAssertFalse(popover.contains("ViftyStatusItemController"))
        XCTAssertTrue(settings.contains(".scenePadding()\n        .frame(width: 600, height: 420)"))
    }

    func testReviewFixtureReleaseExclusionAndEvidenceResourcesAreRequired() throws {
        let verifier = try read("scripts/lib/ui_review_verifier.rb")
        let makefile = try read("Makefile")
        let manifestData = try Data(
            contentsOf: repositoryRoot.appendingPathComponent("docs/ui-review/evidence-manifest.json")
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let safetyContract = try XCTUnwrap(manifest["safetyContract"] as? [String: Any])

        XCTAssertTrue(verifier.contains("RELEASE_FORBIDDEN_MARKERS = [\"--ui-review-fixture\", \"ViftyReviewFixture\"].freeze"))
        XCTAssertTrue(verifier.contains("(RELEASE_FORBIDDEN_MARKERS + STATES).each do |marker|"))
        XCTAssertTrue(verifier.contains("ViftyUIReview.fixture_recorder_errors(recorder)"))
        XCTAssertTrue(makefile.contains("scripts/run-ui-review-fixture.sh"))
        XCTAssertEqual(manifest["status"] as? String, "pending")
        XCTAssertEqual(safetyContract["modelStartSkipped"] as? Bool, true)
    }

    func testCurvePointsExposeIndependentAccessibleAdjustersAndExactControls() throws {
        let chart = try read("Sources/Vifty/FanCurveChartEditor.swift")
        let editor = try read("Sources/Vifty/TemperatureCurveEditor.swift")

        XCTAssertTrue(chart.contains(".accessibilityRepresentation"))
        XCTAssertTrue(chart.contains("ForEach(ViftyCurveAccessibilityControl.allCases)"))
        XCTAssertTrue(chart.contains("CurveAccessibilitySlider("))
        XCTAssertTrue(chart.contains("ViftyAccessibilityIdentifier.curveChart"))
        XCTAssertTrue(chart.contains(".accessibilityAdjustableAction"))
        XCTAssertTrue(editor.contains("DisclosureGroup(\"Exact point controls\")"))
        XCTAssertTrue(editor.contains(".accessibilityHidden(true)"))
    }

    func testHelperLifecycleResourcesUseOneFailClosedBoundary() throws {
        let makefile = try read("Makefile")
        let repair = try read("scripts/repair-vifty-helper.sh")
        let uninstall = try read("scripts/uninstall-vifty.sh")
        let lifecycle = try read("scripts/vifty-helper-lifecycle.sh")

        XCTAssertTrue(makefile.contains("scripts/vifty-helper-lifecycle.sh \"$(CONTENTS)/Resources/vifty-helper-lifecycle.sh\""))
        XCTAssertTrue(makefile.contains("scripts/repair-vifty-helper.sh \"$(CONTENTS)/Resources/repair-vifty-helper.sh\""))
        XCTAssertTrue(makefile.contains("scripts/uninstall-vifty.sh \"$(CONTENTS)/Resources/uninstall-vifty.sh\""))
        XCTAssertTrue(repair.contains("vifty-helper-lifecycle.sh"))
        XCTAssertTrue(uninstall.contains("vifty-helper-lifecycle.sh"))
        XCTAssertTrue(lifecycle.contains("exit 75"))
        XCTAssertFalse(lifecycle.contains("pkill"))
    }

    func testAXCollectorIsReadOnlyNonBundledAndSeparatedFromApplicationTargets() throws {
        let package = try read("Package.swift")
        let reader = try read("Sources/ViftyAXCollector/AXReader.swift")
        let traversal = try read("Sources/ViftyAXCollector/AXTraversal.swift")
        let main = try read("Sources/ViftyAXCollector/main.swift")
        let core = try read("Sources/ViftyAXEvidenceCore/AXEvidenceModels.swift")
            + (try read("Sources/ViftyAXEvidenceCore/AXPredicateCatalog.swift"))
        let collector = reader + traversal + main

        XCTAssertTrue(package.contains(".executable(name: \"ViftyAXCollector\", targets: [\"ViftyAXCollector\"])"))
        XCTAssertTrue(package.contains("name: \"ViftyAXCollector\",\n            dependencies: [\"ViftyAXEvidenceCore\", \"ViftyBuildProvenance\"]"))
        XCTAssertTrue(package.contains(".linkedFramework(\"ApplicationServices\")"))
        XCTAssertTrue(package.contains("name: \"Vifty\",\n            dependencies: [\"ViftyCore\", \"ViftyBuildProvenance\"]"))
        XCTAssertFalse(core.contains("import ApplicationServices"))
        XCTAssertFalse(core.contains("AXUIElement"))
        XCTAssertFalse(collector.contains("import AppKit"))
        XCTAssertFalse(collector.contains("import SwiftUI"))

        XCTAssertTrue(reader.contains("AXIsProcessTrusted()"))
        XCTAssertFalse(reader.contains("AXIsProcessTrustedWithOptions"))
        XCTAssertTrue(reader.contains("AXUIElementSetMessagingTimeout"))
        let forbidden = [
            "AXUIElementPerformAction",
            "AXUIElementSetAttributeValue",
            "CGEventCreate",
            "CGEventPost",
            "AXMakeProcessTrusted",
            "NSRunningApplication",
            "NSWorkspace.shared.open",
            ".activate(options:",
            ".terminate()"
        ]
        for symbol in forbidden {
            XCTAssertFalse(collector.contains(symbol), "AX collector contains forbidden mutator: \(symbol)")
        }
    }

    private func swiftSources(under relativeDirectory: String) throws -> [String] {
        let root = repositoryRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Could not enumerate \(relativeDirectory)")
            return []
        }
        return try enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
        }.sorted()
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
