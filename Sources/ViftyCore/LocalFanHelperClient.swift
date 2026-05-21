import Foundation

public struct LocalFanHelperClient: Sendable {
    public init() {}

    public func apply(_ command: FanCommand, fan: Fan) throws {
        guard fan.controllable else { throw ViftyError.noControllableFans }

        switch command.mode {
        case .fixedRPM(let rpm):
            let clamped = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
            try writeFixedRPM(clamped, fanID: fan.id)
        case .temperatureCurve(let curve):
            throw ViftyError.helperRejected("Curve commands must be resolved to fixed RPM before reaching the helper. \(curve.points.count) points were provided.")
        case .auto:
            try restoreAuto(fan: fan)
        }
    }

    public func restoreAuto(fan: Fan) throws {
        let smc = try SMCClient()
        // Common SMC convention: F{n}Md = 0 returns a fan to automatic mode.
        try smc.write("F\(fan.id)Md", dataType: "ui8 ", bytes: [0])
        if let targetInfo = try? smc.read("F\(fan.id)Tg") {
            try? smc.write(
                "F\(fan.id)Tg",
                dataType: targetInfo.dataType,
                bytes: SMCDecoding.encodeRPM(fan.minimumRPM, dataType: targetInfo.dataType, size: targetInfo.bytes.count)
            )
        }
    }

    private func writeFixedRPM(_ rpm: Int, fanID: Int) throws {
        let smc = try SMCClient()
        // Common SMC convention: F{n}Md = 1 enables forced/manual mode and F{n}Tg stores target RPM as fpe2.
        try smc.write("F\(fanID)Md", dataType: "ui8 ", bytes: [1])
        let targetInfo = try smc.read("F\(fanID)Tg")
        try smc.write(
            "F\(fanID)Tg",
            dataType: targetInfo.dataType,
            bytes: SMCDecoding.encodeRPM(rpm, dataType: targetInfo.dataType, size: targetInfo.bytes.count)
        )
    }
}
