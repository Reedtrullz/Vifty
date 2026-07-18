import XCTest
@testable import ViftyCore

final class XPCClientValidatorTests: XCTestCase {
    private let allowedSigningIdentifier = "tech.reidar.Vifty"
    private let allowedTeamIdentifier = "REIDARTEAM"

    func testAllowsMatchingAppIdentity() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: allowedTeamIdentifier
        )

        XCTAssertTrue(validator.isAllowed(identity))
    }

    func testRejectsWrongSigningIdentifier() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: "com.example.OtherApp",
            teamIdentifier: allowedTeamIdentifier
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testRejectsWrongTeamIdentifier() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: "OTHERTEAM"
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testRejectsMissingIdentityFields() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: nil,
            teamIdentifier: allowedTeamIdentifier
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testRejectsNilIdentity() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )

        XCTAssertFalse(validator.isAllowed(nil))
    }

    func testRejectsMatchingAdHocIdentifierWithoutExplicitUIDAndPathRequirement() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: nil
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: nil
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testRejectsSignedClientWhenAdHocRequirementIsIncomplete() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: nil
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: "SOME_TEAM"
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testLegacyAllowedClientPropertiesReturnSingleInitializerValues() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )

        XCTAssertEqual(validator.allowedSigningIdentifier, allowedSigningIdentifier)
        XCTAssertEqual(validator.allowedTeamIdentifier, allowedTeamIdentifier)
    }

    func testRejectsMissingTeamIdentifierWhenTeamIsRequired() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: nil
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testPlatformBinaryStatusDoesNotBypassIdentifierValidation() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )
        let identity = XPCClientIdentity(
            signingIdentifier: "com.example.PlatformTool",
            teamIdentifier: allowedTeamIdentifier,
            isPlatformBinary: true
        )

        XCTAssertFalse(validator.isAllowed(identity))
    }

    func testIdentityAndValidatorAreSendable() {
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: allowedTeamIdentifier
        )
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: allowedTeamIdentifier
        )

        assertSendable(identity)
        assertSendable(validator)
    }

    func testMissingReleaseTeamFailsClosedInsteadOfCreatingIdentifierOnlyAllowlist() {
        let validator = XPCClientValidator(allowedClients: XPCTrustConfiguration.allowedClients(releaseTeamIdentifier: nil))

        XCTAssertTrue(validator.allowedClients.isEmpty)
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil)))
    }

    func testExplicitAdHocRequirementRequiresIdentifierUIDPathAndNilTeam() {
        let validator = XPCClientValidator(allowedClients: [
            XPCAllowedClient(
                signingIdentifier: "com.example.app",
                teamIdentifier: nil,
                effectiveUserID: 501,
                executablePath: "/Applications/Vifty.app/Contents/MacOS/Vifty"
            )
        ])

        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(
            signingIdentifier: "com.example.app",
            teamIdentifier: nil,
            effectiveUserID: 501,
            executablePath: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        )))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(
            signingIdentifier: "com.example.app",
            teamIdentifier: nil,
            effectiveUserID: 502,
            executablePath: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        )))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(
            signingIdentifier: "com.example.app",
            teamIdentifier: nil,
            effectiveUserID: 501,
            executablePath: "/tmp/Vifty"
        )))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(
            signingIdentifier: "com.example.app",
            teamIdentifier: "ABCDE12345",
            effectiveUserID: 501,
            executablePath: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        )))
    }

    func testDevelopmentEnvironmentBuildsExactUIDAndPathAllowlist() {
        let clients = XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty",
            XPCTrustConfiguration.developmentCtlPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
        ])

        XCTAssertEqual(clients, [
            XPCAllowedClient(
                signingIdentifier: XPCTrustConfiguration.appSigningIdentifier,
                teamIdentifier: nil,
                effectiveUserID: 501,
                executablePath: "/Applications/Vifty.app/Contents/MacOS/Vifty"
            ),
            XPCAllowedClient(
                signingIdentifier: XPCTrustConfiguration.ctlSigningIdentifier,
                teamIdentifier: nil,
                effectiveUserID: 501,
                executablePath: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
            )
        ])
    }

    func testDevelopmentEnvironmentFailsClosedWithoutValidUIDOrAbsolutePath() {
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [:]).isEmpty)
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "not-a-uid",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        ]).isEmpty)
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "relative/Vifty",
            XPCTrustConfiguration.developmentCtlPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
        ]).isEmpty)
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        ]).isEmpty, "the development allowlist is all-or-nothing")
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty",
            XPCTrustConfiguration.developmentCtlPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/viftyctl",
            "VIFTY_XPC_ADHOC_HELPER_PATH": "/Applications/Vifty.app/Contents/MacOS/ViftyHelper"
        ]).isEmpty)
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "true",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty",
            XPCTrustConfiguration.developmentCtlPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
        ]).isEmpty)
        XCTAssertTrue(XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty",
            XPCTrustConfiguration.developmentCtlPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/viftyctl"
        ]).isEmpty, "UID and paths without the explicit development flag must fail closed")
    }

    func testReleaseTeamConfigurationRejectsMixedDevelopmentAllowlistKeys() {
        let clients = XPCTrustConfiguration.allowedClients(from: [
            XPCTrustConfiguration.teamEnvironmentKey: "REIDARTEAM",
            XPCTrustConfiguration.developmentEnableEnvironmentKey: "1",
            XPCTrustConfiguration.developmentUIDEnvironmentKey: "501",
            XPCTrustConfiguration.developmentAppPathEnvironmentKey: "/Applications/Vifty.app/Contents/MacOS/Vifty"
        ])

        XCTAssertTrue(clients.isEmpty)
    }

    func testTrustConfigurationReadsTeamIDFromEnvironment() {
        XCTAssertNil(XPCTrustConfiguration.releaseTeamIdentifier(from: [:]))
        XCTAssertNil(XPCTrustConfiguration.releaseTeamIdentifier(from: [
            XPCTrustConfiguration.teamEnvironmentKey: "  \n"
        ]))
        XCTAssertEqual(
            XPCTrustConfiguration.releaseTeamIdentifier(from: [
                XPCTrustConfiguration.teamEnvironmentKey: " REIDARTEAM \n"
            ]),
            "REIDARTEAM"
        )
    }

    func testReleaseTeamIdentifierAppliesToAppAndCtlClients() {
        let clients = XPCTrustConfiguration.allowedClients(releaseTeamIdentifier: "REIDARTEAM")

        XCTAssertEqual(clients, [
            XPCAllowedClient(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "REIDARTEAM"),
            XPCAllowedClient(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: "REIDARTEAM")
        ])

        let validator = XPCClientValidator(allowedClients: clients)
        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "REIDARTEAM")))
        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: "REIDARTEAM")))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.helper", teamIdentifier: "REIDARTEAM")))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "OTHERTEAM")))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.helper", teamIdentifier: nil)))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
