import Darwin
import XCTest
import ViftyCore
@testable import ViftyCtl

final class ViftyCtlProcessRunnerTests: XCTestCase {
    func testResolveAcceptsExecutableAbsolutePath() throws {
        let runner = ViftyCtlProcessRunner()

        let resolved = try runner.resolve(["/bin/echo", "hello"])

        XCTAssertEqual(resolved, ["/bin/echo", "hello"])
    }

    func testResolveCanonicalizesExecutableRelativePathBeforeRun() throws {
        let originalDirectory = FileManager.default.currentDirectoryPath
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-process-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            _ = FileManager.default.changeCurrentDirectoryPath(originalDirectory)
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        let childURL = tempDirectory.appendingPathComponent("tool")
        FileManager.default.createFile(atPath: childURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: childURL.path)
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(tempDirectory.path))
        let runner = ViftyCtlProcessRunner()

        let resolved = try runner.resolve(["./tool", "arg"])

        XCTAssertEqual(resolved, [childURL.path, "arg"])
    }

    func testResolveRejectsNonExecutableAbsolutePathBeforeRun() throws {
        let runner = ViftyCtlProcessRunner()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-process-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let childPath = tempDirectory.appendingPathComponent("not-executable").path
        FileManager.default.createFile(atPath: childPath, contents: Data("#!/bin/sh\nexit 0\n".utf8))

        XCTAssertThrowsError(try runner.resolve([childPath])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Child command is not executable"))
        }
    }

    func testResolveRejectsExecutableDirectoryBeforeRun() throws {
        let runner = ViftyCtlProcessRunner()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-process-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tempDirectory.path))
        XCTAssertThrowsError(try runner.resolve([tempDirectory.path])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Child command is not executable"))
        }
    }

    func testResolveSkipsExecutableDirectoryOnPATH() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-process-runner-\(UUID().uuidString)", isDirectory: true)
        let directoryPath = tempDirectory.appendingPathComponent("path-dir", isDirectory: true)
        let executablePath = tempDirectory.appendingPathComponent("path-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryPath.appendingPathComponent("tool", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: executablePath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let toolPath = executablePath.appendingPathComponent("tool").path
        FileManager.default.createFile(atPath: toolPath, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolPath)
        let runner = ViftyCtlProcessRunner(environment: ["PATH": "\(directoryPath.path):\(executablePath.path)"])

        let resolved = try runner.resolve(["tool", "arg"])

        XCTAssertEqual(resolved, [toolPath, "arg"])
    }

    func testResolveRejectsMissingBareCommandBeforeRun() throws {
        let runner = ViftyCtlProcessRunner()

        XCTAssertThrowsError(try runner.resolve(["vifty-missing-command-\(UUID().uuidString)"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Child command was not found on PATH"))
        }
    }

    func testRunReturnsShellStyleExitCodeWhenChildIsSignaled() throws {
        let runner = ViftyCtlProcessRunner()

        let exitCode = try runner.run(["/bin/sh", "-c", "kill -TERM $$"])

        XCTAssertEqual(exitCode, 143)
    }

    func testRunForwardsSignalReceivedBeforeChildSpawn() throws {
        let supervisor = ChildProcessSupervisor(
            policy: .test,
            beforeSpawn: {
                XCTAssertEqual(Darwin.kill(Darwin.getpid(), SIGTERM), 0)
            }
        )
        let runner = ViftyCtlProcessRunner(supervisor: supervisor)

        let exitCode = try runner.run(["/bin/sleep", "2"])

        XCTAssertEqual(exitCode, 143)
    }

    func testRunUsesDistinctProcessGroupAndForwardsSignalToChildAndGrandchild() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let pidFile = temporaryDirectory.appendingPathComponent("processes.txt")
        let observation = LockedProcessObservation()
        let supervisor = ChildProcessSupervisor(
            policy: .test,
            afterSpawn: { childPID in
                observation.record(
                    childPID: childPID,
                    childProcessGroup: Darwin.getpgid(childPID),
                    wrapperProcessGroup: Darwin.getpgrp()
                )
                _ = Self.waitForFile(at: pidFile, timeout: 1)
                XCTAssertEqual(Darwin.kill(Darwin.getpid(), SIGTERM), 0)
            }
        )
        let runner = ViftyCtlProcessRunner(supervisor: supervisor)

        let exitCode = try runner.run([
            "/bin/sh",
            "-c",
            #"/bin/sleep 5 & grandchild=$!; printf '%s %s\n' "$$" "$grandchild" > "$1"; wait"#,
            "vifty-process-fixture",
            pidFile.path
        ])

        XCTAssertEqual(exitCode, 143)
        let processIDs = try readProcessIDs(from: pidFile)
        let recorded = try XCTUnwrap(observation.value)
        XCTAssertEqual(processIDs.child, recorded.childPID)
        XCTAssertEqual(recorded.childProcessGroup, recorded.childPID)
        XCTAssertNotEqual(recorded.childProcessGroup, recorded.wrapperProcessGroup)
        XCTAssertTrue(Self.waitForProcessToExit(processIDs.child, timeout: 1))
        XCTAssertTrue(Self.waitForProcessToExit(processIDs.grandchild, timeout: 1))
    }

    func testRunEscalatesAndCleansBackgroundProcessGroupBeforeReturning() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let pidFile = temporaryDirectory.appendingPathComponent("background.txt")
        let supervisor = ChildProcessSupervisor(
            policy: .test,
            afterSpawn: { _ in
                _ = Self.waitForFile(at: pidFile, timeout: 1)
            }
        )
        let runner = ViftyCtlProcessRunner(supervisor: supervisor)

        let exitCode = try runner.run([
            "/bin/sh",
            "-c",
            #"/bin/sh -c 'trap "" HUP TERM; exec /bin/sleep 5' & printf '%s\n' "$!" > "$1"; exit 0"#,
            "vifty-background-fixture",
            pidFile.path
        ])

        XCTAssertEqual(exitCode, 0)
        let backgroundPID = try XCTUnwrap(
            Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        XCTAssertTrue(Self.waitForProcessToExit(backgroundPID, timeout: 1))
    }

    func testRunFailsClosedWhenDescendantProcessGroupSurvivesEscalation() throws {
        let observation = LockedSignalObservation()
        let operations = ProcessGroupOperations(
            signal: { _, signalNumber in
                observation.record(signalNumber)
                return signalNumber == SIGTERM ? EPERM : nil
            },
            exists: { _ in true }
        )
        let supervisor = ChildProcessSupervisor(
            policy: .init(
                naturalExitGraceNanoseconds: 0,
                terminationGraceNanoseconds: 0,
                killGraceNanoseconds: 0,
                pollIntervalNanoseconds: 0
            ),
            processGroupOperations: operations
        )
        let runner = ViftyCtlProcessRunner(supervisor: supervisor)

        XCTAssertThrowsError(try runner.run(["/bin/sh", "-c", "exit 0"])) { error in
            let lifecycleError = error as? ViftyCtlChildProcessLifecycleError
            XCTAssertEqual(lifecycleError?.phase, .descendantCleanup)
            XCTAssertEqual(lifecycleError?.childExitCode, 0)
            XCTAssertEqual(lifecycleError?.descendantCleanupCompleted, false)
            XCTAssertEqual(lifecycleError?.backgroundProcessesMayRemain, true)
            XCTAssertTrue(error.localizedDescription.contains("clean descendant process group"))
            XCTAssertTrue(error.localizedDescription.contains("before Auto restoration"))
            XCTAssertTrue(error.localizedDescription.contains("SIGTERM failed with errno \(EPERM)"))
        }
        XCTAssertEqual(observation.signals, [SIGTERM, SIGKILL])
    }

    func testRunRestoresPreviousSignalHandlerAfterChildExits() throws {
        let originalHandler = Darwin.signal(SIGHUP, SIG_DFL)
        defer { _ = Darwin.signal(SIGHUP, originalHandler) }

        let runner = ViftyCtlProcessRunner()
        let exitCode = try runner.run(["/bin/sh", "-c", "exit 0"])

        XCTAssertEqual(exitCode, 0)
        let observedHandler = Darwin.signal(SIGHUP, originalHandler)
        XCTAssertEqual(Self.signalHandlerBits(observedHandler), Self.signalHandlerBits(SIG_DFL))
    }

    func testShieldedRunDefersSignalHandlerRestorationUntilAutoRestoreFinishes() throws {
        let originalHandler = Darwin.signal(SIGHUP, SIG_DFL)
        defer { _ = Darwin.signal(SIGHUP, originalHandler) }
        let runner = ViftyCtlProcessRunner()

        let completion = runner.runMaintainingSignalShield(["/bin/sh", "-c", "exit 0"])

        XCTAssertEqual(try completion.get(), 0)
        let handlerWhileShielded = Darwin.signal(SIGHUP, SIG_IGN)
        XCTAssertEqual(Self.signalHandlerBits(handlerWhileShielded), Self.signalHandlerBits(SIG_IGN))

        completion.finishSignalHandling()

        let handlerAfterFinish = Darwin.signal(SIGHUP, originalHandler)
        XCTAssertEqual(Self.signalHandlerBits(handlerAfterFinish), Self.signalHandlerBits(SIG_DFL))
    }

    func testRunRestoresPreviousSignalHandlerWhenSpawnFails() {
        let originalHandler = Darwin.signal(SIGHUP, SIG_DFL)
        defer { _ = Darwin.signal(SIGHUP, originalHandler) }
        let runner = ViftyCtlProcessRunner()

        XCTAssertThrowsError(try runner.run(["/vifty/missing/child-command"]))

        let observedHandler = Darwin.signal(SIGHUP, originalHandler)
        XCTAssertEqual(Self.signalHandlerBits(observedHandler), Self.signalHandlerBits(SIG_DFL))
    }

    func testExitCodeReturnsNormalChildExitStatus() {
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .exit, status: 7),
            7
        )
    }

    func testExitCodeMapsUncaughtSignalToShellStyleExitCode() {
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .uncaughtSignal, status: SIGINT),
            130
        )
        XCTAssertEqual(
            ViftyCtlProcessRunner.exitCode(for: .uncaughtSignal, status: SIGTERM),
            143
        )
    }

    private static func signalHandlerBits(_ handler: (@convention(c) (Int32) -> Void)?) -> UInt {
        unsafeBitCast(handler, to: UInt.self)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-process-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readProcessIDs(from file: URL) throws -> (child: Int32, grandchild: Int32) {
        let components = try String(contentsOf: file, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(components.count, 2)
        guard components.count == 2,
              let child = Int32(components[0]),
              let grandchild = Int32(components[1]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (child, grandchild)
    }

    private static func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private static func waitForProcessToExit(_ processID: pid_t, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            guard Darwin.kill(processID, 0) != 0 else { return false }
            return errno == ESRCH
        }
    }

    private static func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            usleep(5_000)
        } while Date() < deadline
        return condition()
    }
}

private final class LockedProcessObservation: @unchecked Sendable {
    struct Value {
        var childPID: pid_t
        var childProcessGroup: pid_t
        var wrapperProcessGroup: pid_t
    }

    private let lock = NSLock()
    private var storage: Value?

    var value: Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(childPID: pid_t, childProcessGroup: pid_t, wrapperProcessGroup: pid_t) {
        lock.lock()
        storage = Value(
            childPID: childPID,
            childProcessGroup: childProcessGroup,
            wrapperProcessGroup: wrapperProcessGroup
        )
        lock.unlock()
    }
}

private final class LockedSignalObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int32] = []

    var signals: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ signalNumber: Int32) {
        lock.lock()
        storage.append(signalNumber)
        lock.unlock()
    }
}
