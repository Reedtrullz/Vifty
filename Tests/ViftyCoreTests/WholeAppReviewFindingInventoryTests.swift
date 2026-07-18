import Foundation
import XCTest

final class WholeAppReviewFindingInventoryTests: XCTestCase {
    private struct Finding: Equatable {
        var id: String
        var title: String
        var planResolution: String
        var tasks: [Int]
        var testSuites: [String]
    }

    private static let inventory: [Finding] = [
        Finding(
            id: "F01",
            title: "Empty/partial restore clears ownership",
            planResolution: "Tasks 1, 3, 4",
            tasks: [1, 3, 4],
            testSuites: ["FanControlArbiterTests", "AgentControlServiceTests", "FanControlCoordinatorTests"]
        ),
        Finding(
            id: "F02",
            title: "Non-transactional mode/target/`Ftst` writes",
            planResolution: "Task 2",
            tasks: [2],
            testSuites: ["LocalFanHelperClientTests"]
        ),
        Finding(
            id: "F03",
            title: "Manual/agent daemon race and per-fan global lease clear",
            planResolution: "Tasks 3-4",
            tasks: [3, 4],
            testSuites: ["FanControlArbiterTests", "DaemonServiceTests", "AgentControlServiceTests"]
        ),
        Finding(
            id: "F04",
            title: "Fail-open marker/lease persistence",
            planResolution: "Tasks 1, 3-4",
            tasks: [1, 3, 4],
            testSuites: ["FanControlJournalStoreTests", "AgentControlServiceTests", "ViftyCtlRunnerTests"]
        ),
        Finding(
            id: "F05",
            title: "Synthesized SMC bounds authorize writes",
            planResolution: "Task 1",
            tasks: [1],
            testSuites: ["FanInfoReaderTests", "AgentControlPolicyTests"]
        ),
        Finding(
            id: "F06",
            title: "Forced/Unknown readiness and direct-prepare ownership gaps",
            planResolution: "Task 4",
            tasks: [4],
            testSuites: ["FanControlArbiterTests", "AgentControlServiceTests", "ViftyCtlRunnerTests"]
        ),
        Finding(
            id: "F07",
            title: "Ad-hoc daemon identity too weak",
            planResolution: "Task 4",
            tasks: [4],
            testSuites: ["XPCClientValidatorTests", "DaemonServiceTests"]
        ),
        Finding(
            id: "F08",
            title: "Unsafe repair, installer, shutdown, cask uninstall",
            planResolution: "Task 5",
            tasks: [5],
            testSuites: ["DaemonLifecycleCoordinatorTests", "DaemonInstallerTests", "HelperLifecycleScriptTests"]
        ),
        Finding(
            id: "F09",
            title: "Main-actor-blocking administrator prompt",
            planResolution: "Task 5",
            tasks: [5],
            testSuites: ["DaemonInstallServiceTests", "AppModelHelperHealthTests"]
        ),
        Finding(
            id: "F10",
            title: "Installer force-kill and unbounded `/tmp` fallback",
            planResolution: "Task 5",
            tasks: [5],
            testSuites: ["DaemonInstallerTests", "HelperLifecycleScriptTests"]
        ),
        Finding(
            id: "F11",
            title: "Per-fan curve preview differs from applied command",
            planResolution: "Task 6",
            tasks: [6],
            testSuites: ["FanCurveTargetResolverTests", "AppModelFanControlTests", "FanControlCoordinatorTests"]
        ),
        Finding(
            id: "F12",
            title: "Menu ownership headline inferred from editor state",
            planResolution: "Task 6",
            tasks: [6],
            testSuites: ["ControlSessionPresentationTests", "MenuBarPanelPresentationTests"]
        ),
        Finding(
            id: "F13",
            title: "Notification preferences hide authorization state",
            planResolution: "Task 6",
            tasks: [6],
            testSuites: ["NotificationAuthorizationTests", "AppModelNotificationTests"]
        ),
        Finding(
            id: "F14",
            title: "Profile dirty/overwrite ambiguity",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["CurveProfilePresentationTests", "AppModelPreferencesTests"]
        ),
        Finding(
            id: "F15",
            title: "Profile backup unused and decoded points unsorted",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["CurveProfileStoreTests", "CurveProfileTests"]
        ),
        Finding(
            id: "F16",
            title: "Selected temperature conflated with hottest",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["TemperatureSensorSelectionTests", "TelemetryHistoryTests"]
        ),
        Finding(
            id: "F17",
            title: "Smoothed plot presented as raw evidence",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["SparklineGeometryTests", "TelemetryHistoryTests"]
        ),
        Finding(
            id: "F18",
            title: "Curve handles not directly AX-adjustable",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["CurvePointAdjustmentTests", "FanCurveChartPresentationTests"]
        ),
        Finding(
            id: "F19",
            title: "Settings vertical dead space and weak hierarchy",
            planResolution: "Task 7",
            tasks: [7],
            testSuites: ["SettingsSceneSourceTests", "ViftyReviewFixtureTests"]
        ),
        Finding(
            id: "F20",
            title: "Stale README screenshot and incomplete appearance/AX QA",
            planResolution: "Task 8",
            tasks: [8],
            testSuites: ["ViftyReviewFixtureTests", "UIReviewEvidenceScriptTests"]
        ),
        Finding(
            id: "F21",
            title: "Thin arm64 artifact lacks cask/public constraint",
            planResolution: "Task 9",
            tasks: [9],
            testSuites: ["ReleaseArtifactScriptTests", "ReleaseMetadataScriptTests"]
        ),
        Finding(
            id: "F22",
            title: "Release credentials imported too early/write token too broad",
            planResolution: "Task 9",
            tasks: [9],
            testSuites: ["ReleaseManifestScriptTests", "ReleaseMetadataScriptTests"]
        ),
        Finding(
            id: "F23",
            title: "Unsigned/unproven tag provenance",
            planResolution: "Task 9",
            tasks: [9],
            testSuites: ["ReleaseProvenanceScriptTests"]
        ),
        Finding(
            id: "F24",
            title: "Artifact verifier omits app/daemon identity and architecture",
            planResolution: "Task 9",
            tasks: [9],
            testSuites: ["ReleaseArtifactScriptTests"]
        ),
        Finding(
            id: "F25",
            title: "Contradictory release/security/docs versions",
            planResolution: "Task 10",
            tasks: [10],
            testSuites: ["ReleaseManifestScriptTests", "DocumentationTrustSurfaceTests"]
        ),
        Finding(
            id: "F26",
            title: "Hardware issue form lacks truthful not-run option",
            planResolution: "Task 10",
            tasks: [10],
            testSuites: ["GitHubMetadataScriptTests", "DocumentationTrustSurfaceTests"]
        ),
        Finding(
            id: "F27",
            title: "Text-oriented workflow/community gates",
            planResolution: "Tasks 9-10",
            tasks: [9, 10],
            testSuites: ["ReleaseManifestScriptTests", "CommunityStandardsScriptTests", "GitHubMetadataScriptTests"]
        ),
        Finding(
            id: "F28",
            title: "Daemon/helper executable logic not behavior-testable",
            planResolution: "Tasks 3, 5, 11",
            tasks: [3, 5, 11],
            testSuites: ["DaemonServiceTests", "HelperCommandRunnerTests", "AppArchitectureBoundaryTests"]
        ),
        Finding(
            id: "F29",
            title: "`AppModel`, `FanControlPanel`, and tests oversized",
            planResolution: "Task 11",
            tasks: [11],
            testSuites: ["AppModelFanControlTests", "FanControlPanelPresentationTests", "AppArchitectureBoundaryTests"]
        ),
        Finding(
            id: "F30",
            title: "Real sleeps and polling flake risk",
            planResolution: "Task 11",
            tasks: [11],
            testSuites: ["AppPollingControllerTests", "AppModelPollingTests"]
        ),
        Finding(
            id: "F31",
            title: "CLI signal forwarding ignores process groups",
            planResolution: "Task 12",
            tasks: [12],
            testSuites: ["ViftyCtlProcessRunnerTests", "ViftyCtlRunnerTests"]
        ),
        Finding(
            id: "F32",
            title: "Path-casing and monotonic build-number gaps",
            planResolution: "Tasks 9-10",
            tasks: [9, 10],
            testSuites: ["ReleaseManifestScriptTests", "CommunityStandardsScriptTests", "ReleaseMetadataScriptTests"]
        )
    ]

