import Foundation

struct CodexUsageLimitWindow: Equatable, Sendable {
    var name: String
    var windowLabel: String?
    var usedPercent: Double?
    var resetDate: Date?
}

struct CodexUsageSnapshot: Equatable, Sendable {
    var usedPercent: Double
    var resetDate: Date?
    var windowLabel: String?
    var updatedAt: Date?
    var planType: String?
    var creditsSummary: String?
    var resetCreditsSummary: String?
    var monthlySummary: String?
    var limitWindows: [CodexUsageLimitWindow]
    var sourceFileName: String?
    var sourceSummary: String?

    var leftPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    init(
        usedPercent: Double,
        resetDate: Date? = nil,
        windowLabel: String? = nil,
        updatedAt: Date? = nil,
        planType: String? = nil,
        creditsSummary: String? = nil,
        resetCreditsSummary: String? = nil,
        monthlySummary: String? = nil,
        limitWindows: [CodexUsageLimitWindow] = [],
        sourceFileName: String? = nil,
        sourceSummary: String? = nil
    ) {
        self.usedPercent = usedPercent
        self.resetDate = resetDate
        self.windowLabel = windowLabel
        self.updatedAt = updatedAt
        self.planType = planType
        self.creditsSummary = creditsSummary
        self.resetCreditsSummary = resetCreditsSummary
        self.monthlySummary = monthlySummary
        self.limitWindows = limitWindows
        self.sourceFileName = sourceFileName
        self.sourceSummary = sourceSummary
    }
}

enum CodexUsageMetricMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentLeft
    case percentUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percentLeft:
            return "% left"
        case .percentUsed:
            return "% used"
        }
    }
}

enum CodexUsageResetMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case countdown
    case resetTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .countdown:
            return "Countdown"
        case .resetTime:
            return "Reset time"
        }
    }
}

enum CodexUsageRefreshCadence: Int, Codable, CaseIterable, Identifiable, Sendable {
    case thirtySeconds = 30
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .thirtySeconds:
            return "30 sec"
        case .oneMinute:
            return "1 min"
        case .threeMinutes:
            return "3 min"
        case .fiveMinutes:
            return "5 min"
        }
    }

    init?(seconds: TimeInterval) {
        let rounded = Int(seconds.rounded())
        self.init(rawValue: rounded)
    }
}

struct CodexUsageDisplayPreferences: Codable, Equatable, Sendable {
    var metricMode: CodexUsageMetricMode
    var resetMode: CodexUsageResetMode
    var refreshCadence: CodexUsageRefreshCadence

    static let defaults = CodexUsageDisplayPreferences(
        metricMode: .percentLeft,
        resetMode: .countdown,
        refreshCadence: .fiveMinutes
    )

    init(
        metricMode: CodexUsageMetricMode = .percentLeft,
        resetMode: CodexUsageResetMode = .countdown,
        refreshCadence: CodexUsageRefreshCadence = .fiveMinutes
    ) {
        self.metricMode = metricMode
        self.resetMode = resetMode
        self.refreshCadence = refreshCadence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricMode = try container.decodeIfPresent(CodexUsageMetricMode.self, forKey: .metricMode) ?? Self.defaults.metricMode
        resetMode = try container.decodeIfPresent(CodexUsageResetMode.self, forKey: .resetMode) ?? Self.defaults.resetMode
        refreshCadence = try container.decodeIfPresent(CodexUsageRefreshCadence.self, forKey: .refreshCadence) ?? Self.defaults.refreshCadence
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
        let sourceMode = ProcessInfo.processInfo.environment["VIFTY_CODEX_USAGE_SOURCE"]?.lowercased()
        if sourceMode != "local",
           let snapshot = CodexUsageAppServerClient().read() {
            return snapshot
        }
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
              let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        let timestamp = event["timestamp"] as? String ?? ""
        let updatedAt = Self.parseTimestamp(timestamp)
        let sourceName = sourceURL.lastPathComponent
        let snapshot = Self.snapshot(
            fromLegacyRateLimits: rateLimits,
            updatedAt: updatedAt,
            sourceFileName: sourceName,
            sourceSummary: "Local JSONL: \(sourceName)"
        ) ?? Self.snapshot(
            fromAppServerSnapshot: rateLimits,
            updatedAt: updatedAt,
            sourceSummary: "Local JSONL: \(sourceName)"
        ) ?? Self.snapshot(
            fromAppServerResult: rateLimits,
            updatedAt: updatedAt,
            sourceSummary: "Local JSONL: \(sourceName)"
        )
        guard let snapshot else { return nil }
        return (timestamp, snapshot)
    }

