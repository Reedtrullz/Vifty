import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelHelperHealthTests: XCTestCase {
    func testHelperHealthSummaryReportsCheckingBeforeFirstHardwarePoll() {
        let model = AppModel()

        XCTAssertEqual(model.helperHealthSummary, "Checking fan helper")
        XCTAssertEqual(model.helperHealthState, .checking)
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertNil(model.helperRecoverySuggestion)
    }

    func testHelperHealthSummaryReportsHealthyWhenDaemonAndFansAvailable() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper healthy · 1 fan")
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 1))
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertNil(model.helperRecoverySuggestion)
    }

    func testHelperHealthSummaryReportsHelperErrorBeforeHealthyState() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "The fan helper rejected the command"

        XCTAssertEqual(model.helperHealthSummary, "Fan helper error · repair needed")
        XCTAssertEqual(model.helperHealthState, .error)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "The helper may be installed, but the current daemon path still needs repair.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck.")
    }

    func testHelperHealthSummaryReportsRuntimeMismatchBeforeHealthyState() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = agentHardwareSnapshot()
        model.lastError = "Installed privileged fan helper does not match this Vifty build; use Repair/Reinstall Helper before requesting cooling."

        XCTAssertEqual(model.helperHealthSummary, "Fan helper build mismatch · repair needed")
        XCTAssertEqual(model.helperHealthMenuSummary, "Helper build mismatch")
        XCTAssertEqual(model.helperHealthState, .runtimeMismatch)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "The installed LaunchDaemon does not match this Vifty app; repair the helper before fan writes.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper from this Vifty app, approve Login Items if prompted, then rerun diagnose. Fan writes stay blocked until the installed daemon matches this build.")
        XCTAssertEqual(model.helperMenuRecoverySuggestion, "Repair/Reinstall Helper from this app before fan control.")
    }

    func testHelperHealthSummaryReportsReachableWithNoFanData() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper reachable · waiting for fan data")
        XCTAssertEqual(model.helperHealthState, .noFanData)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "Keep Auto selected and collect read-only diagnostics. Fan writes stay blocked until controllable fans appear.")
    }

    func testHelperHealthSummaryPluralizesFanCount() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 2450, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan helper healthy · 2 fans")
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 2))
        XCTAssertFalse(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
    }

    func testHelperHealthSummaryWarnsWhenTelemetryFallbackWorksButDaemonDoesNotRespond() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Read-only fan telemetry · repair daemon for writes")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper or approve Login Items if prompted. Fan telemetry is read-only, and manual or agent cooling stays blocked until the daemon responds.")
    }

    func testAutoRestoreActionCopyUsesRequestLanguageWhenWritesCannotBeConfirmed() {
        let healthy = AppModel()
        healthy.daemonResponding = true
        healthy.daemonReachable = true
        healthy.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 65, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(healthy.autoRestoreActionTitle, "Auto")
        XCTAssertEqual(healthy.autoRestoreActionHelp, "Restore Auto")
        XCTAssertEqual(healthy.modeSelectionActionTitle, "Auto")
        XCTAssertEqual(healthy.modeSelectionActionHelp, "Restore Auto")
        healthy.selectedMode = .fixed
        XCTAssertEqual(healthy.modeSelectionActionTitle, "Apply")
        XCTAssertEqual(healthy.modeSelectionActionHelp, "Fan ownership is unconfirmed; manual fan control stays blocked.")

        let telemetryOnly = AppModel()
        telemetryOnly.daemonResponding = false
        telemetryOnly.daemonReachable = true
        telemetryOnly.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(telemetryOnly.autoRestoreActionTitle, "Request Auto")
        XCTAssertEqual(telemetryOnly.autoRestoreActionHelp, "Request Auto restore; the write cannot be confirmed until the helper responds")
        XCTAssertEqual(telemetryOnly.modeSelectionActionTitle, "Request Auto")
        XCTAssertEqual(telemetryOnly.modeSelectionActionHelp, "Request Auto restore; the write cannot be confirmed until the helper responds")
        telemetryOnly.selectedMode = .fixed
        XCTAssertEqual(telemetryOnly.modeSelectionActionTitle, "Apply")
        XCTAssertEqual(telemetryOnly.modeSelectionActionHelp, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")
    }

    func testHelperMenuCopyUsesCompactRepairHintWhenTelemetryIsReadOnly() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 72, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Read-only fan telemetry · repair daemon for writes")
        XCTAssertEqual(model.helperHealthMenuSummary, "Fan writes blocked")
        XCTAssertEqual(model.helperInstallRuntimeContext, "macOS helper may be installed, but daemon XPC is not responding; fan reads are read-only and writes stay blocked.")
        XCTAssertEqual(model.helperMenuRecoverySuggestion, "Repair/Reinstall Helper; approve Login Items if prompted.")
    }

    func testHelperInstallRuntimeContextIsNilForHealthyAndEvidenceOnlyStates() {
        let model = AppModel()

        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .healthy(fanCount: 1))
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .noFanData)
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false),
                Fan(id: 1, name: "Right", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        XCTAssertEqual(model.helperHealthState, .noControllableFans(fanCount: 2))
        XCTAssertNil(model.helperInstallRuntimeContext)

        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "Mac14,2",
            isAppleSilicon: true,
            isMacBookPro: false
        )
        XCTAssertEqual(model.helperHealthState, .unsupported)
        XCTAssertNil(model.helperInstallRuntimeContext)
    }

    func testHotBlockedFanWritesSuppressRedundantHelperMenuRecovery() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.fanWriteBlockedWhileHotSummary, "High temp · fan writes blocked")
        XCTAssertEqual(model.fanWriteBlockedWhileHotRecoverySuggestion, "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds.")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(model.helperHealthMenuSummary, "Fan writes blocked")
        XCTAssertNil(model.helperMenuRecoverySuggestion)
    }

    func testHotBlockedFanWritesExplainManualRetryInsteadOfAutoOnlyGuidance() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.fanWriteBlockedWhileHotSummary, "High temp · fan writes blocked")
        XCTAssertEqual(model.fanWriteBlockedWhileHotRecoverySuggestion, "Reduce heavy work now. Repair/Reinstall Helper; Vifty will retry Curve when the daemon responds. Use Request Auto to stop retries.")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertFalse(model.fanWriteBlockedWhileHotRecoverySuggestion?.contains("Keep Auto selected") == true)
    }

    func testManualPendingHelperOutageShowsRetryCopyInsteadOfBlockedStartCopy() {
        let model = AppModel()
        model.selectedMode = .curve
        model.daemonResponding = false
        model.daemonReachable = true
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 81.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.manualControlAttentionSummary, "Curve request pending · fan writes blocked")
        XCTAssertEqual(
            model.manualControlAttentionRecoverySuggestion,
            "Vifty will retry Curve when the helper responds. Use Request Auto to stop retries; copy support evidence if repair does not clear it."
        )
        XCTAssertEqual(model.modeSelectionActionTitle, "Request Auto")
        XCTAssertEqual(
            model.modeSelectionActionHelp,
            "Request Auto restore; the write cannot be confirmed until the helper responds"
        )
        XCTAssertTrue(model.modeSelectionActionRestoresAuto)
        XCTAssertFalse(model.modeSelectionActionDisabled)
        XCTAssertFalse(model.manualControlAttentionRecoverySuggestion?.contains("before manual fan control") == true)
    }

    func testManualPendingBlockedPrimaryActionPreservesDraftForHelperRepair() async {
        let snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 81.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.selectedMode = .curve
        model.daemonResponding = false
        model.daemonReachable = true
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.snapshot = snapshot

        await model.performModeSelectionActionNow()

        XCTAssertEqual(model.selectedMode, .curve)
        XCTAssertNil(model.manualSessionExpiresAt)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(restoredFanIDs.isEmpty)
        XCTAssertEqual(model.controlSessionPresentation.primaryAction, .repairHelper)
    }

    func testHelperSupportEvidenceContextCapturesHotManualOutageState() {
        let model = AppModel()
        model.selectedMode = .curve
        model.manualRunLimit = .indefinitely
        model.daemonResponding = false
        model.daemonReachable = true
        model.thermalPressure = .nominal
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.lastError = "Daemon request timed out."
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 1780,
                    minimumRPM: 1499,
                    maximumRPM: 4296,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                ),
                Fan(
                    id: 1,
                    name: "Right Fan",
                    currentRPM: 1939,
                    minimumRPM: 1499,
                    maximumRPM: 4744,
                    controllable: true,
                    hardwareMode: .automatic,
                    targetRPM: nil
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let context = model.helperSupportEvidenceContext

        XCTAssertTrue(context.lines.contains("selectedMode=Curve"))
        XCTAssertTrue(context.lines.contains("manualRun=Until changed"))
        XCTAssertTrue(context.lines.contains("daemon=reachable=true responding=false"))
        XCTAssertTrue(context.lines.contains("helper=Read-only fan telemetry · repair daemon for writes"))
        XCTAssertTrue(context.lines.contains("controlOwner=Read-only fan telemetry; repair helper for fan writes · Vifty will retry Curve when the helper responds"))
        XCTAssertTrue(context.lines.contains("hotFanWrites=High temp · fan writes blocked"))
        XCTAssertTrue(context.lines.contains("selectedTemperature=CPU Efficiency Core 1 91.2 C"))
        XCTAssertTrue(context.lines.contains("fans=Left Fan 1780 RPM (10%); Right Fan 1939 RPM (14%)"))
        XCTAssertTrue(context.lines.contains("lastError=Daemon request timed out."))
    }

    func testVisibleLastErrorSuppressesManualHelperBlockedDuplicate() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "Manual fan control blocked: Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked."

        XCTAssertNil(model.visibleLastError)
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertTrue(model.helperHealthNeedsAttention)
    }

    func testVisibleLastErrorKeepsUnrelatedErrorsDuringHelperOutage() {
        let model = AppModel()
        model.daemonResponding = false
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.lastError = "Failed to save profiles: disk full"

        XCTAssertEqual(model.visibleLastError, "Failed to save profiles: disk full")
        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
    }

    func testHelperHealthSummaryReportsNoControllableFansWithoutRepairAction() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: false),
                Fan(id: 1, name: "Right", currentRPM: 2450, minimumRPM: 1400, maximumRPM: 6000, controllable: false)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 63, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.helperHealthSummary, "Fan telemetry available · no controllable fans")
        XCTAssertEqual(model.helperHealthState, .noControllableFans(fanCount: 2))
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "The helper can read 2 fans, but none are marked controllable. Keep fan writes blocked and collect read-only hardware validation evidence before changing support claims.")
        XCTAssertEqual(model.manualFanControlBlockedReason, "No controllable fans are available. Manual fan control stays blocked.")
    }

    func testManualFanControlAvailabilityRequiresDaemonBackedWritePathAndConfirmedOwnership() async {
        let snapshot = agentHardwareSnapshot()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: snapshot),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.snapshot = snapshot
        model.daemonReachable = true
        model.daemonResponding = false

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")

        await model.pollOnce()

        XCTAssertTrue(model.manualFanControlAvailable)
        XCTAssertNil(model.manualFanControlBlockedReason)
    }

    func testManualFanControlBlocksWhenHelperRuntimeMismatchIsDetected() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.lastError = "daemonRuntimeMatchesExpected failed: installed daemon differs from the installed app bundle."

        XCTAssertEqual(model.helperHealthState, .runtimeMismatch)
        XCTAssertEqual(model.controlOwnershipSummary, "Fan writes blocked until helper matches this app")
        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; the installed helper does not match this Vifty app.")
    }

    func testHelperOutageSuppressesAgentStatusNoiseWhenTelemetryIsReadOnly() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        model.daemonReachable = true
        model.daemonResponding = false
        model.controlState = ControlState(mode: .auto)
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.helperHealthState, .telemetryOnly)
        XCTAssertEqual(model.controlOwnershipSummary, "Read-only fan telemetry; repair helper for fan writes")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertNil(model.agentCoolingMenuSummary)
        XCTAssertNil(model.agentCoolingSummary)
        XCTAssertNil(model.agentCoolingRecoverySuggestion)
        XCTAssertFalse(model.agentCoolingNeedsAttention)
        XCTAssertFalse(model.menuTitle.contains("Agent status unavailable"))
        XCTAssertEqual(model.manualFanControlBlockedReason, "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked.")
    }

    func testManualControlOwnershipPrioritizesBlockedHelperRetryOverAgentStatusNoise() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot(hardwareMode: .automatic)
        model.daemonReachable = true
        model.daemonResponding = false
        model.controlState = ControlState(mode: .temperatureCurve(.defaultCurve()))
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(
            model.controlOwnershipSummary,
            "Read-only fan telemetry; repair helper for fan writes · Vifty will retry Curve when the helper responds"
        )
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
        XCTAssertFalse(model.controlOwnershipSummary.contains("Agent control status unavailable"))
    }

    func testManualFanControlBlocksWhileAgentLeaseOwnsCooling() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1200) })
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent Build cooling owns fan control; restore Auto before manual fan control.")
    }

    func testManualFanControlBlocksWhileAgentRestoreIsPending() {
        let model = AppModel(now: { Date(timeIntervalSince1970: 1700) })
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: agentLease(),
            lastDecision: nil,
            lastErrorCode: nil
        )

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent cooling restore is pending; restore Auto before manual fan control.")
    }

    func testManualFanControlBlocksWhenAgentStatusIsUnavailable() {
        let model = AppModel()
        model.snapshot = agentHardwareSnapshot()
        model.daemonReachable = true
        model.daemonResponding = true
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertFalse(model.manualFanControlAvailable)
        XCTAssertEqual(model.manualFanControlBlockedReason, "Agent control status is unavailable; repair helper before manual fan control.")
    }

    func testHelperHealthSummaryReportsUnreachableDaemon() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = false
        model.snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "MacBookPro18,3", isAppleSilicon: true, isMacBookPro: true)

        XCTAssertEqual(model.helperHealthSummary, "Fan helper not responding · repair or approve")
        XCTAssertEqual(model.helperHealthState, .unreachable)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertTrue(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperInstallRuntimeContext, "Install status and daemon response are separate; approve or repair before fan writes.")
        XCTAssertEqual(model.helperRecoverySuggestion, "Use Repair/Reinstall Helper or approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds.")
    }

    func testHelperHealthSummaryReportsUnsupportedHardwareWithoutRepairAction() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "Macmini9,1",
            isAppleSilicon: true,
            isMacBookPro: false
        )

        XCTAssertEqual(model.helperHealthSummary, "Unsupported hardware · fan writes blocked")
        XCTAssertEqual(model.helperHealthState, .unsupported)
        XCTAssertTrue(model.helperHealthNeedsAttention)
        XCTAssertFalse(model.helperRepairActionAvailable)
        XCTAssertEqual(model.helperRecoverySuggestion, "Vifty supports fan control on Apple Silicon MacBook Pro hardware. Keep this machine on read-only diagnostics; do not retry fan writes.")
        XCTAssertEqual(model.manualFanControlBlockedReason, "Unsupported hardware. Manual fan control stays blocked.")
    }

    func testControlOwnershipSummaryReportsMacOSAutoAfterDaemonOwnershipConfirmation() async {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let hardware = AppModelFakeHardware(snapshot: snapshot)
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.controlState = ControlState(mode: .auto)

        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: Owner?")
        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "macOS Auto owns fan control")
        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: Mac")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryReportsBlockedWritesWhenAutoHasNoHelperPath() {
        let model = AppModel()
        model.hasCompletedHardwarePoll = true
        model.daemonResponding = false
        model.daemonReachable = false
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Auto selected · fan writes blocked until helper responds")
        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: Mac?")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryWarnsWhenAutoSelectedButHardwareIsForced() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware reports Forced mode while Vifty is Auto · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenAgentStatusIsUnavailable() {
        let model = AppModel()
        model.daemonResponding = true
        model.daemonReachable = true
        model.controlState = ControlState(mode: .auto)
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.agentControlStatusError = ViftyError.helperRejected("Daemon request timed out.").localizedDescription

        XCTAssertEqual(model.controlOwnershipSummary, "Agent control status unavailable; fan ownership uncertain")
        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: uncertain")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSummaryReportsViftyManualModes() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 3200)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 68, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.selectedSensorID = "Tp09"

        model.controlState = ControlState(mode: .fixedRPM(3200), manualControlActive: true)
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3200 RPM · until changed; reasserts if macOS drifts")
        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: Vifty Fixed")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        model.controlState = ControlState(mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")), manualControlActive: true)
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Curve owns fan targets · CPU Proximity · until changed; reasserts if macOS drifts")
        XCTAssertEqual(model.compactControlOwnershipSummary, "Owner: Vifty Curve")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        model.manualSessionExpiresAt = Date(timeIntervalSince1970: 1600)
        XCTAssertTrue(model.controlOwnershipSummary.contains("until "))
        XCTAssertTrue(model.controlOwnershipSummary.hasSuffix("; reasserts if macOS drifts"))
    }

    func testControlOwnershipWarnsWhenManualModeTelemetryShowsMacOSReclaimedAuto() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 84, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")),
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware reports Auto while Vifty manual is selected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenManualTargetDrifts() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2200, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: 2200)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware fan target drift detected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSuppressesTargetDriftDuringRecentManualWriteSettling() async {
        func snapshot(targetRPM: Int) -> HardwareSnapshot {
            HardwareSnapshot(
                fans: [
                    Fan(
                        id: 0,
                        name: "Left",
                        currentRPM: targetRPM,
                        minimumRPM: 1400,
                        maximumRPM: 6000,
                        controllable: true,
                        hardwareMode: .forced,
                        targetRPM: targetRPM
                    )
                ],
                temperatureSensors: [
                    TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
                ],
                modelIdentifier: "MacBookPro18,3",
                isAppleSilicon: true,
                isMacBookPro: true
            )
        }

        let hardware = AppModelFakeHardware(snapshot: snapshot(targetRPM: 2200))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: hardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath()),
                initialState: ControlState(
                    mode: .fixedRPM(3600),
                    lastAppliedRPM: [0: 3600],
                    manualControlActive: true
                )
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.daemonReachable = true
        model.daemonResponding = true

        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        await hardware.setSnapshot(snapshot(targetRPM: 3600))
        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipSettlesDelayedTargetReadbackAfterManualWriteThenWarns() async {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let clock = AppModelTestClock(now: startedAt)
        let staleSnapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left",
                    currentRPM: 2200,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 2200
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: startedAt
        )
        let hardware = AppModelFakeHardware(snapshot: staleSnapshot)
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(url: temporaryMarkerPath()),
            manualReassertionInterval: 30
        )
        await coordinator.setMode(.fixedRPM(3600))
        let model = AppModel(
            coordinator: coordinator,
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.daemonReachable = true
        model.daemonResponding = true

        await model.pollOnce()
        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)

        clock.now = startedAt.addingTimeInterval(AppModel.manualTargetWriteSettleInterval + 0.1)
        await model.pollOnce()
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
        await model.pollOnce()

        XCTAssertEqual(model.controlOwnershipSummary, "Hardware fan target drift detected; Vifty will reassert · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenHotManualResponseCannotBeConfirmed() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Manual fan response not confirmed; current RPM is still below requested target · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipWarnsWhenElevatedThermalPressureCannotConfirmManualResponse() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.thermalPressure = .serious
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2100, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .temperatureCurve(FanCurve.defaultCurve(sensorID: "Tp09")),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Manual fan response not confirmed; current RPM is still below requested target · F0")
        XCTAssertTrue(model.controlOwnershipNeedsAttention)
    }

    func testControlOwnershipDoesNotWarnForMissingManualTargetWhenRPMIsNearExpected() {
        let model = AppModel()
        model.daemonReachable = true
        model.daemonResponding = true
        model.snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 3425, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .forced, targetRPM: nil)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 91.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.controlState = ControlState(
            mode: .fixedRPM(3600),
            lastAppliedRPM: [0: 3600],
            manualControlActive: true
        )

        XCTAssertEqual(model.controlOwnershipSummary, "Vifty Fixed owns fan targets · 3600 RPM · until changed; reasserts if macOS drifts")
        XCTAssertFalse(model.controlOwnershipNeedsAttention)
    }

}
