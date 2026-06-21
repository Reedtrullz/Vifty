import Foundation

struct CodexUsageSnapshot: Equatable, Sendable {
    var usedPercent: Double
    var resetDate: Date?
    var updatedAt: Date?
    var planType: String?
    var creditsSummary: String?
    var sourceFileName: String?

    var leftPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CodexUsageReader {
    static let maxRecentFiles = 150
    static let tailBytes: UInt64 = 4 * 1024 * 1024

    private let codexHome: URL
    private let fileManager: FileManager

    init(
        codexHome: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.codexHome = codexHome ?? Self.defaultCodexHome()
        self.fileManager = fileManager
    }

    static func readDefault() -> CodexUsageSnapshot? {
        guard shouldReadDefaultCodexHome else { return nil }
        return CodexUsageReader().read()
    }

    func read() -> CodexUsageSnapshot? {
        var latest: (timestamp: String, snapshot: CodexUsageSnapshot)?
        for file in usageFiles() {
            guard let event = latestUsageEvent(in: file) else { continue }
            if latest == nil || event.timestamp > latest!.timestamp {
                latest = event
            }
        }
        return latest?.snapshot
    }

    private func latestUsageEvent(in url: URL) -> (timestamp: String, snapshot: CodexUsageSnapshot)? {
        var lines = candidateLines(fromTailOf: url)
        if lines.isEmpty {
            lines = candidateLines(fromFullFile: url)
        }

        for line in lines {
            guard let event = parseEvent(line, sourceURL: url) else { continue }
            return event
        }
        return nil
    }

    private func usageFiles() -> [URL] {
        let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(modifiedAt: Date, url: URL)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile != false else {
                continue
            }
            files.append((values.contentModificationDate ?? .distantPast, url))
        }

        return files
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(Self.maxRecentFiles)
            .map(\.url)
    }

    private func candidateLines(fromTailOf url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > Self.tailBytes ? size - Self.tailBytes : 0
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return []
        }
        let data = (try? handle.readToEnd()) ?? Data()
        return candidateLines(in: data)
    }

    private func candidateLines(fromFullFile url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return candidateLines(in: data)
    }

    private func candidateLines(in data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reversed()
            .map(String.init)
            .filter { $0.contains("token_count") && $0.contains("rate_limits") }
    }

    private func parseEvent(_ line: String, sourceURL: URL) -> (timestamp: String, snapshot: CodexUsageSnapshot)? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = event["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any],
              let primary = rateLimits["primary"] as? [String: Any],
              let usedPercent = numericValue(primary["used_percent"]) else {
            return nil
        }

        let timestamp = event["timestamp"] as? String ?? ""
        let resetDate = numericValue(primary["resets_at"]).map(Date.init(timeIntervalSince1970:))
        let updatedAt = Self.parseTimestamp(timestamp)
        let snapshot = CodexUsageSnapshot(
            usedPercent: usedPercent,
            resetDate: resetDate,
            updatedAt: updatedAt,
            planType: rateLimits["plan_type"] as? String,
            creditsSummary: creditsSummary(rateLimits["credits"]),
            sourceFileName: sourceURL.lastPathComponent
        )
        return (timestamp, snapshot)
    }

    private func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func creditsSummary(_ value: Any?) -> String? {
        guard let credits = value as? [String: Any] else { return nil }
        if (credits["unlimited"] as? Bool) == true {
            return "Credits: unlimited"
        }
        guard let balance = numericValue(credits["balance"]) else { return nil }
        return "Credits: \(String(format: "%.2f", balance))"
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func defaultCodexHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static var shouldReadDefaultCodexHome: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["VIFTY_ENABLE_CODEX_USAGE_XCTEST"] == "1" {
            return true
        }
        if let override = environment["CODEX_HOME"], !override.isEmpty {
            return true
        }
        return !isRunningUnderXCTest
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}

enum CodexUsageFormatter {
    static func menuBarText(for snapshot: CodexUsageSnapshot?) -> String {
        guard let snapshot else { return "Codex --" }
        return "Codex \(roundedPercent(snapshot.leftPercent))% left"
    }

    static func summaryText(
        for snapshot: CodexUsageSnapshot?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> String {
        guard let snapshot else { return "Codex usage unavailable" }
        var text = "Codex: \(roundedPercent(snapshot.leftPercent))% left, \(roundedPercent(snapshot.usedPercent))% used"
        if let resetDate = snapshot.resetDate {
            text += " · resets in \(countdownText(until: resetDate, now: now()))"
        }
        return text
    }

    static func detailText(for snapshot: CodexUsageSnapshot?) -> String? {
        guard let snapshot else { return nil }
        return [
            snapshot.planType.map { "Plan: \($0)" },
            snapshot.creditsSummary,
            snapshot.sourceFileName.map { "Source: \($0)" }
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
        .nilIfEmpty
    }

    private static func roundedPercent(_ value: Double) -> Int {
        Int(max(0, min(100, value)).rounded())
    }

    private static func countdownText(until date: Date, now: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded()))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
