import Foundation
import XCTest
import ViftyAXEvidenceCore
import ViftyBuildProvenance
@testable import ViftyAXCollector

final class AXCollectorAdapterTests: XCTestCase {
    func testSystemReaderOnlyTreatsGenericOptionalMetadataFailuresAsMissing() {
        XCTAssertTrue(
            AXSystemReader.treatsGenericFailureAsMissing(
                errorCode: -25_200,
                attribute: AXReadAttribute.valueDescription
            )
        )
        XCTAssertTrue(
            AXSystemReader.treatsGenericFailureAsMissing(
                errorCode: -25_200,
                attribute: AXReadAttribute.identifier
            )
        )
        XCTAssertFalse(
            AXSystemReader.treatsGenericFailureAsMissing(
                errorCode: -25_200,
                attribute: AXReadAttribute.description
            )
        )
        XCTAssertFalse(
            AXSystemReader.treatsGenericFailureAsMissing(
                errorCode: -25_200,
                attribute: AXReadAttribute.value
            )
        )
        XCTAssertFalse(
            AXSystemReader.treatsGenericFailureAsMissing(
                errorCode: -25_212,
                attribute: AXReadAttribute.valueDescription
            )
        )
    }

    func testNonWhitelistedGenericAPIFailureRemainsFailClosedWithOperationContext() {
        let reader = FakeAXReader.standard()
        reader.valueFailure = (
            .ownerTitle,
            AXReadAttribute.value,
            .apiFailure(operation: "AXUIElementCopyAttributeValue(AXValue)", code: -25_200)
        )

        XCTAssertThrowsError(try AXEvidenceCollector(reader: reader).collect(configuration())) { error in
            XCTAssertEqual(
                error as? AXCollectorError,
                .readFailure(
                    "apiFailure(operation: \"AXUIElementCopyAttributeValue(AXValue)\", code: -25200)"
                )
            )
            XCTAssertEqual(AXCollectorExitCode.code(for: error), AXCollectorExitCode.blocked)
        }
    }

