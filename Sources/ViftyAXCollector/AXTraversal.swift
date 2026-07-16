import CryptoKit
import Darwin
import Foundation
import ViftyAXEvidenceCore
import ViftyBuildProvenance

public struct AXCollectionConfiguration: Equatable, Sendable {
    public var request: AXEvidenceRequest
    public var timeoutSeconds: Double
    public var maximumNodeCount: Int
    public var maximumDepth: Int
    public var childPageSize: Int
    public var collectorBuildProvenance: ViftyBuildProvenance

    public init(
        request: AXEvidenceRequest,
        timeoutSeconds: Double = 2,
        maximumNodeCount: Int = 2_048,
        maximumDepth: Int = 32,
        childPageSize: Int = 64,
        collectorBuildProvenance: ViftyBuildProvenance
    ) {
        self.request = request
        self.timeoutSeconds = timeoutSeconds
        self.maximumNodeCount = maximumNodeCount
        self.maximumDepth = maximumDepth
        self.childPageSize = childPageSize
        self.collectorBuildProvenance = collectorBuildProvenance
    }
}

public enum AXCollectorError: Error, Equatable, Sendable {
    case permissionMissing
    case invalidConfiguration(String)
    case processIdentifierMismatch(expected: Int32, actual: Int32)
    case windowMatchCount(Int)
    case rootMatchCount(Int)
    case timedOut
    case targetUnavailable
    case targetReplaced
    case cycleDetected
    case nodeLimitExceeded
    case depthLimitExceeded
    case readFailure(String)
}

public enum AXCollectorExitCode {
    public static let success: Int32 = 0
    public static let usage: Int32 = 64
    public static let unavailable: Int32 = 69
    public static let internalError: Int32 = 70
    public static let inputOutput: Int32 = 74
    public static let blocked: Int32 = 75
    public static let permissionMissing: Int32 = 77

    public static func code(for error: Error) -> Int32 {
        if let error = error as? AXCollectorError {
            switch error {
            case .permissionMissing:
                permissionMissing
            case .invalidConfiguration:
                usage
            case .processIdentifierMismatch, .windowMatchCount, .rootMatchCount,
                 .timedOut, .targetUnavailable, .targetReplaced, .cycleDetected,
                 .nodeLimitExceeded, .depthLimitExceeded, .readFailure:
                blocked
            }
        } else if error is AXCollectorCommandError {
            usage
        } else if error is AXSealError {
            blocked
        } else if error is CocoaError || error is POSIXError || error is DecodingError {
            inputOutput
        } else {
            internalError
        }
    }
}

private enum AXReadBound {
    static let maximumStringUTF8Bytes = 4_096
    static let maximumActionCount = 256
}

private func boundedAXString(_ value: String, label: String) throws -> String {
    guard value.utf8.count <= AXReadBound.maximumStringUTF8Bytes else {
        throw AXCollectorError.readFailure("\(label) exceeds the UTF-8 byte limit")
    }
    return value
}

private func finiteAXNumber(_ value: Double, label: String) throws -> Double {
    guard value.isFinite else {
        throw AXCollectorError.readFailure("\(label) is not finite")
    }
    // Canonicalize negative zero so equivalent geometry has one JSON encoding.
    return value == 0 ? 0 : value
}

private func normalizedAXValue(_ value: AXTypedValue?, attribute: String) throws -> AXTypedValue? {
    guard let value else { return nil }
    switch value {
    case let .string(string):
        return .string(try boundedAXString(string, label: attribute))
    case let .number(number):
        return .number(try finiteAXNumber(number, label: attribute))
    case let .point(point):
        // SwiftUI uses this exact sentinel for some offscreen
        // AXOpaqueProviderGroup positions. Do not invent geometry: preserve it
        // as missing while all other non-finite points remain fail-closed.
        if attribute == AXReadAttribute.position,
           point.x == .infinity,
           point.y == .infinity {
            return nil
        }
        return .point(AXPoint(
            x: try finiteAXNumber(point.x, label: "\(attribute).x"),
            y: try finiteAXNumber(point.y, label: "\(attribute).y")
        ))
    case let .size(size):
        let width = try finiteAXNumber(size.width, label: "\(attribute).width")
        let height = try finiteAXNumber(size.height, label: "\(attribute).height")
        guard width >= 0, height >= 0 else {
            throw AXCollectorError.readFailure("\(attribute) contains a negative size")
        }
        return .size(AXSize(width: width, height: height))
    case let .rectangle(rectangle):
        let width = try finiteAXNumber(rectangle.width, label: "\(attribute).width")
        let height = try finiteAXNumber(rectangle.height, label: "\(attribute).height")
        guard width >= 0, height >= 0 else {
            throw AXCollectorError.readFailure("\(attribute) contains a negative size")
        }
        return .rectangle(AXRect(
            x: try finiteAXNumber(rectangle.x, label: "\(attribute).x"),
            y: try finiteAXNumber(rectangle.y, label: "\(attribute).y"),
            width: width,
            height: height
        ))
    case let .range(range):
        guard range.location >= 0, range.length >= 0 else {
            throw AXCollectorError.readFailure("\(attribute) contains a negative range")
        }
        return .range(range)
    case .boolean, .signedInteger, .unsignedInteger, .error:
        return value
    }
}

private func boundedAXActions(_ actions: [String]) throws -> [String] {
    guard actions.count <= AXReadBound.maximumActionCount else {
        throw AXCollectorError.readFailure("action names exceed the count limit")
    }
    return try actions.map { action in
        guard !action.isEmpty else {
            throw AXCollectorError.readFailure("action name is empty")
        }
        return try boundedAXString(action, label: "action name")
    }
}

public struct AXEvidenceCollector<Reader: AXReadAdapter> {
    private let reader: Reader

