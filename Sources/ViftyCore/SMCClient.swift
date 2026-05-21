import Foundation
import IOKit
import ViftyPrivateIOKit

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: IOByteCount32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCBytes {
    var b0: UInt8 = 0
    var b1: UInt8 = 0
    var b2: UInt8 = 0
    var b3: UInt8 = 0
    var b4: UInt8 = 0
    var b5: UInt8 = 0
    var b6: UInt8 = 0
    var b7: UInt8 = 0
    var b8: UInt8 = 0
    var b9: UInt8 = 0
    var b10: UInt8 = 0
    var b11: UInt8 = 0
    var b12: UInt8 = 0
    var b13: UInt8 = 0
    var b14: UInt8 = 0
    var b15: UInt8 = 0
    var b16: UInt8 = 0
    var b17: UInt8 = 0
    var b18: UInt8 = 0
    var b19: UInt8 = 0
    var b20: UInt8 = 0
    var b21: UInt8 = 0
    var b22: UInt8 = 0
    var b23: UInt8 = 0
    var b24: UInt8 = 0
    var b25: UInt8 = 0
    var b26: UInt8 = 0
    var b27: UInt8 = 0
    var b28: UInt8 = 0
    var b29: UInt8 = 0
    var b30: UInt8 = 0
    var b31: UInt8 = 0

    subscript(index: Int) -> UInt8 {
        get {
            withUnsafeBytes(of: self) { raw in raw[index] }
        }
        set {
            withUnsafeMutableBytes(of: &self) { raw in raw[index] = newValue }
        }
    }

    var array: [UInt8] {
        withUnsafeBytes(of: self) { Array($0) }
    }
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes()
}

public struct SMCValue: Sendable {
    public var key: String
    public var dataType: String
    public var bytes: [UInt8]

    public init(key: String, dataType: String, bytes: [UInt8]) {
        self.key = key
        self.dataType = dataType
        self.bytes = bytes
    }
}

public final class SMCClient: @unchecked Sendable {
    private let connection: io_connect_t

    public init() throws {
        let service = Self.firstSMCService()
        guard service != 0 else { throw ViftyError.smcUnavailable }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else { throw ViftyError.smcOpenFailed(result) }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    public func read(_ key: String) throws -> SMCValue {
        let keyCode = Self.fourCharCode(key)
        var infoInput = SMCKeyData()
        infoInput.key = keyCode
        infoInput.data8 = 9
        let infoOutput = try call(infoInput)
        guard infoOutput.result == 0, infoOutput.keyInfo.dataSize > 0 else {
            throw ViftyError.smcKeyUnavailable(key)
        }

        var readInput = SMCKeyData()
        readInput.key = keyCode
        readInput.keyInfo = infoOutput.keyInfo
        readInput.data8 = 5
        let readOutput = try call(readInput)
        guard readOutput.result == 0 else { throw ViftyError.smcKeyUnavailable(key) }

        let size = min(Int(infoOutput.keyInfo.dataSize), 32)
        return SMCValue(
            key: key,
            dataType: Self.string(from: infoOutput.keyInfo.dataType),
            bytes: Array(readOutput.bytes.array.prefix(size))
        )
    }

    public func write(_ key: String, dataType: String, bytes: [UInt8]) throws {
        var infoInput = SMCKeyData()
        infoInput.key = Self.fourCharCode(key)
        infoInput.data8 = 9
        let infoOutput = try call(infoInput)
        guard infoOutput.result == 0, infoOutput.keyInfo.dataSize > 0 else {
            throw ViftyError.smcKeyUnavailable(key)
        }

        var input = infoInput
        input.keyInfo = infoOutput.keyInfo
        input.keyInfo.dataSize = UInt32(min(bytes.count, Int(infoOutput.keyInfo.dataSize), 32))
        input.data8 = 6
        for (index, byte) in bytes.prefix(32).enumerated() {
            input.bytes[index] = byte
        }

        let output = try call(input)
        guard output.result == 0 else { throw ViftyError.smcKeyUnavailable(key) }
    }

    private func call(_ input: SMCKeyData) throws -> SMCKeyData {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPointer,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == KERN_SUCCESS else { throw ViftyError.smcCallFailed(result) }
        return output
    }

    private static func firstSMCService() -> io_service_t {
        let appleSMC = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if appleSMC != 0 {
            return appleSMC
        }

        for name in ["AppleSMCKeysEndpoint", "SMCEndpoint1"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(name))
            if service != 0 {
                return service
            }
        }

        for className in ["AppleSMCKeysEndpoint"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
            if service != 0 {
                return service
            }
        }

        let knownPath = "IOService:/AppleARMPE/arm-io/AppleT600xIO/smc@90400000/AppleASCWrapV4/iop-smc-nub/RTBuddy(SMC)/SMCEndpoint1/AppleSMCKeysEndpoint"
        let pathService = IORegistryEntryFromPath(kIOMainPortDefault, knownPath)
        if pathService != 0 {
            return pathService
        }

        return 0
    }

    public static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) + UInt32(byte)
        }
        return result
    }

    public static func string(from code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes.filter { $0 != 0 }, encoding: .ascii) ?? ""
    }

    public static func diagnostics() -> [String] {
        var lines: [String] = []

        for name in ["AppleSMCKeysEndpoint", "SMCEndpoint1"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(name))
            lines.append("name \(name) service=\(service)")
            if service != 0 {
                var connection = io_connect_t()
                let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
                lines.append("name \(name) open=\(result) connection=\(connection)")
                if connection != 0 { IOServiceClose(connection) }
                IOObjectRelease(service)
            }
        }

        for className in ["AppleSMCKeysEndpoint", "AppleSMC"] {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
            lines.append("class \(className) service=\(service)")
            if service != 0 {
                var connection = io_connect_t()
                let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
                lines.append("class \(className) open=\(result) connection=\(connection)")
                if connection != 0 { IOServiceClose(connection) }
                IOObjectRelease(service)
            }
        }

        return lines
    }
}

public enum SMCDecoding {
    public static func decodeFloat(_ value: SMCValue) -> Double? {
        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else { return nil }
            let signed = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(signed) / 256.0
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            return Double(value.bytes.withUnsafeBytes { rawBuffer in
                rawBuffer.loadUnaligned(as: Float.self)
            })
        case "fpe2":
            guard value.bytes.count >= 2 else { return nil }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4.0
        case "ui8 ":
            return value.bytes.first.map(Double.init)
        case "ui16":
            guard value.bytes.count >= 2 else { return nil }
            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
        default:
            return nil
        }
    }

    public static func encodeFPE2(_ value: Int) -> [UInt8] {
        let raw = UInt16(max(0, value) * 4)
        return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
    }

    public static func encodeRPM(_ value: Int, dataType: String, size: Int) -> [UInt8] {
        if dataType == "flt " || size == 4 {
            var float = Float(value)
            return withUnsafeBytes(of: &float) { Array($0) }
        }

        return encodeFPE2(value)
    }
}
