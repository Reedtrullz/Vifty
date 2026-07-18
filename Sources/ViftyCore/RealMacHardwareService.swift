import Foundation

public final class RealMacHardwareService: HardwareService, @unchecked Sendable {
    private let smcFactory: @Sendable () throws -> SMCClient
    private let hidTemperatureReader: @Sendable () -> [TemperatureSensor]
    private let preferDaemon: Bool
    private let daemonSnapshot: @Sendable () async throws -> HardwareSnapshot
    private let daemonApply: @Sendable (FanCommand, Fan) async throws -> Void
    private let daemonRestoreAuto: @Sendable (Fan) async throws -> Void
    private let daemonOwnershipStatus: @Sendable () async throws -> FanControlOwnershipStatus
    private let daemonApplyManual: @Sendable (ManualFanControlRequest) async throws -> FanControlTransactionResult
    private let daemonRestoreAll: @Sendable (
        AutoRestoreRequest,
        @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult

    public init(
        preferDaemon: Bool = true,
        smcFactory: @escaping @Sendable () throws -> SMCClient = { try SMCClient() },
        hidTemperatureReader: @escaping @Sendable () -> [TemperatureSensor] = {
            HIDTemperatureReader.readTemperatures()
        },
        daemonSnapshot: @escaping @Sendable () async throws -> HardwareSnapshot = {
            try await ViftyDaemonClient().snapshot()
        },
        daemonApply: @escaping @Sendable (FanCommand, Fan) async throws -> Void = { command, fan in
            try await ViftyDaemonClient().apply(command, fan: fan)
        },
        daemonRestoreAuto: @escaping @Sendable (Fan) async throws -> Void = { fan in
            try await ViftyDaemonClient().restoreAuto(fan: fan)
        },
        daemonOwnershipStatus: @escaping @Sendable () async throws -> FanControlOwnershipStatus = {
            try await ViftyDaemonClient().fanControlOwnershipStatus()
        },
        daemonApplyManual: @escaping @Sendable (ManualFanControlRequest) async throws -> FanControlTransactionResult = { request in
            try await ViftyDaemonClient().applyManualFanControl(request)
        },
        daemonRestoreAll: @escaping @Sendable (
            AutoRestoreRequest,
            @escaping @Sendable () throws -> Void
        ) async throws -> FanControlTransactionResult = { request, beforeOwnershipClear in
            let result = try await ViftyDaemonClient().restoreAllAuto(request)
            try beforeOwnershipClear()
            return result
        }
    ) {
        self.preferDaemon = preferDaemon
        self.smcFactory = smcFactory
        self.hidTemperatureReader = hidTemperatureReader
        self.daemonSnapshot = daemonSnapshot
        self.daemonApply = daemonApply
        self.daemonRestoreAuto = daemonRestoreAuto
        self.daemonOwnershipStatus = daemonOwnershipStatus
        self.daemonApplyManual = daemonApplyManual
        self.daemonRestoreAll = daemonRestoreAll
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
            sensors = hidTemperatureReader()
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
                throw helperUnavailable(after: error)
            }
        }
        throw localWriteUnavailable()
    }

    public func restoreAuto(fan: Fan) async throws {
        if preferDaemon {
            do {
                try await daemonRestoreAuto(fan)
                return
            } catch {
                throw helperUnavailable(after: error)
            }
        }
        throw localWriteUnavailable()
    }

    public func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        if preferDaemon {
            do {
                let status = try await daemonOwnershipStatus()
                guard status.protocolVersion >= FanControlProtocolVersion.current else {
                    throw ViftyError.helperRejected("Daemon fan-control protocol v2 is required for writes.")
                }
                return status
            } catch {
                throw helperUnavailable(after: error)
            }
        }
        throw localWriteUnavailable()
    }

    public func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        if preferDaemon {
            do {
                return try await daemonApplyManual(request)
            } catch {
                throw helperUnavailable(after: error)
            }
        }
        throw localWriteUnavailable()
    }

    public func applyAgentFanControl(
        _ request: AgentFanControlRequest
    ) async throws -> FanControlTransactionResult {
        throw ViftyError.helperRejected(
            preferDaemon
                ? "Agent cooling must use the daemon-owned prepare contract, not a direct fan transaction."
                : "Daemon-disabled RealMacHardwareService is read-only and cannot issue fan transactions."
        )
    }

    public func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        if preferDaemon {
            do {
                return try await daemonRestoreAll(request, beforeOwnershipClear)
            } catch {
                throw helperUnavailable(after: error)
            }
        }
        throw localWriteUnavailable()
    }

    private func helperUnavailable(after daemonError: Error) -> ViftyError {
        .helperRejected(
            "Fan helper is unavailable or not responding. Click Reinstall Helper, then approve it if macOS asks. Direct AppleSMC fan writes require root, so Vifty will not fall back to unprivileged local writes. Daemon error: \(daemonError.localizedDescription)"
        )
    }

    private func localWriteUnavailable() -> ViftyError {
        .helperRejected(
            "Daemon-disabled RealMacHardwareService is read-only; fan writes require the daemon-owned safety target."
        )
    }

    private static func readFans(_ smc: SMCClient) -> [Fan] {
        SMCFanInfoReader.readFans { key in
            try smc.read(key)
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
