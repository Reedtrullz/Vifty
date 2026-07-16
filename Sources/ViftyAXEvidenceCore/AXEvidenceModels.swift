import CryptoKit
import Foundation
import ViftyBuildProvenance

private func normalizedStrings(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

public enum AXCanonicalJSON {
    public static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct AXSemanticRequest: Codable, Equatable, Sendable {
    public var appearance: String
    public var contrast: String
    public var interaction: String
    public var state: String
    public var surface: String
    public var textSize: String
    public var transparency: String
    public var window: String

    public init(
        appearance: String = "light",
        contrast: String = "standard",
        interaction: String = "none",
        state: String,
        surface: String = "main",
        textSize: String = "standard",
        transparency: String = "standard",
        window: String = "1180x820"
    ) {
        self.appearance = appearance
        self.contrast = contrast
        self.interaction = interaction
        self.state = state
        self.surface = surface
        self.textSize = textSize
        self.transparency = transparency
        self.window = window
    }

    public var canonicalSHA256: String {
        // Encoding this fixed-shape value cannot fail. Keeping the hash derived
        // prevents callers from silently changing a semantic request in place.
        try! AXCanonicalJSON.sha256(self)
    }
}

public struct AXEvidenceRequest: Codable, Equatable, Sendable {
    public var checkID: String
    public var captureID: String
    public var processIdentifier: Int32
    public var windowIdentifier: String
    public var rootIdentifier: String
    public var semanticRequest: AXSemanticRequest
    public var requestSHA256: String

    public init(
        checkID: String,
        captureID: String,
        processIdentifier: Int32,
        windowIdentifier: String,
        rootIdentifier: String,
        semanticRequest: AXSemanticRequest,
        requestSHA256: String? = nil
    ) {
        self.checkID = checkID
        self.captureID = captureID
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.rootIdentifier = rootIdentifier
        self.semanticRequest = semanticRequest
        self.requestSHA256 = requestSHA256 ?? semanticRequest.canonicalSHA256
    }
}

public struct AXPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct AXSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct AXRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct AXRange: Codable, Equatable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// A lossless, JSON-stable representation of the public value types exposed by
/// the macOS Accessibility API. `valueDescription` remains a separate field on
/// `AXObservation`; it is presentation text, not a replacement for this value.
public enum AXTypedValue: Equatable, Sendable {
    case string(String)
    case boolean(Bool)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)
    case number(Double)
    case point(AXPoint)
    case size(AXSize)
    case rectangle(AXRect)
    case range(AXRange)
    case error(Int32)

    public var numericValue: Double? {
        switch self {
        case let .number(value): value
        case let .signedInteger(value): Double(value)
        case let .unsignedInteger(value): Double(value)
        default: nil
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}

extension AXTypedValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AXTypedValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case string
        case boolean
        case signedInteger = "signed-integer"
        case unsignedInteger = "unsigned-integer"
        case number
        case point
        case size
        case rectangle
        case range
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ValueType.self, forKey: .type) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .boolean:
            self = .boolean(try container.decode(Bool.self, forKey: .value))
        case .signedInteger:
            self = .signedInteger(try container.decode(Int64.self, forKey: .value))
        case .unsignedInteger:
            self = .unsignedInteger(try container.decode(UInt64.self, forKey: .value))
        case .number:
            self = .number(try container.decode(Double.self, forKey: .value))
        case .point:
            self = .point(try container.decode(AXPoint.self, forKey: .value))
        case .size:
            self = .size(try container.decode(AXSize.self, forKey: .value))
        case .rectangle:
            self = .rectangle(try container.decode(AXRect.self, forKey: .value))
        case .range:
            self = .range(try container.decode(AXRange.self, forKey: .value))
        case .error:
            self = .error(try container.decode(Int32.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .boolean(value):
            try container.encode(ValueType.boolean, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .signedInteger(value):
            try container.encode(ValueType.signedInteger, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .unsignedInteger(value):
            try container.encode(ValueType.unsignedInteger, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .number(value):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .point(value):
            try container.encode(ValueType.point, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .size(value):
            try container.encode(ValueType.size, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .rectangle(value):
            try container.encode(ValueType.rectangle, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .range(value):
            try container.encode(ValueType.range, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .error(value):
            try container.encode(ValueType.error, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct AXObservation: Codable, Equatable, Sendable {
    public var path: String
    public var order: Int
    public var depth: Int
    public var role: String
    public var subrole: String?
    public var identifier: String?
    public var title: String?
    public var description: String?
    public var label: String?
    public var help: String?
    public var value: AXTypedValue?
    public var valueDescription: String?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var position: AXPoint?
    public var size: AXSize?
    public var actions: [String]
    public var childCount: Int?
    public var readErrors: [String]

    public init(
        path: String,
        order: Int,
        depth: Int,
        role: String,
        subrole: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        description: String? = nil,
        label: String? = nil,
        help: String? = nil,
        value: AXTypedValue? = nil,
        valueDescription: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        selected: Bool? = nil,
        position: AXPoint? = nil,
        size: AXSize? = nil,
        actions: [String] = [],
        childCount: Int? = nil,
        readErrors: [String] = []
    ) {
        self.path = path
        self.order = order
        self.depth = depth
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.description = description
        self.label = label
        self.help = help
        self.value = value
        self.valueDescription = valueDescription
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.position = position
        self.size = size
        self.actions = normalizedStrings(actions)
        self.childCount = childCount
        self.readErrors = normalizedStrings(readErrors)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case order
        case depth
        case role
        case subrole
        case identifier
        case title
        case description
        case label
        case help
        case value
        case valueDescription
        case enabled
        case focused
        case selected
        case position
        case size
        case actions
        case childCount
        case readErrors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            order: try container.decode(Int.self, forKey: .order),
            depth: try container.decode(Int.self, forKey: .depth),
            role: try container.decode(String.self, forKey: .role),
            subrole: try container.decodeIfPresent(String.self, forKey: .subrole),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            title: try container.decodeIfPresent(String.self, forKey: .title),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            label: try container.decodeIfPresent(String.self, forKey: .label),
            help: try container.decodeIfPresent(String.self, forKey: .help),
            value: try container.decodeIfPresent(AXTypedValue.self, forKey: .value),
            valueDescription: try container.decodeIfPresent(String.self, forKey: .valueDescription),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled),
            focused: try container.decodeIfPresent(Bool.self, forKey: .focused),
            selected: try container.decodeIfPresent(Bool.self, forKey: .selected),
            position: try container.decodeIfPresent(AXPoint.self, forKey: .position),
            size: try container.decodeIfPresent(AXSize.self, forKey: .size),
            actions: try container.decodeIfPresent([String].self, forKey: .actions) ?? [],
            childCount: try container.decodeIfPresent(Int.self, forKey: .childCount),
            readErrors: try container.decodeIfPresent([String].self, forKey: .readErrors) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(order, forKey: .order)
        try container.encode(depth, forKey: .depth)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(subrole, forKey: .subrole)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(help, forKey: .help)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(valueDescription, forKey: .valueDescription)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(focused, forKey: .focused)
        try container.encodeIfPresent(selected, forKey: .selected)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encode(normalizedStrings(actions), forKey: .actions)
        try container.encodeIfPresent(childCount, forKey: .childCount)
        try container.encode(normalizedStrings(readErrors), forKey: .readErrors)
    }
}

public struct AXTraversal: Codable, Equatable, Sendable {
    public var complete: Bool
    public var nodeCount: Int
    public var maximumNodeCount: Int
    public var maximumDepth: Int
    public var truncationReasons: [String]

    public init(
        complete: Bool,
        nodeCount: Int,
        maximumNodeCount: Int,
        maximumDepth: Int,
        truncationReasons: [String]
    ) {
        self.complete = complete
        self.nodeCount = nodeCount
        self.maximumNodeCount = maximumNodeCount
        self.maximumDepth = maximumDepth
        self.truncationReasons = normalizedStrings(truncationReasons)
    }

    private enum CodingKeys: String, CodingKey {
        case complete
        case nodeCount
        case maximumNodeCount
        case maximumDepth
        case truncationReasons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            complete: try container.decode(Bool.self, forKey: .complete),
            nodeCount: try container.decode(Int.self, forKey: .nodeCount),
            maximumNodeCount: try container.decode(Int.self, forKey: .maximumNodeCount),
            maximumDepth: try container.decode(Int.self, forKey: .maximumDepth),
            truncationReasons: try container.decodeIfPresent([String].self, forKey: .truncationReasons) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(complete, forKey: .complete)
        try container.encode(nodeCount, forKey: .nodeCount)
        try container.encode(maximumNodeCount, forKey: .maximumNodeCount)
        try container.encode(maximumDepth, forKey: .maximumDepth)
        try container.encode(normalizedStrings(truncationReasons), forKey: .truncationReasons)
    }
}

public struct AXScrollEvidence: Codable, Equatable, Sendable {
    public var scrollAreaPath: String
    public var verticalScrollBarPath: String
    public var minimumValue: Double?
    public var maximumValue: Double?
    public var currentValue: Double
    public var viewportHeight: Double
    public var contentHeight: Double

    public init(
        scrollAreaPath: String,
        verticalScrollBarPath: String,
        minimumValue: Double?,
        maximumValue: Double?,
        currentValue: Double,
        viewportHeight: Double,
        contentHeight: Double
    ) {
        self.scrollAreaPath = scrollAreaPath
        self.verticalScrollBarPath = verticalScrollBarPath
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.currentValue = currentValue
        self.viewportHeight = viewportHeight
        self.contentHeight = contentHeight
    }

    private enum CodingKeys: String, CodingKey {
        case scrollAreaPath
        case verticalScrollBarPath
        case minimumValue
        case maximumValue
        case currentValue
        case viewportHeight
        case contentHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scrollAreaPath: try container.decode(String.self, forKey: .scrollAreaPath),
            verticalScrollBarPath: try container.decode(String.self, forKey: .verticalScrollBarPath),
            minimumValue: try container.decodeIfPresent(Double.self, forKey: .minimumValue),
            maximumValue: try container.decodeIfPresent(Double.self, forKey: .maximumValue),
            currentValue: try container.decode(Double.self, forKey: .currentValue),
            viewportHeight: try container.decode(Double.self, forKey: .viewportHeight),
            contentHeight: try container.decode(Double.self, forKey: .contentHeight)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scrollAreaPath, forKey: .scrollAreaPath)
        try container.encode(verticalScrollBarPath, forKey: .verticalScrollBarPath)
        if let minimumValue {
            try container.encode(minimumValue, forKey: .minimumValue)
        } else {
            try container.encodeNil(forKey: .minimumValue)
        }
        if let maximumValue {
            try container.encode(maximumValue, forKey: .maximumValue)
        } else {
            try container.encodeNil(forKey: .maximumValue)
        }
        try container.encode(currentValue, forKey: .currentValue)
        try container.encode(viewportHeight, forKey: .viewportHeight)
        try container.encode(contentHeight, forKey: .contentHeight)
    }
}

public struct AXTargetIdentity: Codable, Equatable, Sendable {
    public var processIdentifier: Int32
    public var windowIdentifier: String
    public var rootIdentifier: String

    public init(
        processIdentifier: Int32,
        windowIdentifier: String,
        rootIdentifier: String
    ) {
        self.processIdentifier = processIdentifier
        self.windowIdentifier = windowIdentifier
        self.rootIdentifier = rootIdentifier
    }
}

public struct AXRawCapture: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let schemaID = "https://vifty.app/schemas/ui-review-ax-raw-capture-v1.schema.json"

    public var schemaVersion: Int
    public var schemaID: String
    public var request: AXEvidenceRequest
    public var collectorBuildProvenance: ViftyBuildProvenance
    public var source: String
    public var permissionTrusted: Bool
    public var promptRequested: Bool
    public var initialTarget: AXTargetIdentity
    public var finalTarget: AXTargetIdentity
    public var traversal: AXTraversal
    public var observations: [AXObservation]
    public var scrollEvidence: [AXScrollEvidence]
    public var actionsPerformed: [String]
    public var readErrors: [String]

    public init(
        schemaVersion: Int = AXRawCapture.schemaVersion,
        schemaID: String = AXRawCapture.schemaID,
        request: AXEvidenceRequest,
        collectorBuildProvenance: ViftyBuildProvenance,
        source: String,
        permissionTrusted: Bool,
        promptRequested: Bool,
        initialTarget: AXTargetIdentity,
        finalTarget: AXTargetIdentity,
        traversal: AXTraversal,
        observations: [AXObservation],
        scrollEvidence: [AXScrollEvidence],
        actionsPerformed: [String],
        readErrors: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.request = request
        self.collectorBuildProvenance = collectorBuildProvenance
        self.source = source
        self.permissionTrusted = permissionTrusted
        self.promptRequested = promptRequested
        self.initialTarget = initialTarget
        self.finalTarget = finalTarget
        self.traversal = traversal
        self.observations = observations.sorted {
            ($0.order, $0.path) < ($1.order, $1.path)
        }
        self.scrollEvidence = scrollEvidence.sorted {
            ($0.scrollAreaPath, $0.verticalScrollBarPath)
                < ($1.scrollAreaPath, $1.verticalScrollBarPath)
        }
        self.actionsPerformed = normalizedStrings(actionsPerformed)
        self.readErrors = normalizedStrings(readErrors)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schemaID
        case request
        case collectorBuildProvenance
        case source
        case permissionTrusted
        case promptRequested
        case initialTarget
        case finalTarget
        case traversal
        case observations
        case scrollEvidence
        case actionsPerformed
        case readErrors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            schemaID: try container.decode(String.self, forKey: .schemaID),
            request: try container.decode(AXEvidenceRequest.self, forKey: .request),
            collectorBuildProvenance: try container.decode(
                ViftyBuildProvenance.self,
                forKey: .collectorBuildProvenance
            ),
            source: try container.decode(String.self, forKey: .source),
            permissionTrusted: try container.decode(Bool.self, forKey: .permissionTrusted),
            promptRequested: try container.decode(Bool.self, forKey: .promptRequested),
            initialTarget: try container.decode(AXTargetIdentity.self, forKey: .initialTarget),
            finalTarget: try container.decode(AXTargetIdentity.self, forKey: .finalTarget),
            traversal: try container.decode(AXTraversal.self, forKey: .traversal),
            observations: try container.decode([AXObservation].self, forKey: .observations),
            scrollEvidence: try container.decodeIfPresent([AXScrollEvidence].self, forKey: .scrollEvidence) ?? [],
            actionsPerformed: try container.decodeIfPresent([String].self, forKey: .actionsPerformed) ?? [],
            readErrors: try container.decodeIfPresent([String].self, forKey: .readErrors) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(schemaID, forKey: .schemaID)
        try container.encode(request, forKey: .request)
        try container.encode(collectorBuildProvenance, forKey: .collectorBuildProvenance)
        try container.encode(source, forKey: .source)
        try container.encode(permissionTrusted, forKey: .permissionTrusted)
        try container.encode(promptRequested, forKey: .promptRequested)
        try container.encode(initialTarget, forKey: .initialTarget)
        try container.encode(finalTarget, forKey: .finalTarget)
        try container.encode(traversal, forKey: .traversal)
        try container.encode(
            observations.sorted { ($0.order, $0.path) < ($1.order, $1.path) },
            forKey: .observations
        )
        try container.encode(
            scrollEvidence.sorted {
                ($0.scrollAreaPath, $0.verticalScrollBarPath)
                    < ($1.scrollAreaPath, $1.verticalScrollBarPath)
            },
            forKey: .scrollEvidence
        )
        try container.encode(normalizedStrings(actionsPerformed), forKey: .actionsPerformed)
        try container.encode(normalizedStrings(readErrors), forKey: .readErrors)
    }
}

public struct AXAssertion: Codable, Equatable, Sendable {
    public var id: String
    public var passed: Bool
    public var observationPaths: [String]
    public var facts: [String: String]
    public var failures: [String]

    public init(
        id: String,
        passed: Bool,
        observationPaths: [String],
        facts: [String: String],
        failures: [String]
    ) {
        self.id = id
        self.passed = passed
        self.observationPaths = normalizedStrings(observationPaths)
        self.facts = facts
        self.failures = normalizedStrings(failures)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case passed
        case observationPaths
        case facts
        case failures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            passed: try container.decode(Bool.self, forKey: .passed),
            observationPaths: try container.decodeIfPresent([String].self, forKey: .observationPaths) ?? [],
            facts: try container.decodeIfPresent([String: String].self, forKey: .facts) ?? [:],
            failures: try container.decodeIfPresent([String].self, forKey: .failures) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(passed, forKey: .passed)
        try container.encode(normalizedStrings(observationPaths), forKey: .observationPaths)
        try container.encode(facts, forKey: .facts)
        try container.encode(normalizedStrings(failures), forKey: .failures)
    }
}

public struct AXArtifactBinding: Codable, Equatable, Sendable {
    public var artifact: String
    public var sha256: String

    public init(artifact: String, sha256: String) {
        self.artifact = artifact
        self.sha256 = sha256
    }
}

public struct AXSealedReport: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let schemaID = "https://vifty.app/schemas/ui-review-ax-sealed-report-v1.schema.json"

    public var schemaVersion: Int
    public var schemaID: String
    public var request: AXEvidenceRequest
    public var rawCapture: AXArtifactBinding
    public var fixtureReport: AXArtifactBinding
    public var debugExecutableSHA256: String
    public var debugBuildProvenance: ViftyBuildProvenance
    public var collectorBuildProvenance: ViftyBuildProvenance
    public var runtimeIdentity: AXTargetIdentity
    public var assertion: AXAssertion
    public var actionsPerformed: [String]

    public init(
        schemaVersion: Int = AXSealedReport.schemaVersion,
        schemaID: String = AXSealedReport.schemaID,
        request: AXEvidenceRequest,
        rawCapture: AXArtifactBinding,
        fixtureReport: AXArtifactBinding,
        debugExecutableSHA256: String,
        debugBuildProvenance: ViftyBuildProvenance,
        collectorBuildProvenance: ViftyBuildProvenance,
        runtimeIdentity: AXTargetIdentity,
        assertion: AXAssertion,
        actionsPerformed: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.request = request
        self.rawCapture = rawCapture
        self.fixtureReport = fixtureReport
        self.debugExecutableSHA256 = debugExecutableSHA256
        self.debugBuildProvenance = debugBuildProvenance
        self.collectorBuildProvenance = collectorBuildProvenance
        self.runtimeIdentity = runtimeIdentity
        self.assertion = assertion
        self.actionsPerformed = normalizedStrings(actionsPerformed)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case schemaID
        case request
        case rawCapture
        case fixtureReport
        case debugExecutableSHA256
        case debugBuildProvenance
        case collectorBuildProvenance
        case runtimeIdentity
        case assertion
        case actionsPerformed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            schemaID: try container.decode(String.self, forKey: .schemaID),
            request: try container.decode(AXEvidenceRequest.self, forKey: .request),
            rawCapture: try container.decode(AXArtifactBinding.self, forKey: .rawCapture),
            fixtureReport: try container.decode(AXArtifactBinding.self, forKey: .fixtureReport),
            debugExecutableSHA256: try container.decode(String.self, forKey: .debugExecutableSHA256),
            debugBuildProvenance: try container.decode(
                ViftyBuildProvenance.self,
                forKey: .debugBuildProvenance
            ),
            collectorBuildProvenance: try container.decode(
                ViftyBuildProvenance.self,
                forKey: .collectorBuildProvenance
            ),
            runtimeIdentity: try container.decode(AXTargetIdentity.self, forKey: .runtimeIdentity),
            assertion: try container.decode(AXAssertion.self, forKey: .assertion),
            actionsPerformed: try container.decodeIfPresent([String].self, forKey: .actionsPerformed) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(schemaID, forKey: .schemaID)
        try container.encode(request, forKey: .request)
        try container.encode(rawCapture, forKey: .rawCapture)
        try container.encode(fixtureReport, forKey: .fixtureReport)
        try container.encode(debugExecutableSHA256, forKey: .debugExecutableSHA256)
        try container.encode(debugBuildProvenance, forKey: .debugBuildProvenance)
        try container.encode(collectorBuildProvenance, forKey: .collectorBuildProvenance)
        try container.encode(runtimeIdentity, forKey: .runtimeIdentity)
        try container.encode(assertion, forKey: .assertion)
        try container.encode(normalizedStrings(actionsPerformed), forKey: .actionsPerformed)
    }
}
