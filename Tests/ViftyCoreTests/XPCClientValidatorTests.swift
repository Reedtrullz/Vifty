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

    func testAllowsMatchingSigningIdentifierWhenTeamRequirementIsNil() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: nil
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: nil
        )

        XCTAssertTrue(validator.isAllowed(identity))
    }

    func testAllowsNonNilTeamIdentifierWhenTeamRequirementIsNil() {
        let validator = XPCClientValidator(
            allowedSigningIdentifier: allowedSigningIdentifier,
            allowedTeamIdentifier: nil
        )
        let identity = XPCClientIdentity(
            signingIdentifier: allowedSigningIdentifier,
            teamIdentifier: "SOME_TEAM"
        )

        XCTAssertTrue(validator.isAllowed(identity))
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

    func testAllowsOnlyExplicitClientAllowlist() {
        let validator = XPCClientValidator(allowedClients: XPCTrustConfiguration.allowedClients(releaseTeamIdentifier: nil))

        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil)))
        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)))
        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "SOME_TEAM")))
        XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: "SOME_TEAM")))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.anything", teamIdentifier: nil)))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: nil, teamIdentifier: nil)))
    }

    func testAllowsNonNilTeamIdentifierWhenAllowedClientHasNilTeamRequirement() {
        let validator = XPCClientValidator(allowedClients: [
            XPCAllowedClient(signingIdentifier: "com.example.app", teamIdentifier: nil)
        ])
        let identity = XPCClientIdentity(
            signingIdentifier: "com.example.app",
            teamIdentifier: "ABCDE12345"
        )
        XCTAssertTrue(validator.isAllowed(identity))
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
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "OTHERTEAM")))
        XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)))
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
