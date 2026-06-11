import Foundation
import XCTest

final class MakefileTrustGateTests: XCTestCase {
    func testVerifyTargetRunsLocalTrustGates() throws {
        let makefile = try read("Makefile")

        XCTAssertTrue(makefile.contains("verify: ## Run local trust gates without installing"))
        XCTAssertTrue(makefile.contains("/bin/bash -n scripts/*.sh examples/viftyctl/*.sh"))
        XCTAssertTrue(makefile.contains("scripts/validate-release-metadata.sh"))
        XCTAssertTrue(makefile.contains("swift test"))
        XCTAssertTrue(makefile.contains("swift build -Xswiftc -warnings-as-errors"))
        XCTAssertTrue(makefile.contains("$(MAKE) app CONFIGURATION=release"))
        XCTAssertTrue(makefile.contains("SCHEMAS := $(CONTENTS)/Resources/schemas"))
        XCTAssertTrue(makefile.contains("cp docs/schemas/*.schema.json \"$(SCHEMAS)/\""))
        XCTAssertTrue(makefile.contains("plutil -lint \"$(CONTENTS)/Info.plist\""))
        XCTAssertTrue(makefile.contains("plutil -lint \"$(DAEMON_PLIST)\""))
        XCTAssertTrue(makefile.contains("codesign --verify --deep --strict \"$(APP_DIR)\""))
        XCTAssertTrue(makefile.contains("Identifier=tech.reidar.vifty.ctl"))
    }

    func testVerifyTargetIsListedAsPhonyAndHelpVisible() throws {
        let makefile = try read("Makefile")

        XCTAssertTrue(makefile.contains(".PHONY: app install pkg clean-app clean-pkg test verify help clean"))
        XCTAssertTrue(makefile.contains("verify: ## Run local trust gates without installing"))
    }

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
