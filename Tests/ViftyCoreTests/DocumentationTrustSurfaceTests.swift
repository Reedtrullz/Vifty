import Foundation
import XCTest

final class DocumentationTrustSurfaceTests: XCTestCase {
    func testReadmeLinksCompatibilityAndHardwareValidation() throws {
        let readme = try read("README.md")

        XCTAssertTrue(readme.contains("[docs/compatibility.md](docs/compatibility.md)"))
        XCTAssertTrue(readme.contains("[docs/hardware-validation.md](docs/hardware-validation.md)"))
        XCTAssertTrue(readme.contains("[docs/trust-model.md](docs/trust-model.md)"))
        XCTAssertTrue(readme.contains("[docs/agent-integrations.md](docs/agent-integrations.md)"))
    }

    func testSecurityPolicyLinksTrustModel() throws {
        let security = try read("SECURITY.md")

        XCTAssertTrue(security.contains("[docs/trust-model.md](docs/trust-model.md)"))
    }

    func testTrustModelNamesPrivilegedBoundariesAndWriteAllowlist() throws {
        let trustModel = try read("docs/trust-model.md")

        XCTAssertTrue(trustModel.contains("The SwiftUI app and `viftyctl` run unprivileged."))
        XCTAssertTrue(trustModel.contains("The LaunchDaemon runs as root and owns normal SMC fan writes."))
        XCTAssertTrue(trustModel.contains("F{n}Md"))
        XCTAssertTrue(trustModel.contains("F{n}md"))
        XCTAssertTrue(trustModel.contains("F{n}Tg"))
        XCTAssertTrue(trustModel.contains("Ftst"))
        XCTAssertTrue(trustModel.contains("Agents request bounded cooling intent. They do not get raw SMC write access."))
        XCTAssertTrue(trustModel.contains("Public releases should be Developer ID signed, notarized, stapled, and TeamID-gated over XPC."))
    }

    func testCompatibilityPageRequiresReportBackedEvidence() throws {
        let compatibility = try read("docs/compatibility.md")

        XCTAssertTrue(compatibility.contains("Vifty's compatibility claims are evidence-based"))
        XCTAssertTrue(compatibility.contains("Hardware Validation Report"))
        XCTAssertTrue(compatibility.contains("scripts/collect-validation-evidence.sh"))
        XCTAssertTrue(compatibility.contains("scripts/review-validation-evidence.sh"))
        XCTAssertTrue(compatibility.contains("scripts/summarize-validation-reports.sh"))
        XCTAssertTrue(compatibility.contains("review-result.json"))
        XCTAssertTrue(compatibility.contains("supported-hardware-evidence-needs-manual-smoke"))
        XCTAssertTrue(compatibility.contains("validated-hardware-evidence"))
        XCTAssertTrue(compatibility.contains("manualSmokeTestResult: \"passed-auto-restored\""))
        XCTAssertTrue(compatibility.contains("viftyctl diagnose --json"))
        XCTAssertTrue(compatibility.contains("ViftyHelper probeLocal"))
        XCTAssertTrue(compatibility.contains("Do not run the manual smoke test when readiness is `blocked`"))
        XCTAssertTrue(compatibility.contains("Do not add a README compatibility badge or broad marketing claim until the status table has real report links."))
    }

    func testReleaseAndHardwareDocsPointBackToCompatibilityStatus() throws {
        let release = try read("docs/release.md")
        let hardwareValidation = try read("docs/hardware-validation.md")

        XCTAssertTrue(release.contains("make verify"))
        XCTAssertTrue(release.contains("[compatibility.md](compatibility.md)"))
        XCTAssertTrue(release.contains("scripts/verify-release-artifact.sh"))
        XCTAssertTrue(release.contains("scripts/collect-validation-evidence.sh"))
        XCTAssertTrue(release.contains("scripts/review-validation-evidence.sh"))
        XCTAssertTrue(release.contains("scripts/summarize-validation-reports.sh"))
        XCTAssertTrue(release.contains("review-result.json"))
        XCTAssertTrue(release.contains("validated-hardware-evidence"))
        XCTAssertTrue(release.contains("Vifty-v<version>-artifact-summary.json"))
        XCTAssertTrue(release.contains("review-summary.json"))
        XCTAssertTrue(hardwareValidation.contains("[compatibility.md](compatibility.md)"))
        XCTAssertTrue(hardwareValidation.contains("scripts/collect-validation-evidence.sh"))
        XCTAssertTrue(hardwareValidation.contains("scripts/review-validation-evidence.sh"))
        XCTAssertTrue(hardwareValidation.contains("scripts/summarize-validation-reports.sh"))
        XCTAssertTrue(hardwareValidation.contains("review-result.json"))
        XCTAssertTrue(hardwareValidation.contains("--manual-smoke-result passed-auto-restored"))
        XCTAssertTrue(hardwareValidation.contains("validated-hardware-evidence"))
        XCTAssertTrue(hardwareValidation.contains("review-summary.json"))
    }

    func testAgentIntegrationDocsPreferGuardedRunAndForbidRawWrites() throws {
        let agentWorkflows = try read("docs/agent-workflows.md")
        let integrations = try read("docs/agent-integrations.md")

        XCTAssertTrue(agentWorkflows.contains("[agent-integrations.md](agent-integrations.md)"))
        XCTAssertTrue(integrations.contains("Codex"))
        XCTAssertTrue(integrations.contains("Claude Code"))
        XCTAssertTrue(integrations.contains("Cursor"))
        XCTAssertTrue(integrations.contains("examples/viftyctl/guarded-run.sh"))
        XCTAssertTrue(integrations.contains("safeToRequestCooling"))
        XCTAssertTrue(integrations.contains("restoreAutoBeforeRequestingCooling"))
        XCTAssertTrue(integrations.contains("Never call raw SMC commands"))
        XCTAssertTrue(integrations.contains("Do not give agents permission to call `ViftyHelper setFixed`"))
    }

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
