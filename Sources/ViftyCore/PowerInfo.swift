import Foundation
import IOKit
import IOKit.ps

public struct PowerSnapshot: Equatable, Sendable {
    public var percent: Int?
    public var isCharging: Bool
    public var isCharged: Bool
    public var isPluggedIn: Bool
    public var batteryPresent: Bool

    public var batteryVoltageVolts: Double?
    /// Signed current in amps: positive means charging, negative means draining.
    public var batteryCurrentAmps: Double?
    /// Signed battery-pack power in watts: positive means charging, negative means draining.
    public var batteryPowerWatts: Double?

    public var timeToFullMinutes: Int?
    public var timeToEmptyMinutes: Int?

    public var cycleCount: Int?
    public var temperatureCelsius: Double?
    public var designCapacityMah: Int?
    public var maxCapacityMah: Int?
    public var currentCapacityMah: Int?
    public var healthPercent: Int?
    public var condition: String?
    public var serial: String?

    public var adapter: PowerAdapter?
    public var powerDeliveryProfiles: [PowerDeliveryProfile]
    public var capturedAt: Date

    public init(
        percent: Int? = nil,
        isCharging: Bool = false,
        isCharged: Bool = false,
        isPluggedIn: Bool = false,
        batteryPresent: Bool = true,
        batteryVoltageVolts: Double? = nil,
        batteryCurrentAmps: Double? = nil,
        batteryPowerWatts: Double? = nil,
        timeToFullMinutes: Int? = nil,
        timeToEmptyMinutes: Int? = nil,
        cycleCount: Int? = nil,
        temperatureCelsius: Double? = nil,
        designCapacityMah: Int? = nil,
        maxCapacityMah: Int? = nil,
        currentCapacityMah: Int? = nil,
        healthPercent: Int? = nil,
        condition: String? = nil,
        serial: String? = nil,
        adapter: PowerAdapter? = nil,
        powerDeliveryProfiles: [PowerDeliveryProfile] = [],
        capturedAt: Date = Date()
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isPluggedIn = isPluggedIn
        self.batteryPresent = batteryPresent
        self.batteryVoltageVolts = batteryVoltageVolts
        self.batteryCurrentAmps = batteryCurrentAmps
        self.batteryPowerWatts = batteryPowerWatts
        self.timeToFullMinutes = timeToFullMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
        self.designCapacityMah = designCapacityMah
        self.maxCapacityMah = maxCapacityMah
        self.currentCapacityMah = currentCapacityMah
        self.healthPercent = healthPercent
        self.condition = condition
        self.serial = serial
        self.adapter = adapter
        self.powerDeliveryProfiles = powerDeliveryProfiles
        self.capturedAt = capturedAt
    }

    public var batteryPowerMagnitudeWatts: Double? {
        batteryPowerWatts.map(abs)
    }

    public var batteryIsActivelyCharging: Bool {
        (batteryPowerWatts ?? 0) > 0.1 || (batteryCurrentAmps ?? 0) > 0.02
    }

    public var batteryIsActivelyDraining: Bool {
        (batteryPowerWatts ?? 0) < -0.1 || (batteryCurrentAmps ?? 0) < -0.02
    }
}

public struct PowerAdapter: Equatable, Sendable {
    public var name: String?
    public var manufacturer: String?
    public var ratedWatts: Int?
    public var negotiatedVoltageVolts: Double?
    public var negotiatedCurrentAmps: Double?
    public var serial: String?
    public var model: String?
    public var hardwareVersion: String?
    public var firmwareVersion: String?
    public var family: String?
    public var description: String?