    func testBuiltCollectorLinksOnlyReadSideAccessibilitySymbols() throws {
        let productsDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let binary = productsDirectory.appendingPathComponent("ViftyAXCollector")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), binary.path)

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
        process.arguments = ["-u", binary.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))

        let linkedAXSymbols = Set(
            String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { $0.hasPrefix("_AX") || $0.hasPrefix("_CGEvent") }
        )
        XCTAssertEqual(linkedAXSymbols, [
            "_AXIsProcessTrusted",
            "_AXUIElementCopyActionNames",
            "_AXUIElementCopyAttributeValue",
            "_AXUIElementCopyAttributeValues",
            "_AXUIElementCreateApplication",
            "_AXUIElementGetAttributeValueCount",
            "_AXUIElementGetPid",
            "_AXUIElementGetTypeID",
            "_AXUIElementSetMessagingTimeout",
            "_AXValueGetType",
            "_AXValueGetTypeID",
            "_AXValueGetValue"
        ])
    }

    func testPermissionMissingFailsWithoutPrompting() throws {
        let reader = FakeAXReader.standard()
        reader.permissionTrusted = false

        XCTAssertThrowsError(try AXEvidenceCollector(reader: reader).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .permissionMissing)
            XCTAssertEqual(AXCollectorExitCode.code(for: error), 77)
        }
        XCTAssertFalse(reader.promptRequested)

        let report = AXCollectorFailureReport(error: AXCollectorError.permissionMissing)
        XCTAssertEqual(report.schemaID, AXCollectorFailureReport.schemaID)
        XCTAssertEqual(report.code, "AX_PERMISSION_MISSING")
        XCTAssertFalse(report.promptRequested)
        XCTAssertTrue(report.readOnly)
        XCTAssertTrue(report.actionsPerformed.isEmpty)
    }

    func testCollectCLIPreservesStructuredPermissionAndBlockedArtifactsAtOutputPath() throws {
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let requestURL = temporary.appendingPathComponent("request.json")
        let semanticRequest = try XCTUnwrap(
            AXPredicateCatalog.expectedRequest(for: "confirmed-owner-headline")
        )
        try AXCanonicalJSON.data(semanticRequest).write(to: requestURL)

        let permissionOutput = temporary.appendingPathComponent("permission.json")
        let permissionReader = FakeAXReader.standard()
        permissionReader.permissionTrusted = false
        XCTAssertEqual(
            AXCollectorCLI.run(
                arguments: collectArguments(request: requestURL.path, output: permissionOutput.path),
                reader: permissionReader,
                collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector")
            ),
            AXCollectorExitCode.permissionMissing
        )
        let permissionReport = try JSONDecoder().decode(
            AXCollectorFailureReport.self,
            from: Data(contentsOf: permissionOutput)
        )
        XCTAssertEqual(permissionReport.code, "AX_PERMISSION_MISSING")
        XCTAssertFalse(permissionReport.promptRequested)
        XCTAssertTrue(permissionReport.readOnly)
        XCTAssertTrue(permissionReport.actionsPerformed.isEmpty)

        let blockedOutput = temporary.appendingPathComponent("blocked.json")
        let blockedReader = FakeAXReader.standard()
        blockedReader.records[.application]?.processIdentifier = 9_999
        XCTAssertEqual(
            AXCollectorCLI.run(
                arguments: collectArguments(request: requestURL.path, output: blockedOutput.path),
                reader: blockedReader,
                collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector")
            ),
            AXCollectorExitCode.blocked
        )
        let blockedData = try Data(contentsOf: blockedOutput)
        let blockedReport = try JSONDecoder().decode(AXCollectorFailureReport.self, from: blockedData)
        XCTAssertEqual(blockedReport.code, "AX_COLLECTION_BLOCKED")
        XCTAssertThrowsError(try JSONDecoder().decode(AXRawCapture.self, from: blockedData))
    }

    func testInvalidPIDAndPIDMismatchFailBeforeTraversal() throws {
        XCTAssertThrowsError(
            try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(configuration(processIdentifier: 0))
        ) { error in
            XCTAssertEqual(error as? AXCollectorError, .invalidConfiguration("process identifier must be positive"))
        }

        let reader = FakeAXReader.standard()
        reader.records[.application]?.processIdentifier = 9_999
        XCTAssertThrowsError(try AXEvidenceCollector(reader: reader).collect(configuration())) { error in
            XCTAssertEqual(
                error as? AXCollectorError,
                .processIdentifierMismatch(expected: 4_242, actual: 9_999)
            )
        }
    }

    func testWindowLookupRequiresExactlyOneExactIdentifier() throws {
        let missing = FakeAXReader.standard()
        missing.records[.application]?.elementAttributes[AXReadAttribute.windows] = []
        XCTAssertThrowsError(try AXEvidenceCollector(reader: missing).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .windowMatchCount(0))
        }

        let duplicate = FakeAXReader.standard()
        duplicate.records[.duplicateWindow] = duplicate.records[.window]
        duplicate.records[.duplicateWindow]?.children = [.duplicateRoot]
        duplicate.records[.duplicateRoot] = duplicate.records[.root]
        duplicate.records[.application]?.elementAttributes[AXReadAttribute.windows] = [.window, .duplicateWindow]
        XCTAssertThrowsError(try AXEvidenceCollector(reader: duplicate).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .windowMatchCount(2))
        }
    }

    func testRootLookupRequiresExactlyOneExactMarker() throws {
        let missing = FakeAXReader.standard()
        missing.records[.root]?.values[AXReadAttribute.identifier] = .string("wrong-root")
        XCTAssertThrowsError(try AXEvidenceCollector(reader: missing).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .rootMatchCount(0))
        }

        let duplicate = FakeAXReader.standard()
        duplicate.records[.window]?.children.append(.duplicateRoot)
        duplicate.records[.duplicateRoot] = duplicate.records[.root]
        duplicate.records[.duplicateRoot]?.children = []
        XCTAssertThrowsError(try AXEvidenceCollector(reader: duplicate).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .rootMatchCount(2))
        }
    }

    func testTimeoutAndDisappearingTargetFailClosed() throws {
        let timeout = FakeAXReader.standard()
        timeout.valueFailure = (.ownerTitle, AXReadAttribute.role, .timedOut)
        XCTAssertThrowsError(try AXEvidenceCollector(reader: timeout).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .timedOut)
        }

        let disappearing = FakeAXReader.standard()
        disappearing.failPIDReadAt = 3
        XCTAssertThrowsError(try AXEvidenceCollector(reader: disappearing).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .targetUnavailable)
        }
    }

    func testReplacedWindowOrRootFailsFinalIdentityCheck() throws {
        let reader = FakeAXReader.standard()
        reader.records[.duplicateWindow] = reader.records[.window]
        reader.records[.duplicateWindow]?.children = [.duplicateRoot]
        reader.records[.duplicateRoot] = reader.records[.root]
        reader.windowResults = [[.window], [.duplicateWindow]]

        XCTAssertThrowsError(try AXEvidenceCollector(reader: reader).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .targetReplaced)
        }
    }

    func testCycleDepthAndNodeBoundsFailClosed() throws {
        let cycle = FakeAXReader.standard()
        cycle.records[.ownerSummary]?.children = [.root]
        XCTAssertThrowsError(try AXEvidenceCollector(reader: cycle).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .cycleDetected)
        }

        XCTAssertThrowsError(
            try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(
                configuration(maximumDepth: 1)
            )
        ) { error in
            XCTAssertEqual(error as? AXCollectorError, .depthLimitExceeded)
        }

        XCTAssertThrowsError(
            try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(
                configuration(maximumNodeCount: 3)
            )
        ) { error in
            XCTAssertEqual(error as? AXCollectorError, .nodeLimitExceeded)
        }
    }

    func testTraversalRejectsOversizedStringsActionsChildrenAndNonfiniteGeometry() throws {
        let oversizedString = FakeAXReader.standard()
        oversizedString.records[.ownerTitle]?.values[AXReadAttribute.description] = .string(
            String(repeating: "x", count: 4_097)
        )
        XCTAssertThrowsError(try AXEvidenceCollector(reader: oversizedString).collect(configuration())) { error in
            XCTAssertEqual(
                error as? AXCollectorError,
                .readFailure("AXDescription exceeds the UTF-8 byte limit")
            )
        }

        let oversizedActions = FakeAXReader.standard()
        oversizedActions.records[.ownerTitle]?.actions = (0...256).map { "AXAction\($0)" }
        XCTAssertThrowsError(try AXEvidenceCollector(reader: oversizedActions).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .readFailure("action names exceed the count limit"))
        }

        let nonfiniteGeometry = FakeAXReader.standard()
        nonfiniteGeometry.records[.ownerTitle]?.values[AXReadAttribute.position] = .point(
            AXPoint(x: .infinity, y: 0)
        )
        XCTAssertThrowsError(try AXEvidenceCollector(reader: nonfiniteGeometry).collect(configuration())) { error in
            XCTAssertEqual(error as? AXCollectorError, .readFailure("AXPosition.x is not finite"))
        }

        let offscreenSentinel = FakeAXReader.standard()
        offscreenSentinel.records[.ownerTitle]?.values[AXReadAttribute.position] = .point(
            AXPoint(x: .infinity, y: .infinity)
        )
        let sentinelCapture = try AXEvidenceCollector(reader: offscreenSentinel).collect(configuration())
        XCTAssertNil(
            sentinelCapture.observations.first {
                $0.identifier == AXEvidenceIdentifier.controlSessionTitle
            }?.position
        )

        let oversizedChildren = FakeAXReader.standard()
        oversizedChildren.records[.root]?.children = [.ownerScope, .ownerTitle, .ownerSummary, .scrollArea]
        XCTAssertThrowsError(
            try AXEvidenceCollector(reader: oversizedChildren).collect(configuration(maximumNodeCount: 3))
        ) { error in
            XCTAssertEqual(error as? AXCollectorError, .nodeLimitExceeded)
        }
    }

    func testDeterministicPagedTraversalSortsActionsAndBindsIdentity() throws {
        let firstReader = FakeAXReader.standard()
        firstReader.records[.ownerTitle]?.actions = ["AXShowMenu", "AXPress", "AXPress"]
        let secondReader = FakeAXReader.standard()
        secondReader.records[.ownerTitle]?.actions = ["AXPress", "AXShowMenu"]

        let first = try AXEvidenceCollector(reader: firstReader).collect(configuration(childPageSize: 1))
        let second = try AXEvidenceCollector(reader: secondReader).collect(configuration(childPageSize: 1))

        XCTAssertEqual(try AXCanonicalJSON.data(first), try AXCanonicalJSON.data(second))
        XCTAssertEqual(first.schemaID, AXRawCapture.schemaID)
        XCTAssertEqual(first.source, "macos-accessibility-api")
        XCTAssertTrue(first.permissionTrusted)
        XCTAssertFalse(first.promptRequested)
        XCTAssertEqual(first.initialTarget, first.finalTarget)
        XCTAssertEqual(first.observations.map(\.path), ["root", "root/0", "root/0/0", "root/0/1"])
        XCTAssertEqual(first.observations.map(\.childCount), [1, 2, 0, 0])
        XCTAssertEqual(first.observations[2].actions, ["AXPress", "AXShowMenu"])
        XCTAssertEqual(first.observations[2].value, .boolean(true))
        XCTAssertEqual(firstReader.maximumRequestedPageSize, 1)
        XCTAssertTrue(first.actionsPerformed.isEmpty)
        XCTAssertTrue(first.readErrors.isEmpty)
    }

    func testTitleOnlyLabelsAndSelectableValueFallbackPreserveTypedValue() throws {
        let reader = FakeAXReader.standard()
        reader.records[.ownerTitle]?.values[AXReadAttribute.description] = nil
        reader.records[.ownerTitle]?.values[AXReadAttribute.title] = .string("Title-only button")
        reader.records[.ownerTitle]?.values[AXReadAttribute.role] = .string("AXButton")
        reader.records[.ownerSummary]?.values[AXReadAttribute.role] = .string("AXCheckBox")
        reader.records[.ownerSummary]?.values[AXReadAttribute.value] = .signedInteger(1)

        let capture = try AXEvidenceCollector(reader: reader).collect(configuration())
        let title = try XCTUnwrap(capture.observations.first { $0.identifier == AXEvidenceIdentifier.controlSessionTitle })
        let checkbox = try XCTUnwrap(capture.observations.first { $0.identifier == AXEvidenceIdentifier.controlSessionSummary })
        XCTAssertEqual(title.title, "Title-only button")
        XCTAssertNil(title.description)
        XCTAssertEqual(title.label, "Title-only button")
        XCTAssertEqual(checkbox.value, .signedInteger(1))
        XCTAssertEqual(checkbox.selected, true)

        let staticTextReader = FakeAXReader.standard()
        staticTextReader.records[.ownerTitle]?.values[AXReadAttribute.description] = nil
        staticTextReader.records[.ownerTitle]?.values[AXReadAttribute.title] = nil
        staticTextReader.records[.ownerTitle]?.values[AXReadAttribute.role] = .string("AXStaticText")
        staticTextReader.records[.ownerTitle]?.values[AXReadAttribute.value] = .string("Value-only text")
        let staticTextCapture = try AXEvidenceCollector(reader: staticTextReader).collect(configuration())
        let staticText = try XCTUnwrap(
            staticTextCapture.observations.first {
                $0.identifier == AXEvidenceIdentifier.controlSessionTitle
            }
        )
        XCTAssertEqual(staticText.label, "Value-only text")

        let valueOnlyControl = FakeAXReader.standard()
        valueOnlyControl.records[.ownerTitle]?.values[AXReadAttribute.description] = nil
        valueOnlyControl.records[.ownerTitle]?.values[AXReadAttribute.title] = nil
        valueOnlyControl.records[.ownerTitle]?.values[AXReadAttribute.role] = .string("AXButton")
        valueOnlyControl.records[.ownerTitle]?.values[AXReadAttribute.value] = .string("Not a control label")
        let controlCapture = try AXEvidenceCollector(reader: valueOnlyControl).collect(configuration())
        XCTAssertNil(
            controlCapture.observations.first {
                $0.identifier == AXEvidenceIdentifier.controlSessionTitle
            }?.label
        )

        let explicitReader = FakeAXReader.standard()
        explicitReader.records[.ownerSummary]?.values[AXReadAttribute.role] = .string("AXRadioButton")
        explicitReader.records[.ownerSummary]?.values[AXReadAttribute.value] = .number(1)
        explicitReader.records[.ownerSummary]?.values[AXReadAttribute.selected] = .boolean(false)
        let explicit = try AXEvidenceCollector(reader: explicitReader).collect(configuration())
        XCTAssertEqual(
            explicit.observations.first { $0.identifier == AXEvidenceIdentifier.controlSessionSummary }?.selected,
            false
        )
    }

    func testStructuralScrollEvidenceUsesLinkedBarAndObservedGeometry() throws {
        let reader = FakeAXReader.scrollFixture()
        reader.records[.scrollArea]?.children = [.scrollAnchor]
        reader.records[.root]?.children.append(.ownerSummary)
        reader.records[.ownerSummary] = FakeElementRecord(values: [
            AXReadAttribute.role: .string("AXStaticText"),
            AXReadAttribute.identifier: .string("vifty.ax.after-scroll")
        ])
        let capture = try AXEvidenceCollector(reader: reader).collect(
            configuration(checkID: "compact-main-scroll-reachable", childPageSize: 2)
        )

        let scroll = try XCTUnwrap(capture.scrollEvidence.only)
        let area = try XCTUnwrap(capture.observations.first { $0.identifier == AXEvidenceIdentifier.mainScroll })
        let anchor = try XCTUnwrap(capture.observations.first { $0.identifier == AXEvidenceIdentifier.mainScrollEnd })
        XCTAssertEqual(scroll.scrollAreaPath, area.path)
        XCTAssertTrue(scroll.verticalScrollBarPath.hasPrefix(area.path + "/"))
        XCTAssertEqual(scroll.minimumValue, 0)
        XCTAssertEqual(scroll.maximumValue, 1)
        XCTAssertEqual(scroll.currentValue, 0)
        XCTAssertEqual(scroll.viewportHeight, 420)
        XCTAssertGreaterThan(scroll.contentHeight, scroll.viewportHeight)
        XCTAssertGreaterThanOrEqual(anchor.position?.y ?? 0, 700)
        XCTAssertEqual(
            capture.observations.map(\.path),
            ["root", "root/0", "root/0/0", "root/0/@vertical", "root/1"]
        )
        XCTAssertEqual(scroll.verticalScrollBarPath, "root/0/@vertical")
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)
    }

    func testStructuralScrollEvidencePreservesUnavailableBoundsAsExplicitNulls() throws {
        let reader = FakeAXReader.scrollFixture()
        reader.records[.scrollBar]?.values[AXReadAttribute.minimumValue] = nil
        reader.records[.scrollBar]?.values[AXReadAttribute.maximumValue] = nil

        let capture = try AXEvidenceCollector(reader: reader).collect(
            configuration(checkID: "compact-main-scroll-reachable")
        )
        let scroll = try XCTUnwrap(capture.scrollEvidence.only)
        XCTAssertNil(scroll.minimumValue)
        XCTAssertNil(scroll.maximumValue)
        XCTAssertEqual(scroll.currentValue, 0)
        XCTAssertTrue(try AXPredicateCatalog.evaluate(id: capture.request.checkID, capture: capture).passed)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: AXCanonicalJSON.data(capture)) as? [String: Any]
        )
        let scrollRecords = try XCTUnwrap(object["scrollEvidence"] as? [[String: Any]])
        let encoded = try XCTUnwrap(scrollRecords.only)
        XCTAssertTrue(encoded["minimumValue"] is NSNull)
        XCTAssertTrue(encoded["maximumValue"] is NSNull)
    }

    func testCollectAndSealCommandParsersRequireExactArguments() throws {
        let collect = try AXCollectorCommand.parse(arguments: [
            "collect",
            "--pid", "4242",
            "--capture-id", "capture-owner",
            "--check-id", "confirmed-owner-headline",
            "--window-identifier", "vifty-ui-review-ax-window-capture-owner",
            "--root-identifier", "vifty.ax.fixture.root.capture-owner",
            "--request-json", "request.json",
            "--output", "raw.json"
        ])
        guard case let .collect(options) = collect else { return XCTFail("Expected collect") }
        XCTAssertEqual(options.processIdentifier, 4_242)
        XCTAssertEqual(options.outputPath, "raw.json")
        XCTAssertEqual(options.timeoutSeconds, 2)
        XCTAssertEqual(options.maximumNodeCount, 2_048)
        XCTAssertEqual(options.maximumDepth, 32)

        let seal = try AXCollectorCommand.parse(arguments: [
            "seal",
            "--raw-capture", "raw.json",
            "--raw-capture-sha256", String(repeating: "a", count: 64),
            "--fixture-report", "fixture-report.json",
            "--fixture-report-sha256", String(repeating: "b", count: 64),
            "--debug-executable", "Vifty",
            "--debug-executable-sha256", String(repeating: "c", count: 64),
            "--output", "sealed.json"
        ])
        guard case let .seal(options) = seal else { return XCTFail("Expected seal") }
        XCTAssertEqual(options.outputPath, "sealed.json")
        XCTAssertEqual(options.rawCapturePath, "raw.json")

        XCTAssertThrowsError(try AXCollectorCommand.parse(arguments: ["collect", "--pid", "4242"]))
        XCTAssertThrowsError(try AXCollectorCommand.parse(arguments: ["unknown"]))
        XCTAssertThrowsError(try AXCollectorCommand.parse(arguments: [
            "collect",
            "--pid", "4242",
            "--capture-id", "capture-owner",
            "--check-id", "confirmed-owner-headline",
            "--window-identifier", "vifty-ui-review-ax-window-capture-owner",
            "--root-identifier", "vifty.ax.fixture.root.capture-owner",
            "--request-json", "same.json",
            "--output", "same.json"
        ])) { error in
            XCTAssertEqual(error as? AXCollectorCommandError, .usage("--output must not alias an input path"))
        }

        let aliases = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: aliases) }
        let input = aliases.appendingPathComponent("request.json")
        let hardLink = aliases.appendingPathComponent("output.json")
        try Data("{}".utf8).write(to: input)
        try FileManager.default.linkItem(at: input, to: hardLink)
        XCTAssertThrowsError(try AXCollectorCommand.parse(arguments: [
            "collect",
            "--pid", "4242",
            "--capture-id", "capture-owner",
            "--check-id", "confirmed-owner-headline",
            "--window-identifier", "vifty-ui-review-ax-window-capture-owner",
            "--root-identifier", "vifty.ax.fixture.root.capture-owner",
            "--request-json", input.path,
            "--output", hardLink.path
        ])) { error in
            XCTAssertEqual(error as? AXCollectorCommandError, .usage("--output must not alias an input path"))
        }

        let ioError = CocoaError(.fileReadNoSuchFile)
        XCTAssertEqual(AXCollectorExitCode.code(for: ioError), AXCollectorExitCode.inputOutput)
        XCTAssertEqual(AXCollectorFailureReport(error: ioError).code, "AX_IO_ERROR")
    }

    func testSealerRecomputesHashesAndRequiresFinalSafeMatchingFixture() throws {
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let raw = try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(configuration())
        let rawURL = temporary.appendingPathComponent("raw.json")
        try AXCanonicalJSON.data(raw).write(to: rawURL)

        let executableURL = temporary.appendingPathComponent("Vifty")
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: executableURL)
        let executableSHA = try AXArtifactHasher.sha256(atPath: executableURL.path)
        let fixture = AXFixtureReportEnvelope.valid(
            capture: raw,
            executablePath: executableURL.path,
            executableSHA256: executableSHA
        )
        let fixtureURL = temporary.appendingPathComponent("fixture-report.json")
        try AXCanonicalJSON.data(fixture).write(to: fixtureURL)

        let configuration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: try AXArtifactHasher.sha256(atPath: rawURL.path),
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: temporary.appendingPathComponent("sealed.json").path
        )
        let sealed = try AXEvidenceSealer.seal(configuration)
        XCTAssertEqual(sealed.schemaID, AXSealedReport.schemaID)
        XCTAssertTrue(sealed.assertion.passed)
        XCTAssertEqual(sealed.rawCapture.sha256, configuration.expectedRawCaptureSHA256)
        XCTAssertEqual(sealed.fixtureReport.sha256, configuration.expectedFixtureReportSHA256)
        XCTAssertEqual(sealed.debugExecutableSHA256, executableSHA)
        XCTAssertEqual(sealed.runtimeIdentity, raw.finalTarget)
        XCTAssertTrue(sealed.actionsPerformed.isEmpty)
        XCTAssertTrue(fixture.recorder.isSafe)

        var driftedObservationFixture = fixture
        driftedObservationFixture.observed?.environment.appearance = "dark"
        try AXCanonicalJSON.data(driftedObservationFixture).write(to: fixtureURL)
        let driftedObservationConfiguration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: configuration.expectedRawCaptureSHA256,
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(driftedObservationConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .fixtureBindingMismatch("observed appearance"))
        }

        var invalidRuntimeFixture = fixture
        invalidRuntimeFixture.runtimeIdentity?.windowNumber = 0
        try AXCanonicalJSON.data(invalidRuntimeFixture).write(to: fixtureURL)
        let invalidRuntimeConfiguration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: configuration.expectedRawCaptureSHA256,
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(invalidRuntimeConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .fixtureBindingMismatch("runtime window number"))
        }

        var screenshotFixture = fixture
        screenshotFixture.screenshot = AXFixtureScreenshotObservation(
            method: "native-window-screencapture-crop",
            artifactPath: "unexpected.png",
            sha256: String(repeating: "0", count: 64),
            pointWidth: 1_180,
            pointHeight: 820,
            pixelWidth: 2_360,
            pixelHeight: 1_640,
            backingScaleFactor: 2
        )
        try AXCanonicalJSON.data(screenshotFixture).write(to: fixtureURL)
        let screenshotConfiguration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: configuration.expectedRawCaptureSHA256,
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(screenshotConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .fixtureNotFinalAndSafe)
        }

        var forgedRecorderFixture = fixture
        forgedRecorderFixture.recorder.fixtureConstructions.removeLast()
        XCTAssertFalse(forgedRecorderFixture.recorder.isSafe)
        try AXCanonicalJSON.data(forgedRecorderFixture).write(to: fixtureURL)
        let forgedRecorderConfiguration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: configuration.expectedRawCaptureSHA256,
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(forgedRecorderConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .fixtureNotFinalAndSafe)
        }

        var unknownReadRecorder = fixture.recorder
        unknownReadRecorder.readOperations.append("filesystem-write")
        XCTAssertFalse(unknownReadRecorder.isSafe)

        var unsafeFixture = fixture
        unsafeFixture.phase = "ready"
        try AXCanonicalJSON.data(unsafeFixture).write(to: fixtureURL)
        let unsafeConfiguration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: configuration.expectedRawCaptureSHA256,
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(unsafeConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .fixtureNotFinalAndSafe)
        }

        var badHash = configuration
        badHash.expectedRawCaptureSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try AXEvidenceSealer.seal(badHash)) { error in
            XCTAssertEqual(error as? AXSealError, .artifactHashMismatch("raw capture"))
        }
    }

    func testSealerRejectsNoncanonicalRawBytesEvenWhenTheirHashMatches() throws {
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let raw = try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(configuration())
        let rawURL = temporary.appendingPathComponent("raw.json")
        var rawData = try AXCanonicalJSON.data(raw)
        rawData.append(Data("\n".utf8))
        try rawData.write(to: rawURL)

        let executableURL = temporary.appendingPathComponent("Vifty")
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: executableURL)
        let executableSHA = try AXArtifactHasher.sha256(atPath: executableURL.path)
        let fixture = AXFixtureReportEnvelope.valid(
            capture: raw,
            executablePath: executableURL.path,
            executableSHA256: executableSHA
        )
        let fixtureURL = temporary.appendingPathComponent("fixture-report.json")
        try AXCanonicalJSON.data(fixture).write(to: fixtureURL)

        let configuration = AXSealConfiguration(
            rawCapturePath: rawURL.path,
            expectedRawCaptureSHA256: try AXArtifactHasher.sha256(atPath: rawURL.path),
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: temporary.appendingPathComponent("sealed.json").path
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(configuration)) { error in
            XCTAssertEqual(error as? AXSealError, .rawCaptureNotCanonical)
        }
    }

    func testSealerRejectsSymlinkedArtifactsEvenWhenTargetHashesMatch() throws {
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let raw = try AXEvidenceCollector(reader: FakeAXReader.standard()).collect(configuration())
        let rawTarget = temporary.appendingPathComponent("raw-target.json")
        try AXCanonicalJSON.data(raw).write(to: rawTarget)
        let rawLink = temporary.appendingPathComponent("raw-link.json")
        try FileManager.default.createSymbolicLink(at: rawLink, withDestinationURL: rawTarget)

        let executableURL = temporary.appendingPathComponent("Vifty")
        try TestBuildProvenance.thinMachO(
            provenance: TestBuildProvenance.identity(role: "debug-fixture-app")
        ).write(to: executableURL)
        let executableSHA = try AXArtifactHasher.sha256(atPath: executableURL.path)
        let fixture = AXFixtureReportEnvelope.valid(
            capture: raw,
            executablePath: executableURL.path,
            executableSHA256: executableSHA
        )
        let fixtureURL = temporary.appendingPathComponent("fixture-report.json")
        try AXCanonicalJSON.data(fixture).write(to: fixtureURL)

        let configuration = AXSealConfiguration(
            rawCapturePath: rawLink.path,
            expectedRawCaptureSHA256: try AXArtifactHasher.sha256(atPath: rawLink.path),
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: executableURL.path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: temporary.appendingPathComponent("sealed.json").path
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(configuration)) { error in
            XCTAssertEqual(error as? AXSealError, .artifactNotRegular("raw capture"))
        }

        let rawConfiguration = AXSealConfiguration(
            rawCapturePath: rawTarget.path,
            expectedRawCaptureSHA256: try AXArtifactHasher.sha256(atPath: rawTarget.path),
            fixtureReportPath: fixtureURL.path,
            expectedFixtureReportSHA256: try AXArtifactHasher.sha256(atPath: fixtureURL.path),
            debugExecutablePath: temporary.appendingPathComponent("Vifty-link").path,
            expectedDebugExecutableSHA256: executableSHA,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector"),
            outputPath: configuration.outputPath
        )
        try FileManager.default.createSymbolicLink(
            at: URL(fileURLWithPath: rawConfiguration.debugExecutablePath),
            withDestinationURL: executableURL
        )
        XCTAssertThrowsError(try AXEvidenceSealer.seal(rawConfiguration)) { error in
            XCTAssertEqual(error as? AXSealError, .artifactNotRegular("debug executable"))
        }
    }

    func testAdvertisedRawSealedAndErrorSchemaFilesMatchModelContracts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contracts: [(String, String)] = [
            ("ui-review-ax-raw-capture-v1.schema.json", AXRawCapture.schemaID),
            ("ui-review-ax-sealed-report-v1.schema.json", AXSealedReport.schemaID),
            ("ui-review-ax-collector-error-v1.schema.json", AXCollectorFailureReport.schemaID)
        ]
        for (filename, schemaID) in contracts {
            let url = root.appendingPathComponent("docs/schemas/\(filename)")
            let schema = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                filename
            )
            XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema", filename)
            XCTAssertEqual(schema["$id"] as? String, schemaID, filename)
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false, filename)
        }

        let rawURL = root.appendingPathComponent("docs/schemas/ui-review-ax-raw-capture-v1.schema.json")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: rawURL)) as? [String: Any])
        let definitions = try XCTUnwrap(raw["$defs"] as? [String: Any])
        let observation = try XCTUnwrap(definitions["observation"] as? [String: Any])
        let observationProperties = try XCTUnwrap(observation["properties"] as? [String: Any])
        XCTAssertNotNil(observationProperties["description"])
        XCTAssertNotNil(observationProperties["value"])
        XCTAssertNotNil(observationProperties["valueDescription"])
        XCTAssertNotNil(definitions["typedValue"])

        let scrollEvidence = try XCTUnwrap(definitions["scrollEvidence"] as? [String: Any])
        let scrollProperties = try XCTUnwrap(scrollEvidence["properties"] as? [String: Any])
        let minimumValue = try XCTUnwrap(scrollProperties["minimumValue"] as? [String: Any])
        let maximumValue = try XCTUnwrap(scrollProperties["maximumValue"] as? [String: Any])
        XCTAssertEqual(minimumValue["type"] as? [String], ["number", "null"])
        XCTAssertEqual(maximumValue["type"] as? [String], ["number", "null"])
        XCTAssertEqual((scrollEvidence["oneOf"] as? [[String: Any]])?.count, 2)
    }

    private func configuration(
        processIdentifier: Int32 = 4_242,
        checkID: String = "confirmed-owner-headline",
        maximumNodeCount: Int = 2_048,
        maximumDepth: Int = 32,
        childPageSize: Int = 64
    ) -> AXCollectionConfiguration {
        let captureID = "capture-owner"
        let semanticRequest = AXPredicateCatalog.expectedRequest(for: checkID)!
        return AXCollectionConfiguration(
            request: AXEvidenceRequest(
                checkID: checkID,
                captureID: captureID,
                processIdentifier: processIdentifier,
                windowIdentifier: "vifty-ui-review-ax-window-\(captureID)",
                rootIdentifier: "vifty.ax.fixture.root.\(captureID)",
                semanticRequest: semanticRequest
            ),
            timeoutSeconds: 2,
            maximumNodeCount: maximumNodeCount,
            maximumDepth: maximumDepth,
            childPageSize: childPageSize,
            collectorBuildProvenance: TestBuildProvenance.identity(role: "ax-collector")
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViftyAXCollectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func collectArguments(request: String, output: String) -> [String] {
        [
            "collect",
            "--pid", "4242",
            "--capture-id", "capture-owner",
            "--check-id", "confirmed-owner-headline",
            "--window-identifier", "vifty-ui-review-ax-window-capture-owner",
            "--root-identifier", "vifty.ax.fixture.root.capture-owner",
            "--request-json", request,
            "--output", output
        ]
    }
}

private enum FakeElement: String, Hashable {
    case application
    case window
    case duplicateWindow
    case root
    case duplicateRoot
    case ownerScope
    case ownerTitle
    case ownerSummary
    case scrollArea
    case scrollAnchor
    case scrollBar
}

private struct FakeElementRecord {
    var processIdentifier: Int32 = 4_242
    var values: [String: AXTypedValue] = [:]
    var children: [FakeElement] = []
    var elementAttributes: [String: [FakeElement]] = [:]
    var actions: [String] = []
}

private final class FakeAXReader: AXReadAdapter {
    typealias Element = FakeElement

    var permissionTrusted = true
    var promptRequested = false
    var records: [FakeElement: FakeElementRecord]
    var valueFailure: (FakeElement, String, AXReadError)?
    var failPIDReadAt: Int?
    var windowResults: [[FakeElement]]?
    private(set) var maximumRequestedPageSize = 0
    private var pidReadCount = 0
    private var windowsReadCount = 0

    init(records: [FakeElement: FakeElementRecord]) {
        self.records = records
    }

    func isProcessTrusted() -> Bool { permissionTrusted }

    func application(processIdentifier _: Int32) -> FakeElement { .application }

    func processIdentifier(of element: FakeElement) throws -> Int32 {
        pidReadCount += 1
        if pidReadCount == failPIDReadAt { throw AXReadError.invalidElement }
        guard let record = records[element] else { throw AXReadError.invalidElement }
        return record.processIdentifier
    }

    func setMessagingTimeout(_: Double, for _: FakeElement) throws {}

    func elements(for attribute: String, of element: FakeElement) throws -> [FakeElement] {
        if element == .application,
           attribute == AXReadAttribute.windows,
           let windowResults {
            let result = windowResults[min(windowsReadCount, windowResults.count - 1)]
            windowsReadCount += 1
            return result
        }
        return records[element]?.elementAttributes[attribute] ?? []
    }

    func value(for attribute: String, of element: FakeElement) throws -> AXTypedValue? {
        if let valueFailure,
           valueFailure.0 == element,
           valueFailure.1 == attribute {
            throw valueFailure.2
        }
        return records[element]?.values[attribute]
    }

    func childCount(of element: FakeElement) throws -> Int {
        guard let record = records[element] else { throw AXReadError.invalidElement }
        return record.children.count
    }

    func children(of element: FakeElement, startingAt index: Int, count: Int) throws -> [FakeElement] {
        maximumRequestedPageSize = max(maximumRequestedPageSize, count)
        guard let children = records[element]?.children,
              index >= 0,
              count >= 0,
              index <= children.count else { throw AXReadError.invalidElement }
        return Array(children[index..<min(children.count, index + count)])
    }

    func actionNames(of element: FakeElement) throws -> [String] {
        records[element]?.actions ?? []
    }

    func elementsEqual(_ lhs: FakeElement, _ rhs: FakeElement) -> Bool { lhs == rhs }

    static func standard() -> FakeAXReader {
        let captureID = "capture-owner"
        return FakeAXReader(records: [
            .application: FakeElementRecord(
                elementAttributes: [AXReadAttribute.windows: [.window]]
            ),
            .window: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXWindow"),
                    AXReadAttribute.identifier: .string("vifty-ui-review-ax-window-\(captureID)")
                ],
                children: [.root]
            ),
            .root: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXGroup"),
                    AXReadAttribute.identifier: .string("vifty.ax.fixture.root.\(captureID)"),
                    AXReadAttribute.description: .string("Vifty UI review fixture")
                ],
                children: [.ownerScope]
            ),
            .ownerScope: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXGroup"),
                    AXReadAttribute.identifier: .string(AXEvidenceIdentifier.controlSession)
                ],
                children: [.ownerTitle, .ownerSummary]
            ),
            .ownerTitle: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXStaticText"),
                    AXReadAttribute.identifier: .string(AXEvidenceIdentifier.controlSessionTitle),
                    AXReadAttribute.description: .string("Vifty manual control active"),
                    AXReadAttribute.value: .boolean(true),
                    AXReadAttribute.enabled: .boolean(true)
                ]
            ),
            .ownerSummary: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXStaticText"),
                    AXReadAttribute.identifier: .string(AXEvidenceIdentifier.controlSessionSummary),
                    AXReadAttribute.description: .string("Owner: Vifty manual control"),
                    AXReadAttribute.enabled: .boolean(true)
                ]
            )
        ])
    }

    static func scrollFixture() -> FakeAXReader {
        let captureID = "capture-owner"
        return FakeAXReader(records: [
            .application: FakeElementRecord(
                elementAttributes: [AXReadAttribute.windows: [.window]]
            ),
            .window: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXWindow"),
                    AXReadAttribute.identifier: .string("vifty-ui-review-ax-window-\(captureID)")
                ],
                children: [.root]
            ),
            .root: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXGroup"),
                    AXReadAttribute.identifier: .string("vifty.ax.fixture.root.\(captureID)")
                ],
                children: [.scrollArea]
            ),
            .scrollArea: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXScrollArea"),
                    AXReadAttribute.identifier: .string(AXEvidenceIdentifier.mainScroll),
                    AXReadAttribute.position: .point(AXPoint(x: 100, y: 100)),
                    AXReadAttribute.size: .size(AXSize(width: 600, height: 420))
                ],
                children: [.scrollAnchor, .scrollBar],
                elementAttributes: [AXReadAttribute.verticalScrollBar: [.scrollBar]],
                actions: ["AXScrollDownByPage", "AXScrollUpByPage"]
            ),
            .scrollAnchor: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXStaticText"),
                    AXReadAttribute.identifier: .string(AXEvidenceIdentifier.mainScrollEnd),
                    AXReadAttribute.description: .string("End of content"),
                    AXReadAttribute.position: .point(AXPoint(x: 100, y: 700)),
                    AXReadAttribute.size: .size(AXSize(width: 100, height: 20))
                ]
            ),
            .scrollBar: FakeElementRecord(
                values: [
                    AXReadAttribute.role: .string("AXScrollBar"),
                    AXReadAttribute.identifier: .string("vifty.ax.scroll.main.vertical"),
                    AXReadAttribute.value: .number(0),
                    AXReadAttribute.minimumValue: .number(0),
                    AXReadAttribute.maximumValue: .number(1)
                ]
            )
        ])
    }
}

