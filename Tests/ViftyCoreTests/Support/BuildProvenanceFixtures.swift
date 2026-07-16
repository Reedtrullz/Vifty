import Foundation
import ViftyBuildProvenance

enum TestBuildProvenance {
    static let sourceCommit = String(repeating: "a", count: 40)
    static let sourceTree = String(repeating: "b", count: 40)
    static let transactionID = String(repeating: "c", count: 64)

    static func identity(
        role: String,
        sourceCommit: String = sourceCommit,
        sourceTree: String = sourceTree,
        transactionID: String = transactionID
    ) -> ViftyBuildProvenance {
        ViftyBuildProvenance(
            sourceCommit: sourceCommit,
            sourceTree: sourceTree,
            productRole: role,
            configuration: ViftyBuildProvenance.roleConfigurations[role]!,
            buildTransactionID: transactionID
        )
    }

    static func thinMachO(
        provenance: ViftyBuildProvenance,
        duplicateSection: Bool = false
    ) throws -> Data {
        var payloads = [try provenance.canonicalData]
        if duplicateSection {
            payloads.append(payloads[0])
        }
        return thinMachO(payloads: payloads)
    }

    static func thinMachO(payloads: [Data]) -> Data {
        let headerSize = 32
        let commandSize = 72 + (80 * payloads.count)
        let dataOffset = headerSize + commandSize
        var result = Data()
        append(UInt32(0xfeedfacf), to: &result)
        append(UInt32(0x0100000c), to: &result)
        append(UInt32(0), to: &result)
        append(UInt32(2), to: &result)
        append(UInt32(1), to: &result)
        append(UInt32(commandSize), to: &result)
        append(UInt32(0), to: &result)
        append(UInt32(0), to: &result)

        append(UInt32(0x19), to: &result)
        append(UInt32(commandSize), to: &result)
        result.append(fixedName("__TEXT"))
        append(UInt64(0), to: &result)
        append(UInt64(0), to: &result)
        append(UInt64(dataOffset), to: &result)
        append(UInt64(payloads.reduce(0) { $0 + $1.count }), to: &result)
        append(UInt32(7), to: &result)
        append(UInt32(5), to: &result)
        append(UInt32(payloads.count), to: &result)
        append(UInt32(0), to: &result)

        var offset = dataOffset
        for payload in payloads {
            result.append(fixedName("__vifty_src"))
            result.append(fixedName("__TEXT"))
            append(UInt64(0), to: &result)
            append(UInt64(payload.count), to: &result)
            append(UInt32(offset), to: &result)
            for _ in 0..<7 {
                append(UInt32(0), to: &result)
            }
            offset += payload.count
        }
        payloads.forEach { result.append($0) }
        return result
    }

    private static func fixedName(_ value: String) -> Data {
        var data = Data(value.utf8)
        data.append(Data(repeating: 0, count: 16 - data.count))
        return data
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}
