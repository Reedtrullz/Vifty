import Foundation
import XCTest
import ViftyAXEvidenceCore
import ViftyCore
@testable import Vifty

final class ViftyAccessibilitySemanticsTests: XCTestCase {
    func testAppIdentifiersExactlyMatchAXPredicateCatalog() {
        XCTAssertEqual(ViftyAccessibilityIdentifier.controlSession, AXEvidenceIdentifier.controlSession)
        XCTAssertEqual(ViftyAccessibilityIdentifier.controlSessionTitle, AXEvidenceIdentifier.controlSessionTitle)
        XCTAssertEqual(ViftyAccessibilityIdentifier.controlSessionSummary, AXEvidenceIdentifier.controlSessionSummary)
        XCTAssertEqual(ViftyAccessibilityIdentifier.fanStatus, AXEvidenceIdentifier.fanStatus)
        XCTAssertEqual(ViftyAccessibilityIdentifier.fanDraftTarget(fanID: 0), AXEvidenceIdentifier.leftFanDraftTarget)
        XCTAssertEqual(ViftyAccessibilityIdentifier.fanDraftTarget(fanID: 1), AXEvidenceIdentifier.rightFanDraftTarget)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveChart, AXEvidenceIdentifier.curveChart)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveSeparateFans, AXEvidenceIdentifier.curveSeparateFans)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveEffectiveSummaries, AXEvidenceIdentifier.curveEffectiveSummaries)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveEffectiveSummary(fanID: 0), AXEvidenceIdentifier.leftFanEffectiveSummary)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveEffectiveSummary(fanID: 1), AXEvidenceIdentifier.rightFanEffectiveSummary)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveControls, AXEvidenceIdentifier.curveControls)
        XCTAssertEqual(ViftyAccessibilityIdentifier.sensorList, AXEvidenceIdentifier.sensorList)
        XCTAssertEqual(ViftyAccessibilityIdentifier.sensor(id: "cpu-efficiency", name: "CPU Efficiency"), AXEvidenceIdentifier.sensorCPU)
        XCTAssertEqual(ViftyAccessibilityIdentifier.sensor(id: "gpu-hotspot", name: "GPU Hotspot"), AXEvidenceIdentifier.sensorGPU)
        XCTAssertEqual(ViftyAccessibilityIdentifier.sensor(id: "palm", name: "Palm Rest"), AXEvidenceIdentifier.sensorPalm)
        XCTAssertEqual(ViftyAccessibilityIdentifier.temperatureMetrics, AXEvidenceIdentifier.temperatureMetrics)
        XCTAssertEqual(ViftyAccessibilityIdentifier.curveSensorMetric, AXEvidenceIdentifier.curveSensorMetric)
        XCTAssertEqual(ViftyAccessibilityIdentifier.highestTemperatureMetric, AXEvidenceIdentifier.highestTemperatureMetric)
        XCTAssertEqual(ViftyAccessibilityIdentifier.notifications, AXEvidenceIdentifier.notifications)
        XCTAssertEqual(ViftyAccessibilityIdentifier.notificationOpenSettings, AXEvidenceIdentifier.notificationOpenSettings)
        XCTAssertEqual(ViftyAccessibilityIdentifier.notificationSendTest, AXEvidenceIdentifier.notificationSendTest)
        XCTAssertEqual(ViftyAccessibilityIdentifier.notificationEvents, AXEvidenceIdentifier.notificationEvents)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settings, AXEvidenceIdentifier.settings)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsTabs, AXEvidenceIdentifier.settingsTabs)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsTabGeneral, AXEvidenceIdentifier.settingsTabGeneral)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsTabMenuBar, AXEvidenceIdentifier.settingsTabMenuBar)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsTabNotifications, AXEvidenceIdentifier.settingsTabNotifications)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsTabAgentWorkflows, AXEvidenceIdentifier.settingsTabAgentWorkflows)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsPaneGeneral, AXEvidenceIdentifier.settingsPaneGeneral)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsLaunchAtLogin, AXEvidenceIdentifier.settingsLaunchAtLogin)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsUpdateAutomatic, AXEvidenceIdentifier.settingsUpdateAutomatic)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsUpdateStatus, AXEvidenceIdentifier.settingsUpdateStatus)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsUpdateCheck, AXEvidenceIdentifier.settingsUpdateCheck)
        XCTAssertEqual(ViftyAccessibilityIdentifier.settingsUpdateLatest, AXEvidenceIdentifier.settingsUpdateLatest)
        XCTAssertEqual(ViftyAccessibilityIdentifier.mainScroll, AXEvidenceIdentifier.mainScroll)
        XCTAssertEqual(ViftyAccessibilityIdentifier.mainScrollEnd, AXEvidenceIdentifier.mainScrollEnd)

        for pane in ViftySettingsAccessibilityPane.allCases {
            let expected: AXScrollPredicateContract
            switch pane {
            case .general:
                expected = AXScrollPredicateContract(
                    scrollIdentifier: AXEvidenceIdentifier.settingsGeneralScroll,
                    anchorIdentifier: AXEvidenceIdentifier.settingsGeneralScrollEnd,
                    allowsCaptureRootScrollAreaFallback: true
                )
            case .menuBar:
                expected = AXScrollPredicateContract(
                    scrollIdentifier: AXEvidenceIdentifier.settingsMenuBarScroll,
                    anchorIdentifier: AXEvidenceIdentifier.settingsMenuBarScrollEnd,
                    allowsCaptureRootScrollAreaFallback: true
                )
            case .notifications:
                expected = AXScrollPredicateContract(
                    scrollIdentifier: AXEvidenceIdentifier.settingsNotificationsScroll,
                    anchorIdentifier: AXEvidenceIdentifier.settingsNotificationsScrollEnd,
                    allowsCaptureRootScrollAreaFallback: true
                )
            case .agentWorkflows:
                expected = AXScrollPredicateContract(
                    scrollIdentifier: AXEvidenceIdentifier.settingsAgentWorkflowsScroll,
                    anchorIdentifier: AXEvidenceIdentifier.settingsAgentWorkflowsScrollEnd,
                    allowsCaptureRootScrollAreaFallback: true
                )
            }
            XCTAssertEqual(pane.scrollIdentifier, expected.scrollIdentifier)
            XCTAssertEqual(pane.endAnchorIdentifier, expected.anchorIdentifier)
        }
    }

    func testCurveControlSemanticsExposeSixIndependentCanonicalAdjusters() {
        let controls = ViftyCurveAccessibilityControl.allCases

        XCTAssertEqual(controls.count, 6)
        XCTAssertEqual(controls.map(\.identifier), AXEvidenceIdentifier.curveControls)
        XCTAssertEqual(controls.map(\.label), [
            "Start temperature",
            "Start RPM",
            "Ramp temperature",
            "Ramp RPM",
            "High temperature",
            "High RPM"
        ])
        XCTAssertEqual(
            controls.map { $0.valueText(startTemperature: 55, startRPM: 1_400, rampTemperature: 70, rampRPM: 3_500, highTemperature: 85, highRPM: 6_000) },
            ["55 °C", "1400 RPM", "70 °C", "3500 RPM", "85 °C", "6000 RPM"]
        )
    }

    func testConfirmedOwnerPresentationMatchesAXHeadlineContract() {
        let presentation = ControlSessionPresentation.resolve(ControlSessionInput(
            helperHealth: .healthy(fanCount: 2),
            helperHealthNeedsAttention: false,
            helperRepairActionAvailable: false,
            manualFanControlAvailable: true,
            controlOwnershipNeedsAttention: false,
            controlOwnershipSummary: "",
            agentCoolingSummary: nil,
            agentCoolingNeedsAttention: false,
            manualControlAttentionSummary: nil,
            selectedMode: .curve,
            applyState: .applied,
            manualSessionExpiresAt: nil,
            ownershipStatus: FanControlOwnershipStatus(
                owner: .manual(sessionID: "fixture-manual-session"),
                phase: .active,
                transactionID: "fixture-manual-transaction",
                expectedFanIDs: [0, 1],
                recoveryPending: false
            )
        ))

        XCTAssertEqual(presentation.title, "Vifty manual control active")
        XCTAssertEqual(presentation.summary, "Owner: Vifty manual control")
    }

    func testLaunchAtLoginToggleHasExplicitNativeAccessibilitySemantics() throws {
        let general = try read("Sources/Vifty/SettingsGeneralView.swift")

        XCTAssertTrue(general.contains("Toggle(\"Start Vifty at startup\""))
        XCTAssertTrue(general.contains(".accessibilityLabel(\"Start Vifty at startup\")"))
        XCTAssertTrue(general.contains(
            ".accessibilityIdentifier(ViftyAccessibilityIdentifier.settingsLaunchAtLogin)"
        ))
    }

    func testSoftwareUpdateControlsHaveStableAccessibilitySemantics() throws {
        let general = try read("Sources/Vifty/SettingsGeneralView.swift")

        XCTAssertTrue(general.contains("ViftyAccessibilityIdentifier.settingsUpdateAutomatic"))
        XCTAssertTrue(general.contains("ViftyAccessibilityIdentifier.settingsUpdateStatus"))
        XCTAssertTrue(general.contains("ViftyAccessibilityIdentifier.settingsUpdateCheck"))
        XCTAssertTrue(general.contains("ViftyAccessibilityIdentifier.settingsUpdateLatest"))
        XCTAssertTrue(general.contains("notification: .announcementRequested"))
        XCTAssertTrue(general.contains(".onChange(of: softwareUpdates.errorAnnouncement?.id)"))
        XCTAssertTrue(general.contains(".accessibilityHint(softwareUpdates.primaryActionHint)"))
        XCTAssertEqual(
            general.components(
                separatedBy: "Refreshes GitHub release availability without downloading or installing."
            ).count - 1,
            2,
            "The refresh button's AX hint and AppKit help must stay byte-identical."
        )
    }

    func testTemperatureMetricPresentationKeepsSelectedAndHighestRolesSeparate() throws {
        let sensors = [
            TemperatureSensor(id: "cpu-efficiency", name: "CPU Efficiency", celsius: 64, source: .smc),
            TemperatureSensor(id: "gpu-hotspot", name: "GPU Hotspot", celsius: 83, source: .hid),
            TemperatureSensor(id: "palm", name: "Palm Rest", celsius: 37, source: .hid)
        ]

        let presentation = try XCTUnwrap(
            TemperatureMetricAccessibilityPresentation.resolve(
                sensors: sensors,
                effectiveSensorID: "cpu-efficiency"
            )
        )

        XCTAssertEqual(presentation.curveSensorLabel, "Curve sensor")
        XCTAssertEqual(presentation.curveSensorValue, "Curve sensor · CPU Efficiency")
        XCTAssertEqual(presentation.highestTemperatureLabel, "Highest temperature")
        XCTAssertEqual(presentation.highestTemperatureValue, "Highest 83.0 °C")
        XCTAssertNotEqual(presentation.curveSensorValue, presentation.highestTemperatureValue)
    }

    func testFanDraftAndSensorPresentationsMatchFixturePredicateValues() throws {
        let left = try XCTUnwrap(FanDraftTargetAccessibilityPresentation.resolve(
            fanID: 0,
            fanName: "Left Fan",
            draftTargetText: "Draft 2493 RPM"
        ))
        let right = try XCTUnwrap(FanDraftTargetAccessibilityPresentation.resolve(
            fanID: 1,
            fanName: "Right Fan",
            draftTargetText: "Draft 3080 RPM"
        ))
        XCTAssertEqual(left.identifier, AXEvidenceIdentifier.leftFanDraftTarget)
        XCTAssertEqual(left.label, "Left Fan draft target")
        XCTAssertEqual(left.value, "Draft 2493 RPM")
        XCTAssertEqual(right.identifier, AXEvidenceIdentifier.rightFanDraftTarget)
        XCTAssertEqual(right.label, "Right Fan draft target")
        XCTAssertEqual(right.value, "Draft 3080 RPM")
        XCTAssertNotEqual(left.value, right.value)

        let sensors = [
            TemperatureSensor(id: "cpu-efficiency", name: "CPU Efficiency", celsius: 64, source: .smc),
            TemperatureSensor(id: "gpu-hotspot", name: "GPU Hotspot", celsius: 83, source: .hid),
            TemperatureSensor(id: "palm", name: "Palm Rest", celsius: 37, source: .hid)
        ].map {
            SensorAccessibilityPresentation.resolve(
                sensor: $0,
                selectedSensorID: "cpu-efficiency"
            )
        }
        XCTAssertEqual(sensors.map(\.identifier), [
            AXEvidenceIdentifier.sensorCPU,
            AXEvidenceIdentifier.sensorGPU,
            AXEvidenceIdentifier.sensorPalm
        ])
        XCTAssertEqual(sensors.map(\.label), ["CPU Efficiency", "GPU Hotspot", "Palm Rest"])
        XCTAssertEqual(sensors.map(\.value), [
            "64.0 degrees Celsius, SMC",
            "83.0 degrees Celsius, HID",
            "37.0 degrees Celsius, HID"
        ])
        XCTAssertEqual(sensors.map(\.isSelected), [true, false, false])
    }

    @MainActor
    func testDivergentReviewFixtureDerivesTheTwoDistinctFanDraftValues() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-task6-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let request = ViftyReviewFixtureRequest(
            state: .divergentPerFanCurveDraft,
            surface: .main,
            window: .standard,
            appearance: .light,
            contrast: .standard,
            transparency: .standard,
            textSize: .standard,
            interaction: .none,
            captureID: "task6-divergent-fan-draft",
            outputDirectory: outputDirectory,
            screenshotURL: nil,
            completionFileURL: nil,
            timeoutSeconds: 5,
            readinessDeadlineUptime: nil,
            expectedExecutableSHA256: nil
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let executable = outputDirectory.appendingPathComponent("Vifty-debug-fixture")
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: executable)
        let runtime = try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executable,
            processIdentifier: 42
        )

        try await runtime.prepare()

        let fans = try XCTUnwrap(runtime.model.snapshot?.fans)
        XCTAssertEqual(fans.map(\.id), [0, 1])
        let draftValues = fans.map { fan in
            FanStatusPresentation.make(
                fan: fan,
                appliedTargetRPM: runtime.model.appliedTargetRPM(for: fan),
                draftTargetRPM: runtime.model.draftTargetRPMPreview(for: fan)
            ).draftTargetText
        }
        XCTAssertEqual(draftValues, ["Draft 2493 RPM", "Draft 3080 RPM"])
        XCTAssertTrue(runtime.report().recorder.isSafe)
        XCTAssertFalse(runtime.model.isRunning)
    }

    func testSettingsTabsAndDeniedNotificationSemanticsAreCanonicalInSource() throws {
        XCTAssertEqual(
            ViftySettingsTab.allCases,
            [.general, .menuBar, .notifications, .agentWorkflows]
        )

        let settings = try read("Sources/Vifty/ViftySettingsView.swift")
        let orderedTabTokens = [
            "ViftyAccessibilityIdentifier.settingsTabGeneral",
            "ViftyAccessibilityIdentifier.settingsTabMenuBar",
            "ViftyAccessibilityIdentifier.settingsTabNotifications",
            "ViftyAccessibilityIdentifier.settingsTabAgentWorkflows"
        ]
        var previousIndex = settings.startIndex
        for token in orderedTabTokens {
            let range = try XCTUnwrap(settings.range(of: token, range: previousIndex..<settings.endIndex))
            previousIndex = range.upperBound
        }

        let notifications = try read("Sources/Vifty/SettingsNotificationsView.swift")
        XCTAssertTrue(notifications.contains("model.notificationAuthorization == .denied"))
        XCTAssertTrue(notifications.contains("ViftyAccessibilityIdentifier.notificationOpenSettings"))
        XCTAssertTrue(notifications.contains("model.notificationAuthorization == .authorized"))
        XCTAssertTrue(notifications.contains("ViftyAccessibilityIdentifier.notificationSendTest"))
        for (label, identifier) in [
            ("Helper failure", "notificationHelperFailure"),
            ("High thermal pressure", "notificationThermalPressure"),
            ("Auto restore failure", "notificationAutoRestore"),
            ("Plugged-in battery drain", "notificationBatteryDrain"),
            ("Agent cooling attention", "notificationAgentCooling")
        ] {
            XCTAssertTrue(notifications.contains("Toggle(\"\(label)\""), label)
            XCTAssertTrue(
                notifications.contains("ViftyAccessibilityIdentifier.\(identifier)"),
                identifier
            )
        }
    }

    func testFixtureRootIdentifierIsAttachedToAnExplicitContainingGroup() throws {
        let fixture = try read("Sources/Vifty/ViftyReviewFixture.swift")

        XCTAssertTrue(fixture.contains(
            ".accessibilityElement(children: .contain)\n"
                + "            .accessibilityIdentifier(runtime.request.rootAccessibilityIdentifier)"
        ))
        XCTAssertEqual(
            fixture.components(
                separatedBy: ".accessibilityIdentifier(runtime.request.rootAccessibilityIdentifier)"
            ).count - 1,
            1
        )
    }

    func testSeparateFanCurvesControlPrecedesChartAndRepeatedEditorsNameTheirFan() throws {
        let curveEditor = try read("Sources/Vifty/TemperatureCurveEditor.swift")
        let toggle = try XCTUnwrap(curveEditor.range(of: "Toggle(\"Separate fan curves\""))
        let chart = try XCTUnwrap(curveEditor.range(of: "FanCurveChartEditor("))
        let effectiveSummaries = try XCTUnwrap(
            curveEditor.range(of: "ViftyAccessibilityIdentifier.curveEffectiveSummaries")
        )

        XCTAssertLessThan(toggle.lowerBound, chart.lowerBound)
        XCTAssertLessThan(chart.lowerBound, effectiveSummaries.lowerBound)
        XCTAssertTrue(curveEditor.contains("ViftyAccessibilityIdentifier.curveSeparateFans"))
        XCTAssertTrue(curveEditor.contains("each controllable fan has its own labeled curve"))
        XCTAssertTrue(curveEditor.contains("EffectiveFanCurveSummaryRow(summary: summary)"))
        XCTAssertTrue(curveEditor.contains(".accessibilityLabel(summary.accessibilityLabel)"))
        XCTAssertTrue(curveEditor.contains(".accessibilityValue(summary.accessibilityValue)"))
        let summaryRowStart = try XCTUnwrap(
            curveEditor.range(of: "private struct EffectiveFanCurveSummaryRow")
        )
        let exactControlsStart = try XCTUnwrap(
            curveEditor.range(of: "private struct CurvePointEditor")
        )
        let summaryRowSource = String(
            curveEditor[summaryRowStart.lowerBound..<exactControlsStart.lowerBound]
        )
        XCTAssertFalse(
            summaryRowSource.contains(".accessibilityElement(children: .ignore)"),
            "Keep the summary as native Text so AppKit exposes AXStaticText and AXValue."
        )
        XCTAssertEqual(
            curveEditor.components(separatedBy: "rpmRange: presentation.editingRPMRange").count - 1,
            4,
            "The chart and all three exact RPM sliders must share one stable authoring envelope."
        )
        XCTAssertFalse(curveEditor.contains("requestedRPMRange"))

        let chartEditor = try read("Sources/Vifty/FanCurveChartEditor.swift")
        let legend = try XCTUnwrap(chartEditor.range(of: "private var chartLegend"))
        let plot = try XCTUnwrap(chartEditor.range(of: "GeometryReader { geometry in"))
        let summary = try XCTUnwrap(chartEditor.range(of: "curvePointSummaryStrip"))
        XCTAssertLessThan(legend.lowerBound, plot.lowerBound)
        XCTAssertLessThan(plot.lowerBound, summary.lowerBound)

        let perFanEditor = try read("Sources/Vifty/PerFanCurveOverrideEditor.swift")
        XCTAssertTrue(perFanEditor.contains("\\(presentation.name) \\(label) RPM"))
        XCTAssertTrue(perFanEditor.contains("Adjusts the \\(label.lowercased()) target for \\(presentation.name)."))
    }

    func testTask6SourcesBindEverySemanticScopeWithoutControlPaths() throws {
        let files = [
            "Sources/Vifty/ViftyAccessibilityIdentifiers.swift",
            "Sources/Vifty/ControlSessionCard.swift",
            "Sources/Vifty/FanStatusList.swift",
            "Sources/Vifty/FanStatusRow.swift",
            "Sources/Vifty/FanCurveChartEditor.swift",
            "Sources/Vifty/TemperatureCurveEditor.swift",
            "Sources/Vifty/SensorListView.swift",
            "Sources/Vifty/TelemetryEvidencePanel.swift",
            "Sources/Vifty/ViftySettingsView.swift",
            "Sources/Vifty/SettingsPane.swift",
            "Sources/Vifty/SettingsGeneralView.swift",
            "Sources/Vifty/SettingsMenuBarView.swift",
            "Sources/Vifty/SettingsNotificationsView.swift",
            "Sources/Vifty/SettingsAgentWorkflowView.swift",
            "Sources/Vifty/ContentView.swift"
        ]
        let joined = try files.map(read).joined(separator: "\n")

        for identifierName in [
            "controlSession", "controlSessionTitle", "controlSessionSummary", "fanStatus",
            "curveChart", "curveSeparateFans", "sensorList", "temperatureMetrics", "curveSensorMetric",
            "highestTemperatureMetric", "notifications", "notificationOpenSettings",
            "notificationSendTest", "settings", "settingsTabs", "settingsPaneGeneral",
            "settingsLaunchAtLogin", "settingsUpdateAutomatic", "settingsUpdateStatus",
            "settingsUpdateCheck", "settingsUpdateLatest",
            "mainScroll", "mainScrollEnd"
        ] {
            XCTAssertTrue(joined.contains("ViftyAccessibilityIdentifier.\(identifierName)"), identifierName)
        }
        for pane in ["general", "menuBar", "notifications", "agentWorkflows"] {
            XCTAssertTrue(joined.contains("accessibilityPane: .\(pane)"), pane)
        }
        XCTAssertTrue(joined.contains("ViftyCurveAccessibilityControl.allCases"))
        XCTAssertTrue(joined.contains(".accessibilityRepresentation"))
        XCTAssertTrue(joined.contains(".accessibilityAdjustableAction"))
        XCTAssertTrue(joined.contains("ViftyAccessibilityScrollEndAnchor"))
        XCTAssertFalse(joined.contains("FanCommand("))
        XCTAssertFalse(joined.contains("setFixedFanRPM("))
        XCTAssertFalse(joined.contains("viftyctl"))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
