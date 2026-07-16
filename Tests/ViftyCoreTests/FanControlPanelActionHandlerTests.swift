import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class FanControlPanelActionHandlerTests: XCTestCase {
    func testFanOverrideLookupUsesLastDuplicateLikeCommandResolution() async {
        let (model, hardware, root) = makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.fanOverrides = [
            FanCurveOverride(fanID: 0, startRPM: 1_600, midRPM: 3_200, maxRPM: 5_000),
            FanCurveOverride(fanID: 0, startRPM: 1_800, midRPM: 3_800, maxRPM: 5_500)
        ]

        XCTAssertEqual(model.fanOverride(for: 0)?.midRPM, 3_800)
        let appliedCommands = await hardware.appliedCommands
        XCTAssertTrue(appliedCommands.isEmpty)
    }

    func testFanOverrideActionMutatesLastDuplicateBeforeCanonicalizing() async {
        let (model, hardware, root) = makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let handler = FanControlPanelActionHandler(model: model)
        model.fanOverrides = [
            FanCurveOverride(fanID: 0, startRPM: 1_600, midRPM: 3_200, maxRPM: 5_000),
            FanCurveOverride(fanID: 0, startRPM: 1_800, midRPM: 3_800, maxRPM: 5_500)
        ]

        XCTAssertEqual(
            handler.handle(.fanOverrideRPMChanged(fanID: 0, point: .ramp, rpm: 4_200)),
            .none
        )

        XCTAssertEqual(model.fanOverrides.count, 1)
        XCTAssertEqual(model.fanOverride(for: 0)?.startRPM, 1_800)
        XCTAssertEqual(model.fanOverride(for: 0)?.midRPM, 4_200)
        XCTAssertEqual(model.fanOverride(for: 0)?.maxRPM, 5_500)
        let appliedCommands = await hardware.appliedCommands
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(appliedCommands.isEmpty)
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    func testDraftAndEditorActionsMutateOnlyControllableFanState() async throws {
        let (model, hardware, root) = makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let handler = FanControlPanelActionHandler(model: model)

        model.selectedMode = .fixed
        XCTAssertEqual(handler.handle(.fixedRPMChanged(3_250)), .none)
        XCTAssertEqual(model.fixedRPM, 3_250)
        XCTAssertEqual(handler.handle(.fixedRPMEditingEnded), .none)

        XCTAssertEqual(handler.handle(.perFanFixedRPMChanged(true)), .none)
        XCTAssertTrue(model.usePerFanFixedRPM)
        XCTAssertEqual(model.fixedFanTargets.map(\.fanID), [0])
        model.ensureFixedFanTargets(for: try XCTUnwrap(model.snapshot).fans)
        XCTAssertEqual(model.fixedFanTargets.map(\.fanID), [0])
        XCTAssertEqual(handler.handle(.initializeFixedFanTargets), .none)

        XCTAssertEqual(handler.handle(.fixedFanRPMChanged(fanID: 0, rpm: 5_500)), .none)
        XCTAssertEqual(model.fixedFanTarget(for: 0)?.rpm, 5_500)
        XCTAssertEqual(handler.handle(.fixedFanRPMChanged(fanID: 1, rpm: 5_500)), .none)
        XCTAssertNil(model.fixedFanTarget(for: 1))
        XCTAssertEqual(handler.handle(.fixedFanEditingEnded), .none)

        XCTAssertEqual(handler.handle(.curveTemperatureChanged(point: .start, value: 51)), .none)
        XCTAssertEqual(handler.handle(.curveTemperatureChanged(point: .ramp, value: 69)), .none)
        XCTAssertEqual(handler.handle(.curveTemperatureChanged(point: .high, value: 84)), .none)
        XCTAssertEqual(handler.handle(.curveRPMChanged(point: .start, value: 2_100)), .none)
        XCTAssertEqual(handler.handle(.curveRPMChanged(point: .ramp, value: 3_800)), .none)
        XCTAssertEqual(handler.handle(.curveRPMChanged(point: .high, value: 5_700)), .none)
        XCTAssertEqual(model.curveStartTemp, 51)
        XCTAssertEqual(model.curveMidTemp, 69)
        XCTAssertEqual(model.curveMaxTemp, 84)
        XCTAssertEqual(model.curveStartRPM, 2_100)
        XCTAssertEqual(model.curveMidRPM, 3_800)
        XCTAssertEqual(model.curveMaxRPM, 5_700)

        XCTAssertEqual(handler.handle(.sensorSelected("TB0T")), .none)
        XCTAssertEqual(model.selectedSensorID, "TB0T")
        XCTAssertEqual(handler.handle(.perFanOverridesChanged(true)), .none)
        XCTAssertTrue(model.usePerFanOverrides)
        XCTAssertEqual(model.fanOverrides.map(\.fanID), [0])
        XCTAssertEqual(handler.handle(.initializeFanOverrides), .none)
        XCTAssertEqual(
            handler.handle(.fanOverrideRPMChanged(fanID: 0, point: .ramp, rpm: 4_200)),
            .none
        )
        XCTAssertEqual(model.fanOverride(for: 0)?.midRPM, 4_200)
        XCTAssertEqual(
            handler.handle(.fanOverrideRPMChanged(fanID: 1, point: .ramp, rpm: 4_200)),
            .none
        )
        XCTAssertNil(model.fanOverride(for: 1))

        XCTAssertEqual(handler.handle(.developerPresetSelected(.build)), .none)
        XCTAssertEqual(model.curveStartTemp, DeveloperFanPreset.build.startTemperatureCelsius)
        XCTAssertFalse(model.usePerFanOverrides)

        let appliedCommands = await hardware.appliedCommands
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(appliedCommands.isEmpty)
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    func testProfileActionsPersistSelectUpdateAndDeleteThroughHandler() async throws {
        let (model, hardware, root) = makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let handler = FanControlPanelActionHandler(model: model)

        let saveResult = handler.handle(.saveCurveProfile(name: " Build ", confirmOverwrite: false))
        guard case .curveProfileSave(.created(let created)?) = saveResult else {
            return XCTFail("Expected a created profile, got \(saveResult)")
        }
        XCTAssertEqual(created.name, "Build")
        XCTAssertEqual(model.savedProfiles, [created])
        XCTAssertEqual(model.selectedCurveProfileID, created.id)

        let confirmation = handler.handle(.saveCurveProfile(name: "build", confirmOverwrite: false))
        guard case .curveProfileSave(.overwriteConfirmationRequired(let existing, _)?) = confirmation else {
            return XCTFail("Expected overwrite confirmation, got \(confirmation)")
        }
        XCTAssertEqual(existing.id, created.id)

        model.curveMidRPM = 4_100
        XCTAssertEqual(handler.handle(.updateCurveProfile), .none)
        XCTAssertEqual(model.savedProfiles.first?.midRPM, 4_100)

        XCTAssertEqual(handler.handle(.curveProfileSelected(nil)), .none)
        XCTAssertNil(model.selectedCurveProfileID)
        XCTAssertEqual(handler.handle(.curveProfileSelected(created.id)), .none)
        XCTAssertEqual(model.selectedCurveProfileID, created.id)
        XCTAssertEqual(model.curveMidRPM, 4_100)

        XCTAssertEqual(handler.handle(.deleteCurveProfile(created.id)), .none)
        XCTAssertTrue(model.savedProfiles.isEmpty)
        XCTAssertNil(model.selectedCurveProfileID)
        XCTAssertEqual(handler.handle(.deleteCurveProfile(UUID())), .none)

        let appliedCommands = await hardware.appliedCommands
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(appliedCommands.isEmpty)
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    private func makeModel() -> (AppModel, AppModelFakeHardware, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-panel-action-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 2_400,
                    minimumRPM: 1_400,
                    maximumRPM: 6_000,
                    controllable: true,
                    hardwareMode: .automatic
                ),
                Fan(
                    id: 1,
                    name: "Protected",
                    currentRPM: 2_300,
                    minimumRPM: 1_300,
                    maximumRPM: 5_800,
                    controllable: false,
                    hardwareMode: .system
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc),
                TemperatureSensor(id: "TB0T", name: "Battery", celsius: 44, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: root.appendingPathComponent("manual.marker"))
            ),
            powerReader: { PowerSnapshot() },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil },
            profileStore: CurveProfileStore(url: root.appendingPathComponent("profiles.json")),
            preferencesStore: AppPreferencesStore(
                url: root.appendingPathComponent("preferences.json"),
                legacyDefaults: nil
            )
        )
        model.snapshot = snapshot
        return (model, hardware, root)
    }
}
