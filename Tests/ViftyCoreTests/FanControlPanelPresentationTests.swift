import XCTest
@testable import Vifty
import ViftyCore

final class FanControlPanelPresentationTests: XCTestCase {
    func testPresentationResolvesImmutableEditorAndStatusState() {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let profile = CurveProfile(
            id: profileID,
            name: "Build",
            sensorID: "TC0P",
            startTemp: 55,
            startRPM: 2_200,
            midTemp: 70,
            midRPM: 3_600,
            maxTemp: 85,
            maxRPM: 5_400
        )
        let fans = [
            fan(id: 0, name: "Left fan", controllable: true),
            fan(id: 1, name: "Right fan", controllable: true),
            fan(id: 2, name: "Read-only fan", controllable: false)
        ]
        let input = FanControlPanelPresentation.Input(
            selectedMode: .curve,
            fixedRPM: 3_000,
            usesPerFanFixedRPM: true,
            curveStartTemperature: 55,
            curveRampTemperature: 70,
            curveHighTemperature: 85,
            curveStartRPM: 2_200,
            curveRampRPM: 3_600,
            curveHighRPM: 5_400,
            sensors: [
                TemperatureSensor(id: "TC0P", name: "CPU", celsius: 64.5, source: .smc)
            ],
            effectiveSensorID: "TC0P",
            effectiveTemperature: 64.5,
            usesPerFanOverrides: true,
            savedProfiles: [profile],
            selectedCurveProfileID: profileID,
            curveProfileEditState: .saved(profileID: profileID),
            curveProfileRecoveryMessage: nil,
            fanRange: 1_400...6_000,
            fans: fans,
            fanOverrides: [
                FanCurveOverride(fanID: 0, startRPM: 2_100, midRPM: 3_500, maxRPM: 5_300),
                FanCurveOverride(fanID: 2, startRPM: 2_200, midRPM: 3_600, maxRPM: 5_400),
                FanCurveOverride(fanID: 0, startRPM: 2_300, midRPM: 3_700, maxRPM: 5_500)
            ],
            fanMetrics: [
                metrics(fanID: 0, applied: 2_500, draft: 2_700, fixed: 2_800, percent: 33),
                metrics(fanID: 1, applied: 2_600, draft: nil, fixed: 2_900, percent: 35),
                metrics(fanID: 2, applied: nil, draft: nil, fixed: 3_000, percent: 37)
            ],
            manualFanControlAvailable: true,
            helperRecoverySuggestion: "Repair the helper.",
            fanAccessMessage: "Fan access failed.",
            helperActionTitle: "Repair Helper",
            helperActionHelp: "Repair before fan writes.",
            helperActionDisabled: false,
            helperStatusText: "Helper needs repair",
            helperDiagnosticsCopied: true
        )

        let presentation = FanControlPanelPresentation.resolve(input)
        let identical = FanControlPanelPresentation.resolve(input)

        XCTAssertEqual(presentation, identical)
        XCTAssertEqual(presentation.selectedMode.rawValue, ModeSelection.curve.rawValue)
        XCTAssertEqual(presentation.fixedRPMEditor.fans.map(\.fanID), [0, 1])
        XCTAssertTrue(presentation.fixedRPMEditor.showsPerFanEditors)
        XCTAssertEqual(presentation.temperatureCurveEditor.selectedSensorID, "TC0P")
        XCTAssertEqual(presentation.temperatureCurveEditor.liveTemperature, 64.5)
        XCTAssertEqual(presentation.temperatureCurveEditor.editingRPMRange, 1_000...7_000)
        XCTAssertEqual(presentation.temperatureCurveEditor.chartFans.map(\.id), [0, 1])
        XCTAssertEqual(presentation.temperatureCurveEditor.fanOverrides.map(\.fanID), [0, 0])
        XCTAssertEqual(presentation.temperatureCurveEditor.overrideEditors.map(\.fanID), [0])
        XCTAssertEqual(presentation.temperatureCurveEditor.overrideEditors[0].rampRPM, 3_700)
        XCTAssertTrue(presentation.temperatureCurveEditor.showsPerFanOverrideEditors)
        XCTAssertEqual(presentation.fanStatusList.fans.count, 3)
        XCTAssertEqual(presentation.fanStatusList.fans[0].status.targetText, "Target 2500 RPM")
        XCTAssertEqual(presentation.fanStatusList.fans[0].status.draftTargetText, "Draft 2700 RPM")
        XCTAssertEqual(presentation.fanStatusList.unavailableDescription, "Repair the helper.")
    }

