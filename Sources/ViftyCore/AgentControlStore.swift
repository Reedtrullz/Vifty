import Foundation

public struct AgentControlAuditEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var action: String
    public var leaseID: String?
    public var message: String

    public init(timestamp: Date, action: String, leaseID: String?, message: String) {
        self.timestamp = timestamp
        self.action = action
        self.leaseID = leaseID
        self.message = message
    }
}

public struct AgentControlStore: Sendable {
    public static let defaultMaximumAuditEvents = 2_000

    private let directory: URL
    private let maximumAuditEvents: Int

    public init(
        directory: URL = URL(fileURLWithPath: "/Library/Application Support/Vifty/AgentControl", isDirectory: true),
        maximumAuditEvents: Int = Self.defaultMaximumAuditEvents
    ) {
        self.directory = directory
        self.maximumAuditEvents = max(1, maximumAuditEvents)
    }

    public func saveActiveLease(_ lease: AgentCoolingLease?) throws {
        try createDirectoryIfNeeded()
        let url = directory.appendingPathComponent("active-lease.json")
        if let lease {
            try encoder.encode(lease).write(to: url, options: .atomic)
            try restrictFilePermissions(at: url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadActiveLease() throws -> AgentCoolingLease? {
        let url = directory.appendingPathComponent("active-lease.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(AgentCoolingLease.self, from: Data(contentsOf: url))
    }

    public func appendAuditEvent(_ event: AgentControlAuditEvent) throws {
        try createDirectoryIfNeeded()
        let url = directory.appendingPathComponent("audit.jsonl")
        let data = try encoder.encode(event) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
        try trimAuditFileIfNeeded(at: url)
        try restrictFilePermissions(at: url)
    }

    public func loadRecentAuditEvents(limit: Int = Self.defaultMaximumAuditEvents) throws -> [AgentControlAuditEvent] {
        let url = directory.appendingPathComponent("audit.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let retainedLimit = max(1, limit)
        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        return try lines.suffix(retainedLimit).map { line in
            guard let lineData = line.data(using: .utf8) else {
                throw ViftyError.helperRejected("Could not decode audit event as UTF-8.")
            }
            return try decoder.decode(AgentControlAuditEvent.self, from: lineData)
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
    }

    private func restrictFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private func trimAuditFileIfNeeded(at url: URL) throws {
        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        guard lines.count > maximumAuditEvents else { return }

        let retained = lines.suffix(maximumAuditEvents).joined(separator: "\n") + "\n"
        try Data(retained.utf8).write(to: url, options: .atomic)
    }
}
