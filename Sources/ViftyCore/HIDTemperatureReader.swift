import Foundation
import ViftyPrivateIOKit

public enum HIDTemperatureReader {
    public static func readTemperatures() -> [TemperatureSensor] {
        var buffer = [ViftyHIDTemperature](repeating: ViftyHIDTemperature(), count: 64)
        let count = ViftyCopyHIDTemperatures(&buffer, Int32(buffer.count))

        return buffer.prefix(Int(count)).enumerated().map { index, item in
            let name = withUnsafeBytes(of: item.name) { rawBuffer -> String in
                let bytes = rawBuffer.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
            return TemperatureSensor(
                id: "hid-\(index)",
                name: name.isEmpty ? "Thermal Sensor \(index + 1)" : name,
                celsius: item.celsius,
                source: .hid
            )
        }
    }
}
