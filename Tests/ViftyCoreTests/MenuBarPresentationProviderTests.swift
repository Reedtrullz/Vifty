import XCTest
@testable import ViftyCore
@testable import Vifty

final class MenuBarPresentationProviderTests: XCTestCase {
    func testTitleAndPanelTitleShareTelemetryButOnlyTitleIncludesPower() {
        var input = makeInput()
        input.power = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 96)
        )
        input.thermalPressure = .serious
        input.agentCoolingMenuSummary = "Agent status unavailable"

        let presentation = MenuBarPresentationProvider.resolve(input)

        XCTAssertEqual(
            presentation.title,
            "Curve sensor · CPU Proximity 65 C | 2400 RPM | 96 W adapter | Thermal: Serious | Agent status unavailable"
        )
        XCTAssertEqual(
            presentation.panelTitle,
            "Curve sensor · CPU Proximity 65 C | 2400 RPM | Thermal: Serious | Agent status unavailable"
        )
    }

    func testCustomLabelCalculatesFanAveragesAndAppendsActionableHelperAttention() {
        var input = makeInput()
        input.displayMode = .custom
        input.customFields = [.temperature, .fanStrength, .averageFanRPM]
        input.fans.append(Fan(
            id: 1,
            name: "Right",
            currentRPM: 3_200,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true
        ))
        input.helperState = .telemetryOnly

        let presentation = MenuBarPresentationProvider.resolve(input)

        XCTAssertEqual(
            presentation.labelText,
            "65 C | 31% fan | 2800 RPM avg | Fan writes blocked"
        )
        XCTAssertEqual(
            presentation.statusItemPresentation.accessibilityLabel,
            "Curve sensor · CPU Proximity 65 C | 31% fan | 2800 RPM avg | Fan writes blocked"
        )
        XCTAssertFalse(presentation.labelNeedsTelemetryPrime)
    }

    func testCodexOnlyDisplayCanPublishPlaceholderAfterHardwarePoll() {
        var input = makeInput()
        input.displayMode = .codexUsage
        input.snapshotIsAvailable = false
        input.selectedTemperature = nil
        input.fans = []
        input.hasCompletedHardwarePoll = true
        input.codexUsageSnapshot = nil

        let presentation = MenuBarPresentationProvider.resolve(input)

        XCTAssertTrue(presentation.displaysCodexUsage)
        XCTAssertTrue(presentation.allowsPlaceholderStatusItemText)
        XCTAssertFalse(presentation.labelNeedsTelemetryPrime)
        XCTAssertNotNil(presentation.statusItemText)
    }

    func testConfirmedOwnershipOverridesContradictoryLegacyOwnerProjections() {
        let activeAgent = FanControlOwnershipStatus(
            owner: .agent(leaseID: "lease-1"),
            phase: .active,
            transactionID: "agent-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        )
        let recovery = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-1"),
            phase: .restorePending,
            transactionID: "recovery-transaction",
            expectedFanIDs: [0],
            recoveryPending: true
        )
        let activeManual = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-1"),
            phase: .active,
            transactionID: "manual-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        )
        let mixedOrUnknown = FanControlOwnershipStatus(
            owner: .agent(leaseID: "lease-1"),
            phase: .active,
            transactionID: nil,
            expectedFanIDs: [0],
            recoveryPending: false
        )
        let cases: [(name: String, status: FanControlOwnershipStatus, ownerText: String)] = [
            ("agent", activeAgent, "Agent"),
            ("recovery", recovery, "Recovery?"),
            ("macOS", .osManaged, "Mac"),
            ("manual", activeManual, "Me"),
            ("mixed or unknown", mixedOrUnknown, "Owner?")
        ]

        for testCase in cases {
            var input = makeInput()
            input.displayMode = .custom
            input.customFields = [.owner, .temperature]
            input.fanControlOwnershipStatus = testCase.status

            // Every legacy projection says an expired agent lease owns a selected manual draft.
            // The daemon-confirmed ownership status must remain the single visible authority.
            input.hasAgentLease = true
            input.agentLeaseNeedsAttention = true
            input.controlMode = .fixedRPM(2_800)
            input.controlOwnershipNeedsAttention = true
            input.autoHardwareModeIsUncertain = true

            let presentation = MenuBarPresentationProvider.resolve(input)

            XCTAssertEqual(presentation.fanOwnerText, testCase.ownerText, testCase.name)
            XCTAssertEqual(
                presentation.labelText,
                "\(testCase.ownerText) | 65 C",
                testCase.name
            )
            XCTAssertEqual(presentation.statusItemText, presentation.labelText, testCase.name)
            XCTAssertNil(presentation.panelAttentionText, testCase.name)
        }
    }

    func testFanIconProducesAccessibleIconStatusItem() {
        var input = makeInput()
        input.displayMode = .fanIcon

        let presentation = MenuBarPresentationProvider.resolve(input)

        XCTAssertTrue(presentation.labelUsesFanIcon)
        XCTAssertNil(presentation.statusItemText)
        XCTAssertEqual(
            presentation.statusItemPresentation.content,
            .fanIcon(accessibilityDescription: presentation.title)
        )
        XCTAssertEqual(presentation.statusItemPresentation.tooltip, presentation.title)
    }

    func testCompactSummaryKeepsVisibleTextCompactAndAccessibilitySpecific() {
        var input = makeInput()
        input.displayMode = .compactSummary
        input.power = PowerSnapshot(
            percent: 76,
            isPluggedIn: true,
            adapter: PowerAdapter(ratedWatts: 96)
        )

        let presentation = MenuBarPresentationProvider.resolve(input)

        XCTAssertEqual(presentation.labelText, "65 C | 2400 RPM | 96 W adapter")
        XCTAssertEqual(
            presentation.statusItemPresentation.accessibilityLabel,
            "Curve sensor · CPU Proximity 65 C | 2400 RPM | 96 W adapter"
        )
        XCTAssertEqual(presentation.statusItemPresentation.tooltip, presentation.title)
    }

    private func makeInput() -> MenuBarPresentationInput {
        MenuBarPresentationInput(
            displayMode: .temperatureAndRPM,
            customFields: MenuBarField.defaultCustomFields,
            snapshotIsAvailable: true,
            selectedTemperature: TemperatureSensor(
                id: "Tp09",
                name: "CPU Proximity",
                celsius: 65,
                source: .smc
            ),
            selectedTemperatureLabel: "Curve sensor · CPU Proximity",
            fans: [Fan(
                id: 0,
                name: "Left",
                currentRPM: 2_400,
                minimumRPM: 1_400,
                maximumRPM: 6_000,
                controllable: true
            )],
            power: nil,
            thermalPressure: .nominal,
            temperatureAttentionSummary: nil,
            fanWriteBlockedWhileHotSummary: nil,
            helperState: .healthy(fanCount: 1),
            hasCompletedHardwarePoll: true,
            daemonReachable: true,
            daemonResponding: true,
            lastErrorIsPresent: false,
            agentCoolingMenuSummary: nil,
            agentStatusIsUnavailable: false,
            shouldPreferHelperRecoveryOverAgentStatusError: false,
            hasAgentLease: false,
            agentLeaseNeedsAttention: false,
            fanControlOwnershipStatus: .osManaged,
            controlMode: .auto,
            controlOwnershipNeedsAttention: false,
            autoHardwareModeIsUncertain: false,
            codexUsageSnapshot: nil,
            codexUsageDisplayPreferences: .defaults,
            currentDate: Date(timeIntervalSince1970: 1_000)
        )
    }
}
