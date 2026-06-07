import Foundation
import XCTest
@testable import ViftyCore

final class ViftyCtlRunnerTests: XCTestCase {
    func testStatusReturnsJSONAndDoesNotMutate() async throws {
        let client = FakeAgentControlClient(
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil
            )
        )
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.status(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["enabled"] as? Bool, true)
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testCapabilitiesReturnsSupportedCommands() async throws {
        let runner = ViftyCtlRunner(client: FakeAgentControlClient(), processRunner: FakeProcessRunner())

        let result = try await runner.run(.capabilities(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("status"))
        XCTAssertTrue(result.stdout.contains("prepare"))
    }

    func testPrepareCallsAgentControlClient() async throws {
        let client = FakeAgentControlClient()
        let processRunner = FakeProcessRunner(exitCode: 0)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let result = try await runner.run(.prepare(request, json: true))

        XCTAssertEqual(result.exitCode, 0)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, [])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRestoreAutoCallsAgentControlRestore() async throws {
        let client = FakeAgentControlClient()
        let processRunner = FakeProcessRunner(exitCode: 0)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.restoreAuto(reason: "done", idempotencyKey: nil, json: true))

        XCTAssertEqual(result.exitCode, 0)
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["done"])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunPreparesRunsChildRestoresAndReturnsChildExitCode() async throws {
        let client = FakeAgentControlClient()
        let processRunner = FakeProcessRunner(exitCode: 7)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"]))

        XCTAssertEqual(result.exitCode, 7)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 7"])
    }

    func testRunRestoresIfChildLaunchThrows() async throws {
        let client = FakeAgentControlClient()
        let launchError = ViftyError.helperRejected("launch failed")
        let processRunner = FakeProcessRunner(error: launchError)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        do {
            _ = try await runner.run(.run(request, childArguments: ["missing-command"]))
            XCTFail("Expected child launch error")
        } catch {
            XCTAssertEqual(error.localizedDescription, launchError.localizedDescription)
            let prepareRequests = await client.prepareRequests
            let restoreReasons = await client.restoreReasons
            XCTAssertEqual(prepareRequests, [request])
            XCTAssertEqual(restoreReasons, ["viftyctl run failed to launch child: \(error.localizedDescription)"])
        }
    }
}

private actor FakeAgentControlClient: ViftyCtlAgentControlClient {
    private let statusResponse: AgentControlStatus
    private var storedPrepareRequests: [AgentControlRequest] = []
    private var storedRestoreReasons: [String] = []

    init(
        status: AgentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: nil,
            lastErrorCode: nil
        )
    ) {
        self.statusResponse = status
    }

    var prepareRequestCount: Int {
        storedPrepareRequests.count
    }

    var restoreReasonCount: Int {
        storedRestoreReasons.count
    }

    var prepareRequests: [AgentControlRequest] {
        storedPrepareRequests
    }

    var restoreReasons: [String] {
        storedRestoreReasons
    }

    func status() async throws -> AgentControlStatus {
        statusResponse
    }

    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        storedPrepareRequests.append(request)
        return statusResponse
    }

    func restore(reason: String) async throws -> AgentControlStatus {
        storedRestoreReasons.append(reason)
        return statusResponse
    }
}

private final class FakeProcessRunner: ViftyCtlProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let exitCode: Int32
    private let error: (any Error)?
    private var storedRunArguments: [[String]] = []

    init(exitCode: Int32 = 0, error: (any Error)? = nil) {
        self.exitCode = exitCode
        self.error = error
    }

    var runCallCount: Int {
        withLock { storedRunArguments.count }
    }

    func run(_ arguments: [String]) throws -> Int32 {
        try withLock {
            storedRunArguments.append(arguments)
            if let error {
                throw error
            }
            return exitCode
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