    func testSelectedPersistedProfileAnchorsStableCurveEditingEnvelope() {
        let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let selectedProfile = CurveProfile(
            id: selectedID,
            name: "Selected legacy",
            startTemp: 55,
            startRPM: 950,
            midTemp: 70,
            midRPM: 3_500,
            maxTemp: 85,
            maxRPM: 7_601
        )
        let unrelatedProfile = CurveProfile(
            id: otherID,
            name: "Unrelated outlier",
            startTemp: 55,
            startRPM: 500,
            midTemp: 70,
            midRPM: 8_000,
            maxTemp: 85,
            maxRPM: 9_000
        )
        let input = makeInput(
            savedProfiles: [selectedProfile, unrelatedProfile],
            selectedCurveProfileID: selectedID,
            fans: [
                fan(id: 0, name: "Left fan", controllable: true)
            ]
        )

        let presentation = FanControlPanelPresentation.resolve(input)

        XCTAssertEqual(presentation.temperatureCurveEditor.editingRPMRange, 950...7_650)
    }

    func testLiveDraftChangesDoNotRachetCurveEditingEnvelope() {
        let fans = [fan(id: 0, name: "Left fan", controllable: true)]
        let sixThousand = FanControlPanelPresentation.resolve(
            makeInput(
                savedProfiles: [],
                selectedCurveProfileID: nil,
                fans: fans,
                curveHighRPM: 6_000
            )
        )
        let fiftyFiveHundred = FanControlPanelPresentation.resolve(
            makeInput(
                savedProfiles: [],
                selectedCurveProfileID: nil,
                fans: fans,
                curveHighRPM: 5_500
            )
        )

        XCTAssertEqual(sixThousand.temperatureCurveEditor.editingRPMRange, 1_000...7_000)
        XCTAssertEqual(
            fiftyFiveHundred.temperatureCurveEditor.editingRPMRange,
            sixThousand.temperatureCurveEditor.editingRPMRange
        )
    }

    func testDispatcherRoutesEveryEditorActionAndReturnsSaveResult() {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let savedProfile = CurveProfile(
            id: profileID,
            name: "Saved",
            startTemp: 50,
            startRPM: 2_000,
            midTemp: 70,
            midRPM: 3_500,
            maxTemp: 90,
            maxRPM: 5_500
        )
        var received: [FanControlPanelAction] = []
        let dispatcher = FanControlPanelActionDispatcher { action in
            received.append(action)
            if case .saveCurveProfile = action {
                return .curveProfileSave(.created(savedProfile))
            }
            return .none
        }

        dispatcher.fixedRPMChanged(3_100)
        dispatcher.fixedRPMEditingEnded()
        dispatcher.perFanFixedRPMChanged(true)
        dispatcher.initializeFixedFanTargets()
        dispatcher.fixedFanRPMChanged(fanID: 0, rpm: 3_200)
        dispatcher.fixedFanEditingEnded()
        dispatcher.curveTemperatureChanged(point: .start, value: 54)
        dispatcher.curveRPMChanged(point: .ramp, value: 3_700)
        dispatcher.sensorSelected("TC0P")
        dispatcher.perFanOverridesChanged(true)
        dispatcher.initializeFanOverrides()
        dispatcher.fanOverrideRPMChanged(fanID: 1, point: .high, rpm: 5_600)
        dispatcher.curveProfileSelected(profileID)
        dispatcher.developerPresetSelected(.build)
        dispatcher.updateCurveProfile()
        let saveResult = dispatcher.saveCurveProfile(name: "Saved", confirmOverwrite: false)
        dispatcher.deleteCurveProfile(profileID)

        XCTAssertEqual(saveResult, .created(savedProfile))
        XCTAssertEqual(received, [
            .fixedRPMChanged(3_100),
            .fixedRPMEditingEnded,
            .perFanFixedRPMChanged(true),
            .initializeFixedFanTargets,
            .fixedFanRPMChanged(fanID: 0, rpm: 3_200),
            .fixedFanEditingEnded,
            .curveTemperatureChanged(point: .start, value: 54),
            .curveRPMChanged(point: .ramp, value: 3_700),
            .sensorSelected("TC0P"),
            .perFanOverridesChanged(true),
            .initializeFanOverrides,
            .fanOverrideRPMChanged(fanID: 1, point: .high, rpm: 5_600),
            .curveProfileSelected(profileID),
            .developerPresetSelected(.build),
            .updateCurveProfile,
            .saveCurveProfile(name: "Saved", confirmOverwrite: false),
            .deleteCurveProfile(profileID)
        ])
    }

