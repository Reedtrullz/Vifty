import Foundation

public enum ViftyDaemonConstants {
    public static let machServiceName = "tech.reidar.vifty.daemon"
    public static let plistName = "tech.reidar.vifty.daemon.plist"
}

@objc public protocol ViftyDaemonProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func snapshot(reply: @escaping (NSDictionary?, String?) -> Void)
    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
    )
    func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
    )
}

public enum XPCSnapshotCoding {
    public static func encode(_ snapshot: HardwareSnapshot) -> NSDictionary {
        [
            "modelIdentifier": snapshot.modelIdentifier,
            "isAppleSilicon": snapshot.isAppleSilicon,
            "isMacBookPro": snapshot.isMacBookPro,
            "fans": snapshot.fans.map { fan in
                var encodedFan: [String: Any] = [
                    "id": fan.id,
                    "name": fan.name,
                    "currentRPM": fan.currentRPM,
                    "minimumRPM": fan.minimumRPM,
                    "maximumRPM": fan.maximumRPM,
                    "controllable": fan.controllable
                ]
                if let hardwareMode = fan.hardwareMode {
                    encodedFan["hardwareMode"] = hardwareMode.rawValue
                }
                if let targetRPM = fan.targetRPM {
                    encodedFan["targetRPM"] = targetRPM
                }
                return encodedFan as NSDictionary
            },
            "temperatureSensors": snapshot.temperatureSensors.map { sensor in
                [
                    "id": sensor.id,
                    "name": sensor.name,
                    "celsius": sensor.celsius,
                    "source": sensor.source.rawValue
                ] as NSDictionary
            }
        ] as NSDictionary
    }

    public static func decode(_ dictionary: NSDictionary) -> HardwareSnapshot? {
        guard let modelIdentifier = dictionary["modelIdentifier"] as? String,
              let isAppleSilicon = dictionary["isAppleSilicon"] as? Bool,
              let isMacBookPro = dictionary["isMacBookPro"] as? Bool else {
            return nil
        }

        let fans = (dictionary["fans"] as? [NSDictionary] ?? []).compactMap { item -> Fan? in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String,
                  let currentRPM = item["currentRPM"] as? Int,
                  let minimumRPM = item["minimumRPM"] as? Int,
                  let maximumRPM = item["maximumRPM"] as? Int,
                  let controllable = item["controllable"] as? Bool else {
                return nil
            }
            let hardwareModeRaw = item["hardwareMode"] as? Int
            let targetRPM = item["targetRPM"] as? Int
            return Fan(
                id: id,
                name: name,
                currentRPM: currentRPM,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                controllable: controllable,
                hardwareMode: FanHardwareMode(rawValue: hardwareModeRaw),
                targetRPM: targetRPM
            )
        }

        let sensors = (dictionary["temperatureSensors"] as? [NSDictionary] ?? []).compactMap { item -> TemperatureSensor? in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let celsius = item["celsius"] as? Double,
                  let sourceRaw = item["source"] as? String,
                  let source = SensorSource(rawValue: sourceRaw) else {
                return nil
            }
            return TemperatureSensor(id: id, name: name, celsius: celsius, source: source)
        }

        return HardwareSnapshot(
            fans: fans,
            temperatureSensors: sensors,
            modelIdentifier: modelIdentifier,
            isAppleSilicon: isAppleSilicon,
            isMacBookPro: isMacBookPro
        )
    }
}
