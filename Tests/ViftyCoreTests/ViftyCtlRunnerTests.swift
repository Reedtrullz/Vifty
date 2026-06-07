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
}

private actor FakeAgentControlClient: ViftyCtlAgentControlClient {
    private let statusResponse: AgentControlStatus
    private var prepareRequests: [AgentControlRequest] = []
    private var restoreReasons: [String] = []

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
        prepareRequests.count
    }

    var restoreReasonCount: Int {
        restoreReasons.count
    }

    func status() async throws -> AgentControlStatus {
        statusResponse
    }

    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        prepareRequests.append(request)
        return statusResponse
    }

    func restore(reason: String) async throws -> AgentControlStatus {
        restoreReasons.append(reason)
        return statusResponse
    }
}

private struct FakeProcessRunner: ViftyCtlProcessRunning {
    func run(_ arguments: [String]) throws -> Int32 {
        0
    }
}