    func testFanControlViewsCannotConstructHardwareOrIssueRawCommands() throws {
        let viewPaths = [
            "Sources/Vifty/FanControlPanel.swift",
            "Sources/Vifty/FixedRPMEditor.swift",
            "Sources/Vifty/TemperatureCurveEditor.swift",
            "Sources/Vifty/PerFanCurveOverrideEditor.swift",
            "Sources/Vifty/FanStatusList.swift",
            "Sources/Vifty/CurveProfileToolbar.swift"
        ]
        let forbidden = [
            "AppModel",
            "HardwareService",
            "SMCClient(",
            "RealMacHardwareService(",
            "ViftyDaemonClient(",
            "FanControlCoordinator(",
            "LocalFanHelperClient(",
            "FanCommand(",
            "setFixedRPM(",
            "applyManualFanControl(",
            "applyAgentFanControl(",
            "restoreAllAuto("
        ]

        for path in viewPaths {
            let source = try read(path)
            for marker in forbidden {
                XCTAssertFalse(source.contains(marker), "\(path) contains forbidden view-layer marker \(marker)")
            }
        }

        let editorSource = try viewPaths.map { try read($0) }.joined(separator: "\n")
        let requiredDispatcherCalls = [
            "dispatcher.fixedRPMChanged(",
            "dispatcher.fixedRPMEditingEnded(",
            "dispatcher.perFanFixedRPMChanged(",
            "dispatcher.initializeFixedFanTargets(",
            "dispatcher.fixedFanRPMChanged(",
            "dispatcher.fixedFanEditingEnded(",
            "dispatcher.curveTemperatureChanged(",
            "dispatcher.curveRPMChanged(",
            "dispatcher.sensorSelected(",
            "dispatcher.perFanOverridesChanged(",
            "dispatcher.initializeFanOverrides(",
            "dispatcher.fanOverrideRPMChanged(",
            "dispatcher.curveProfileSelected(",
            "dispatcher.developerPresetSelected(",
            "dispatcher.updateCurveProfile(",
            "dispatcher.saveCurveProfile(",
            "dispatcher.deleteCurveProfile("
        ]
        for call in requiredDispatcherCalls {
            XCTAssertTrue(editorSource.contains(call), "Editor layer does not dispatch \(call)")
        }

        let root = try read("Sources/Vifty/FanControlPanel.swift")
        XCTAssertTrue(root.contains("let presentation: FanControlPanelPresentation"))
        XCTAssertTrue(root.contains("let dispatcher: FanControlPanelActionDispatcher"))
        XCTAssertTrue(root.contains("let onHelperAction: () -> Void"))
        XCTAssertTrue(root.contains("let onCopyDiagnostics: () -> Void"))
    }

    private func fan(id: Int, name: String, controllable: Bool) -> Fan {
        Fan(
            id: id,
            name: name,
            currentRPM: 2_400 + id * 100,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: controllable,
            hardwareMode: .automatic
        )
    }

    private func makeInput(
        savedProfiles: [CurveProfile],
        selectedCurveProfileID: CurveProfile.ID?,
        fans: [Fan],
        curveHighRPM: Double = 6_000
    ) -> FanControlPanelPresentation.Input {
        FanControlPanelPresentation.Input(
            selectedMode: .curve,
            fixedRPM: 3_000,
            usesPerFanFixedRPM: false,
            curveStartTemperature: 55,
            curveRampTemperature: 70,
            curveHighTemperature: 85,
            curveStartRPM: 2_000,
            curveRampRPM: 3_500,
            curveHighRPM: curveHighRPM,
            sensors: [],
            effectiveSensorID: nil,
            effectiveTemperature: nil,
            usesPerFanOverrides: false,
            savedProfiles: savedProfiles,
            selectedCurveProfileID: selectedCurveProfileID,
            curveProfileEditState: .unsaved,
            curveProfileRecoveryMessage: nil,
            fanRange: 1_400...6_000,
            fans: fans,
            fanOverrides: [],
            fanMetrics: fans.map {
                metrics(fanID: $0.id, applied: nil, draft: nil, fixed: 3_000, percent: 35)
            },
            manualFanControlAvailable: true,
            helperRecoverySuggestion: nil,
            fanAccessMessage: nil,
            helperActionTitle: nil,
            helperActionHelp: nil,
            helperActionDisabled: false,
            helperStatusText: "Ready",
            helperDiagnosticsCopied: false
        )
    }

    private func metrics(
        fanID: Int,
        applied: Int?,
        draft: Int?,
        fixed: Int,
        percent: Int
    ) -> FanControlPanelFanMetrics {
        FanControlPanelFanMetrics(
            fanID: fanID,
            appliedTargetRPM: applied,
            draftTargetRPM: draft,
            fixedSliderRPM: fixed,
            fixedTargetRPM: fixed,
            fixedTargetPercent: percent
        )
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
