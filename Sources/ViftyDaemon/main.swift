import Foundation
import ViftyCore

private final class DaemonService: NSObject, ViftyDaemonProtocol {
    private let hardware = RealMacHardwareService(preferDaemon: false)
    private lazy var agentControl = AgentControlService(
        hardware: hardware,
        policy: AgentControlPolicy(enabled: true)
    )

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func snapshot(reply: @escaping (NSDictionary?, String?) -> Void) {
        do {
            let snapshot = try awaitSnapshot()
            reply(XPCSnapshotCoding.encode(snapshot), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        let agentControl = self.agentControl
        Task {
            let status = await agentControl.status()
            reply(XPCAgentControlCoding.encode(status), nil)
        }
    }

    func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        guard let decoded = XPCAgentControlCoding.decodeRequest(request) else {
            reply(nil, AgentControlErrorCode.invalidArguments.rawValue)
            return
        }
        let agentControl = self.agentControl
        Task {
            do {
                let status = try await agentControl.prepare(decoded)
                reply(XPCAgentControlCoding.encode(status), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        let agentControl = self.agentControl
        Task {
            do {
                let status = try await agentControl.restoreAuto(reason: reason)
                reply(XPCAgentControlCoding.encode(status), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            let fan = Fan(
                id: fanID,
                name: fanID == 0 ? "Left Fan" : "Right Fan",
                currentRPM: rpm,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                controllable: true
            )
            try LocalFanHelperClient().apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        do {
            let fan = Fan(
                id: fanID,
                name: fanID == 0 ? "Left Fan" : "Right Fan",
                currentRPM: minimumRPM,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                controllable: true
            )
            try LocalFanHelperClient().restoreAuto(fan: fan)
            let agentControl = self.agentControl
            Task {
                do {
                    _ = try await agentControl.clearActiveLease(reason: "User/app restored Auto through daemon restoreAuto")
                    reply(true, nil)
                } catch {
                    reply(false, error.localizedDescription)
                }
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func awaitSnapshot() throws -> HardwareSnapshot {
        try hardware.localSnapshot()
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = DaemonService()
    private let identityExtractor = XPCConnectionIdentityExtractor()
    // XPC clients must match both signing identifier and TeamID.
    // Only binaries signed with the Apple Development identity are accepted.
    private let validator = XPCClientValidator(allowedClients: [
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty", teamIdentifier: "X88J3853S2"),
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: "X88J3853S2")
    ])

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard validator.isAllowed(identityExtractor.identity(for: connection)) else {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: ViftyDaemonProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: ViftyDaemonConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