    public init(
        name: String? = nil,
        manufacturer: String? = nil,
        ratedWatts: Int? = nil,
        negotiatedVoltageVolts: Double? = nil,
        negotiatedCurrentAmps: Double? = nil,
        serial: String? = nil,
        model: String? = nil,
        hardwareVersion: String? = nil,
        firmwareVersion: String? = nil,
        family: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.ratedWatts = ratedWatts
        self.negotiatedVoltageVolts = negotiatedVoltageVolts
        self.negotiatedCurrentAmps = negotiatedCurrentAmps
        self.serial = serial
        self.model = model
        self.hardwareVersion = hardwareVersion
        self.firmwareVersion = firmwareVersion
        self.family = family
        self.description = description
    }

    /// Headline charger power. Prefer the adapter-reported wattage; otherwise use negotiated V·A.
    public var powerWatts: Double {
        if let ratedWatts, ratedWatts > 0 { return Double(ratedWatts) }
        let negotiated = (negotiatedVoltageVolts ?? 0) * (negotiatedCurrentAmps ?? 0)
        return negotiated > 0 ? negotiated : 0
    }
}

public struct PowerDeliveryProfile: Equatable, Sendable, Identifiable {
    public var voltageVolts: Double
    public var currentAmps: Double

    public init(voltageVolts: Double, currentAmps: Double) {
        self.voltageVolts = voltageVolts
        self.currentAmps = currentAmps
    }

    public var id: String { "\(voltageVolts)-\(currentAmps)" }
    public var watts: Double { voltageVolts * currentAmps }
}

public enum PowerDisplayFormatter {
    public static func summary(for snapshot: PowerSnapshot) -> String {
        if snapshot.isPluggedIn, let adapter = snapshot.adapter, adapter.powerWatts >= 0.5 {
            return "\(adapterWatts(adapter.powerWatts)) adapter"
        }
        if let batteryPower = snapshot.batteryPowerWatts {
            if batteryPower < -0.1 { return "\(watts(abs(batteryPower))) drain" }
            if batteryPower > 0.1 { return "\(watts(batteryPower)) charge" }
        }
        if let percent = snapshot.percent { return "\(percent)% battery" }
        return "Power unknown"
    }

    public static func batteryFlow(for snapshot: PowerSnapshot) -> String? {
        guard let batteryPower = snapshot.batteryPowerWatts, abs(batteryPower) >= 0.1 else { return nil }
        if batteryPower > 0 {
            return "Charging battery at \(watts(batteryPower))"
        }
        return "Battery draining at \(watts(abs(batteryPower)))"
    }

    public static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private static func adapterWatts(_ value: Double) -> String {
        abs(value) < 10 ? String(format: "%.1f W", value) : String(format: "%.0f W", value)
    }

    public static func volts(_ value: Double) -> String {
        String(format: "%.2f V", value)
    }

    public static func amps(_ value: Double) -> String {
        String(format: "%.2f A", value)
    }

    public static func temperature(_ value: Double) -> String {
        String(format: "%.1f C", value)
    }

    public static func duration(minutes: Int) -> String {
        guard minutes >= 0 else { return "Unknown" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(remainingMinutes)m"
    }
}

public enum PowerInfoReader {
    public static func read() -> PowerSnapshot {
        makeSnapshot(
            powerSourceDescriptions: readPowerSourceDescriptions(),
            smartBatteryProperties: readSmartBatteryProperties(),
            externalAdapterDetails: readExternalAdapterDetails()
        )
    }

    /// Pure parser used by tests and by `read()` after macOS dictionaries are collected.
    public static func makeSnapshot(
        powerSourceDescriptions: [[String: Any]],
        smartBatteryProperties: [String: Any]?,
        externalAdapterDetails: [String: Any]?
    ) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        for description in powerSourceDescriptions {
            applyPowerSourceDescription(description, into: &snapshot)
        }
        if let smartBatteryProperties {
            applySmartBatteryProperties(smartBatteryProperties, into: &snapshot)
        }
        if snapshot.adapter == nil, let externalAdapterDetails {
            applyAdapterDetails(externalAdapterDetails, into: &snapshot)
        }
        snapshot.powerDeliveryProfiles.sort { $0.watts < $1.watts }
        return snapshot
    }

