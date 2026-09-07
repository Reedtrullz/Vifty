import OSLog

enum ViftyCoreLog {
    static let xpc = Logger(subsystem: "tech.reidar.vifty", category: "XPC")
    static let agentControl = Logger(subsystem: "tech.reidar.vifty", category: "AgentControl")
}