    func testPlanCoverageMatrixMatchesExecutableInventory() throws {
        let planRows = try Self.planCoverageRows()
        let inventoryByTitle = Dictionary(uniqueKeysWithValues: Self.inventory.map { ($0.title, $0) })

        XCTAssertEqual(planRows.count, Self.inventory.count, "Every plan matrix row must have one inventory owner.")
        XCTAssertEqual(
            Set(planRows.map(\.title)),
            Set(inventoryByTitle.keys),
            "Adding, removing, or renaming a review finding requires an explicit inventory update."
        )

        for row in planRows {
            let finding = try XCTUnwrap(inventoryByTitle[row.title], "Missing inventory record for \(row.title)")
            XCTAssertEqual(
                row.resolution,
                finding.planResolution,
                "Changing task ownership for \(finding.id) requires an explicit inventory update."
            )
        }
    }

    func testEveryFindingHasUniqueTaskAndTestSuiteOwners() {
        XCTAssertEqual(Set(Self.inventory.map(\.id)).count, Self.inventory.count)
        XCTAssertEqual(Set(Self.inventory.map(\.title)).count, Self.inventory.count)

        for finding in Self.inventory {
            XCTAssertFalse(finding.tasks.isEmpty, "\(finding.id) has no owning task.")
            XCTAssertEqual(Set(finding.tasks).count, finding.tasks.count, "\(finding.id) repeats a task owner.")
            XCTAssertTrue(finding.tasks.allSatisfy { (1...13).contains($0) }, "\(finding.id) references an unknown task.")

            XCTAssertFalse(finding.testSuites.isEmpty, "\(finding.id) has no test-suite owner.")
            XCTAssertEqual(
                Set(finding.testSuites).count,
                finding.testSuites.count,
                "\(finding.id) repeats a test-suite owner."
            )
            XCTAssertTrue(
                finding.testSuites.allSatisfy { $0.hasSuffix("Tests") },
                "\(finding.id) test-suite owners must use stable XCTest suite names."
            )
        }
    }