    public init(reader: Reader) {
        self.reader = reader
    }

    public func collect(_ configuration: AXCollectionConfiguration) throws -> AXRawCapture {
        try collect(configuration: configuration)
    }

    public func collect(configuration: AXCollectionConfiguration) throws -> AXRawCapture {
        try validate(configuration)
        guard reader.isProcessTrusted() else { throw AXCollectorError.permissionMissing }

        let application = reader.application(processIdentifier: configuration.request.processIdentifier)
        try mapRead { try reader.setMessagingTimeout(configuration.timeoutSeconds, for: application) }
        try requirePID(application, expected: configuration.request.processIdentifier)

        let initial = try locateTargets(application: application, configuration: configuration)
        try requirePID(initial.window, expected: configuration.request.processIdentifier)
        try requirePID(initial.root, expected: configuration.request.processIdentifier)
        let identity = AXTargetIdentity(
            processIdentifier: configuration.request.processIdentifier,
            windowIdentifier: configuration.request.windowIdentifier,
            rootIdentifier: configuration.request.rootIdentifier
        )

        var traversal = AXBoundTraversal(reader: reader, configuration: configuration)
        var snapshot = try traversal.capture(root: initial.root)
        try appendScrollEvidence(to: &snapshot, configuration: configuration)
        try normalizeDepthFirstOrder(of: &snapshot)

        try requirePID(application, expected: configuration.request.processIdentifier)
        let final = try locateTargets(application: application, configuration: configuration)
        try requirePID(final.window, expected: configuration.request.processIdentifier)
        try requirePID(final.root, expected: configuration.request.processIdentifier)
        guard reader.elementsEqual(initial.window, final.window),
              reader.elementsEqual(initial.root, final.root) else {
            throw AXCollectorError.targetReplaced
        }

        return AXRawCapture(
            request: configuration.request,
            collectorBuildProvenance: configuration.collectorBuildProvenance,
            source: "macos-accessibility-api",
            permissionTrusted: true,
            promptRequested: false,
            initialTarget: identity,
            finalTarget: identity,
            traversal: AXTraversal(
                complete: true,
                nodeCount: snapshot.observations.count,
                maximumNodeCount: configuration.maximumNodeCount,
                maximumDepth: configuration.maximumDepth,
                truncationReasons: []
            ),
            observations: snapshot.observations,
            scrollEvidence: snapshot.scrollEvidence,
            actionsPerformed: [],
            readErrors: []
        )
    }

