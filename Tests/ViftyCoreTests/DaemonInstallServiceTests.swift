import Darwin
import Foundation
import XCTest
@testable import Vifty

final class DaemonInstallServiceTests: XCTestCase {
    func testServiceRunsInjectedLifecycleRunnerOffMainThreadAndPreservesArguments() async throws {
        let recorder = InstallRunnerRecorder()
        let scriptSnapshot = Data("#!/usr/bin/env bash\nexit 75\n".utf8)
        let runner = DaemonInstallProcessRunner { executable, arguments, standardInput in
            await recorder.record(
                executable: executable,
                arguments: arguments,
                standardInput: standardInput,
                ranOnMainThread: pthread_main_np() != 0
            )
            return DaemonInstallProcessOutput(
                terminationStatus: 75,
                standardOutput: "",
                standardError: "maintenance safety interface unavailable"
            )
        }
        let service = DaemonInstallService(
            processRunner: runner,
            lifecycleScriptLoader: DaemonLifecycleScriptLoader { _ in scriptSnapshot }
        )
        let app = URL(fileURLWithPath: "/Applications/Vifty.app")
        let script = app.appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")

        let result = await service.perform(
            operation: .repair,
            appBundleURL: app,
            lifecycleScriptURL: script
        )

        XCTAssertEqual(result.outcome, .blocked)
        let recordedInvocation = await recorder.invocation
        let invocation = try XCTUnwrap(recordedInvocation)
        XCTAssertFalse(invocation.ranOnMainThread)
        XCTAssertEqual(invocation.executable, URL(fileURLWithPath: "/bin/bash"))
        XCTAssertEqual(
            invocation.arguments,
            ["--noprofile", "--norc", "-s", "--", "--operation", "repair", "--app", app.path]
        )
        XCTAssertEqual(invocation.standardInput, scriptSnapshot)
    }

    func testServiceMapsSuccessBlockedAndFailureWithoutLeakingRawCommandText() async {
        for testCase in [
            (Int32(0), DaemonInstallOutcome.completed),
            (Int32(75), DaemonInstallOutcome.blocked),
            (Int32(1), DaemonInstallOutcome.failed)
        ] {
            let service = DaemonInstallService(
                processRunner: DaemonInstallProcessRunner { _, _, _ in
                    DaemonInstallProcessOutput(
                        terminationStatus: testCase.0,
                        standardOutput: "",
                        standardError: "launchctl /private/operator/path"
                    )
                },
                lifecycleScriptLoader: DaemonLifecycleScriptLoader { _ in
                    Data("#!/usr/bin/env bash\n".utf8)
                }
            )
            let app = URL(fileURLWithPath: "/Applications/Vifty.app")

            let result = await service.perform(
                operation: .repair,
                appBundleURL: app,
                lifecycleScriptURL: app.appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")
            )

            XCTAssertEqual(result.outcome, testCase.1)
            XCTAssertFalse(result.operatorMessage.contains("launchctl"))
            XCTAssertFalse(result.operatorMessage.contains("/private/operator/path"))
        }
    }

    func testSystemRunnerDrainsLargeOutputWithoutDeadlock() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-output-" + UUID().uuidString + ".sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try Data("#!/bin/bash\ncat >/dev/null\ndd if=/dev/zero bs=262144 count=1 2>/dev/null\ndd if=/dev/zero bs=262144 count=1 1>&2 2>/dev/null\nexit 0\n".utf8)
            .write(to: script)
        XCTAssertEqual(chmod(script.path, 0o755), 0)

        let resultBox = ProcessOutputBox()
        let completion = expectation(description: "high-output process completes")
        let maximumBytesPerStream = 64 * 1_024
        let task = Task {
            defer { completion.fulfill() }
            resultBox.set(try? await DaemonInstallProcessRunner.system.run(script, [], Data("input\n".utf8)))
        }
        defer { task.cancel() }

