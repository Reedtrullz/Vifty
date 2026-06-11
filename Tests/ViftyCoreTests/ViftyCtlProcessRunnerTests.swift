import Darwin
import XCTest
@testable import ViftyCtl

final class ViftyCtlProcessRunnerTests: XCTestCase {
    func testResolveAcceptsExecutableAbsolutePath() throws {
        let runner = ViftyCtlProcessRunner()

        let resolved = try runner.resolve(["/bin/echo", "hello"])

        XCTAssertEqual(resolved, ["/bin/echo", "hello"])
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
}