    private func validate(_ configuration: AXCollectionConfiguration) throws {
        let request = configuration.request
        guard request.processIdentifier > 0 else {
            throw AXCollectorError.invalidConfiguration("process identifier must be positive")
        }
        guard !request.captureID.isEmpty,
              request.captureID.count <= 128,
              request.captureID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
              }) else {
            throw AXCollectorError.invalidConfiguration("capture identifier is invalid")
        }
        guard request.windowIdentifier == "vifty-ui-review-ax-window-\(request.captureID)" else {
            throw AXCollectorError.invalidConfiguration("window identifier does not bind the capture identifier")
        }
        guard request.rootIdentifier == "vifty.ax.fixture.root.\(request.captureID)" else {
            throw AXCollectorError.invalidConfiguration("root identifier does not bind the capture identifier")
        }
        guard let expectedRequest = AXPredicateCatalog.expectedRequest(for: request.checkID),
              request.semanticRequest == expectedRequest,
              request.requestSHA256 == expectedRequest.canonicalSHA256 else {
            throw AXCollectorError.invalidConfiguration("semantic request is not canonical for the check identifier")
        }
        guard configuration.timeoutSeconds.isFinite,
              (0.1...10).contains(configuration.timeoutSeconds) else {
            throw AXCollectorError.invalidConfiguration("messaging timeout must be between 0.1 and 10 seconds")
        }
        guard (1...16_384).contains(configuration.maximumNodeCount) else {
            throw AXCollectorError.invalidConfiguration("maximum node count is invalid")
        }
        guard (1...128).contains(configuration.maximumDepth) else {
            throw AXCollectorError.invalidConfiguration("maximum depth is invalid")
        }
        guard (1...256).contains(configuration.childPageSize) else {
            throw AXCollectorError.invalidConfiguration("child page size is invalid")
        }
        do {
            try configuration.collectorBuildProvenance.validate(
                expectedRole: "ax-collector",
                expectedConfiguration: "debug"
            )
        } catch {
            throw AXCollectorError.invalidConfiguration("collector build provenance is invalid")
        }
    }

    private func requirePID(_ element: Reader.Element, expected: Int32) throws {
        let actual = try mapRead { try reader.processIdentifier(of: element) }
        guard actual == expected else {
            throw AXCollectorError.processIdentifierMismatch(expected: expected, actual: actual)
        }
    }

    private func locateTargets(
        application: Reader.Element,
        configuration: AXCollectionConfiguration
    ) throws -> (window: Reader.Element, root: Reader.Element) {
        let windows = try mapRead {
            try reader.elements(for: AXReadAttribute.windows, of: application)
        }
        guard windows.count <= configuration.maximumNodeCount else {
            throw AXCollectorError.nodeLimitExceeded
        }
        var matchingWindows: [Reader.Element] = []
        for window in windows {
            let identifier = try mapRead {
                try reader.value(for: AXReadAttribute.identifier, of: window)?.stringValue
            }
            if identifier == configuration.request.windowIdentifier {
                matchingWindows.append(window)
            }
        }
        guard matchingWindows.count == 1, let window = matchingWindows.first else {
            throw AXCollectorError.windowMatchCount(matchingWindows.count)
        }

        var search = AXElementSearch(reader: reader, configuration: configuration)
        let roots = try search.matches(
            below: window,
            identifier: configuration.request.rootIdentifier
        )
        guard roots.count == 1, let root = roots.first else {
            throw AXCollectorError.rootMatchCount(roots.count)
        }
        return (window, root)
    }

    private func appendScrollEvidence(
        to snapshot: inout AXTraversalSnapshot<Reader.Element>,
        configuration: AXCollectionConfiguration
    ) throws {
        let areas = snapshot.nodes.filter { $0.observation.role == "AXScrollArea" }
        for area in areas {
            let barElements = try mapRead {
                try reader.elements(for: AXReadAttribute.verticalScrollBar, of: area.element)
            }
            guard barElements.count == 1, let barElement = barElements.first else { continue }

            var barNode = snapshot.nodes.first { reader.elementsEqual($0.element, barElement) }
            if barNode == nil {
                guard snapshot.nodes.count < configuration.maximumNodeCount else {
                    throw AXCollectorError.nodeLimitExceeded
                }
                let depth = area.observation.depth + 1
                guard depth <= configuration.maximumDepth else {
                    throw AXCollectorError.depthLimitExceeded
                }
                let observation = try makeObservation(
                    element: barElement,
                    path: area.observation.path + "/@vertical",
                    order: snapshot.nodes.count,
                    depth: depth,
                    childCount: 0
                )
                let node = AXTraversalNode(element: barElement, observation: observation)
                snapshot.nodes.append(node)
                snapshot.observations.append(observation)
                barNode = node
            }
            guard let barNode,
                  barNode.observation.role == "AXScrollBar",
                  let currentValue = barNode.observation.value?.numericValue,
                  currentValue.isFinite,
                  let viewportHeight = area.observation.size?.height,
                  viewportHeight.isFinite else { continue }

            let minimumValue = try numericValue(AXReadAttribute.minimumValue, of: barElement)
            let maximumValue = try numericValue(AXReadAttribute.maximumValue, of: barElement)
            guard minimumValue?.isFinite ?? true,
                  maximumValue?.isFinite ?? true else { continue }

            let descendants = snapshot.observations.filter {
                $0.path.hasPrefix(area.observation.path + "/")
            }
            let verticalFrames = descendants.compactMap { observation -> (Double, Double)? in
                guard let position = observation.position, let size = observation.size else { return nil }
                return (position.y, position.y + size.height)
            }
            guard let minimumY = verticalFrames.map(\.0).min(),
                  let maximumY = verticalFrames.map(\.1).max() else { continue }
            let areaMinimumY = area.observation.position?.y ?? minimumY
            let areaMaximumY = areaMinimumY + viewportHeight
            let contentHeight = max(maximumY, areaMaximumY) - min(minimumY, areaMinimumY)
            guard contentHeight.isFinite else { continue }
            snapshot.scrollEvidence.append(AXScrollEvidence(
                scrollAreaPath: area.observation.path,
                verticalScrollBarPath: barNode.observation.path,
                minimumValue: minimumValue,
                maximumValue: maximumValue,
                currentValue: currentValue,
                viewportHeight: viewportHeight,
                contentHeight: contentHeight
            ))
        }
    }

    private func numericValue(_ attribute: String, of element: Reader.Element) throws -> Double? {
        try mapRead { try reader.value(for: attribute, of: element)?.numericValue }
    }

    private func normalizeDepthFirstOrder(
        of snapshot: inout AXTraversalSnapshot<Reader.Element>
    ) throws {
        var nodesByPath: [String: AXTraversalNode<Reader.Element>] = [:]
        for node in snapshot.nodes {
            guard nodesByPath[node.observation.path] == nil else {
                throw AXCollectorError.readFailure("collector produced a duplicate observation path")
            }
            nodesByPath[node.observation.path] = node
        }

        var ordered: [AXTraversalNode<Reader.Element>] = []
        func appendSubtree(_ path: String) {
            guard let node = nodesByPath[path] else { return }
            ordered.append(node)
            for index in 0..<(node.observation.childCount ?? 0) {
                appendSubtree("\(path)/\(index)")
            }
            appendSubtree("\(path)/@vertical")
        }
        appendSubtree("root")
        guard ordered.count == snapshot.nodes.count else {
            throw AXCollectorError.readFailure("collector could not normalize strict depth-first order")
        }
        snapshot.nodes = ordered.enumerated().map { order, node in
            var observation = node.observation
            observation.order = order
            return AXTraversalNode(element: node.element, observation: observation)
        }
        snapshot.observations = snapshot.nodes.map(\.observation)
    }

    private func makeObservation(
        element: Reader.Element,
        path: String,
        order: Int,
        depth: Int,
        childCount: Int
    ) throws -> AXObservation {
        let role = try stringValue(AXReadAttribute.role, of: element) ?? "AXUnknown"
        let title = try stringValue(AXReadAttribute.title, of: element)
        let description = try stringValue(AXReadAttribute.description, of: element)
        let rawValue = try typedValue(AXReadAttribute.value, of: element)
        let explicitSelected = try booleanValue(AXReadAttribute.selected, of: element)
        let selected = explicitSelected ?? selectableState(role: role, value: rawValue)
        return AXObservation(
            path: path,
            order: order,
            depth: depth,
            role: role,
            subrole: try stringValue(AXReadAttribute.subrole, of: element),
            identifier: try stringValue(AXReadAttribute.identifier, of: element),
            title: title,
            description: description,
            label: nonempty(description) ?? nonempty(title) ?? staticTextLabel(role: role, value: rawValue),
            help: try stringValue(AXReadAttribute.help, of: element),
            value: rawValue,
            valueDescription: try stringValue(AXReadAttribute.valueDescription, of: element),
            enabled: try booleanValue(AXReadAttribute.enabled, of: element),
            focused: try booleanValue(AXReadAttribute.focused, of: element),
            selected: selected,
            position: try pointValue(AXReadAttribute.position, of: element),
            size: try sizeValue(AXReadAttribute.size, of: element),
            actions: try boundedAXActions(mapRead { try reader.actionNames(of: element) }),
            childCount: childCount,
            readErrors: []
        )
    }

    private func typedValue(_ attribute: String, of element: Reader.Element) throws -> AXTypedValue? {
        try normalizedAXValue(mapRead { try reader.value(for: attribute, of: element) }, attribute: attribute)
    }

    private func stringValue(_ attribute: String, of element: Reader.Element) throws -> String? {
        try typedValue(attribute, of: element)?.stringValue
    }

    private func booleanValue(_ attribute: String, of element: Reader.Element) throws -> Bool? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .boolean(boolean) = value { return boolean }
        return nil
    }

    private func pointValue(_ attribute: String, of element: Reader.Element) throws -> AXPoint? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .point(point) = value { return point }
        return nil
    }

    private func sizeValue(_ attribute: String, of element: Reader.Element) throws -> AXSize? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .size(size) = value { return size }
        return nil
    }

    private func selectableState(role: String, value: AXTypedValue?) -> Bool? {
        guard role == "AXCheckBox" || role == "AXRadioButton", let value else { return nil }
        return switch value {
        case let .boolean(boolean): boolean
        case let .signedInteger(integer) where integer == 0 || integer == 1: integer == 1
        case let .unsignedInteger(integer) where integer == 0 || integer == 1: integer == 1
        case let .number(number) where number == 0 || number == 1: number == 1
        default: nil
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func staticTextLabel(role: String, value: AXTypedValue?) -> String? {
        guard role == "AXStaticText" else { return nil }
        return nonempty(value?.stringValue)
    }

    private func mapRead<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch AXReadError.timedOut {
            throw AXCollectorError.timedOut
        } catch AXReadError.invalidElement {
            throw AXCollectorError.targetUnavailable
        } catch let error as AXReadError {
            throw AXCollectorError.readFailure(String(describing: error))
        } catch {
            throw AXCollectorError.readFailure(String(describing: error))
        }
    }
}

