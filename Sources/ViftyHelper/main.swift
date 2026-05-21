import Foundation
import ViftyCore

enum HelperCommand: String {
    case setFixed
    case auto
    case probe
    case probeLocal
    case readKey
    case smcDiagnostics
}

func usage() -> Never {
    fputs("Usage: ViftyHelper probe | ViftyHelper probeLocal | ViftyHelper smcDiagnostics | ViftyHelper readKey <SMC key> | ViftyHelper setFixed <fanID> <rpm> <minRPM> <maxRPM> | ViftyHelper auto <fanID> <minRPM> <maxRPM>\n", stderr)
    exit(64)
}

let arguments = CommandLine.arguments.dropFirst()
guard let commandValue = arguments.first, let command = HelperCommand(rawValue: commandValue) else {
    usage()
}

do {
    switch command {
    case .probe:
        let snapshot = try awaitSnapshot()
        printSnapshot(snapshot)
    case .probeLocal:
        let snapshot = try RealMacHardwareService(preferDaemon: false).localSnapshot()
        printSnapshot(snapshot)
    case .readKey:
        guard arguments.count == 2, let key = arguments.dropFirst().first else {
            usage()
        }
        let value = try SMCClient().read(String(key))
        let bytes = value.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        let decoded = SMCDecoding.decodeFloat(value).map { String(format: "%.2f", $0) } ?? "nil"
        print("key=\(value.key) type=\(value.dataType) size=\(value.bytes.count) bytes=\(bytes) decoded=\(decoded)")
    case .smcDiagnostics:
        for line in SMCClient.diagnostics() {
            print(line)
        }
    case .setFixed:
        guard arguments.count == 5,
              let fanID = Int(arguments.dropFirst().first ?? ""),
              let rpm = Int(arguments.dropFirst(2).first ?? ""),
              let minRPM = Int(arguments.dropFirst(3).first ?? ""),
              let maxRPM = Int(arguments.dropFirst(4).first ?? "") else {
            usage()
        }
        let fan = Fan(id: fanID, name: "Fan \(fanID + 1)", currentRPM: rpm, minimumRPM: minRPM, maximumRPM: maxRPM, controllable: true)
        try LocalFanHelperClient().apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
    case .auto:
        guard arguments.count == 4,
              let fanID = Int(arguments.dropFirst().first ?? ""),
              let minRPM = Int(arguments.dropFirst(2).first ?? ""),
              let maxRPM = Int(arguments.dropFirst(3).first ?? "") else {
            usage()
        }
        let fan = Fan(id: fanID, name: "Fan \(fanID + 1)", currentRPM: minRPM, minimumRPM: minRPM, maximumRPM: maxRPM, controllable: true)
        try LocalFanHelperClient().restoreAuto(fan: fan)
    }
} catch {
    fputs("ViftyHelper failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private func printSnapshot(_ snapshot: HardwareSnapshot) {
        print("model=\(snapshot.modelIdentifier) appleSilicon=\(snapshot.isAppleSilicon) macBookPro=\(snapshot.isMacBookPro)")
        print("fans=\(snapshot.fans.count)")
        for fan in snapshot.fans {
            print("fan[\(fan.id)] name=\"\(fan.name)\" rpm=\(fan.currentRPM) min=\(fan.minimumRPM) max=\(fan.maximumRPM) controllable=\(fan.controllable)")
        }
        print("temperatures=\(snapshot.temperatureSensors.count)")
        for sensor in snapshot.temperatureSensors {
            print("temp[\(sensor.id)] name=\"\(sensor.name)\" celsius=\(String(format: "%.1f", sensor.celsius)) source=\(sensor.source.rawValue)")
        }
}

private func awaitSnapshot() throws -> HardwareSnapshot {
    let semaphore = DispatchSemaphore(value: 0)
    final class Box: @unchecked Sendable {
        var result: Result<HardwareSnapshot, Error>?
    }
    let box = Box()
    Task {
        do {
            box.result = .success(try await RealMacHardwareService().snapshot())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.result!.get()
}
