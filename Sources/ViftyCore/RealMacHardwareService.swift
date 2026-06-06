import Darwin
import Foundation

public final class RealMacHardwareService: HardwareService, @unchecked Sendable {
    private let smcFactory: @Sendable () throws -> SMCClient
    private let preferDaemon: Bool
    private let daemonSnapshot: @Sendable () async throws -> HardwareSnapshot
    private let daemonApply: @Sendable (FanCommand, Fan) async throws -> Void
    private let daemonRestoreAuto: @Sendable (Fan) async throws -> Void
    private let localApply: @Sendable (FanCommand, Fan) throws -> Void
    private let localRestoreAuto: @Sendable (Fan) throws -> Void
    private let allowsLocalFanWriteFallback: @Sendable () -> Bool

    public init(
        preferDaemon: Bool = true,
        smcFactory: @escaping @Sendable () throws -> SMCClient = { try SMCClient() },
        daemonSnapshot: @escaping @Sendable () async throws -> HardwareSnapshot = {
            try await ViftyDaemonClient().snapshot()
        },
        daemonApply: @escaping @Sendable (FanCommand, Fan) async throws -> Void = { command, fan in
            try await ViftyDaemonClient().apply(command, fan: fan)
        },
        daemonRestoreAuto: @escaping @Sendable (Fan) async throws -> Void = { fan in
            try await ViftyDaemonClient().restoreAuto(fan: fan)
        },
        localApply: @escaping @Sendable (FanCommand, Fan) throws -> Void = { command, fan in
            try LocalFanHelperClient().apply(command, fan: fan)
        },
        localRestoreAuto: @escaping @Sendable (Fan) throws -> Void = { fan in
            try LocalFanHelperClient().restoreAuto(fan: fan)
        },
        allowsLocalFanWriteFallback: @escaping @Sendable () -> Bool = { geteuid() == 0 }
    ) {
        self.preferDaemon = preferDaemon
        self.smcFactory = smcFactory
        self.daemonSnapshot = daemonSnapshot
        self.daemonApply = daemonApply
        self.daemonRestoreAuto = daemonRestoreAuto
        self.localApply = localApply
        self.localRestoreAuto = localRestoreAuto
        self.allowsLocalFanWriteFallback = allowsLocalFanWriteFallback
    }

    public func snapshot() async throws -> HardwareSnapshot {
        if preferDaemon, let daemonSnapshot = try? await daemonSnapshot() {
            return daemonSnapshot
        }

        return try localSnapshot()
    }

    public func localSnapshot() throws -> HardwareSnapshot {
        let model = SystemInfo.modelIdentifier
        let isAppleSilicon = SystemInfo.isAppleSilicon
        let isMacBookPro = SystemInfo.isMacBookPro

        guard isAppleSilicon, isMacBookPro else {
            return HardwareSnapshot(
                fans: [],
                temperatureSensors: [],
                modelIdentifier: model,
                isAppleSilicon: isAppleSilicon,
                isMacBookPro: isMacBookPro
            )
        }

        let smc = try? smcFactory()
        let fans = smc.map(Self.readFans) ?? []
        var sensors = smc.map(Self.readTemperatureSensors) ?? []

        if sensors.isEmpty {
            sensors = HIDTemperatureReader.readTemperatures()
        }

        return HardwareSnapshot(
            fans: fans,
            temperatureSensors: sensors,
            modelIdentifier: model,
            isAppleSilicon: isAppleSilicon,
            isMacBookPro: isMacBookPro
        )
    }

    public func apply(_ command: FanCommand, fan: Fan) async throws {
        if preferDaemon {
            do {
                try await daemonApply(command, fan)
                return
            } catch {
                guard allowsLocalFanWriteFallback() else {
                    throw helperUnavailable(after: error)
                }
            }
        }
        try localApply(command, fan)
    }

    public func restoreAuto(fan: Fan) async throws {
        if preferDaemon {
            do {
                try await daemonRestoreAuto(fan)
                return
            } catch {
                guard allowsLocalFanWriteFallback() else {
                    throw helperUnavailable(after: error)
                }
            }
        }
        try localRestoreAuto(fan)
    }

    private func helperUnavailable(after daemonError: Error) -> ViftyError {
        .helperRejected(
            "Fan helper is unavailable or not responding. Click Reinstall Helper, then approve it if macOS asks. Direct AppleSMC fan writes require root, so Vifty will not fall back to unprivileged local writes. Daemon error: \(daemonError.localizedDescription)"
        )
    }

    private static func readFans(_ smc: SMCClient) -> [Fan] {
        let fanCount = (try? smc.read("FNum")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).map { index in
            let actual = (try? smc.read("F\(index)Ac")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
            let minimum = (try? smc.read("F\(index)Mn")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 1200
            let maximum = (try? smc.read("F\(index)Mx")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? max(actual, 6000)
            return Fan(
                id: index,
                name: fanName(index),
                currentRPM: actual,
                minimumRPM: minimum,
                maximumRPM: maximum,
                controllable: maximum > minimum
            )
        }
    }

    private static func readTemperatureSensors(_ smc: SMCClient) -> [TemperatureSensor] {
        appleSiliconTemperatureKeys.compactMap { key, name in
            guard let value = try? smc.read(key),
                  let celsius = SMCDecoding.decodeFloat(value),
                  celsius > 0,
                  celsius < 130 else {
                return nil
            }
            return TemperatureSensor(id: key, name: name, celsius: celsius, source: .smc)
        }.sorted { $0.name < $1.name }
    }

    private static func fanName(_ index: Int) -> String {
        switch index {
        case 0: "Left Fan"
        case 1: "Right Fan"
        default: "Fan \(index + 1)"
        }
    }
}

private let appleSiliconTemperatureKeys: [(String, String)] = [
    ("Tp09", "CPU Performance Core 1"),
    ("Tp0T", "CPU Performance Core 2"),
    ("Tp01", "CPU Efficiency Core 1"),
    ("Tp05", "CPU Efficiency Core 2"),
    ("Tg0f", "GPU"),
    ("Tm02", "Memory"),
    ("Ts0S", "SoC"),
    ("Ta0P", "Ambient"),
    ("TB1T", "Battery")
]