private struct AXElementSearch<Reader: AXReadAdapter> {
    let reader: Reader
    let configuration: AXCollectionConfiguration
    var visited: [Reader.Element] = []
    var matched: [Reader.Element] = []

    mutating func matches(below root: Reader.Element, identifier: String) throws -> [Reader.Element] {
        try visitChildren(of: root, depth: 0, identifier: identifier)
        return matched
    }

    private mutating func visitChildren(
        of parent: Reader.Element,
        depth: Int,
        identifier: String
    ) throws {
        let children = try readChildren(of: parent)
        for child in children {
            let childDepth = depth + 1
            guard childDepth <= configuration.maximumDepth else { throw AXCollectorError.depthLimitExceeded }
            guard visited.count < configuration.maximumNodeCount else { throw AXCollectorError.nodeLimitExceeded }
            guard !visited.contains(where: { reader.elementsEqual($0, child) }) else {
                throw AXCollectorError.cycleDetected
            }
            visited.append(child)
            let observedIdentifier = try mapRead {
                try reader.value(for: AXReadAttribute.identifier, of: child)?.stringValue
            }
            if observedIdentifier == identifier { matched.append(child) }
            try visitChildren(of: child, depth: childDepth, identifier: identifier)
        }
    }

    private func readChildren(of element: Reader.Element) throws -> [Reader.Element] {
        let count = try mapRead { try reader.childCount(of: element) }
        guard count >= 0 else { throw AXCollectorError.readFailure("negative child count") }
        guard count <= configuration.maximumNodeCount else { throw AXCollectorError.nodeLimitExceeded }
        var children: [Reader.Element] = []
        var index = 0
        while index < count {
            let requested = min(configuration.childPageSize, count - index)
            let page = try mapRead { try reader.children(of: element, startingAt: index, count: requested) }
            guard !page.isEmpty, page.count <= requested else {
                throw AXCollectorError.readFailure("paged child read did not make bounded progress")
            }
            children.append(contentsOf: page)
            index += page.count
        }
        guard children.count == count else { throw AXCollectorError.readFailure("child count changed during traversal") }
        return children
    }

    private func mapRead<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch AXReadError.timedOut {
            throw AXCollectorError.timedOut
        } catch AXReadError.invalidElement {
            throw AXCollectorError.targetUnavailable
        } catch let error as AXReadError {
            throw AXCollectorError.readFailure(String(describing: error))
        }
    }
}

private struct AXTraversalNode<Element> {
    let element: Element
    let observation: AXObservation
}

private struct AXTraversalSnapshot<Element> {
    var nodes: [AXTraversalNode<Element>]
    var observations: [AXObservation]
    var scrollEvidence: [AXScrollEvidence]
}

private struct AXBoundTraversal<Reader: AXReadAdapter> {
    let reader: Reader
    let configuration: AXCollectionConfiguration
    var visited: [Reader.Element] = []
    var nodes: [AXTraversalNode<Reader.Element>] = []

    mutating func capture(root: Reader.Element) throws -> AXTraversalSnapshot<Reader.Element> {
        try visit(root, path: "root", depth: 0)
        return AXTraversalSnapshot(
            nodes: nodes,
            observations: nodes.map(\.observation),
            scrollEvidence: []
        )
    }

    private mutating func visit(_ element: Reader.Element, path: String, depth: Int) throws {
        guard depth <= configuration.maximumDepth else { throw AXCollectorError.depthLimitExceeded }
        guard nodes.count < configuration.maximumNodeCount else { throw AXCollectorError.nodeLimitExceeded }
        guard !visited.contains(where: { reader.elementsEqual($0, element) }) else {
            throw AXCollectorError.cycleDetected
        }
        visited.append(element)
        let children = try readChildren(of: element)
        let observation = try makeObservation(
            element: element,
            path: path,
            order: nodes.count,
            depth: depth,
            childCount: children.count
        )
        nodes.append(AXTraversalNode(element: element, observation: observation))
        for (index, child) in children.enumerated() {
            try visit(child, path: "\(path)/\(index)", depth: depth + 1)
        }
    }

