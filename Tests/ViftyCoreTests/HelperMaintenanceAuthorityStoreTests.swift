import Darwin
import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyDaemonSupport

final class HelperMaintenanceAuthorityStoreTests: XCTestCase {
    func testPublishedAuthorityAndExecutionSchemasMatchTheEncodedContracts() throws {
        let authoritySchemaURL = repositoryRoot.appendingPathComponent(
            "docs/schemas/helper-maintenance-authority-v1.schema.json"
        )
        let authoritySchema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: authoritySchemaURL))
                as? [String: Any]
        )
        XCTAssertEqual(
            authoritySchema["$id"] as? String,
            HelperMaintenanceAuthorityReceipt.schemaID
        )
        let required = Set(try XCTUnwrap(authoritySchema["required"] as? [String]))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(Self.receipt()))
                as? [String: Any]
        )
        XCTAssertEqual(required, Set(encoded.keys))

        let executionSchemaURL = repositoryRoot.appendingPathComponent(
            "docs/schemas/helper-maintenance-execution-v1.schema.json"
        )
        let executionSchema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: executionSchemaURL))
                as? [String: Any]
        )
        XCTAssertEqual(
            executionSchema["$id"] as? String,
            "https://vifty.app/schemas/helper-maintenance-execution-v1.json"
        )
    }

    func testRoundTripUsesPrivateDescriptorAnchoredStorageAndClear() throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HelperMaintenanceAuthorityStore(
            directoryURL: root.appendingPathComponent("Maintenance"),
            requiredOwnerID: geteuid()
        )
        let receipt = Self.receipt()

        try store.save(receipt)

        XCTAssertEqual(try store.load(), receipt)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: store.directoryURL.path
        )
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: store.authorityURL.path
        )
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let claimedAuthorityURL = store.directoryURL.appendingPathComponent(
            HelperMaintenanceAuthorityStore.claimedAuthorityFileName
        )
        try Data("claimed".utf8).write(to: claimedAuthorityURL, options: .withoutOverwriting)
        XCTAssertEqual(chmod(claimedAuthorityURL.path, 0o600), 0)

        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimedAuthorityURL.path))
    }

    func testSymlinkOrMalformedReceiptFailsClosed() throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Maintenance")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        XCTAssertEqual(chmod(directory.path, 0o700), 0)
        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let authority = directory.appendingPathComponent(
            HelperMaintenanceAuthorityStore.authorityFileName
        )
        try FileManager.default.createSymbolicLink(at: authority, withDestinationURL: target)
        let store = HelperMaintenanceAuthorityStore(
            directoryURL: directory,
            requiredOwnerID: geteuid()
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(Self.receipt()))
    }

    func testInvalidBindingsNeverPersist() throws {
        let root = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HelperMaintenanceAuthorityStore(
            directoryURL: root.appendingPathComponent("Maintenance"),
            requiredOwnerID: geteuid()
        )
        var receipt = Self.receipt()
        receipt.expectedFanIDs = []

        XCTAssertThrowsError(try store.save(receipt))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.authorityURL.path))
    }

    private static func receipt() -> HelperMaintenanceAuthorityReceipt {
        let authorizedAt = Date(timeIntervalSince1970: 1_005)
        return HelperMaintenanceAuthorityReceipt(
            operation: .repair,
            tokenID: "fixture-token",
            tokenIssuedAt: Date(timeIntervalSince1970: 1_000),
            authorizedAt: authorizedAt,
            expiresAt: authorizedAt.addingTimeInterval(300),
            bootSessionID: "boot-A",
            daemonSessionID: "daemon-A",
            journalGeneration: 7,
            expectedFanIDs: [0],
            helperSHA256: String(repeating: "a", count: 64),
            quiesceGeneration: 3
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let parent = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(
            "maintenance-authority-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        XCTAssertEqual(chmod(root.path, 0o700), 0)
        return root
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
