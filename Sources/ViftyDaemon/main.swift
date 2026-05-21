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

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
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