    private func readChildren(of element: Reader.Element) throws -> [Reader.Element] {
        let count = try mapRead { try reader.childCount(of: element) }
        guard count >= 0 else { throw AXCollectorError.readFailure("negative child count") }
        guard count <= configuration.maximumNodeCount else { throw AXCollectorError.nodeLimitExceeded }
        var children: [Reader.Element] = []
        var index = 0
        while index < count {
            let requested = min(configuration.childPageSize, count - index)
            let page = try mapRead { try reader.children(of: element, startingAt: index, count: requested) }
            guard !page.isEmpty, page.count <= requested else {
                throw AXCollectorError.readFailure("paged child read did not make bounded progress")
            }
            children.append(contentsOf: page)
            index += page.count
        }
        guard children.count == count else { throw AXCollectorError.readFailure("child count changed during traversal") }
        return children
    }

    private func makeObservation(
        element: Reader.Element,
        path: String,
        order: Int,
        depth: Int,
        childCount: Int
    ) throws -> AXObservation {
        let role = try stringValue(AXReadAttribute.role, of: element) ?? "AXUnknown"
        let title = try stringValue(AXReadAttribute.title, of: element)
        let description = try stringValue(AXReadAttribute.description, of: element)
        let rawValue = try typedValue(AXReadAttribute.value, of: element)
        let explicitSelected = try booleanValue(AXReadAttribute.selected, of: element)
        let selected = explicitSelected ?? selectableState(role: role, value: rawValue)
        return AXObservation(
            path: path,
            order: order,
            depth: depth,
            role: role,
            subrole: try stringValue(AXReadAttribute.subrole, of: element),
            identifier: try stringValue(AXReadAttribute.identifier, of: element),
            title: title,
            description: description,
            label: nonempty(description) ?? nonempty(title) ?? staticTextLabel(role: role, value: rawValue),
            help: try stringValue(AXReadAttribute.help, of: element),
            value: rawValue,
            valueDescription: try stringValue(AXReadAttribute.valueDescription, of: element),
            enabled: try booleanValue(AXReadAttribute.enabled, of: element),
            focused: try booleanValue(AXReadAttribute.focused, of: element),
            selected: selected,
            position: try pointValue(AXReadAttribute.position, of: element),
            size: try sizeValue(AXReadAttribute.size, of: element),
            actions: try boundedAXActions(mapRead { try reader.actionNames(of: element) }),
            childCount: childCount,
            readErrors: []
        )
    }

    private func typedValue(_ attribute: String, of element: Reader.Element) throws -> AXTypedValue? {
        try normalizedAXValue(mapRead { try reader.value(for: attribute, of: element) }, attribute: attribute)
    }

    private func stringValue(_ attribute: String, of element: Reader.Element) throws -> String? {
        try typedValue(attribute, of: element)?.stringValue
    }

    private func booleanValue(_ attribute: String, of element: Reader.Element) throws -> Bool? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .boolean(boolean) = value { return boolean }
        return nil
    }

    private func pointValue(_ attribute: String, of element: Reader.Element) throws -> AXPoint? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .point(point) = value { return point }
        return nil
    }

    private func sizeValue(_ attribute: String, of element: Reader.Element) throws -> AXSize? {
        guard let value = try typedValue(attribute, of: element) else { return nil }
        if case let .size(size) = value { return size }
        return nil
    }

    private func selectableState(role: String, value: AXTypedValue?) -> Bool? {
        guard role == "AXCheckBox" || role == "AXRadioButton", let value else { return nil }
        return switch value {
        case let .boolean(boolean): boolean
        case let .signedInteger(integer) where integer == 0 || integer == 1: integer == 1
        case let .unsignedInteger(integer) where integer == 0 || integer == 1: integer == 1
        case let .number(number) where number == 0 || number == 1: number == 1
        default: nil
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func staticTextLabel(role: String, value: AXTypedValue?) -> String? {
        guard role == "AXStaticText" else { return nil }
        return nonempty(value?.stringValue)
    }

    private func mapRead<Value>(_ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch AXReadError.timedOut {
            throw AXCollectorError.timedOut
        } catch AXReadError.invalidElement {
            throw AXCollectorError.targetUnavailable
        } catch let error as AXReadError {
            throw AXCollectorError.readFailure(String(describing: error))
        }
    }
}

public struct AXSealConfiguration: Equatable, Sendable {
    public var rawCapturePath: String
    public var expectedRawCaptureSHA256: String
    public var fixtureReportPath: String
    public var expectedFixtureReportSHA256: String
    public var debugExecutablePath: String
    public var expectedDebugExecutableSHA256: String
    public var collectorBuildProvenance: ViftyBuildProvenance
    public var outputPath: String

    public init(
        rawCapturePath: String,
        expectedRawCaptureSHA256: String,
        fixtureReportPath: String,
        expectedFixtureReportSHA256: String,
        debugExecutablePath: String,
        expectedDebugExecutableSHA256: String,
        collectorBuildProvenance: ViftyBuildProvenance,
        outputPath: String
    ) {
        self.rawCapturePath = rawCapturePath
        self.expectedRawCaptureSHA256 = expectedRawCaptureSHA256
        self.fixtureReportPath = fixtureReportPath
        self.expectedFixtureReportSHA256 = expectedFixtureReportSHA256
        self.debugExecutablePath = debugExecutablePath
        self.expectedDebugExecutableSHA256 = expectedDebugExecutableSHA256
        self.collectorBuildProvenance = collectorBuildProvenance
        self.outputPath = outputPath
    }
}

public enum AXSealError: Error, Equatable, Sendable {
    case invalidExpectedHash(String)
    case artifactReadFailure(String)
    case artifactNotRegular(String)
    case artifactTooLarge(String)
    case artifactHashMismatch(String)
    case rawSchemaMismatch
    case rawCaptureNotCanonical
    case fixtureSchemaMismatch
    case fixtureNotFinalAndSafe
    case fixtureBindingMismatch(String)
    case assertionFailed([String])
}

public enum AXArtifactHasher {
    public static func sha256(atPath path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        return sha256(data)
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum AXSealArtifactReader {
    static func readRegularFile(
        atPath path: String,
        label: String,
        maximumBytes: Int
    ) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw AXSealError.artifactNotRegular(label) }
            throw AXSealError.artifactReadFailure(label)
        }
        defer { _ = close(descriptor) }

        var initialStatus = stat()
        guard fstat(descriptor, &initialStatus) == 0 else {
            throw AXSealError.artifactReadFailure(label)
        }
        guard (initialStatus.st_mode & S_IFMT) == S_IFREG else {
            throw AXSealError.artifactNotRegular(label)
        }
        guard initialStatus.st_size >= 0,
              initialStatus.st_size <= off_t(maximumBytes) else {
            throw AXSealError.artifactTooLarge(label)
        }

        var data = Data()
        data.reserveCapacity(Int(initialStatus.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw AXSealError.artifactReadFailure(label)
            }
            guard data.count <= maximumBytes - count else {
                throw AXSealError.artifactTooLarge(label)
            }
            data.append(buffer, count: count)
        }

        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0,
              finalStatus.st_dev == initialStatus.st_dev,
              finalStatus.st_ino == initialStatus.st_ino,
              finalStatus.st_size == off_t(data.count) else {
            throw AXSealError.artifactReadFailure(label)
        }
        return data
    }
}