    private static func readPowerSourceDescriptions() -> [[String: Any]] {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        return sources.compactMap { source in
            IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        }
    }

    private static func readSmartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return unmanaged?.takeRetainedValue() as? [String: Any]
    }

    private static func readExternalAdapterDetails() -> [String: Any]? {
        IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
    }

    private static func applyPowerSourceDescription(_ description: [String: Any], into snapshot: inout PowerSnapshot) {
        if let current = intValue(description, keys: ["Current Capacity", kIOPSCurrentCapacityKey]),
           let maximum = intValue(description, keys: ["Max Capacity", kIOPSMaxCapacityKey]),
           maximum > 0 {
            snapshot.percent = max(0, min(100, Int((Double(current) / Double(maximum) * 100).rounded())))
        }
        if let charging = boolValue(description, keys: ["Is Charging", kIOPSIsChargingKey]) {
            snapshot.isCharging = charging
        }
        if let charged = boolValue(description, keys: ["Is Charged", kIOPSIsChargedKey]) {
            snapshot.isCharged = charged
        }
        if let present = boolValue(description, keys: ["Is Present", kIOPSIsPresentKey]) {
            snapshot.batteryPresent = present
        }
        if let state = stringValue(description, keys: ["Power Source State", kIOPSPowerSourceStateKey]) {
            snapshot.isPluggedIn = state == kIOPSACPowerValue
        }
        if let condition = stringValue(description, keys: ["BatteryHealth", kIOPSBatteryHealthKey]), !condition.isEmpty {
            snapshot.condition = condition
        }
        if let timeToFull = intValue(description, keys: ["Time to Full Charge", kIOPSTimeToFullChargeKey]), timeToFull >= 0 {
            snapshot.timeToFullMinutes = timeToFull
        }
        if let timeToEmpty = intValue(description, keys: ["Time to Empty", kIOPSTimeToEmptyKey]), timeToEmpty >= 0 {
            snapshot.timeToEmptyMinutes = timeToEmpty
        }
    }

    private static func applySmartBatteryProperties(_ properties: [String: Any], into snapshot: inout PowerSnapshot) {
        if let installed = boolValue(properties, keys: ["BatteryInstalled"]) {
            snapshot.batteryPresent = installed
        }
        if let externalConnected = boolValue(properties, keys: ["ExternalConnected"]) {
            snapshot.isPluggedIn = externalConnected
        }
        if let charging = boolValue(properties, keys: ["IsCharging"]) {
            snapshot.isCharging = charging
        }
        if let fullyCharged = boolValue(properties, keys: ["FullyCharged"]) {
            snapshot.isCharged = fullyCharged
        }

        if let millivolts = intValue(properties, keys: ["Voltage"]), millivolts > 0 {
            snapshot.batteryVoltageVolts = Double(millivolts) / 1000.0
        }
        let milliamps = intValue(properties, keys: ["InstantAmperage"]) ?? intValue(properties, keys: ["Amperage"])
        if let milliamps {
            let amps = Double(milliamps) / 1000.0
            snapshot.batteryCurrentAmps = amps
            if let volts = snapshot.batteryVoltageVolts {
                snapshot.batteryPowerWatts = volts * amps
            }
        }

        if let cycleCount = intValue(properties, keys: ["CycleCount"]), cycleCount >= 0 {
            snapshot.cycleCount = cycleCount
        }
        if let temperature = intValue(properties, keys: ["Temperature"]) {
            snapshot.temperatureCelsius = Double(temperature) / 100.0
        }
        if let serial = stringValue(properties, keys: ["Serial"]) {
            snapshot.serial = serial
        }

        let designCapacity = intValue(properties, keys: ["DesignCapacity"])
        let maxCapacity = intValue(properties, keys: ["AppleRawMaxCapacity"]) ?? intValue(properties, keys: ["MaxCapacity"])
        let currentCapacity = intValue(properties, keys: ["AppleRawCurrentCapacity"]) ?? intValue(properties, keys: ["CurrentCapacity"])
        snapshot.designCapacityMah = positive(designCapacity)
        snapshot.maxCapacityMah = positive(maxCapacity)
        snapshot.currentCapacityMah = positive(currentCapacity)
        if let designCapacity, let maxCapacity, designCapacity > 0, maxCapacity > 0 {
            snapshot.healthPercent = Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
        }

        if let condition = stringValue(properties, keys: ["Condition", "BatteryHealth"]), !condition.isEmpty {
            snapshot.condition = condition
        } else if let permanentFailure = intValue(properties, keys: ["PermanentFailureStatus"]) {
            snapshot.condition = permanentFailure == 0 ? "Normal" : "Service Recommended"
        }

        if let adapterDetails = dictionaryValue(properties, keys: ["AdapterDetails"]) {
            applyAdapterDetails(adapterDetails, into: &snapshot)
        }
    }

    private static func applyAdapterDetails(_ details: [String: Any], into snapshot: inout PowerSnapshot) {
        var adapter = snapshot.adapter ?? PowerAdapter()
        adapter.name = stringValue(details, keys: ["Name"]) ?? adapter.name
        adapter.manufacturer = stringValue(details, keys: ["Manufacturer"]) ?? adapter.manufacturer
        adapter.ratedWatts = positive(intValue(details, keys: ["Watts"])) ?? adapter.ratedWatts
        if let millivolts = intValue(details, keys: ["AdapterVoltage", "Voltage"]), millivolts > 0 {
            adapter.negotiatedVoltageVolts = Double(millivolts) / 1000.0
        }
        if let milliamps = intValue(details, keys: ["Current"]), milliamps > 0 {
            adapter.negotiatedCurrentAmps = Double(milliamps) / 1000.0
        }
        adapter.serial = stringValue(details, keys: ["SerialString", "SerialNumber"]) ?? adapter.serial
        adapter.model = stringValue(details, keys: ["Model"]) ?? adapter.model
        adapter.hardwareVersion = stringValue(details, keys: ["HwVersion", "HardwareVersion"]) ?? adapter.hardwareVersion
        adapter.firmwareVersion = stringValue(details, keys: ["FwVersion", "FirmwareVersion"]) ?? adapter.firmwareVersion
        adapter.description = stringValue(details, keys: ["Description"]) ?? adapter.description
        if let familyCode = intValue(details, keys: ["FamilyCode"]) {
            adapter.family = familyName(familyCode)
        }
        snapshot.adapter = adapter
        snapshot.isPluggedIn = true

        if let menu = details["UsbHvcMenu"] as? [[String: Any]] {
            snapshot.powerDeliveryProfiles = menu.compactMap { entry in
                guard let millivolts = intValue(entry, keys: ["MaxVoltage"]),
                      let milliamps = intValue(entry, keys: ["MaxCurrent"]),
                      millivolts > 0,
                      milliamps > 0
                else { return nil }
                return PowerDeliveryProfile(
                    voltageVolts: Double(millivolts) / 1000.0,
                    currentAmps: Double(milliamps) / 1000.0
                )
            }.sorted { $0.watts < $1.watts }
        }
    }

    private static func familyName(_ code: Int) -> String {
        switch code {
        case 0xe0004000...0xe0004fff:
            return "USB-C Power Delivery"
        case 0x00000003:
            return "MagSafe"
        case 0x00000004:
            return "MagSafe 2"
        case 0x0000ff00:
            return "USB-C"
        default:
            return String(format: "0x%08x", code)
        }
    }

    private static func intValue(_ dictionary: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String, let int = Int(string) { return int }
        }
        return nil
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private static func boolValue(_ dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "yes", "1": return true
                case "false", "no", "0": return false
                default: break
                }
            }
        }
        return nil
    }

    private static func dictionaryValue(_ dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] { return value }
        }
        return nil
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
