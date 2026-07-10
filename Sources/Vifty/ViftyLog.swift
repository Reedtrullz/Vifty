import OSLog

enum ViftyLogCategory: String, CaseIterable {
    case lifecycle = "Lifecycle"
    case polling = "Polling"
    case xpc = "XPC"
    case notifications = "Notifications"
    case fanControl = "FanControl"
    case codexUsage = "CodexUsage"
}

enum ViftyLog {
    static let subsystem = "tech.reidar.vifty"

    static let lifecycle = logger(for: .lifecycle)
    static let polling = logger(for: .polling)
    static let xpc = logger(for: .xpc)
    static let notifications = logger(for: .notifications)
    static let fanControl = logger(for: .fanControl)
    static let codexUsage = logger(for: .codexUsage)
    static let pollingSignposter = OSSignposter(logger: polling)

    private static func logger(for category: ViftyLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