public struct AXFixtureRuntimeIdentity: Codable, Equatable, Sendable {
    public var processIdentifier: Int32
    public var executablePath: String
    public var executableSHA256: String
    public var windowNumber: Int
    public var windowIdentifier: String
    public var accessibilityIdentifier: String
    public var windowClass: String
    public var containerKind: String
    public var provenance: String
    public var isVisible: Bool
    public var contentWidth: Int
    public var contentHeight: Int
    public var backingScaleFactor: Double

    public init(
        processIdentifier: Int32,
        executablePath: String,
        executableSHA256: String,
        windowNumber: Int,
        windowIdentifier: String,
        accessibilityIdentifier: String,
        windowClass: String,
        containerKind: String,
        provenance: String,
        isVisible: Bool,
        contentWidth: Int,
        contentHeight: Int,
        backingScaleFactor: Double
    ) {
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
        self.executableSHA256 = executableSHA256
        self.windowNumber = windowNumber
        self.windowIdentifier = windowIdentifier
        self.accessibilityIdentifier = accessibilityIdentifier
        self.windowClass = windowClass
        self.containerKind = containerKind
        self.provenance = provenance
        self.isVisible = isVisible
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.backingScaleFactor = backingScaleFactor
    }
}

public struct AXFixtureEnvironmentObservation: Codable, Equatable, Sendable {
    public var source: String
    public var appearance: String
    public var contrast: String
    public var transparency: String
    public var textSize: String
}

public struct AXFixtureWindowObservation: Codable, Equatable, Sendable {
    public var source: String
    public var provenance: String
    public var windowIdentifier: String
    public var accessibilityIdentifier: String
    public var windowNumber: Int
    public var windowClass: String
    public var containerKind: String
    public var isVisible: Bool
    public var contentWidth: Int
    public var contentHeight: Int
    public var backingScaleFactor: Double

    fileprivate func matches(_ runtime: AXFixtureRuntimeIdentity) -> Bool {
        source == "nswindow-content-layout-rect"
            && provenance == runtime.provenance
            && windowIdentifier == runtime.windowIdentifier
            && accessibilityIdentifier == runtime.accessibilityIdentifier
            && windowNumber == runtime.windowNumber
            && windowClass == runtime.windowClass
            && containerKind == runtime.containerKind
            && isVisible == runtime.isVisible
            && contentWidth == runtime.contentWidth
            && contentHeight == runtime.contentHeight
            && backingScaleFactor == runtime.backingScaleFactor
    }
}

public struct AXFixtureObservation: Codable, Equatable, Sendable {
    public var environment: AXFixtureEnvironmentObservation
    public var window: AXFixtureWindowObservation
}

public struct AXFixtureScreenshotObservation: Codable, Equatable, Sendable {
    public var method: String
    public var artifactPath: String
    public var sha256: String
    public var pointWidth: Int
    public var pointHeight: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var backingScaleFactor: Double
}

public struct AXFixtureSafetyRecorder: Codable, Equatable, Sendable {
    public static let requiredFixtureConstructions: Set<String> = [
        "daemon-client",
        "hardware",
        "helper-installer",
        "login-item",
        "notification-center",
        "power-client"
    ]
    public static let requiredReadOperations: Set<String> = [
        "agent-status",
        "daemon-ping",
        "fan-control-ownership",
        "hardware-snapshot",
        "login-item-status",
        "notification-authorization",
        "power",
        "thermal-pressure"
    ]
    public static let optionalReadOperations: Set<String> = ["codex-usage"]

    public var fixtureConstructions: [String]
    public var readOperations: [String]
    public var attemptedHardwareCommands: [String]
    public var attemptedExternalMutations: [String]
    public var realControlPathConstructions: [String]

