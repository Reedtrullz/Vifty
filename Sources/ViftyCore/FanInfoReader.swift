import Foundation

public enum SMCFanInfoReader {
    public typealias ReadValue = (String) throws -> SMCValue

    public static func readFans(read: ReadValue) -> [Fan] {
        let fanCount = (try? read("FNum")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).map { index in
            let actual = (try? read("F\(index)Ac")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
            let minimum = (try? read("F\(index)Mn")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 1200
            let maximum = (try? read("F\(index)Mx")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? max(actual, 6000)
            let modeRaw = (try? read("F\(index)Md")).flatMap(SMCDecoding.decodeFloat).map(Int.init)
            let target = (try? read("F\(index)Tg")).flatMap(SMCDecoding.decodeFloat).map(Int.init)

            return Fan(
                id: index,
                name: fanName(index),
                currentRPM: actual,
                minimumRPM: minimum,
                maximumRPM: maximum,
                controllable: maximum > minimum,
                hardwareMode: FanHardwareMode(rawValue: modeRaw),
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
}