    func testEveryNamedTestSuiteHasAnExecutableSourceFile() {
        let testDirectory = Self.repositoryRoot.appendingPathComponent("Tests/ViftyCoreTests", isDirectory: true)

        for suite in Set(Self.inventory.flatMap(\.testSuites)).sorted() {
            let suiteURL = testDirectory.appendingPathComponent("\(suite).swift")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: suiteURL.path),
                "Inventory references missing XCTest suite source \(suiteURL.lastPathComponent)."
            )
        }
    }

    func testSafetyContractKeepsStableInvariantAndCrashPointLedger() throws {
        let specification = try String(contentsOf: Self.safetySpecificationURL, encoding: .utf8)

        for index in 1...10 {
            XCTAssertTrue(
                specification.contains(String(format: "INV-%02d", index)),
                "The safety contract must retain invariant INV-\(String(format: "%02d", index))."
            )
        }

        for index in 1...12 {
            XCTAssertTrue(
                specification.contains(String(format: "CRASH-%02d", index)),
                "The safety contract must retain crash point CRASH-\(String(format: "%02d", index))."
            )
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var implementationPlanURL: URL {
        repositoryRoot.appendingPathComponent(
            "docs/superpowers/plans/2026-07-14-vifty-whole-app-review-remediation.md"
        )
    }

    private static var safetySpecificationURL: URL {
        repositoryRoot.appendingPathComponent(
            "docs/superpowers/specs/2026-07-14-fan-control-transaction-safety.md"
        )
    }

    private static func planCoverageRows() throws -> [(title: String, resolution: String)] {
        let plan = try String(contentsOf: implementationPlanURL, encoding: .utf8)
        let lines = plan.components(separatedBy: .newlines)
        let matrixHeading = try XCTUnwrap(
            lines.firstIndex(of: "## Finding Coverage Matrix"),
            "Implementation plan is missing the Finding Coverage Matrix."
        )
        let rows = lines.dropFirst(matrixHeading + 1).prefix { $0 != "---" }

        var parsed: [(title: String, resolution: String)] = []
        for row in rows where row.hasPrefix("|") {
            let columns = row
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count == 2,
                  columns[0] != "Review finding",
                  !columns[0].allSatisfy({ $0 == "-" || $0 == " " }) else {
                continue
            }
            parsed.append((title: columns[0], resolution: columns[1]))
        }

        XCTAssertEqual(Set(parsed.map(\.title)).count, parsed.count, "Plan matrix contains duplicate findings.")
        return parsed
    }
}