        await fulfillment(of: [completion], timeout: 2)
        let output = resultBox.value
        let result = try XCTUnwrap(output)
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.standardOutput.utf8.count, maximumBytesPerStream)
        XCTAssertEqual(result.standardError.utf8.count, maximumBytesPerStream)
    }

    func testSystemRunnerBoundsCleanupAfterStdinWriteFailure() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-input-failure-" + UUID().uuidString + ".sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try Data("#!/bin/bash\nexec 0<&-\ntrap '' TERM\nwhile :; do :; done\n".utf8).write(to: script)
        XCTAssertEqual(chmod(script.path, 0o755), 0)

        let previousSIGPIPEHandler = signal(SIGPIPE, SIG_IGN)
        defer { signal(SIGPIPE, previousSIGPIPEHandler) }
        let resultBox = ProcessFailureBox()
        let completion = expectation(description: "stdin failure cleanup completes")
        let startedAt = Date()
        let task = Task {
            defer { completion.fulfill() }
            do {
                _ = try await DaemonInstallProcessRunner.system.run(
                    script,
                    [],
                    Data(repeating: 0, count: 1 * 1_024 * 1_024)
                )
                resultBox.set(threw: false)
            } catch {
                resultBox.set(threw: true)
            }
        }
        defer { task.cancel() }

        await fulfillment(of: [completion], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1.25)
        let didThrow = resultBox.threw
        XCTAssertTrue(didThrow)
    }

    func testBundledLoaderAcceptsOnlyTheReviewedLifecycleScriptBytes() throws {
        let reviewedScript = repositoryRoot.appendingPathComponent("scripts/vifty-helper-lifecycle.sh")
        let expectedData = try Data(contentsOf: reviewedScript)

        XCTAssertEqual(try DaemonLifecycleScriptLoader.bundled.load(reviewedScript), expectedData)

        let tamperedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-lifecycle-tampered-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: tamperedURL) }
        var tamperedData = expectedData
        tamperedData.append(Data("# same-uid replacement\n".utf8))
        try tamperedData.write(to: tamperedURL)

        XCTAssertThrowsError(try DaemonLifecycleScriptLoader.bundled.load(tamperedURL))

        let symlinkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-lifecycle-symlink-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: symlinkURL) }
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: reviewedScript)
        XCTAssertThrowsError(try DaemonLifecycleScriptLoader.bundled.load(symlinkURL))
    }

    func testTamperedBundledScriptFailsClosedBeforeAnyProcessStarts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-install-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Vifty.app", isDirectory: true)
        let script = app.appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env bash\necho replaced\n".utf8).write(to: script)
        let recorder = InstallRunnerRecorder()
        let service = DaemonInstallService(
            processRunner: DaemonInstallProcessRunner { executable, arguments, standardInput in
                await recorder.record(
                    executable: executable,
                    arguments: arguments,
                    standardInput: standardInput,
                    ranOnMainThread: pthread_main_np() != 0
                )
                return DaemonInstallProcessOutput(
                    terminationStatus: 0,
                    standardOutput: "",
                    standardError: ""
                )
            },
            lifecycleScriptLoader: .bundled
        )

        let result = await service.perform(
            operation: .repair,
            appBundleURL: app,
            lifecycleScriptURL: script
        )

        XCTAssertEqual(result.outcome, .failed)
        let invocation = await recorder.invocation
        XCTAssertNil(invocation)
    }

    func testUnexpectedLifecycleResourceLocationFailsClosedBeforeLoadingOrRunning() async {
        let recorder = InstallRunnerRecorder()
        let service = DaemonInstallService(
            processRunner: DaemonInstallProcessRunner { executable, arguments, standardInput in
                await recorder.record(
                    executable: executable,
                    arguments: arguments,
                    standardInput: standardInput,
                    ranOnMainThread: pthread_main_np() != 0
                )
                return DaemonInstallProcessOutput(terminationStatus: 0, standardOutput: "", standardError: "")
            },
            lifecycleScriptLoader: DaemonLifecycleScriptLoader { _ in
                Data("#!/usr/bin/env bash\n".utf8)
            }
        )

        let result = await service.perform(
            operation: .repair,
            appBundleURL: URL(fileURLWithPath: "/Applications/Vifty.app"),
            lifecycleScriptURL: URL(fileURLWithPath: "/tmp/swapped-lifecycle.sh")
        )

        XCTAssertEqual(result.outcome, .failed)
        let invocation = await recorder.invocation
        XCTAssertNil(invocation)
    }

    func testSourceKeepsProcessWaitOffMainActor() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Vifty/DaemonInstallService.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("@MainActor"))
        XCTAssertTrue(source.contains("actor DaemonInstallService"))
        XCTAssertTrue(source.contains("Task.detached"))
        XCTAssertTrue(source.contains("URL(fileURLWithPath: \"/bin/bash\")"))
        XCTAssertTrue(source.contains("process.environment = ["))
        XCTAssertTrue(source.contains("\"PATH\": \"/usr/bin:/bin:/usr/sbin:/sbin\""))
        XCTAssertTrue(source.contains("[\"--noprofile\", \"--norc\", \"-s\""))
        XCTAssertFalse(source.contains("processRunner.run(\n                lifecycleScriptURL"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor InstallRunnerRecorder {
    struct Invocation: Sendable {
        var executable: URL
        var arguments: [String]
        var standardInput: Data
        var ranOnMainThread: Bool
    }

    private(set) var invocation: Invocation?

    func record(
        executable: URL,
        arguments: [String],
        standardInput: Data,
        ranOnMainThread: Bool
    ) {
        invocation = Invocation(
            executable: executable,
            arguments: arguments,
            standardInput: standardInput,
            ranOnMainThread: ranOnMainThread
        )
    }
}

private final class ProcessOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: DaemonInstallProcessOutput?

    var value: DaemonInstallProcessOutput? {
        lock.withLock { storedValue }
    }

    func set(_ value: DaemonInstallProcessOutput?) {
        lock.withLock { storedValue = value }
    }
}

private final class ProcessFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedThrew = false

    var threw: Bool {
        lock.withLock { storedThrew }
    }

    func set(threw: Bool) {
        lock.withLock { storedThrew = threw }
    }
}
