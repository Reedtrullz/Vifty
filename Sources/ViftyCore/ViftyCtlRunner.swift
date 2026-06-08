import Foundation

public struct ViftyCtlResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol ViftyCtlAgentControlClient: Sendable {
    func status() async throws -> AgentControlStatus
    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus
    func restore(reason: String) async throws -> AgentControlStatus
}

public protocol ViftyCtlProcessRunning: Sendable {
    func run(_ arguments: [String]) throws -> Int32
}

public struct ViftyCtlDaemonClient: ViftyCtlAgentControlClient {
    private let client: ViftyDaemonClient

    public init(client: ViftyDaemonClient = ViftyDaemonClient()) {
        self.client = client
    }

    public func status() async throws -> AgentControlStatus {
        try await client.agentControlStatus()
    }

    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        try await client.prepareAgentControl(request)
    }

    public func restore(reason: String) async throws -> AgentControlStatus {
        try await client.restoreAgentControl(reason: reason)
    }
}

public struct ViftyCtlRunner: Sendable {
    private let client: any ViftyCtlAgentControlClient
    private let processRunner: any ViftyCtlProcessRunning

    public init(client: any ViftyCtlAgentControlClient, processRunner: any ViftyCtlProcessRunning) {
        self.client = client
        self.processRunner = processRunner
    }

    public func run(_ command: ViftyCtlCommand) async throws -> ViftyCtlResult {
        switch command {
        case .status(let json):
            let status = try await client.status()
            let stdout = try format(status, json: json)
            return ViftyCtlResult(stdout: stdout)
        case .capabilities(let json):
            let capabilities = ["status", "capabilities", "prepare", "restore-auto", "run"]
            let stdout = try format(capabilities, json: json)
            return ViftyCtlResult(stdout: stdout)
        case .prepare(let request, let json, let force):
            let status = try await client.prepare(request)
            if force, status.lastErrorCode == .prepareRateLimited {
                // Retry once after sleeping for the cooldown
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                let retryStatus = try await client.prepare(request)
                let stdout = try format(retryStatus, json: json)
                return ViftyCtlResult(stdout: stdout)
            }
            let stdout = try format(status, json: json)
            return ViftyCtlResult(stdout: stdout)
        case .restoreAuto(let reason, _, let json):
            let status = try await client.restore(reason: reason)
            let stdout = try format(status, json: json)
            return ViftyCtlResult(stdout: stdout)
        case .run(let request, let childArguments, let force):
            var prepareStatus = try await client.prepare(request)
            if force, prepareStatus.lastErrorCode == .prepareRateLimited {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                prepareStatus = try await client.prepare(request)
            }
            if prepareStatus.lastErrorCode == .prepareRateLimited {
                let stderr = "viftyctl run: prepare rate-limited — \(prepareStatus.lastDecision?.message ?? "cooldown active")\n"
                return ViftyCtlResult(stderr: stderr, exitCode: 1)
            }
            do {
                let exitCode = try processRunner.run(childArguments)
                _ = try? await client.restore(reason: "viftyctl run child exited with \(exitCode)")
                return ViftyCtlResult(exitCode: exitCode)
            } catch {
                _ = try? await client.restore(reason: "viftyctl run failed to launch child: \(error.localizedDescription)")
                throw error
            }
        }
    }

    private func format<T: Encodable>(_ value: T, json: Bool) throws -> String {
        if json {
            return try encodeJSON(value) + "\n"
        }

        if let strings = value as? [String] {
            return strings.joined(separator: "\n") + "\n"
        }

        return String(describing: value) + "\n"
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