    static func snapshot(
        fromAppServerResult result: [String: Any],
        updatedAt: Date? = Date(),
        sourceSummary: String = "Codex app-server"
    ) -> CodexUsageSnapshot? {
        guard let preferred = preferredAppServerSnapshot(in: result) else { return nil }
        var snapshot = buildSnapshot(
            from: preferred,
            keyStyle: .appServer,
            updatedAt: updatedAt,
            sourceFileName: nil,
            sourceSummary: sourceSummary,
            limitWindows: appServerLimitWindows(in: result)
        )
        snapshot?.resetCreditsSummary = resetCreditsSummary(result["rateLimitResetCredits"])
        return snapshot
    }

    private static func snapshot(
        fromLegacyRateLimits rateLimits: [String: Any],
        updatedAt: Date?,
        sourceFileName: String?,
        sourceSummary: String
    ) -> CodexUsageSnapshot? {
        buildSnapshot(
            from: rateLimits,
            keyStyle: .legacy,
            updatedAt: updatedAt,
            sourceFileName: sourceFileName,
            sourceSummary: sourceSummary,
            limitWindows: limitWindows(in: rateLimits, keyStyle: .legacy, fallbackName: nil)
        )
    }

    private static func snapshot(
        fromAppServerSnapshot rateLimits: [String: Any],
        updatedAt: Date?,
        sourceSummary: String
    ) -> CodexUsageSnapshot? {
        buildSnapshot(
            from: rateLimits,
            keyStyle: .appServer,
            updatedAt: updatedAt,
            sourceFileName: nil,
            sourceSummary: sourceSummary,
            limitWindows: limitWindows(in: rateLimits, keyStyle: .appServer, fallbackName: nil)
        )
    }

    private static func buildSnapshot(
        from rawSnapshot: [String: Any],
        keyStyle: RateLimitKeyStyle,
        updatedAt: Date?,
        sourceFileName: String?,
        sourceSummary: String,
        limitWindows: [CodexUsageLimitWindow]
    ) -> CodexUsageSnapshot? {
        guard let primary = rawSnapshot["primary"] as? [String: Any],
              let usedPercent = numericValue(primary[keyStyle.usedPercentKey]) else {
            return nil
        }

        let resetDate = numericValue(primary[keyStyle.resetDateKey]).map(Date.init(timeIntervalSince1970:))
        let windowLabel = windowLabel(for: primary, keyStyle: keyStyle)
        return CodexUsageSnapshot(
            usedPercent: usedPercent,
            resetDate: resetDate,
            windowLabel: windowLabel,
            updatedAt: updatedAt,
            planType: stringValue(rawSnapshot[keyStyle.planTypeKey]),
            creditsSummary: creditsSummary(rawSnapshot["credits"]),
            resetCreditsSummary: nil,
            monthlySummary: monthlySummary(rawSnapshot["individualLimit"]),
            limitWindows: limitWindows,
            sourceFileName: sourceFileName,
            sourceSummary: sourceSummary
        )
    }