    public init(
        fixtureConstructions: [String],
        readOperations: [String],
        attemptedHardwareCommands: [String],
        attemptedExternalMutations: [String],
        realControlPathConstructions: [String]
    ) {
        self.fixtureConstructions = fixtureConstructions
        self.readOperations = readOperations
        self.attemptedHardwareCommands = attemptedHardwareCommands
        self.attemptedExternalMutations = attemptedExternalMutations
        self.realControlPathConstructions = realControlPathConstructions
    }

    public var isSafe: Bool {
        let constructions = Set(fixtureConstructions)
        let reads = Set(readOperations)
        let allowedReads = Self.requiredReadOperations.union(Self.optionalReadOperations)
        return attemptedHardwareCommands.isEmpty
            && attemptedExternalMutations.isEmpty
            && realControlPathConstructions.isEmpty
            && constructions == Self.requiredFixtureConstructions
            && fixtureConstructions.count == Self.requiredFixtureConstructions.count
            && Self.requiredReadOperations.isSubset(of: reads)
            && reads.isSubset(of: allowedReads)
    }
}

public struct AXFixtureReportEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var captureID: String
    public var request: AXSemanticRequest
    public var requestSHA256: String
    public var debugExecutablePath: String
    public var debugExecutableSHA256: String
    public var debugBuildProvenance: ViftyBuildProvenance
    public var runtimeIdentity: AXFixtureRuntimeIdentity?
    public var observed: AXFixtureObservation?
    public var screenshot: AXFixtureScreenshotObservation?
    public var phase: String
    public var modelStartSkipped: Bool
    public var recorder: AXFixtureSafetyRecorder
    public var runtimeFailure: String?
    public var passed: Bool

    public init(
        schemaVersion: Int,
        captureID: String,
        request: AXSemanticRequest,
        requestSHA256: String,
        debugExecutablePath: String,
        debugExecutableSHA256: String,
        debugBuildProvenance: ViftyBuildProvenance,
        runtimeIdentity: AXFixtureRuntimeIdentity?,
        observed: AXFixtureObservation?,
        screenshot: AXFixtureScreenshotObservation?,
        phase: String,
        modelStartSkipped: Bool,
        recorder: AXFixtureSafetyRecorder,
        runtimeFailure: String?,
        passed: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.captureID = captureID
        self.request = request
        self.requestSHA256 = requestSHA256
        self.debugExecutablePath = debugExecutablePath
        self.debugExecutableSHA256 = debugExecutableSHA256
        self.debugBuildProvenance = debugBuildProvenance
        self.runtimeIdentity = runtimeIdentity
        self.observed = observed
        self.screenshot = screenshot
        self.phase = phase
        self.modelStartSkipped = modelStartSkipped
        self.recorder = recorder
        self.runtimeFailure = runtimeFailure
        self.passed = passed
    }
}

public enum AXEvidenceSealer {
    public static func seal(_ configuration: AXSealConfiguration) throws -> AXSealedReport {
        try validateExpectedHash(configuration.expectedRawCaptureSHA256, label: "raw capture")
        try validateExpectedHash(configuration.expectedFixtureReportSHA256, label: "fixture report")
        try validateExpectedHash(configuration.expectedDebugExecutableSHA256, label: "debug executable")

        let rawData = try AXSealArtifactReader.readRegularFile(
            atPath: configuration.rawCapturePath,
            label: "raw capture",
            maximumBytes: 64 * 1_024 * 1_024
        )
        try verifyHash(rawData, expected: configuration.expectedRawCaptureSHA256, label: "raw capture")
        let raw = try JSONDecoder().decode(AXRawCapture.self, from: rawData)
        guard raw.schemaVersion == AXRawCapture.schemaVersion,
              raw.schemaID == AXRawCapture.schemaID else { throw AXSealError.rawSchemaMismatch }
        guard rawData == (try AXCanonicalJSON.data(raw)) else {
            throw AXSealError.rawCaptureNotCanonical
        }

        let fixtureData = try AXSealArtifactReader.readRegularFile(
            atPath: configuration.fixtureReportPath,
            label: "fixture report",
            maximumBytes: 64 * 1_024 * 1_024
        )
        try verifyHash(fixtureData, expected: configuration.expectedFixtureReportSHA256, label: "fixture report")
        let fixture = try JSONDecoder().decode(AXFixtureReportEnvelope.self, from: fixtureData)
        guard fixture.schemaVersion == 3 else { throw AXSealError.fixtureSchemaMismatch }
        guard fixture.phase == "final",
              fixture.passed,
              fixture.modelStartSkipped,
              fixture.runtimeFailure == nil,
              fixture.recorder.isSafe,
              fixture.screenshot == nil,
              let runtime = fixture.runtimeIdentity,
              let observed = fixture.observed else {
            throw AXSealError.fixtureNotFinalAndSafe
        }

        let debugExecutableData = try AXSealArtifactReader.readRegularFile(
            atPath: configuration.debugExecutablePath,
            label: "debug executable",
            maximumBytes: 512 * 1_024 * 1_024
        )
        try verifyHash(
            debugExecutableData,
            expected: configuration.expectedDebugExecutableSHA256,
            label: "debug executable"
        )
        let debugBuildProvenance: ViftyBuildProvenance
        do {
            debugBuildProvenance = try ViftyBuildProvenanceReader.read(
                data: debugExecutableData,
                expectedRole: "debug-fixture-app",
                expectedConfiguration: "debug"
            )
            try configuration.collectorBuildProvenance.validate(
                expectedRole: "ax-collector",
                expectedConfiguration: "debug"
            )
        } catch {
            throw AXSealError.fixtureBindingMismatch("embedded build provenance")
        }

        try require(fixture.captureID == raw.request.captureID, "capture identifier")
        try require(fixture.request == raw.request.semanticRequest, "semantic request")
        try require(fixture.requestSHA256 == raw.request.requestSHA256, "request hash")
        try require(fixture.debugExecutableSHA256 == configuration.expectedDebugExecutableSHA256, "fixture executable hash")
        try require(fixture.debugBuildProvenance == debugBuildProvenance, "fixture embedded build provenance")
        try require(raw.collectorBuildProvenance == configuration.collectorBuildProvenance, "collector embedded build provenance")
        try require(
            debugBuildProvenance.sourceCommit == configuration.collectorBuildProvenance.sourceCommit &&
                debugBuildProvenance.sourceTree == configuration.collectorBuildProvenance.sourceTree &&
                debugBuildProvenance.buildTransactionID == configuration.collectorBuildProvenance.buildTransactionID,
            "one source build transaction"
        )
        try require(runtime.processIdentifier == raw.request.processIdentifier, "process identifier")
        try require(runtime.executableSHA256 == configuration.expectedDebugExecutableSHA256, "runtime executable hash")
        try validateRuntimeIdentity(runtime, request: raw.request)
        try require(observed.window.matches(runtime), "observed AppKit window identity")
        try validateEnvironment(observed.environment, request: raw.request.semanticRequest)
        try require(runtime.accessibilityIdentifier == raw.request.windowIdentifier, "window Accessibility identifier")
        let expectedExecutablePath = resolvedPath(configuration.debugExecutablePath)
        try require(resolvedPath(fixture.debugExecutablePath) == expectedExecutablePath, "fixture executable path")
        try require(resolvedPath(runtime.executablePath) == expectedExecutablePath, "runtime executable path")
        try require(raw.initialTarget == raw.finalTarget, "stable raw target")
        try require(raw.actionsPerformed.isEmpty, "raw capture actions")

        let assertion = try AXPredicateCatalog.evaluate(id: raw.request.checkID, capture: raw)
        guard assertion.passed else { throw AXSealError.assertionFailed(assertion.failures) }
        return AXSealedReport(
            request: raw.request,
            rawCapture: AXArtifactBinding(
                artifact: configuration.rawCapturePath,
                sha256: configuration.expectedRawCaptureSHA256
            ),
            fixtureReport: AXArtifactBinding(
                artifact: configuration.fixtureReportPath,
                sha256: configuration.expectedFixtureReportSHA256
            ),
            debugExecutableSHA256: configuration.expectedDebugExecutableSHA256,
            debugBuildProvenance: debugBuildProvenance,
            collectorBuildProvenance: configuration.collectorBuildProvenance,
            runtimeIdentity: raw.finalTarget,
            assertion: assertion,
            actionsPerformed: []
        )
    }

