import Foundation
import XCTest

final class MakefileTrustGateTests: XCTestCase {
    func testVerifyTargetRunsLocalTrustGates() throws {
        let makefile = try read("Makefile")

        XCTAssertTrue(makefile.contains("verify: ## Run local trust gates without installing"))
        XCTAssertTrue(makefile.contains("agent-cooling-evidence: ## Collect read-only agent/helper support evidence"))
        XCTAssertTrue(makefile.contains("agent-cooling-evidence-review: ## Review a read-only agent/helper support evidence bundle"))
        XCTAssertTrue(makefile.contains("source-first-release-notes: ## Write source-first release notes for the current version"))
        XCTAssertTrue(makefile.contains("unsigned-dev-artifact: ## Build source-first unsigned tester zip and checksum"))
        XCTAssertTrue(makefile.contains("source-first-readiness: ## Check published source-first release readiness"))
        XCTAssertTrue(makefile.contains("RELEASE_VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"))
        XCTAssertTrue(makefile.contains("RELEASE_REPO ?= Reedtrullz/Vifty"))
        XCTAssertTrue(makefile.contains("UNSIGNED_DEV_SOURCE_REF ?= v$(RELEASE_VERSION)"))
        XCTAssertTrue(makefile.contains("RELEASE_METADATA_MODE ?= source-first"))
        XCTAssertTrue(makefile.contains("AGENT_EVIDENCE_BUNDLE ?="))
        XCTAssertTrue(makefile.contains("AGENT_EVIDENCE_REVIEW_SUMMARY ?="))
        XCTAssertTrue(makefile.contains("/bin/bash -n scripts/*.sh examples/viftyctl/*.sh"))
        XCTAssertTrue(makefile.contains("scripts/check-community-standards.sh"))
        XCTAssertTrue(makefile.contains("scripts/validate-release-metadata.sh --mode \"$(RELEASE_METADATA_MODE)\""))
        XCTAssertTrue(makefile.contains("swift test"))
        XCTAssertTrue(makefile.contains("swift build -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(makefile.contains("$(MAKE) app CONFIGURATION=release"))
        XCTAssertTrue(makefile.contains("SCHEMAS := $(CONTENTS)/Resources/schemas"))
        XCTAssertTrue(makefile.contains("cp docs/schemas/*.schema.json \"$(SCHEMAS)/\""))
        XCTAssertTrue(makefile.contains("plutil -lint \"$(CONTENTS)/Info.plist\""))
        XCTAssertTrue(makefile.contains("plutil -lint \"$(DAEMON_PLIST)\""))
        XCTAssertTrue(makefile.contains("codesign --verify --deep --strict \"$(APP_DIR)\""))
        XCTAssertTrue(makefile.contains("--identifier tech.reidar.vifty.daemon \"$(MACOS)/ViftyDaemon\""))
        XCTAssertTrue(makefile.contains("Identifier=tech.reidar.vifty.daemon"))
        XCTAssertTrue(makefile.contains("Identifier=tech.reidar.vifty.ctl"))
    }

    func testVerifyTargetIsListedAsPhonyAndHelpVisible() throws {
        let makefile = try read("Makefile")

        XCTAssertTrue(makefile.contains(".PHONY: app install pkg agent-cooling-evidence agent-cooling-evidence-review source-first-release-notes unsigned-dev-artifact source-first-readiness clean-app clean-pkg test verify help clean"))
        XCTAssertTrue(makefile.contains("verify: ## Run local trust gates without installing"))
        XCTAssertTrue(makefile.contains("agent-cooling-evidence: ## Collect read-only agent/helper support evidence"))
        XCTAssertTrue(makefile.contains("scripts/collect-agent-cooling-evidence.sh --viftyctl \"$(VIFTYCTL)\""))
        XCTAssertTrue(makefile.contains("agent-cooling-evidence-review: ## Review a read-only agent/helper support evidence bundle"))
        XCTAssertTrue(makefile.contains("scripts/review-agent-cooling-evidence.sh --bundle \"$(AGENT_EVIDENCE_BUNDLE)\""))
        XCTAssertTrue(makefile.contains("source-first-release-notes: ## Write source-first release notes for the current version"))
        XCTAssertTrue(makefile.contains("unsigned-dev-artifact: ## Build source-first unsigned tester zip and checksum"))
        XCTAssertTrue(makefile.contains("source-first-readiness: ## Check published source-first release readiness"))
        XCTAssertTrue(makefile.contains("scripts/write-release-checklist.sh --mode source-first --version \"$(RELEASE_VERSION)\""))
        XCTAssertTrue(makefile.contains("scripts/build-unsigned-dev-artifact.sh --version \"$(RELEASE_VERSION)\" $(if $(UNSIGNED_DEV_SOURCE_REF),--require-source-ref \"$(UNSIGNED_DEV_SOURCE_REF)\",)"))
        XCTAssertTrue(makefile.contains("scripts/check-release-readiness.sh --mode source-first --version \"$(RELEASE_VERSION)\" --repo \"$(RELEASE_REPO)\" --json"))
    }

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
