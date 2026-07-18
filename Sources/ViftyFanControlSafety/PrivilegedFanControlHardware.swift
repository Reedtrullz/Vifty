import Foundation
import ViftyCore

/// Synchronous privileged hardware seam. The arbiter calls this without an
/// actor suspension so one logical transaction cannot interleave physical
/// writes with a second owner.
public protocol PrivilegedFanControlHardware: Sendable {
    func freshSnapshot() throws -> HardwareSnapshot
    func applyFixedRPM(_ rpm: Int, to fan: Fan) throws -> FanMutationReceipt
    func restoreOSManagedMode(for fan: Fan) throws -> FanMutationReceipt
}

public struct LocalPrivilegedFanControlHardware: PrivilegedFanControlHardware {
    private let snapshotProvider: @Sendable () throws -> HardwareSnapshot
    private let helper: LocalFanHelperClient

    public init(
        snapshotProvider: @escaping @Sendable () throws -> HardwareSnapshot,
        helper: LocalFanHelperClient = LocalFanHelperClient()
    ) {
        self.snapshotProvider = snapshotProvider
        self.helper = helper
    }

    public func freshSnapshot() throws -> HardwareSnapshot {
        try snapshotProvider()
    }

    public func applyFixedRPM(_ rpm: Int, to fan: Fan) throws -> FanMutationReceipt {
        try helper.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(rpm)), fan: fan)
    }

    public func restoreOSManagedMode(for fan: Fan) throws -> FanMutationReceipt {
        try helper.restoreAuto(fan: fan)
    }
}