    private static func preferredAppServerSnapshot(in result: [String: Any]) -> [String: Any]? {
        if let byLimitID = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byLimitID["codex"] as? [String: Any] {
                return codex
            }
            for key in sortedLimitKeys(byLimitID.keys) {
                if let snapshot = byLimitID[key] as? [String: Any] {
                    return snapshot
                }
            }
        }
        return result["rateLimits"] as? [String: Any]
    }

    private static func appServerLimitWindows(in result: [String: Any]) -> [CodexUsageLimitWindow] {
        if let byLimitID = result["rateLimitsByLimitId"] as? [String: Any] {
            return sortedLimitKeys(byLimitID.keys).flatMap { key -> [CodexUsageLimitWindow] in
                guard let snapshot = byLimitID[key] as? [String: Any] else { return [] }
                return limitWindows(in: snapshot, keyStyle: .appServer, fallbackName: key)
            }
        }
        if let rateLimits = result["rateLimits"] as? [String: Any] {
            return limitWindows(in: rateLimits, keyStyle: .appServer, fallbackName: "Codex")
        }
        return []
    }

    private static func sortedLimitKeys(_ keys: Dictionary<String, Any>.Keys) -> [String] {
        keys.sorted { left, right in
            if left == "codex" {
                return right != "codex"
            }
            if right == "codex" {
                return false
            }
            return left < right
        }
    }

    private static func limitWindows(
        in snapshot: [String: Any],
        keyStyle: RateLimitKeyStyle,
        fallbackName: String?
    ) -> [CodexUsageLimitWindow] {
        let name = stringValue(snapshot[keyStyle.limitNameKey])
            ?? stringValue(snapshot[keyStyle.limitIDKey])
            ?? fallbackName
            ?? "Codex"
        return ["primary", "secondary"].compactMap { key in
            guard let window = snapshot[key] as? [String: Any] else { return nil }
            let label = windowLabel(for: window, keyStyle: keyStyle)
            let qualifiedName = label.map { "\(name) \($0)" } ?? name
            return CodexUsageLimitWindow(
                name: qualifiedName,
                windowLabel: label,
                usedPercent: numericValue(window[keyStyle.usedPercentKey]),
                resetDate: numericValue(window[keyStyle.resetDateKey]).map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    private static func windowLabel(for window: [String: Any], keyStyle: RateLimitKeyStyle) -> String? {
        guard let minutes = numericValue(window[keyStyle.windowMinutesKey]) else { return nil }
        let value = Int(minutes.rounded())
        guard value > 0 else { return nil }
        if value % 1440 == 0 {
            return "\(value / 1440)d"
        }
        if value % 60 == 0 {
            return "\(value / 60)h"
        }
        return "\(value)m"
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func creditsSummary(_ value: Any?) -> String? {
        guard let credits = value as? [String: Any] else { return nil }
        if (credits["unlimited"] as? Bool) == true {
            return "Credits: unlimited"
        }
        if let balance = stringValue(credits["balance"]) {
            return "Credits: \(balance)"
        }
        if let balance = numericValue(credits["balance"]) {
            return "Credits: \(String(format: "%.2f", balance))"
        }
        if let hasCredits = credits["hasCredits"] as? Bool, !hasCredits {
            return "Credits: none"
        }
        return nil
    }

    private static func resetCreditsSummary(_ value: Any?) -> String? {
        guard let resetCredits = value as? [String: Any],
              let available = numericValue(resetCredits["availableCount"]) else {
            return nil
        }
        return "Usage resets: \(Int(available)) available"
    }

    private static func monthlySummary(_ value: Any?) -> String? {
        guard let monthly = value as? [String: Any] else { return nil }
        var parts: [String] = []
        if let used = stringValue(monthly["used"]),
           let limit = stringValue(monthly["limit"]) {
            parts.append("\(used) of \(limit)")
        }
        if let remaining = numericValue(monthly["remainingPercent"]) {
            parts.append("\(Int(remaining.rounded()))% left")
        }
        guard !parts.isEmpty else { return nil }
        return "Monthly: \(parts.joined(separator: ", "))"
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

private struct RateLimitKeyStyle {
    var usedPercentKey: String
    var resetDateKey: String
    var windowMinutesKey: String
    var planTypeKey: String
    var limitNameKey: String
    var limitIDKey: String

    static let legacy = RateLimitKeyStyle(
        usedPercentKey: "used_percent",
        resetDateKey: "resets_at",
        windowMinutesKey: "window_minutes",
        planTypeKey: "plan_type",
        limitNameKey: "limit_name",
        limitIDKey: "limit_id"
    )

    static let appServer = RateLimitKeyStyle(
        usedPercentKey: "usedPercent",
        resetDateKey: "resetsAt",
        windowMinutesKey: "windowDurationMins",
        planTypeKey: "planType",
        limitNameKey: "limitName",
        limitIDKey: "limitId"
    )
}

struct CodexUsageAppServerClient {
    private static let initializeRequestID = "vifty-codex-usage-init"
    private static let requestID = "vifty-codex-usage"
    private let executableURL: URL?
    private let timeout: TimeInterval

    init(executableURL: URL? = nil, timeout: TimeInterval = 2.5) {
        self.executableURL = executableURL ?? Self.defaultExecutableURL()
        self.timeout = timeout
    }

    func read() -> CodexUsageSnapshot? {
        guard let executableURL else { return nil }
        if let snapshot = readUsingStdioAppServer(executableURL) {
            return snapshot
        }
        return readUsingProxy(executableURL)
    }

    private func readUsingStdioAppServer(_ executableURL: URL) -> CodexUsageSnapshot? {
        let initialize: [String: Any] = [
            "id": Self.initializeRequestID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "vifty",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "local"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        ]
        let initialized: [String: Any] = [
            "method": "notifications/initialized",
            "params": [:]
        ]
        return readRateLimits(
            executableURL,
            arguments: ["app-server", "--stdio"],
            prefixRequests: [initialize, initialized]
        )
    }

    private func readUsingProxy(_ executableURL: URL) -> CodexUsageSnapshot? {
        readRateLimits(
            executableURL,
            arguments: ["app-server", "proxy"],
            prefixRequests: []
        )
    }

    private func readRateLimits(
        _ executableURL: URL,
        arguments: [String],
        prefixRequests: [[String: Any]]
    ) -> CodexUsageSnapshot? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let responseReady = DispatchSemaphore(value: 0)
        let output = LockedOutput()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if output.appendAndContainsResult(data, requestID: Self.requestID) {
                responseReady.signal()
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { _ in
            responseReady.signal()
        }

        do {
            try process.run()
            let request: [String: Any] = [
                "id": Self.requestID,
                "method": "account/rateLimits/read",
                "params": NSNull()
            ]
            for payload in prefixRequests + [request] {
                let requestData = try JSONSerialization.data(withJSONObject: payload)
                stdin.fileHandleForWriting.write(requestData)
                stdin.fileHandleForWriting.write(Data("\n".utf8))
            }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            return nil
        }

        _ = responseReady.wait(timeout: .now() + timeout)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        let remainingData = stdout.fileHandleForReading.readDataToEndOfFile()
        if !remainingData.isEmpty {
            output.append(remainingData)
        }

        let responseData = output.snapshot()
        guard let result = Self.resultPayload(from: responseData, requestID: Self.requestID) else {
            return nil
        }
        return CodexUsageReader.snapshot(
            fromAppServerResult: result,
            updatedAt: Date(),
            sourceSummary: "Codex app-server"
        )
    }

    private static func resultPayload(from data: Data, requestID: String) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["id"] as? String == requestID,
           let result = object["result"] as? [String: Any] {
            return result
        }

        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  object["id"] as? String == requestID,
                  let result = object["result"] as? [String: Any] else {
                continue
            }
            return result
        }
        return nil
    }

    private static func defaultExecutableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CODEX_CLI"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private final class LockedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func appendAndContainsResult(_ chunk: Data, requestID: String) -> Bool {
            lock.lock()
            data.append(chunk)
            let hasResult = CodexUsageAppServerClient.resultPayload(from: data, requestID: requestID) != nil
            lock.unlock()
            return hasResult
        }

        func snapshot() -> Data {
            lock.lock()
            let snapshot = data
            lock.unlock()
            return snapshot
        }
    }
}

enum CodexUsageFormatter {
    static func menuBarText(
        for snapshot: CodexUsageSnapshot?,
        options: CodexUsageDisplayPreferences = .defaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> String {
        guard let snapshot else { return "Codex --" }
        var text = "Codex \(metricText(for: snapshot, mode: options.metricMode))"
        if let resetDate = snapshot.resetDate {
            text += " · \(menuResetText(until: resetDate, mode: options.resetMode, now: now()))"
        }
        return text
    }

    static func summaryText(
        for snapshot: CodexUsageSnapshot?,
        options: CodexUsageDisplayPreferences = .defaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> String {
        guard let snapshot else { return "Codex usage unavailable" }
        let scope = snapshot.windowLabel.map { " \($0)" } ?? ""
        var text = "Codex\(scope): \(metricText(for: snapshot, mode: options.metricMode)), \(alternateMetricText(for: snapshot, mode: options.metricMode))"
        if let resetDate = snapshot.resetDate {
            text += " · \(summaryResetText(until: resetDate, mode: options.resetMode, now: now()))"
        }
        return text
    }

    static func detailText(
        for snapshot: CodexUsageSnapshot?,
        options: CodexUsageDisplayPreferences = .defaults
    ) -> String? {
        detailLines(for: snapshot, options: options).joined(separator: " · ").nilIfEmpty
    }

    static func detailLines(
        for snapshot: CodexUsageSnapshot?,
        options: CodexUsageDisplayPreferences = .defaults,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> [String] {
        guard let snapshot else { return [] }
        var lines: [String] = []
        if let planType = snapshot.planType {
            lines.append("Plan: \(planType)")
        }
        if let creditsSummary = snapshot.creditsSummary {
            lines.append(creditsSummary)
        }
        if let resetCreditsSummary = snapshot.resetCreditsSummary {
            lines.append(resetCreditsSummary)
        }
        if let monthlySummary = snapshot.monthlySummary {
            lines.append(monthlySummary)
        }
        lines.append(contentsOf: limitSummaryLines(for: snapshot, options: options, now: now))
        if let sourceSummary = snapshot.sourceSummary {
            lines.append("Source: \(sourceSummary)")
        } else if let sourceFileName = snapshot.sourceFileName {
            lines.append("Source: \(sourceFileName)")
        }
        return lines
    }

    private static func roundedPercent(_ value: Double) -> Int {
        Int(max(0, min(100, value)).rounded())
    }

    private static func metricText(for snapshot: CodexUsageSnapshot, mode: CodexUsageMetricMode) -> String {
        switch mode {
        case .percentLeft:
            return "\(roundedPercent(snapshot.leftPercent))% left"
        case .percentUsed:
            return "\(roundedPercent(snapshot.usedPercent))% used"
        }
    }

    private static func alternateMetricText(for snapshot: CodexUsageSnapshot, mode: CodexUsageMetricMode) -> String {
        switch mode {
        case .percentLeft:
            return "\(roundedPercent(snapshot.usedPercent))% used"
        case .percentUsed:
            return "\(roundedPercent(snapshot.leftPercent))% left"
        }
    }

    private static func countdownText(until date: Date, now: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now).rounded()))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }

    private static func compactCountdownText(until date: Date, now: Date) -> String {
        let remainingSeconds = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int((remainingSeconds / 60).rounded(.up))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func resetClockText(for date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private static func menuResetText(
        until date: Date,
        mode: CodexUsageResetMode,
        now: Date
    ) -> String {
        switch mode {
        case .countdown:
            return compactCountdownText(until: date, now: now)
        case .resetTime:
            return resetClockText(for: date)
        }
    }

    private static func summaryResetText(
        until date: Date,
        mode: CodexUsageResetMode,
        now: Date
    ) -> String {
        switch mode {
        case .countdown:
            return "resets in \(countdownText(until: date, now: now))"
        case .resetTime:
            return "resets at \(resetClockText(for: date))"
        }
    }

    private static func limitSummaryLines(
        for snapshot: CodexUsageSnapshot,
        options: CodexUsageDisplayPreferences,
        now: @escaping @Sendable () -> Date
    ) -> [String] {
        snapshot.limitWindows.map { window in
            let usedText = window.usedPercent.map { "\(roundedPercent($0))% used" } ?? "--% used"
            let resetText = window.resetDate.map { summaryResetText(until: $0, mode: options.resetMode, now: now()) } ?? "reset unknown"
            return "\(window.name): \(usedText), \(resetText)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
