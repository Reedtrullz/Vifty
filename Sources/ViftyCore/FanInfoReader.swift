import Foundation

public enum SMCFanControlKeys {
    public static func isValidFanID(_ fanID: Int) -> Bool {
        (0...9).contains(fanID)
    }

    public static func modeKeyCandidates(forFanID fanID: Int) -> [String] {
        ["F\(fanID)Md", "F\(fanID)md"]
    }

    public static func targetKey(forFanID fanID: Int) -> String {
        "F\(fanID)Tg"
    }
}

public enum SMCFanInfoReader {
    public typealias ReadValue = (String) throws -> SMCValue

    public static func readFans(read: ReadValue) -> [Fan] {
        let fanCount = (try? read("FNum")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).map { index in
            let actual = (try? read("F\(index)Ac")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
            let minimum = (try? read("F\(index)Mn")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 1200
            let maximum = (try? read("F\(index)Mx")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? max(actual, 6000)
            let mode = firstDecodedInteger(
                keys: SMCFanControlKeys.modeKeyCandidates(forFanID: index),
                read: read
            )
            let target = (try? read(SMCFanControlKeys.targetKey(forFanID: index))).flatMap(SMCDecoding.decodeFloat).map(Int.init)

            return Fan(
                id: index,
                name: fanName(index),
                currentRPM: actual,
                minimumRPM: minimum,
                maximumRPM: maximum,
                controllable: maximum > minimum,
                hardwareMode: FanHardwareMode(rawValue: mode?.value),
                hardwareModeKey: mode?.key,
                targetRPM: target
            )
        }
    }

    private static func fanName(_ index: Int) -> String {
        switch index {
        case 0: "Left Fan"
        case 1: "Right Fan"
        default: "Fan \(index + 1)"
        }
    }

    private static func firstDecodedInteger(keys: [String], read: ReadValue) -> (value: Int, key: String)? {
        for key in keys {
            if let value = try? read(key),
               let decoded = SMCDecoding.decodeFloat(value) {
                return (Int(decoded), key)
            }
        }
        return nil
    }
}
