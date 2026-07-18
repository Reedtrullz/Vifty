import Darwin
import Foundation
import XCTest
@testable import ViftyFanControlSafety

final class FanControlExclusiveLockTests: XCTestCase {
    func testOnlyOneOwnerCanHoldPathAndReleaseAllowsReacquisition() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lock/writer.lock")
        let first = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())

        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        ) { error in
            XCTAssertEqual(error as? FanControlExclusiveLockError, .alreadyOwned)
        }

        first.release()
        let second = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        second.release()
    }

    func testLockFileAndDirectoryArePrivate() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lock/writer.lock")
        let lock = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        defer { lock.release() }

        XCTAssertEqual(try Self.mode(of: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try Self.mode(of: url), 0o600)
    }

    func testUnsafeDirectoryAndSymlinkLockAreRejected() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unsafeDirectory = root.appendingPathComponent("unsafe", isDirectory: true)
        try FileManager.default.createDirectory(at: unsafeDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unsafeDirectory.path)

        XCTAssertThrowsError(
            try FanControlExclusiveLock(
                url: unsafeDirectory.appendingPathComponent("writer.lock"),
                requiredOwnerID: geteuid()
            )
        )

        let safeDirectory = root.appendingPathComponent("safe", isDirectory: true)
        try FileManager.default.createDirectory(at: safeDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: safeDirectory.path)
        let target = safeDirectory.appendingPathComponent("target")
        XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data()))
        let linkURL = safeDirectory.appendingPathComponent("writer.lock")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: target)

        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: linkURL, requiredOwnerID: geteuid())
        )
    }

    func testIntermediateDirectorySymlinkIsRejected() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let realParent = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realParent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: realParent.path)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: realParent)

        XCTAssertThrowsError(
            try FanControlExclusiveLock(
                url: alias.appendingPathComponent("lock/writer.lock"),
                requiredOwnerID: geteuid()
            )
        ) { error in
            guard case .unsafePath = error as? FanControlExclusiveLockError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testPreExistingWrongModeIsRejectedWithoutRepairingIt() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("lock", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("writer.lock")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o644]
        ))

        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        ) { error in
            guard case .unsafePath = error as? FanControlExclusiveLockError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
        XCTAssertEqual(try Self.mode(of: url), 0o644)
    }

    func testPreExistingHardLinkedLockIsRejected() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("lock", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let target = directory.appendingPathComponent("target")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: target.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ))
        let url = directory.appendingPathComponent("writer.lock")
        guard link(target.path, url.path) == 0 else {
            return XCTFail("link failed: \(String(cString: strerror(errno)))")
        }

        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        ) { error in
            guard case .unsafePath = error as? FanControlExclusiveLockError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
    }

    func testOwnerMismatchIsRejectedBeforeTouchingPreExistingPath() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("lock", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("writer.lock")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: url.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o600]
        ))
        let mismatchedOwner = geteuid() == uid_t.max ? geteuid() - 1 : geteuid() + 1

        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: url, requiredOwnerID: mismatchedOwner)
        ) { error in
            guard case .unsafePath = error as? FanControlExclusiveLockError else {
                return XCTFail("Expected unsafePath, got \(error)")
            }
        }
        XCTAssertEqual(try Self.mode(of: url), 0o600)
    }

    func testKernelLockExcludesIndependentProcessAndReleasesAfterExit() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lock/writer.lock")
        let parentLock = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        let blockedAttempt = try Self.runHelper(["attempt", url.path, String(geteuid())])
        XCTAssertEqual(blockedAttempt, 75, "Independent process must observe the kernel lock as owned")

        parentLock.release()
        XCTAssertEqual(try Self.runHelper(["attempt", url.path, String(geteuid())]), 0)
    }

    func testKernelReleasesLockWhenOwnerProcessExitsWithoutCleanup() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lock/writer.lock")
        let readyURL = root.appendingPathComponent("ready")
        let releaseURL = root.appendingPathComponent("release")
        let process = Process()
        process.executableURL = try Self.lockHelperURL()
        process.arguments = [
            "holdUntilReleased",
            url.path,
            String(geteuid()),
            readyURL.path,
            releaseURL.path
        ]
        try process.run()
        try Self.waitForFile(readyURL, process: process)
        XCTAssertThrowsError(
            try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        ) { error in
            XCTAssertEqual(error as? FanControlExclusiveLockError, .alreadyOwned)
        }
        try Data("release".utf8).write(to: releaseURL, options: .atomic)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let recovered = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())
        recovered.release()
    }

    func testRuntimeDirectoryReplacementInvalidatesOwnerAndGuardBlocksSecondProcess() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("lock", isDirectory: true)
        let movedDirectory = root.appendingPathComponent("moved", isDirectory: true)
        let url = directory.appendingPathComponent("writer.lock")
        let original = try FanControlExclusiveLock(url: url, requiredOwnerID: geteuid())

        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        XCTAssertFalse(original.isHeld, "the original owner must fail closed after path substitution")
        XCTAssertEqual(
            try Self.runHelper(["attempt", url.path, String(geteuid())]),
            75,
            "the retained parent guard must block a second process from locking a replacement directory"
        )

        original.release()
        XCTAssertEqual(try Self.runHelper(["attempt", url.path, String(geteuid())]), 0)
    }

    func testManagedAncestorReplacementCannotCreateSecondLockUniverse() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stableDirectory = root.appendingPathComponent("stable", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stableDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let guardURL = stableDirectory.appendingPathComponent("writer.guard")
        let managedAncestor = root.appendingPathComponent("Vifty", isDirectory: true)
        let movedAncestor = root.appendingPathComponent("Vifty-moved", isDirectory: true)
        let url = managedAncestor.appendingPathComponent("FanControl/writer.lock")
        let original = try FanControlExclusiveLock(
            url: url,
            guardURL: guardURL,
            requiredOwnerID: geteuid()
        )

        try FileManager.default.moveItem(at: managedAncestor, to: movedAncestor)
        try FileManager.default.createDirectory(
            at: managedAncestor.appendingPathComponent("FanControl", isDirectory: true),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: managedAncestor.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: managedAncestor.appendingPathComponent("FanControl").path
        )

        XCTAssertFalse(original.isHeld)
        XCTAssertEqual(
            try Self.runHelper(
                ["attempt", url.path, String(geteuid())],
                guardURL: guardURL
            ),
            75
        )

        original.release()
        XCTAssertEqual(
            try Self.runHelper(
                ["attempt", url.path, String(geteuid())],
                guardURL: guardURL
            ),
            0
        )
    }

    func testLockHelperResolutionUsesSuppliedExternalProductsDirectory() throws {
        let productsDirectory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: productsDirectory) }
        let helper = productsDirectory.appendingPathComponent("ViftyLockTestHelper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )

        XCTAssertEqual(
            try Self.lockHelperURL(productsDirectory: productsDirectory),
            helper
        )
    }

    private static func runHelper(
        _ arguments: [String],
        guardURL: URL? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = try lockHelperURL()
        process.arguments = arguments
        if let guardURL {
            process.environment = ProcessInfo.processInfo.environment.merging([
                "VIFTY_LOCK_TEST_GUARD_PATH": guardURL.path
            ]) { _, new in new }
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func lockHelperURL(productsDirectory: URL? = nil) throws -> URL {
        let resolvedProductsDirectory = productsDirectory
            ?? Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let candidate = resolvedProductsDirectory.appendingPathComponent("ViftyLockTestHelper")
        var metadata = stat()
        guard lstat(candidate.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw NSError(
                domain: "FanControlExclusiveLockTests",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ViftyLockTestHelper is not a regular executable sibling of the test bundle"
                ]
            )
        }
        return candidate
    }

    private static func waitForFile(_ url: URL, process: Process) throws {
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            if !process.isRunning {
                throw NSError(
                    domain: "FanControlExclusiveLockTests",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Lock helper exited before becoming ready"]
                )
            }
            usleep(10_000)
        }
        process.terminate()
        throw NSError(
            domain: "FanControlExclusiveLockTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for lock helper"]
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
