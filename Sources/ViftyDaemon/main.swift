import Foundation
import ViftyCore

private final class DaemonService: NSObject, ViftyDaemonProtocol, @unchecked Sendable {
    private let hardware = RealMacHardwareService(preferDaemon: false)
    private let snapshotCacheTTL: TimeInterval = 1
    private let snapshotCacheLock = NSLock()
    private var cachedSnapshot: (capturedAt: Date, snapshot: HardwareSnapshot)?
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

    func agentControlAudit(_ limit: Int, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        let agentControl = self.agentControl
        Task {
            do {
                let events = try await agentControl.auditEvents(limit: limit)
                reply(XPCAgentControlCoding.encodeAuditEvents(events), nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
    }

    func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
        guard let decoded = XPCAgentControlCoding.decodeRequest(request) else {
            reply(nil, AgentControlErrorCode.invalidArguments.rawValue)
            return
        }
        let agentControl = self.agentControl
        Task {
            defer { clearSnapshotCache() }
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
            defer { clearSnapshotCache() }
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
        minimumRPM _: Int,
        maximumRPM _: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        let agentControl = self.agentControl
        Task {
            defer { clearSnapshotCache() }
            let status = await agentControl.status()
            if let lease = status.activeLease {
                if lease.isActive(at: Date()) {
                    reply(false, "Agent \(lease.request.workload.displayName) cooling owns fan control; restore Auto before manual fan control.")
                } else {
                    reply(false, "Agent cooling restore is pending; restore Auto before manual fan control.")
                }
                return
            }

            do {
                let fan = try resolveWritableFan(fanID: fanID)
                try LocalFanHelperClient().apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func restoreAuto(
        _ fanID: Int,
        minimumRPM _: Int,
        maximumRPM _: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        defer { clearSnapshotCache() }
        do {
            let fan = try resolveWritableFan(fanID: fanID)
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

    private func resolveWritableFan(fanID: Int) throws -> Fan {
        let snapshot = try hardware.localSnapshot()
        guard let fan = snapshot.fans.first(where: { $0.id == fanID }) else {
            throw ViftyError.helperRejected("Fan \(fanID) is not present in daemon hardware telemetry; refusing privileged fan write.")
        }
        guard fan.controllable, fan.maximumRPM > fan.minimumRPM else {
            throw ViftyError.noControllableFans
        }
        return fan
    }

    private func awaitSnapshot() throws -> HardwareSnapshot {
        let now = Date()
        if let cached = cachedSnapshotIfFresh(now: now) {
            return cached
        }
        let snapshot = try hardware.localSnapshot()
        storeSnapshotCache(snapshot, capturedAt: now)
        return snapshot
    }

    private func cachedSnapshotIfFresh(now: Date) -> HardwareSnapshot? {
        snapshotCacheLock.lock()
        defer { snapshotCacheLock.unlock() }
        guard let cachedSnapshot,
              now.timeIntervalSince(cachedSnapshot.capturedAt) < snapshotCacheTTL else {
            return nil
        }
        return cachedSnapshot.snapshot
    }

    private func storeSnapshotCache(_ snapshot: HardwareSnapshot, capturedAt: Date) {
        snapshotCacheLock.lock()
        cachedSnapshot = (capturedAt, snapshot)
        snapshotCacheLock.unlock()
    }

    private func clearSnapshotCache() {
        snapshotCacheLock.lock()
        cachedSnapshot = nil
        snapshotCacheLock.unlock()
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = DaemonService()
    private let identityExtractor = XPCConnectionIdentityExtractor()
    // XPC clients must match signing identifier. The TeamID requirement is
    // empty by default so ad-hoc local builds keep working. Release packaging
    // should set VIFTY_XPC_ALLOWED_TEAM_ID in the LaunchDaemon plist to require
    // Developer ID signed clients from that team.
    private let validator = XPCClientValidator(allowedClients: XPCTrustConfiguration.allowedClients(
        releaseTeamIdentifier: XPCTrustConfiguration.releaseTeamIdentifier(from: ProcessInfo.processInfo.environment)
    ))

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
