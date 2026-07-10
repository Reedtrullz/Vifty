import Foundation

final class LocalNotificationHistoryStore: @unchecked Sendable {
    private struct History: Codable {
        var deliveredAtByKind: [String: Date] = [:]
    }

    private let url: URL
    private let lock = NSLock()
    private var history: History

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
        if let data = try? Data(contentsOf: self.url),
           let decoded = try? JSONDecoder().decode(History.self, from: data) {
            history = decoded
        } else {
            history = History()
        }
    }

    func lastDeliveredAt(for kind: LocalNotificationKind) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return history.deliveredAtByKind[kind.rawValue]
    }

    func isCoolingDown(
        _ kind: LocalNotificationKind,
        at date: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard let previous = lastDeliveredAt(for: kind) else { return false }
        return date.timeIntervalSince(previous) < minimumInterval
    }

    func recordDelivery(of kind: LocalNotificationKind, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        var updatedHistory = history
        updatedHistory.deliveredAtByKind[kind.rawValue] = date
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
        let data = try JSONEncoder().encode(updatedHistory)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
        history = updatedHistory
    }

    private static func defaultURL() -> URL {
        if isRunningUnderXCTest {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("vifty-notification-history-xctest")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("notification-history.json")
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/notification-history.json")
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}
