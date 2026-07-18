import Darwin
import Foundation

public struct ViftyBuildProvenance: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let schemaID = "https://vifty.app/schemas/ui-review-build-provenance-v1.schema.json"
    public static let roleConfigurations = [
        "debug-fixture-app": "debug",
        "release-exclusion": "release",
        "ax-collector": "debug"
    ]

    public var schemaVersion: Int
    public var schemaID: String
    public var sourceCommit: String
    public var sourceTree: String
    public var productRole: String
    public var configuration: String
    public var buildTransactionID: String

    public init(
        schemaVersion: Int = ViftyBuildProvenance.schemaVersion,
        schemaID: String = ViftyBuildProvenance.schemaID,
        sourceCommit: String,
        sourceTree: String,
        productRole: String,
        configuration: String,
        buildTransactionID: String
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.sourceCommit = sourceCommit
        self.sourceTree = sourceTree
        self.productRole = productRole
        self.configuration = configuration
        self.buildTransactionID = buildTransactionID
    }

    public var canonicalData: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(self)
        }
    }

    public func validate(expectedRole: String? = nil, expectedConfiguration: String? = nil) throws {
        guard schemaVersion == Self.schemaVersion, schemaID == Self.schemaID else {
            throw ViftyBuildProvenanceError.invalidSchema
        }
        guard Self.isGitObjectID(sourceCommit), Self.isGitObjectID(sourceTree) else {
            throw ViftyBuildProvenanceError.invalidSourceIdentity
        }
        guard Self.isLowercaseHex(buildTransactionID, count: 64) else {
            throw ViftyBuildProvenanceError.invalidTransactionIdentity
        }
        guard let canonicalConfiguration = Self.roleConfigurations[productRole],
              canonicalConfiguration == configuration else {
            throw ViftyBuildProvenanceError.invalidRoleConfiguration
        }
        if let expectedRole, productRole != expectedRole {
            throw ViftyBuildProvenanceError.unexpectedRole(expected: expectedRole, actual: productRole)
        }
        if let expectedConfiguration, configuration != expectedConfiguration {
            throw ViftyBuildProvenanceError.unexpectedConfiguration(
                expected: expectedConfiguration,
                actual: configuration
            )
        }
    }

    private static func isGitObjectID(_ value: String) -> Bool {
        isLowercaseHex(value, count: 40)
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ||
                (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }
}

public enum ViftyBuildProvenanceError: Error, Equatable, Sendable {
    case executableUnavailable
    case unsupportedMachO
    case malformedMachO(String)
    case missingOrDuplicateSection(Int)
    case invalidJSON
    case noncanonicalJSON
    case invalidSchema
    case invalidSourceIdentity
    case invalidTransactionIdentity
    case invalidRoleConfiguration
    case unexpectedRole(expected: String, actual: String)
    case unexpectedConfiguration(expected: String, actual: String)
    case architectureMismatch
}

public enum ViftyBuildProvenanceReader {
    public static let segmentName = "__TEXT"
    public static let sectionName = "__vifty_src"

    private static let maximumSectionBytes = 4 * 1_024
    private static let maximumArchitectures = 32
    private static let maximumLoadCommands = 4_096
    private static let documentKeys = Set([
        "schemaVersion",
        "schemaID",
        "sourceCommit",
        "sourceTree",
        "productRole",
        "configuration",
        "buildTransactionID"
    ])

    private enum Endian {
        case little
        case big
    }

    private struct ThinFormat {
        var endian: Endian
        var width: Int
    }

    private struct FatFormat {
        var endian: Endian
        var width: Int
    }

    public static func readCurrentExecutable(
        expectedRole: String? = nil,
        expectedConfiguration: String? = nil
    ) throws -> ViftyBuildProvenance {
        try read(
            at: currentExecutableURL(),
            expectedRole: expectedRole,
            expectedConfiguration: expectedConfiguration
        )
    }

