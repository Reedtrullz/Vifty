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

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