private extension AXFixtureReportEnvelope {
    static func valid(
        capture: AXRawCapture,
        executablePath: String,
        executableSHA256: String
    ) -> AXFixtureReportEnvelope {
        AXFixtureReportEnvelope(
            schemaVersion: 3,
            captureID: capture.request.captureID,
            request: capture.request.semanticRequest,
            requestSHA256: capture.request.requestSHA256,
            debugExecutablePath: executablePath,
            debugExecutableSHA256: executableSHA256,
            debugBuildProvenance: TestBuildProvenance.identity(role: "debug-fixture-app"),
            runtimeIdentity: AXFixtureRuntimeIdentity(
                processIdentifier: capture.request.processIdentifier,
                executablePath: executablePath,
                executableSHA256: executableSHA256,
                windowNumber: 42,
                windowIdentifier: "vifty-ui-review-window-\(capture.request.captureID)",
                accessibilityIdentifier: capture.request.windowIdentifier,
                windowClass: "NSWindow",
                containerKind: "main-window",
                provenance: "swiftui-main-window",
                isVisible: true,
                contentWidth: 1_180,
                contentHeight: 820,
                backingScaleFactor: 2
            ),
            observed: AXFixtureObservation(
                environment: AXFixtureEnvironmentObservation(
                    source: "swiftui-environment",
                    appearance: capture.request.semanticRequest.appearance,
                    contrast: capture.request.semanticRequest.contrast,
                    transparency: capture.request.semanticRequest.transparency,
                    textSize: capture.request.semanticRequest.textSize
                ),
                window: AXFixtureWindowObservation(
                    source: "nswindow-content-layout-rect",
                    provenance: "swiftui-main-window",
                    windowIdentifier: "vifty-ui-review-window-\(capture.request.captureID)",
                    accessibilityIdentifier: capture.request.windowIdentifier,
                    windowNumber: 42,
                    windowClass: "NSWindow",
                    containerKind: "main-window",
                    isVisible: true,
                    contentWidth: 1_180,
                    contentHeight: 820,
                    backingScaleFactor: 2
                )
            ),
            screenshot: nil,
            phase: "final",
            modelStartSkipped: true,
            recorder: AXFixtureSafetyRecorder(
                fixtureConstructions: [
                    "hardware",
                    "notification-center",
                    "login-item",
                    "helper-installer",
                    "daemon-client",
                    "power-client"
                ],
                readOperations: [
                    "hardware-snapshot",
                    "fan-control-ownership",
                    "power",
                    "thermal-pressure",
                    "daemon-ping",
                    "agent-status",
                    "notification-authorization",
                    "login-item-status",
                    "codex-usage",
                    "power"
                ],
                attemptedHardwareCommands: [],
                attemptedExternalMutations: [],
                realControlPathConstructions: []
            ),
            runtimeFailure: nil,
            passed: true
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
