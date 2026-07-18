import Foundation
import XCTest
import ViftyBuildProvenance
@testable import ViftyAXEvidenceCore

final class AXEvidencePredicateTests: XCTestCase {
    func testConfirmedOwnerHeadlineRequiresUniqueOrderedTitleAndSummary() throws {
        var capture = validCapture("confirmed-owner-headline")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations[3].description = "Owner: macOS"
        capture.observations[3].label = "Owner: macOS"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("confirmed-owner-headline")
        capture.observations[2].title = "Vifty manual control active"
        capture.observations[2].description = nil
        capture.observations[2].label = "Vifty manual control active"
        XCTAssertTrue(
            try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed,
            "Native static text may expose its semantic label outside AXDescription"
        )

        capture.observations[2].label = "Wrong owner headline"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testCorrectPerFanTargetRequiresExactDistinctDraftValues() throws {
        var capture = validCapture("correct-per-fan-target")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations[3].value = "Draft 2493 RPM"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testSixAdjustablePointControlsRequiresExactUniqueControlsValuesAndActions() throws {
        var capture = validCapture("six-adjustable-point-controls")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations[4].actions = ["AXIncrement"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("six-adjustable-point-controls")
        appendObservation(
            observation(
                capture.observations.count,
                "root/1/6",
                role: "AXSlider",
                identifier: "vifty.ax.curve.unexpected",
                label: "Unexpected curve control",
                value: "4000 RPM",
                actions: ["AXIncrement", "AXDecrement"]
            ),
            to: &capture
        )
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testSixAdjustablePointControlsRequiresVisibleSelectedSeparateFanToggleBeforeChart() throws {
        let id = "six-adjustable-point-controls"
        var capture = validCapture(id)
        let toggleIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.curveSeparateFans }
        )
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture.observations[toggleIndex].enabled = false
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations[toggleIndex].selected = false
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations[toggleIndex].actions = ["AXShowMenu"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations[toggleIndex].position = AXPoint(x: 120, y: 990)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations[toggleIndex].position = AXPoint(x: 120, y: 240)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations.remove(at: toggleIndex)
        normalizeTraversalMetadata(&capture.observations)
        capture.traversal.nodeCount = capture.observations.count
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)
    }

    func testSixAdjustablePointControlsRequiresExactEffectiveSummariesAfterAndOutsideChart() throws {
        let id = "six-adjustable-point-controls"
        var capture = validCapture(id)
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        let leftIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.leftFanEffectiveSummary }
        )
        capture.observations[leftIndex].value = "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5600 RPM"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        let missingIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.rightFanEffectiveSummary }
        )
        capture.observations.remove(at: missingIndex)
        normalizeTraversalMetadata(&capture.observations)
        capture.traversal.nodeCount = capture.observations.count
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        var duplicate = try XCTUnwrap(
            capture.observations.first { $0.identifier == AXEvidenceIdentifier.leftFanEffectiveSummary }
        )
        duplicate.path = "root/2/2"
        appendObservation(duplicate, to: &capture)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        let scopeIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.curveEffectiveSummaries }
        )
        let leftSummaryIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.leftFanEffectiveSummary }
        )
        let rightSummaryIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == AXEvidenceIdentifier.rightFanEffectiveSummary }
        )
        capture.observations[scopeIndex].path = "root/1/6"
        capture.observations[leftSummaryIndex].path = "root/1/6/0"
        capture.observations[rightSummaryIndex].path = "root/1/6/1"
        normalizeTraversalMetadata(&capture.observations)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)
    }

    func testSensorSelectedTraitValueRequiresCPUSelectionAndUnselectedPeers() throws {
        var capture = validCapture("sensor-selected-trait-value")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations[3].selected = true
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[3].selected = false
        XCTAssertTrue(
            try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed,
            "an explicit false remains valid for an exact unselected sensor value"
        )

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[3].value = "82.0 degrees Celsius, HID"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[2].actions = ["AXPress"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[1].role = "AXGroup"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[1].actions = ["AXScrollToBottom"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[4].path = "root/0/1/0"
        normalizeTraversalMetadata(&capture.observations)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        appendObservation(
            observation(
                capture.observations.count,
                "root/0/3",
                role: "AXButton",
                identifier: "vifty.ax.sensor.unexpected",
                label: "Unexpected sensor",
                value: "40.0 degrees Celsius, HID",
                actions: ["AXPress", "AXScrollToVisible"]
            ),
            to: &capture
        )
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("sensor-selected-trait-value")
        capture.observations[2].identifier = AXEvidenceIdentifier.sensorPalm
        capture.observations[2].label = "Palm Rest"
        capture.observations[2].description = "Palm Rest"
        capture.observations[2].value = "37.0 degrees Celsius, HID"
        capture.observations[2].selected = nil
        capture.observations[4].identifier = AXEvidenceIdentifier.sensorCPU
        capture.observations[4].label = "CPU Efficiency"
        capture.observations[4].description = "CPU Efficiency"
        capture.observations[4].value = "64.0 degrees Celsius, SMC"
        capture.observations[4].selected = true
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testExplicitTemperatureRoleRequiresSeparateCurveAndHighestMetrics() throws {
        var capture = validCapture("explicit-temperature-role")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations[2].value = "CPU Efficiency"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testNotificationActionsRequireDeniedActionEventsAndNoTestAction() throws {
        var capture = validCapture("notification-actions")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations.append(observation(
            capture.observations.count,
            "root/0/7",
            role: "AXButton",
            identifier: AXEvidenceIdentifier.notificationSendTest,
            label: "Send Test Notification",
            actions: ["AXPress"]
        ))
        capture.traversal.nodeCount = capture.observations.count
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("notification-actions")
        appendObservation(
            observation(
                capture.observations.count,
                "root/0/7",
                role: "AXButton",
                identifier: "vifty.ax.notifications.unexpected-action",
                label: "Send Test Notification",
                actions: ["AXPress"]
            ),
            to: &capture
        )
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testSettingsLogicalTraversalRequiresExactOrderedButtonsValuesSelectionAndPaneAnchor() throws {
        var capture = validCapture("settings-logical-traversal")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture.observations.swapAt(4, 5)
        capture.observations[4].order = 4
        capture.observations[5].order = 5
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        capture.observations[1].label = "Wrong group label"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        capture.observations[2].value = .string("Not selected")
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        capture.observations[3].selected = true
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        capture.observations[3].value = .string("Selected")
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        capture.observations[3].selected = false
        XCTAssertTrue(
            try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed,
            "an explicit false selected state remains valid when paired with the exact Not selected value"
        )

        capture = validCapture("settings-logical-traversal")
        appendObservation(
            observation(
                capture.observations.count,
                "root/0/4",
                role: "AXButton",
                identifier: "vifty.ax.settings.tab.unexpected",
                label: "Unexpected",
                value: .string("Not selected"),
                actions: ["AXPress"]
            ),
            to: &capture
        )
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testSettingsLogicalTraversalRequiresAvailableUpdateSemanticsOrderAndVisibility() throws {
        var capture = validCapture("settings-logical-traversal")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        let automaticID = AXEvidenceIdentifier.settingsUpdateAutomatic
        let statusID = AXEvidenceIdentifier.settingsUpdateStatus
        let latestID = AXEvidenceIdentifier.settingsUpdateLatest
        let refreshID = AXEvidenceIdentifier.settingsUpdateCheck

        let automaticIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == automaticID }
        )
        capture.observations[automaticIndex].selected = false
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        let statusIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == statusID }
        )
        capture.observations[statusIndex].label = "Vifty is up to date."
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        var latestIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == latestID }
        )
        capture.observations[latestIndex].help = "Downloads and installs automatically."
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        latestIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == latestID }
        )
        let refreshIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == refreshID }
        )
        capture.observations[latestIndex].identifier = refreshID
        capture.observations[latestIndex].label = "Check now"
        capture.observations[latestIndex].description = "Check now"
        capture.observations[latestIndex].help =
            "Refreshes GitHub release availability without downloading or installing."
        capture.observations[refreshIndex].identifier = latestID
        capture.observations[refreshIndex].label = "Update to latest version"
        capture.observations[refreshIndex].description = "Update to latest version"
        capture.observations[refreshIndex].help =
            "Opens Vifty's fixed GitHub release page in your default browser. "
            + "Vifty does not download or install the update."
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("settings-logical-traversal")
        latestIndex = try XCTUnwrap(
            capture.observations.firstIndex { $0.identifier == latestID }
        )
        capture.observations[latestIndex].position = AXPoint(x: 990, y: 220)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testNoDuplicateChartElementsRequiresOneScopeAndSixCanonicalControls() throws {
        var capture = validCapture("no-duplicate-chart-elements")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        var duplicate = capture.observations[3]
        duplicate.path = "root/1/6"
        duplicate.order = capture.observations.count
        capture.observations.append(duplicate)
        capture.traversal.nodeCount = capture.observations.count
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("no-duplicate-chart-elements")
        appendObservation(
            observation(
                capture.observations.count,
                "root/1/6",
                role: "AXStaticText",
                identifier: "vifty.ax.curve.decorative-axis",
                label: "Axis"
            ),
            to: &capture
        )
        XCTAssertFalse(
            try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed,
            "arbitrary noninteractive chart descendants must not pass the no-duplicate check"
        )
    }

    func testCompactMainScrollRequiresOverflowRangeAndEndAnchor() throws {
        try assertScrollPredicate("compact-main-scroll-reachable")
    }

    func testSettingsGeneralScrollRequiresOverflowRangeAndEndAnchor() throws {
        try assertScrollPredicate("settings-general-scroll-reachable")
    }

    func testSettingsMenuBarScrollRequiresOverflowRangeAndEndAnchor() throws {
        try assertScrollPredicate("settings-menu-bar-scroll-reachable")
    }

    func testSettingsNotificationsScrollRequiresOverflowRangeAndEndAnchor() throws {
        try assertScrollPredicate("settings-notifications-scroll-reachable")
    }

    func testSettingsAgentWorkflowsScrollRequiresOverflowRangeAndEndAnchor() throws {
        try assertScrollPredicate("settings-agent-workflows-scroll-reachable")
    }

    func testSettingsScrollAllowsOnlyTheExactCaptureRootFallback() throws {
        var settings = captureWithRootScrollArea(validCapture("settings-general-scroll-reachable"))
        XCTAssertTrue(
            try AXPredicateCatalog.evaluate(id: settings.request.checkID, capture: settings).passed
        )

        settings.observations[0].identifier = "vifty.ax.not-the-capture-root"
        XCTAssertFalse(
            try AXPredicateCatalog.evaluate(id: settings.request.checkID, capture: settings).passed
        )

        let main = captureWithRootScrollArea(validCapture("compact-main-scroll-reachable"))
        XCTAssertFalse(
            try AXPredicateCatalog.evaluate(id: main.request.checkID, capture: main).passed,
            "the compact main contract must retain its exact canonical scroll identifier"
        )
    }

    func testCanonicalRequestValidationRejectsWrongStateAndHash() throws {
        var wrongState = validCapture("confirmed-owner-headline")
        wrongState.request.semanticRequest.state = "healthy-auto"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: wrongState.request.checkID, capture: wrongState).passed)

        var wrongHash = validCapture("confirmed-owner-headline")
        wrongHash.request.requestSHA256 = String(repeating: "0", count: 64)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: wrongHash.request.checkID, capture: wrongHash).passed)
    }

    func testSwiftCatalogMatchesCanonicalRubyRequestCatalogAndHashes() throws {
        struct RubyRequest: Decodable {
            let request: AXSemanticRequest
            let sha256: String
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contractPath = repositoryRoot.appendingPathComponent("scripts/lib/ui_review_contract.rb").path
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ruby")
        process.arguments = [
            "-r", contractPath,
            "-r", "json",
            "-e",
            "STDOUT.write(JSON.generate(ViftyUIReview.expected_ax_requests.transform_values { |request| { request: request, sha256: ViftyUIReview.sha256_json(request) } }))"
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))

        let rubyRequests = try JSONDecoder().decode([String: RubyRequest].self, from: data)
        XCTAssertEqual(Set(rubyRequests.keys), Set(AXPredicateCatalog.ids))
        for id in AXPredicateCatalog.ids {
            let ruby = try XCTUnwrap(rubyRequests[id], id)
            let swift = try XCTUnwrap(AXPredicateCatalog.expectedRequest(for: id), id)
            XCTAssertEqual(swift, ruby.request, id)
            XCTAssertEqual(swift.canonicalSHA256, ruby.sha256, id)
        }
    }

    func testUnknownIDAndIncompleteTraversalFailClosed() throws {
        var capture = validCapture("confirmed-owner-headline")
        capture.traversal.complete = false
        capture.traversal.truncationReasons = ["node-limit"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        XCTAssertThrowsError(try AXPredicateCatalog.evaluate(id: "unknown", capture: capture)) { error in
            XCTAssertEqual(error as? AXPredicateError, .unknownPredicate("unknown"))
        }
    }

    func testTraversalCompletenessRejectsImpossibleBoundsDepthAndChildCounts() throws {
        var capture = validCapture("confirmed-owner-headline")
        capture.traversal.maximumNodeCount = capture.observations.count - 1
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("confirmed-owner-headline")
        capture.observations[2].depth += 1
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        capture = validCapture("confirmed-owner-headline")
        capture.observations[0].childCount = 0
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testDuplicatePathsFailAsEvidenceWithoutTrapping() throws {
        var capture = validCapture("confirmed-owner-headline")
        var duplicate = capture.observations[2]
        duplicate.order = capture.observations.count
        capture.observations.append(duplicate)
        capture.traversal.nodeCount = capture.observations.count

        let assertion = try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture)
        XCTAssertFalse(assertion.passed)
        XCTAssertTrue(assertion.failures.contains("observation paths are not unique"))
    }

    func testTopologyRequiresStrictDepthFirstPreorder() throws {
        var capture = validCapture("confirmed-owner-headline")
        appendObservation(
            observation(
                capture.observations.count,
                "root/0/0/0",
                role: "AXStaticText",
                identifier: "vifty.ax.control-session.title.detail",
                label: "Detail"
            ),
            to: &capture
        )
        XCTAssertEqual(
            capture.observations.map(\.path),
            ["root", "root/0", "root/0/0", "root/0/1", "root/0/0/0"]
        )
        let assertion = try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture)
        XCTAssertFalse(assertion.passed)
        XCTAssertTrue(assertion.failures.contains("observations are not in strict depth-first pre-order"))
    }

    func testEveryPredicateRejectsMissingDuplicateAndWrongRoleRequiredNodes() throws {
        for id in AXPredicateCatalog.ids {
            let requiredIdentifier: String
            if let scroll = AXPredicateCatalog.scrollContract(for: id) {
                requiredIdentifier = scroll.anchorIdentifier
            } else {
                requiredIdentifier = [
                    "confirmed-owner-headline": AXEvidenceIdentifier.controlSessionTitle,
                    "correct-per-fan-target": AXEvidenceIdentifier.leftFanDraftTarget,
                    "six-adjustable-point-controls": AXEvidenceIdentifier.curveStartTemperature,
                    "sensor-selected-trait-value": AXEvidenceIdentifier.sensorCPU,
                    "explicit-temperature-role": AXEvidenceIdentifier.curveSensorMetric,
                    "notification-actions": AXEvidenceIdentifier.notificationOpenSettings,
                    "settings-logical-traversal": AXEvidenceIdentifier.settingsTabGeneral,
                    "no-duplicate-chart-elements": AXEvidenceIdentifier.curveStartTemperature
                ][id]!
            }

            var missing = validCapture(id)
            missing.observations.removeAll { $0.identifier == requiredIdentifier }
            normalizeTraversalMetadata(&missing.observations)
            missing.traversal.nodeCount = missing.observations.count
            XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: missing).passed, "missing \(id)")

            var duplicate = validCapture(id)
            let original = duplicate.observations.first { $0.identifier == requiredIdentifier }!
            let parentPath = original.path.split(separator: "/").dropLast().joined(separator: "/")
            let siblingIndex = duplicate.observations.filter { candidate in
                let candidateParent = candidate.path.split(separator: "/").dropLast().joined(separator: "/")
                return candidateParent == parentPath && Int(candidate.path.split(separator: "/").last ?? "") != nil
            }.count
            var copy = original
            copy.path = "\(parentPath)/\(siblingIndex)"
            appendObservation(copy, to: &duplicate)
            XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: duplicate).passed, "duplicate \(id)")

            var wrongRole = validCapture(id)
            let index = wrongRole.observations.firstIndex { $0.identifier == requiredIdentifier }!
            wrongRole.observations[index].role = "AXUnknown"
            XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: wrongRole).passed, "role \(id)")
        }
    }

    func testTypedAXValuesRoundTripStructuredBooleanAndDescriptionValues() throws {
        let observations = [
            AXObservation(
                path: "root/0",
                order: 0,
                depth: 1,
                role: "AXSlider",
                description: "Start temperature",
                label: "Start temperature",
                value: .number(55),
                valueDescription: "55 °C"
            ),
            AXObservation(
                path: "root/1",
                order: 1,
                depth: 1,
                role: "AXCheckBox",
                value: .boolean(true)
            ),
            AXObservation(
                path: "root/2",
                order: 2,
                depth: 1,
                role: "AXUnknown",
                value: .rectangle(AXRect(x: 1, y: 2, width: 3, height: 4))
            )
        ]

        let data = try AXCanonicalJSON.data(observations)
        XCTAssertEqual(try JSONDecoder().decode([AXObservation].self, from: data), observations)
    }

    func testDecodedModelsNormalizeOrderInsensitiveArrays() throws {
        var capture = validCapture("six-adjustable-point-controls")
        capture.observations[3].actions = ["AXIncrement", "AXDecrement", "AXIncrement"]
        capture.observations[3].readErrors = ["z", "a", "z"]
        capture.actionsPerformed = ["z", "a", "z"]
        capture.readErrors = ["z", "a", "z"]

        let decoded = try JSONDecoder().decode(
            AXRawCapture.self,
            from: JSONEncoder().encode(capture)
        )
        XCTAssertEqual(decoded.observations[3].actions, ["AXDecrement", "AXIncrement"])
        XCTAssertEqual(decoded.observations[3].readErrors, ["a", "z"])
        XCTAssertEqual(decoded.actionsPerformed, ["a", "z"])
        XCTAssertEqual(decoded.readErrors, ["a", "z"])
    }

    func testGenericOneNodeAXGroupFailsAllThirteenPredicates() throws {
        for id in AXPredicateCatalog.ids {
            var capture = baseCapture(id: id, observations: [
                observation(
                    0,
                    "0",
                    role: "AXGroup",
                    identifier: "generic",
                    label: id,
                    value: "observed",
                    actions: ["AXPress"]
                )
            ])
            capture.scrollEvidence = []
            XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed, id)
        }
    }

    func testCanonicalJSONIgnoresActionErrorAndFactInputOrder() throws {
        let firstObservation = AXObservation(
            path: "0",
            order: 0,
            depth: 0,
            role: "AXButton",
            identifier: "button",
            label: "Button",
            actions: ["AXShowMenu", "AXPress"],
            readErrors: ["z", "a"]
        )
        let secondObservation = AXObservation(
            path: "0",
            order: 0,
            depth: 0,
            role: "AXButton",
            identifier: "button",
            label: "Button",
            actions: ["AXPress", "AXShowMenu"],
            readErrors: ["a", "z"]
        )
        let first = baseCapture(id: "confirmed-owner-headline", observations: [firstObservation])
        let second = baseCapture(id: "confirmed-owner-headline", observations: [secondObservation])

        XCTAssertEqual(try AXCanonicalJSON.data(first), try AXCanonicalJSON.data(second))
        XCTAssertEqual(try AXCanonicalJSON.sha256(first), try AXCanonicalJSON.sha256(second))

        let firstAssertion = AXAssertion(
            id: "assertion",
            passed: true,
            observationPaths: ["z", "a"],
            facts: Dictionary(uniqueKeysWithValues: [("z", "last"), ("a", "first")]),
            failures: []
        )
        let secondAssertion = AXAssertion(
            id: "assertion",
            passed: true,
            observationPaths: ["a", "z"],
            facts: Dictionary(uniqueKeysWithValues: [("a", "first"), ("z", "last")]),
            failures: []
        )
        XCTAssertEqual(try AXCanonicalJSON.data(firstAssertion), try AXCanonicalJSON.data(secondAssertion))
    }

    private func assertScrollPredicate(_ id: String) throws {
        var capture = validCapture(id)
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture.scrollEvidence[0].minimumValue = nil
        capture.scrollEvidence[0].maximumValue = nil
        XCTAssertTrue(
            try AXPredicateCatalog.evaluate(id: id, capture: capture).passed,
            "unavailable AXMinValue/AXMaxValue must not be replaced with invented bounds"
        )

        capture.scrollEvidence[0].maximumValue = 1
        XCTAssertFalse(
            try AXPredicateCatalog.evaluate(id: id, capture: capture).passed,
            "one-sided bounds must fail closed"
        )

        capture = validCapture(id)
        capture.scrollEvidence[0].maximumValue = 0
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.scrollEvidence[0].currentValue = 0.5
        capture.observations[2].value = .number(0.5)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.scrollEvidence[0].contentHeight = capture.scrollEvidence[0].viewportHeight
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.observations.removeAll { $0.identifier == AXPredicateCatalog.scrollContract(for: id)?.anchorIdentifier }
        capture.traversal.nodeCount = capture.observations.count
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        let anchorIdentifier = AXPredicateCatalog.scrollContract(for: id)!.anchorIdentifier
        let anchorIndex = capture.observations.firstIndex { $0.identifier == anchorIdentifier }!
        capture.observations[anchorIndex].position = AXPoint(x: 120, y: 120)
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        capture.scrollEvidence[0].verticalScrollBarPath = "root/0/0"
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)

        capture = validCapture(id)
        let areaIndex = capture.observations.firstIndex {
            $0.identifier == AXPredicateCatalog.scrollContract(for: id)?.scrollIdentifier
        }!
        capture.observations[areaIndex].actions = ["AXScrollDownByPage"]
        XCTAssertFalse(try AXPredicateCatalog.evaluate(id: id, capture: capture).passed)
    }

    private func validCapture(_ id: String) -> AXRawCapture {
        switch id {
        case "confirmed-owner-headline":
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.controlSession),
                observation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.controlSessionTitle, label: "Vifty manual control active"),
                observation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.controlSessionSummary, label: "Owner: Vifty manual control")
            ])
        case "correct-per-fan-target":
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.fanStatus),
                observation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.leftFanDraftTarget, label: "Left Fan draft target", value: "Draft 2493 RPM"),
                observation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.rightFanDraftTarget, label: "Right Fan draft target", value: "Draft 3080 RPM")
            ])
        case "six-adjustable-point-controls", "no-duplicate-chart-elements":
            let controls = zip(
                AXEvidenceIdentifier.curveControls,
                [
                    ("Start temperature", "55 °C"),
                    ("Start RPM", "1200 RPM"),
                    ("Ramp temperature", "70 °C"),
                    ("Ramp RPM", "3500 RPM"),
                    ("High temperature", "85 °C"),
                    ("High RPM", "6200 RPM")
                ]
            ).enumerated().map { offset, pair in
                observation(
                    offset + 2,
                    "1/\(offset)",
                    role: "AXSlider",
                    identifier: pair.0,
                    label: pair.1.0,
                    value: pair.1.1,
                    actions: ["AXIncrement", "AXDecrement"]
                )
            }
            let summaries = [
                observation(
                    8,
                    "2/0",
                    role: "AXStaticText",
                    identifier: AXEvidenceIdentifier.leftFanEffectiveSummary,
                    label: "Left Fan effective curve",
                    value: "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5700 RPM"
                ),
                observation(
                    9,
                    "2/1",
                    role: "AXStaticText",
                    identifier: AXEvidenceIdentifier.rightFanEffectiveSummary,
                    label: "Right Fan effective curve",
                    value: "Start 55 °C, 2100 RPM; Ramp 70 °C, 4200 RPM; High 85 °C, 6400 RPM"
                )
            ]
            return baseCapture(id: id, observations: [
                observation(
                    0,
                    "0",
                    role: "AXCheckBox",
                    identifier: AXEvidenceIdentifier.curveSeparateFans,
                    label: "Separate fan curves",
                    selected: true,
                    actions: ["AXPress"],
                    position: AXPoint(x: 120, y: 180),
                    size: AXSize(width: 200, height: 22)
                ),
                observation(
                    1,
                    "1",
                    role: "AXGroup",
                    identifier: AXEvidenceIdentifier.curveChart,
                    position: AXPoint(x: 100, y: 220),
                    size: AXSize(width: 600, height: 300)
                )
            ] + controls + [
                observation(
                    8,
                    "2",
                    role: "AXGroup",
                    identifier: AXEvidenceIdentifier.curveEffectiveSummaries,
                    position: AXPoint(x: 100, y: 540),
                    size: AXSize(width: 600, height: 44)
                )
            ] + summaries)
        case "sensor-selected-trait-value":
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXOpaqueProviderGroup", identifier: AXEvidenceIdentifier.sensorList, actions: ["AXScrollToBottom", "AXScrollToTop"]),
                observation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.sensorCPU, label: "CPU Efficiency", value: "64.0 degrees Celsius, SMC", selected: true, actions: ["AXPress", "AXScrollToVisible"]),
                observation(2, "0/1", role: "AXButton", identifier: AXEvidenceIdentifier.sensorGPU, label: "GPU Hotspot", value: "83.0 degrees Celsius, HID", actions: ["AXPress", "AXScrollToVisible"]),
                observation(3, "0/2", role: "AXButton", identifier: AXEvidenceIdentifier.sensorPalm, label: "Palm Rest", value: "37.0 degrees Celsius, HID", actions: ["AXPress", "AXScrollToVisible"])
            ])
        case "explicit-temperature-role":
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.temperatureMetrics),
                observation(1, "0/0", role: "AXStaticText", identifier: AXEvidenceIdentifier.curveSensorMetric, label: "Curve sensor", value: "Curve sensor · CPU Efficiency"),
                observation(2, "0/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.highestTemperatureMetric, label: "Highest temperature", value: "Highest 83.0 °C")
            ])
        case "notification-actions":
            let events = zip(
                AXEvidenceIdentifier.notificationEvents,
                ["Helper failure", "High thermal pressure", "Auto restore failure", "Plugged-in battery drain", "Agent cooling attention"]
            ).enumerated().map { offset, pair in
                observation(
                    offset + 2,
                    "0/\(offset + 1)",
                    role: "AXCheckBox",
                    identifier: pair.0,
                    label: pair.1,
                    selected: true,
                    actions: ["AXPress"]
                )
            }
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.notifications),
                observation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.notificationOpenSettings, label: "Open Notification Settings", actions: ["AXPress"])
            ] + events)
        case "settings-logical-traversal":
            return baseCapture(id: id, observations: [
                observation(0, "0", role: "AXGroup", identifier: AXEvidenceIdentifier.settingsTabs, label: "Settings sections"),
                observation(1, "0/0", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabGeneral, label: "General", value: .string("Selected"), selected: true, actions: ["AXPress"]),
                observation(2, "0/1", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabMenuBar, label: "Menu Bar", value: .string("Not selected"), actions: ["AXPress"]),
                observation(3, "0/2", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabNotifications, label: "Notifications", value: .string("Not selected"), actions: ["AXPress"]),
                observation(4, "0/3", role: "AXButton", identifier: AXEvidenceIdentifier.settingsTabAgentWorkflows, label: "Agent Workflows", value: .string("Not selected"), actions: ["AXPress"]),
                observation(5, "1", role: "AXGroup", identifier: AXEvidenceIdentifier.settingsPaneGeneral, label: "General settings"),
                observation(6, "1/0", role: "AXCheckBox", identifier: AXEvidenceIdentifier.settingsUpdateAutomatic, label: "Automatically check for updates", selected: true, actions: ["AXPress"], position: AXPoint(x: 130, y: 160), size: AXSize(width: 300, height: 22)),
                observation(7, "1/1", role: "AXStaticText", identifier: AXEvidenceIdentifier.settingsUpdateStatus, label: "Vifty 1.3.3 is available.", position: AXPoint(x: 130, y: 190), size: AXSize(width: 300, height: 18)),
                observation(8, "1/2", role: "AXButton", identifier: AXEvidenceIdentifier.settingsUpdateLatest, label: "Update to latest version", help: "Opens Vifty's fixed GitHub release page in your default browser. Vifty does not download or install the update.", actions: ["AXPress"], position: AXPoint(x: 130, y: 220), size: AXSize(width: 190, height: 28)),
                observation(9, "1/3", role: "AXButton", identifier: AXEvidenceIdentifier.settingsUpdateCheck, label: "Check now", help: "Refreshes GitHub release availability without downloading or installing.", actions: ["AXPress"], position: AXPoint(x: 330, y: 220), size: AXSize(width: 90, height: 28)),
                observation(10, "1/4", role: "AXCheckBox", identifier: AXEvidenceIdentifier.settingsLaunchAtLogin, label: "Start Vifty at startup", selected: false, actions: ["AXPress"], position: AXPoint(x: 130, y: 360), size: AXSize(width: 250, height: 22))
            ])
        default:
            guard let contract = AXPredicateCatalog.scrollContract(for: id) else {
                fatalError("Missing valid fixture for \(id)")
            }
            let areaPath = "0"
            return baseCapture(
                id: id,
                observations: [
                    observation(
                        0,
                        areaPath,
                        role: "AXScrollArea",
                        identifier: contract.scrollIdentifier,
                        actions: ["AXScrollDownByPage", "AXScrollUpByPage"],
                        position: AXPoint(x: 100, y: 100),
                        size: AXSize(width: 600, height: 420)
                    ),
                    observation(1, "0/0", role: "AXStaticText", identifier: contract.anchorIdentifier, label: "End of content", position: AXPoint(x: 100, y: 700), size: AXSize(width: 100, height: 20)),
                    observation(2, "0/@vertical", role: "AXScrollBar", identifier: "\(contract.scrollIdentifier).vertical", value: .number(0))
                ],
                scrollEvidence: [AXScrollEvidence(
                    scrollAreaPath: areaPath,
                    verticalScrollBarPath: "0/@vertical",
                    minimumValue: 0,
                    maximumValue: 1,
                    currentValue: 0,
                    viewportHeight: 420,
                    contentHeight: 840
                )]
            )
        }
    }

    private func baseCapture(
        id: String,
        observations: [AXObservation],
        scrollEvidence: [AXScrollEvidence] = []
    ) -> AXRawCapture {
        let semanticRequest = AXPredicateCatalog.expectedRequest(for: id)!
        let request = AXEvidenceRequest(
            checkID: id,
            captureID: "capture-\(id)",
            processIdentifier: 4_242,
            windowIdentifier: "vifty-ui-review-ax-window-capture-\(id)",
            rootIdentifier: "vifty.ax.fixture.root.capture-\(id)",
            semanticRequest: semanticRequest
        )
        let identity = AXTargetIdentity(
            processIdentifier: request.processIdentifier,
            windowIdentifier: request.windowIdentifier,
            rootIdentifier: request.rootIdentifier
        )
        let root = observation(
            0,
            "root",
            role: "AXGroup",
            identifier: request.rootIdentifier,
            label: "Vifty UI review fixture",
            position: AXPoint(x: 0, y: 0),
            size: AXSize(width: 1_000, height: 1_000)
        )
        var boundObservations = [root] + observations.map { value in
            var value = value
            value.path = "root/\(value.path)"
            value.order += 1
            value.depth += 1
            return value
        }
        normalizeTraversalMetadata(&boundObservations)
        let boundScrollEvidence = scrollEvidence.map { value in
            var value = value
            value.scrollAreaPath = "root/\(value.scrollAreaPath)"
            value.verticalScrollBarPath = "root/\(value.verticalScrollBarPath)"
            return value
        }
        return AXRawCapture(
            request: request,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            source: "macos-accessibility-api",
            permissionTrusted: true,
            promptRequested: false,
            initialTarget: identity,
            finalTarget: identity,
            traversal: AXTraversal(
                complete: true,
                nodeCount: boundObservations.count,
                maximumNodeCount: 2_048,
                maximumDepth: 32,
                truncationReasons: []
            ),
            observations: boundObservations,
            scrollEvidence: boundScrollEvidence,
            actionsPerformed: [],
            readErrors: []
        )
    }

    private func observation(
        _ order: Int,
        _ path: String,
        role: String,
        identifier: String,
        label: String? = nil,
        value: AXTypedValue? = nil,
        help: String? = nil,
        selected: Bool? = nil,
        actions: [String] = [],
        position: AXPoint? = nil,
        size: AXSize? = nil
    ) -> AXObservation {
        AXObservation(
            path: path,
            order: order,
            depth: path.split(separator: "/").count - 1,
            role: role,
            identifier: identifier,
            description: label,
            label: label,
            help: help,
            value: value,
            enabled: true,
            selected: selected,
            position: position,
            size: size,
            actions: actions
        )
    }

    private func captureWithRootScrollArea(_ source: AXRawCapture) -> AXRawCapture {
        var capture = source
        let contract = AXPredicateCatalog.scrollContract(for: capture.request.checkID)!
        let area = capture.observations.first { $0.identifier == contract.scrollIdentifier }!
        var root = capture.observations.first { $0.identifier == capture.request.rootIdentifier }!
        var anchor = capture.observations.first { $0.identifier == contract.anchorIdentifier }!
        var bar = capture.observations.first { $0.role == "AXScrollBar" }!

        root.role = "AXScrollArea"
        root.position = area.position
        root.size = area.size
        root.actions = area.actions
        anchor.path = "root/0"
        bar.path = "root/@vertical"
        capture.observations = [root, anchor, bar]
        normalizeTraversalMetadata(&capture.observations)
        capture.traversal.nodeCount = capture.observations.count
        capture.scrollEvidence = [AXScrollEvidence(
            scrollAreaPath: "root",
            verticalScrollBarPath: "root/@vertical",
            minimumValue: nil,
            maximumValue: nil,
            currentValue: 0,
            viewportHeight: 420,
            contentHeight: 840
        )]
        return capture
    }


    private func appendObservation(_ observation: AXObservation, to capture: inout AXRawCapture) {
        capture.observations.append(observation)
        normalizeTraversalMetadata(&capture.observations)
        capture.traversal.nodeCount = capture.observations.count
    }

    private func normalizeTraversalMetadata(_ observations: inout [AXObservation]) {
        for index in observations.indices {
            observations[index].order = index
            let path = observations[index].path
            observations[index].depth = path.split(separator: "/").count - 1
            let prefix = path + "/"
            observations[index].childCount = observations.filter { candidate in
                guard candidate.path.hasPrefix(prefix) else { return false }
                let suffix = candidate.path.dropFirst(prefix.count)
                return !suffix.contains("/") && Int(suffix) != nil
            }.count
        }
    }
}
