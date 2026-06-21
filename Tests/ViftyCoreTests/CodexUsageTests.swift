import XCTest
@testable import Vifty

final class CodexUsageTests: XCTestCase {
    func testReaderParsesLatestPrimaryRateLimitFromCodexSessions() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let older = """
        {"timestamp":"2026-06-21T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":80,"resets_at":1800007200,"window_minutes":300},"plan_type":"pro"}}}
        """
        let newer = """
        {"timestamp":"2026-06-21T11:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":37.2,"resets_at":1800003600,"window_minutes":300},"plan_type":"pro","credits":{"balance":123.45}}}}
        """
        try older.write(to: sessions.appendingPathComponent("older.jsonl"), atomically: true, encoding: .utf8)
        try newer.write(to: sessions.appendingPathComponent("newer.jsonl"), atomically: true, encoding: .utf8)

        let reader = CodexUsageReader(codexHome: root)

        let snapshot = try XCTUnwrap(reader.read())

        XCTAssertEqual(snapshot.usedPercent, 37.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.leftPercent, 62.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.resetDate, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.creditsSummary, "Credits: 123.45")
        XCTAssertEqual(snapshot.sourceFileName, "newer.jsonl")
        XCTAssertEqual(CodexUsageFormatter.menuBarText(for: snapshot), "Codex 63% left")
        XCTAssertEqual(
            CodexUsageFormatter.summaryText(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            "Codex: 63% left, 37% used · resets in 1:00:00"
        )
    }

    func testReaderReturnsNilWithoutLocalTokenCountEvents() throws {
        let root = try temporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions", isDirectory: true), withIntermediateDirectories: true)

        let reader = CodexUsageReader(codexHome: root)

        XCTAssertNil(reader.read())
        XCTAssertEqual(CodexUsageFormatter.menuBarText(for: nil), "Codex --")
        XCTAssertEqual(CodexUsageFormatter.summaryText(for: nil), "Codex usage unavailable")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViftyCodexUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
