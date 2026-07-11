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
        XCTAssertEqual(snapshot.windowLabel, "5h")
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.creditsSummary, "Credits: 123.45")
        XCTAssertEqual(snapshot.sourceFileName, "newer.jsonl")
        XCTAssertEqual(
            CodexUsageFormatter.menuBarText(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            "Ai 63% left · 1h"
        )
        XCTAssertEqual(
            CodexUsageFormatter.summaryText(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            "Codex 5h: 63% left, 37% used · resets in 1:00:00"
        )
        XCTAssertEqual(
            CodexUsageFormatter.detailLines(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            [
                "Plan: pro",
                "Credits: 123.45",
                "Codex 5h: 37% used, resets in 1:00:00",
                "Source: Local JSONL: newer.jsonl"
            ]
        )
    }

    func testReaderFindsLatestUsageEventFromBoundedTailOfLargeSessionFile() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let event = """
        {"timestamp":"2026-06-21T11:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":21,"resets_at":1800003600,"window_minutes":300},"plan_type":"pro"}}}
        """
        let filler = String(repeating: "{\"payload\":{\"type\":\"noise\"}}\n", count: 30_000)
        try (filler + event + "\n").write(
            to: sessions.appendingPathComponent("large.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try XCTUnwrap(CodexUsageReader(codexHome: root).read())

        XCTAssertEqual(snapshot.usedPercent, 21, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceFileName, "large.jsonl")
    }

    func testReaderDoesNotScanEntireLargeSessionFileWhenTailHasNoUsageEvent() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let event = """
        {"timestamp":"2026-06-21T11:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":21,"resets_at":1800003600,"window_minutes":300},"plan_type":"pro"}}}
        """
        let filler = String(repeating: "{\"payload\":{\"type\":\"noise\"}}\n", count: 30_000)
        try (event + "\n" + filler).write(
            to: sessions.appendingPathComponent("large.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNil(CodexUsageReader(codexHome: root).read())
    }

    func testReaderKeepsScanningBoundedTailPastMalformedUsageCandidates() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let validEvent = """
        {"timestamp":"2026-06-21T11:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":21,"resets_at":1800003600,"window_minutes":300},"plan_type":"pro"}}}
        """
        let malformedEvents = (0..<30).map { index in
            """
            {"timestamp":"2026-06-21T11:01:\(String(format: "%02d", index))Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"invalid-\(index)"}}}}
            """
        }
        try ([validEvent] + malformedEvents).joined(separator: "\n").write(
            to: sessions.appendingPathComponent("malformed-tail.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try XCTUnwrap(CodexUsageReader(codexHome: root).read())

        XCTAssertEqual(snapshot.usedPercent, 21, accuracy: 0.001)
        XCTAssertEqual(snapshot.sourceFileName, "malformed-tail.jsonl")
    }

    func testReaderParsesAppServerRateLimitSnapshotShape() throws {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "limitName": "Codex",
                    "planType": "pro",
                    "primary": [
                        "usedPercent": 44.4,
                        "resetsAt": 1_800_003_600,
                        "windowDurationMins": 300
                    ],
                    "secondary": [
                        "usedPercent": 12.0,
                        "resetsAt": 1_800_086_400,
                        "windowDurationMins": 10_080
                    ],
                    "credits": [
                        "balance": "8.50"
                    ],
                    "individualLimit": [
                        "used": "12",
                        "limit": "100",
                        "remainingPercent": 88
                    ]
                ],
                "chatgpt": [
                    "limitName": "ChatGPT",
                    "primary": [
                        "usedPercent": 10.0,
                        "resetsAt": 1_800_010_800,
                        "windowDurationMins": 180
                    ]
                ]
            ],
            "rateLimitResetCredits": [
                "availableCount": 2
            ]
        ]

        let snapshot = try XCTUnwrap(CodexUsageReader.snapshot(
            fromAppServerResult: result,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceSummary: "Codex app-server"
        ))

        XCTAssertEqual(snapshot.usedPercent, 44.4, accuracy: 0.001)
        XCTAssertEqual(snapshot.leftPercent, 55.6, accuracy: 0.001)
        XCTAssertEqual(snapshot.windowLabel, "5h")
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.creditsSummary, "Credits: 8.50")
        XCTAssertEqual(snapshot.resetCreditsSummary, "Usage resets: 2 available")
        XCTAssertEqual(snapshot.monthlySummary, "Monthly: 12 of 100, 88% left")
        XCTAssertEqual(
            CodexUsageFormatter.menuBarText(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            "Ai 56% left · 1h"
        )
        XCTAssertEqual(
            CodexUsageFormatter.summaryText(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            "Codex 5h: 56% left, 44% used · resets in 1:00:00"
        )
        XCTAssertEqual(
            CodexUsageFormatter.detailLines(for: snapshot, now: { Date(timeIntervalSince1970: 1_800_000_000) }),
            [
                "Plan: pro",
                "Credits: 8.50",
                "Usage resets: 2 available",
                "Monthly: 12 of 100, 88% left",
                "Codex 5h: 44% used, resets in 1:00:00",
                "Codex 7d: 12% used, resets in 24:00:00",
                "ChatGPT 3h: 10% used, resets in 3:00:00",
                "Source: Codex app-server"
            ]
        )
    }

    func testFormatterCanShowUsedPercentAndResetClockTime() throws {
        let resetDate = Date(timeIntervalSince1970: 1_800_003_600)
        let snapshot = CodexUsageSnapshot(
            usedPercent: 42.4,
            resetDate: resetDate,
            windowLabel: "5h",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            planType: "pro",
            creditsSummary: "Credits: 10.00",
            sourceFileName: "session.jsonl"
        )
        let options = CodexUsageDisplayPreferences(
            metricMode: .percentUsed,
            resetMode: .resetTime,
            refreshCadence: .thirtySeconds
        )
        let resetTime = DateFormatter.localizedString(from: resetDate, dateStyle: .none, timeStyle: .short)

        XCTAssertEqual(
            CodexUsageFormatter.menuBarText(
                for: snapshot,
                options: options,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ),
            "Ai 42% used · \(resetTime)"
        )
        XCTAssertEqual(
            CodexUsageFormatter.summaryText(
                for: snapshot,
                options: options,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ),
            "Codex 5h: 42% used, 58% left · resets at \(resetTime)"
        )
    }

    func testFormatterCanShowBatteryStyleMenuBarText() throws {
        let resetDate = Date(timeIntervalSince1970: 1_800_003_600)
        let snapshot = CodexUsageSnapshot(
            usedPercent: 42.4,
            resetDate: resetDate,
            windowLabel: "5h",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let leftOptions = CodexUsageDisplayPreferences(
            displayStyle: .battery,
            metricMode: .percentLeft,
            resetMode: .countdown,
            refreshCadence: .fiveMinutes
        )
        let usedOptions = CodexUsageDisplayPreferences(
            displayStyle: .battery,
            metricMode: .percentUsed,
            resetMode: .countdown,
            refreshCadence: .fiveMinutes
        )

        XCTAssertEqual(
            CodexUsageFormatter.menuBarText(
                for: snapshot,
                options: leftOptions,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ),
            "Ai [###--] 58% left · 1h"
        )
        XCTAssertEqual(
            CodexUsageFormatter.menuBarText(
                for: snapshot,
                options: usedOptions,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            ),
            "Ai [##---] 42% used · 1h"
        )
    }

    func testAppServerClientReadsRateLimitsOverDirectStdio() throws {
        let root = try temporaryDirectory()
        let executable = root.appendingPathComponent("fake-codex")
        let argsLog = root.appendingPathComponent("args.log")
        let stdinLog = root.appendingPathComponent("stdin.log")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" > \(shellSingleQuote(argsLog.path))
        initialized=0
        while IFS= read -r line
        do
          printf '%s\\n' "$line" >> \(shellSingleQuote(stdinLog.path))
          case "$line" in
            *vifty-codex-usage-init*)
              printf '%s\\n' '{"id":"vifty-codex-usage-init","result":{"ok":true}}'
              ;;
            *initialized*)
              initialized=1
              ;;
            *account*rateLimits*read*)
              if [ "$initialized" != "1" ]; then
                exit 3
              fi
              printf '%s\\n' '{"method":"remoteControl/status/changed","params":{"status":"disabled"}}'
              printf '%s\\n' '{"id":"vifty-codex-usage","result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","planType":"pro","primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":2,"windowDurationMins":10080,"resetsAt":1800086400},"credits":{"hasCredits":false,"balance":"0"}}},"rateLimitResetCredits":{"availableCount":0}}}'
              exit 0
              ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: executable.path)

        let snapshot = try XCTUnwrap(CodexUsageAppServerClient(executableURL: executable, timeout: 1).read())

        XCTAssertEqual(snapshot.usedPercent, 12.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.leftPercent, 87.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.resetDate, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(snapshot.windowLabel, "5h")
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.creditsSummary, "Credits: 0")
        XCTAssertEqual(snapshot.resetCreditsSummary, "Usage resets: 0 available")
        XCTAssertEqual(snapshot.sourceSummary, "Codex app-server")
        XCTAssertEqual(
            Set(snapshot.limitWindows.map(\.name)),
            Set(["codex 5h", "codex 7d"])
        )
        XCTAssertEqual(try String(contentsOf: argsLog, encoding: .utf8), "app-server --listen stdio://\n")
        let stdin = try String(contentsOf: stdinLog, encoding: .utf8)
        XCTAssertTrue(stdin.contains("initialize"))
        XCTAssertTrue(stdin.contains("account"))
        XCTAssertTrue(stdin.contains("rateLimits"))
        XCTAssertTrue(stdin.contains("read"))
    }

    func testAppServerClientPrefersCurrentChatGPTBundleExecutable() {
        XCTAssertEqual(
            CodexUsageAppServerClient.defaultExecutablePaths.first,
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        )
        XCTAssertTrue(CodexUsageAppServerClient.defaultExecutablePaths.contains(
            "/Applications/Codex.app/Contents/Resources/codex"
        ))
    }

    func testAppServerClientFallsBackToLegacyStdioFlag() throws {
        let root = try temporaryDirectory()
        let executable = root.appendingPathComponent("legacy-codex")
        let argsLog = root.appendingPathComponent("args.log")
        let script = """
        #!/bin/sh
        printf '%s\n' "$*" >> \(shellSingleQuote(argsLog.path))
        if [ "$*" = "app-server --listen stdio://" ]; then
          exit 2
        fi
        if [ "$*" != "app-server --stdio" ]; then
          exit 3
        fi
        while IFS= read -r line
        do
          case "$line" in
            *account*rateLimits*read*)
              printf '%s\n' '{"id":"vifty-codex-usage","result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800003600}}}}'
              exit 0
              ;;
          esac
        done
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: executable.path
        )

        let snapshot = try XCTUnwrap(CodexUsageAppServerClient(executableURL: executable, timeout: 1).read())

        XCTAssertEqual(snapshot.usedPercent, 25, accuracy: 0.001)
        XCTAssertEqual(
            try String(contentsOf: argsLog, encoding: .utf8),
            "app-server --listen stdio://\napp-server --stdio\n"
        )
    }

    func testAppServerClientBoundsShutdownWhenDescendantKeepsPipeOpen() throws {
        let root = try temporaryDirectory()
        let executable = root.appendingPathComponent("stubborn-codex")
        let script = """
        #!/bin/sh
        trap '' TERM
        sleep 0.6 &
        wait
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: executable.path
        )
        let client = CodexUsageAppServerClient(
            executableURL: executable,
            timeout: 0.05,
            terminationGracePeriod: 0.05
        )

        let startedAt = Date()
        let snapshot = client.read()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertNil(snapshot)
        XCTAssertLessThan(elapsed, 0.7)
    }

    func testReaderReturnsNilWithoutLocalTokenCountEvents() throws {
        let root = try temporaryDirectory()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions", isDirectory: true), withIntermediateDirectories: true)

        let reader = CodexUsageReader(codexHome: root)

        XCTAssertNil(reader.read())
        XCTAssertEqual(CodexUsageFormatter.menuBarText(for: nil), "Ai --")
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

    private func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
