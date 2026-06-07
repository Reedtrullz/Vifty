import Foundation
import ViftyCore

private final class DaemonService: NSObject, ViftyDaemonProtocol {
    private let hardware = RealMacHardwareService(preferDaemon: false)

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
        reply(XPCAgentControlCoding.encode(AgentControlStatus(enabled: false, activeLease: nil, lastDecision: nil, lastErrorCode: nil)), nil)
    }

    func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        reply(nil, "Agent control is not wired yet.")
    }

    func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        reply(XPCAgentControlCoding.encode(AgentControlStatus(enabled: false, activeLease: nil, lastDecision: nil, lastErrorCode: nil)), nil)
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
        reply: @escaping (Bool, String?) -> Void
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
            reply(true, nil)
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
    // Discovered with `codesign -dvvv .build/Vifty.app`: the local app is
    // ad-hoc signed and has `TeamIdentifier=not set`, so local development
    // validation must use signing-identifier-only matching.
    private let validator = XPCClientValidator(allowedClients: [
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil),
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)
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