    private static func validateExpectedHash(_ value: String, label: String) throws {
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({
                  (48...57).contains($0.value) || (97...102).contains($0.value)
              }) else {
            throw AXSealError.invalidExpectedHash(label)
        }
    }

    private static func verifyHash(_ data: Data, expected: String, label: String) throws {
        guard AXArtifactHasher.sha256(data) == expected else {
            throw AXSealError.artifactHashMismatch(label)
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw AXSealError.fixtureBindingMismatch(label) }
    }

    private static func validateRuntimeIdentity(
        _ runtime: AXFixtureRuntimeIdentity,
        request: AXEvidenceRequest
    ) throws {
        let semantic = request.semanticRequest
        let expectedContainer: String
        let expectedProvenance: String
        switch semantic.surface {
        case "main":
            expectedContainer = "main-window"
            expectedProvenance = "swiftui-main-window"
        case "menu-popover":
            expectedContainer = "popover"
            expectedProvenance = "ns-popover-status-item"
        default:
            guard semantic.surface.hasPrefix("settings-") else {
                throw AXSealError.fixtureBindingMismatch("runtime surface")
            }
            expectedContainer = "settings-window"
            expectedProvenance = "swiftui-settings-scene"
        }

        try require(runtime.windowNumber > 0, "runtime window number")
        try require(runtime.windowIdentifier == "vifty-ui-review-window-\(request.captureID)", "runtime window identifier")
        try require(!runtime.windowClass.isEmpty, "runtime window class")
        try require(runtime.containerKind == expectedContainer, "runtime container kind")
        try require(runtime.provenance == expectedProvenance, "runtime provenance")
        try require(runtime.isVisible, "runtime window visibility")
        try require(runtime.contentWidth > 0 && runtime.contentHeight > 0, "runtime window geometry")
        try require(
            runtime.backingScaleFactor.isFinite
                && runtime.backingScaleFactor > 0
                && runtime.backingScaleFactor <= 4,
            "runtime backing scale"
        )

        let expectedGeometry = try geometry(for: semantic.window)
        if let width = expectedGeometry.width {
            try require(runtime.contentWidth == width, "runtime content width")
        }
        if let height = expectedGeometry.height {
            try require(runtime.contentHeight == height, "runtime content height")
        }
    }

    private static func validateEnvironment(
        _ environment: AXFixtureEnvironmentObservation,
        request: AXSemanticRequest
    ) throws {
        try require(environment.source == "swiftui-environment", "observed environment source")
        try require(environment.appearance == request.appearance, "observed appearance")
        try require(environment.contrast == request.contrast, "observed contrast")
        try require(environment.transparency == request.transparency, "observed transparency")
        try require(environment.textSize == request.textSize, "observed text size")
    }

    private static func geometry(for window: String) throws -> (width: Int?, height: Int?) {
        switch window {
        case "native":
            return (600, 420)
        case "320xauto":
            return (320, nil)
        default:
            let parts = window.split(separator: "x", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let width = Int(parts[0]), width > 0,
                  let height = Int(parts[1]), height > 0 else {
                throw AXSealError.fixtureBindingMismatch("runtime request geometry")
            }
            return (width, height)
        }
    }

    private static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }
}