    public static func currentExecutableURL() throws -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { throw ViftyBuildProvenanceError.executableUnavailable }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw ViftyBuildProvenanceError.executableUnavailable
        }
        guard let terminator = buffer.firstIndex(of: 0) else {
            throw ViftyBuildProvenanceError.executableUnavailable
        }
        let pathBytes = buffer[..<terminator].map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self))
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    public static func read(
        at url: URL,
        expectedRole: String? = nil,
        expectedConfiguration: String? = nil
    ) throws -> ViftyBuildProvenance {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ViftyBuildProvenanceError.executableUnavailable
        }
        return try read(
            data: data,
            expectedRole: expectedRole,
            expectedConfiguration: expectedConfiguration
        )
    }

    public static func read(
        data: Data,
        expectedRole: String? = nil,
        expectedConfiguration: String? = nil
    ) throws -> ViftyBuildProvenance {
        guard data.count >= 4 else { throw ViftyBuildProvenanceError.unsupportedMachO }
        let documents: [ViftyBuildProvenance]
        if let format = thinFormat(data, base: 0) {
            documents = [try readThin(data, base: 0, length: data.count, format: format)]
        } else if let format = fatFormat(data, base: 0) {
            documents = try readFat(data, format: format)
        } else {
            throw ViftyBuildProvenanceError.unsupportedMachO
        }
        guard let first = documents.first,
              documents.dropFirst().allSatisfy({ $0 == first }) else {
            throw ViftyBuildProvenanceError.architectureMismatch
        }
        try first.validate(
            expectedRole: expectedRole,
            expectedConfiguration: expectedConfiguration
        )
        return first
    }

    private static func readFat(_ data: Data, format: FatFormat) throws -> [ViftyBuildProvenance] {
        let count = try integer(data, offset: 4, width: 4, endian: format.endian)
        guard count >= 1, count <= UInt64(maximumArchitectures) else {
            throw ViftyBuildProvenanceError.malformedMachO("invalid fat architecture count")
        }
        let entrySize = format.width == 64 ? 32 : 20
        let tableEnd = try checkedAdd(8, try checkedMultiply(Int(count), entrySize))
        guard tableEnd <= data.count else {
            throw ViftyBuildProvenanceError.malformedMachO("truncated fat architecture table")
        }
        var ranges: [Range<Int>] = []
        for index in 0..<Int(count) {
            let entry = 8 + (index * entrySize)
            let offsetWidth = format.width == 64 ? 8 : 4
            let offset = try integer(data, offset: entry + 8, width: offsetWidth, endian: format.endian)
            let sizeOffset = entry + (format.width == 64 ? 16 : 12)
            let size = try integer(data, offset: sizeOffset, width: offsetWidth, endian: format.endian)
            guard let start = Int(exactly: offset),
                  let length = Int(exactly: size),
                  length > 0,
                  start >= tableEnd,
                  length <= data.count,
                  start <= data.count - length else {
                throw ViftyBuildProvenanceError.malformedMachO("invalid fat architecture range")
            }
            ranges.append(start..<(start + length))
        }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.upperBound > pair.1.lowerBound {
            throw ViftyBuildProvenanceError.malformedMachO("overlapping fat architecture ranges")
        }
        return try ranges.map { range in
            guard let format = thinFormat(data, base: range.lowerBound) else {
                throw ViftyBuildProvenanceError.unsupportedMachO
            }
            return try readThin(
                data,
                base: range.lowerBound,
                length: range.count,
                format: format
            )
        }
    }

    private static func readThin(
        _ data: Data,
        base: Int,
        length: Int,
        format: ThinFormat
    ) throws -> ViftyBuildProvenance {
        let headerSize = format.width == 64 ? 32 : 28
        guard length >= headerSize else {
            throw ViftyBuildProvenanceError.malformedMachO("truncated Mach-O header")
        }
        let commandCount = try integer(data, offset: base + 16, width: 4, endian: format.endian)
        let commandBytes = try integer(data, offset: base + 20, width: 4, endian: format.endian)
        guard commandCount >= 1, commandCount <= UInt64(maximumLoadCommands),
              let commandByteCount = Int(exactly: commandBytes),
              commandByteCount <= length,
              headerSize <= length - commandByteCount else {
            throw ViftyBuildProvenanceError.malformedMachO("invalid load command table")
        }
        let commandEnd = base + headerSize + commandByteCount
        var cursor = base + headerSize
        var sections: [(offset: Int, size: Int)] = []
        for _ in 0..<Int(commandCount) {
            guard cursor <= commandEnd - 8 else {
                throw ViftyBuildProvenanceError.malformedMachO("truncated load command")
            }
            let command = try integer(data, offset: cursor, width: 4, endian: format.endian)
            let size = try integer(data, offset: cursor + 4, width: 4, endian: format.endian)
            guard let commandSize = Int(exactly: size),
                  commandSize >= 8,
                  cursor <= commandEnd - commandSize else {
                throw ViftyBuildProvenanceError.malformedMachO("invalid load command size")
            }
            let segmentCommand: UInt64 = format.width == 64 ? 0x19 : 0x1
            if command == segmentCommand {
                sections.append(contentsOf: try provenanceSections(
                    data,
                    base: base,
                    sliceLength: length,
                    cursor: cursor,
                    commandSize: commandSize,
                    format: format
                ))
            }
            cursor += commandSize
        }
        guard cursor == commandEnd else {
            throw ViftyBuildProvenanceError.malformedMachO("inconsistent load command byte count")
        }
        guard sections.count == 1 else {
            throw ViftyBuildProvenanceError.missingOrDuplicateSection(sections.count)
        }
        let section = sections[0]
        let bytes = data.subdata(in: section.offset..<(section.offset + section.size))
        return try decodeDocument(bytes)
    }

    private static func provenanceSections(
        _ data: Data,
        base: Int,
        sliceLength: Int,
        cursor: Int,
        commandSize: Int,
        format: ThinFormat
    ) throws -> [(offset: Int, size: Int)] {
        let segmentSize = format.width == 64 ? 72 : 56
        let sectionSize = format.width == 64 ? 80 : 68
        guard commandSize >= segmentSize else {
            throw ViftyBuildProvenanceError.malformedMachO("truncated segment command")
        }
        let segment = try fixedName(data, offset: cursor + 8)
        let countOffset = cursor + (format.width == 64 ? 64 : 48)
        let count = try integer(data, offset: countOffset, width: 4, endian: format.endian)
        guard let sectionCount = Int(exactly: count) else {
            throw ViftyBuildProvenanceError.malformedMachO("inconsistent segment section count")
        }
        let expectedCommandSize = try checkedAdd(
            segmentSize,
            try checkedMultiply(sectionCount, sectionSize)
        )
        guard commandSize == expectedCommandSize else {
            throw ViftyBuildProvenanceError.malformedMachO("inconsistent segment section count")
        }
        guard segment == segmentName else { return [] }

        var result: [(offset: Int, size: Int)] = []
        for index in 0..<sectionCount {
            let section = cursor + segmentSize + (index * sectionSize)
            guard try fixedName(data, offset: section) == sectionName,
                  try fixedName(data, offset: section + 16) == segmentName else { continue }
            let width = format.width == 64 ? 8 : 4
            let rawSize = try integer(
                data,
                offset: section + (format.width == 64 ? 40 : 36),
                width: width,
                endian: format.endian
            )
            let rawOffset = try integer(
                data,
                offset: section + (format.width == 64 ? 48 : 40),
                width: 4,
                endian: format.endian
            )
            guard let size = Int(exactly: rawSize),
                  let relativeOffset = Int(exactly: rawOffset),
                  size >= 1,
                  size <= maximumSectionBytes,
                  size <= sliceLength,
                  relativeOffset <= sliceLength - size else {
                throw ViftyBuildProvenanceError.malformedMachO("invalid provenance section range")
            }
            result.append((base + relativeOffset, size))
        }
        return result
    }

    private static func decodeDocument(_ data: Data) throws -> ViftyBuildProvenance {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ViftyBuildProvenanceError.invalidJSON
        }
        guard let dictionary = object as? [String: Any], Set(dictionary.keys) == documentKeys else {
            throw ViftyBuildProvenanceError.invalidJSON
        }
        let document: ViftyBuildProvenance
        do {
            document = try JSONDecoder().decode(ViftyBuildProvenance.self, from: data)
        } catch {
            throw ViftyBuildProvenanceError.invalidJSON
        }
        guard try document.canonicalData == data else {
            throw ViftyBuildProvenanceError.noncanonicalJSON
        }
        try document.validate()
        return document
    }

    private static func thinFormat(_ data: Data, base: Int) -> ThinFormat? {
        guard base >= 0, base <= data.count - 4 else { return nil }
        switch Array(data[base..<(base + 4)]) {
        case [0xce, 0xfa, 0xed, 0xfe]: return ThinFormat(endian: .little, width: 32)
        case [0xcf, 0xfa, 0xed, 0xfe]: return ThinFormat(endian: .little, width: 64)
        case [0xfe, 0xed, 0xfa, 0xce]: return ThinFormat(endian: .big, width: 32)
        case [0xfe, 0xed, 0xfa, 0xcf]: return ThinFormat(endian: .big, width: 64)
        default: return nil
        }
    }

    private static func fatFormat(_ data: Data, base: Int) -> FatFormat? {
        guard base >= 0, base <= data.count - 4 else { return nil }
        switch Array(data[base..<(base + 4)]) {
        case [0xca, 0xfe, 0xba, 0xbe]: return FatFormat(endian: .big, width: 32)
        case [0xca, 0xfe, 0xba, 0xbf]: return FatFormat(endian: .big, width: 64)
        case [0xbe, 0xba, 0xfe, 0xca]: return FatFormat(endian: .little, width: 32)
        case [0xbf, 0xba, 0xfe, 0xca]: return FatFormat(endian: .little, width: 64)
        default: return nil
        }
    }

    private static func fixedName(_ data: Data, offset: Int) throws -> String {
        guard offset >= 0, offset <= data.count - 16 else {
            throw ViftyBuildProvenanceError.malformedMachO("truncated fixed-width name")
        }
        let bytes = data[offset..<(offset + 16)]
        let prefix = bytes.prefix { $0 != 0 }
        guard let value = String(bytes: prefix, encoding: .utf8) else {
            throw ViftyBuildProvenanceError.malformedMachO("invalid fixed-width name")
        }
        return value
    }

    private static func integer(
        _ data: Data,
        offset: Int,
        width: Int,
        endian: Endian
    ) throws -> UInt64 {
        guard (width == 4 || width == 8), offset >= 0, offset <= data.count - width else {
            throw ViftyBuildProvenanceError.malformedMachO("truncated integer")
        }
        let bytes = data[offset..<(offset + width)]
        switch endian {
        case .little:
            return bytes.enumerated().reduce(0) { result, item in
                result | (UInt64(item.element) << UInt64(item.offset * 8))
            }
        case .big:
            return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw ViftyBuildProvenanceError.malformedMachO("integer overflow")
        }
        return value
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw ViftyBuildProvenanceError.malformedMachO("integer overflow")
        }
        return value
    }
}
