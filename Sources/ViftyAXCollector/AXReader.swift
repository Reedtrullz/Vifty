import ApplicationServices
import Foundation
import ViftyAXEvidenceCore

public enum AXReadAttribute {
    public static let windows = kAXWindowsAttribute as String
    public static let children = kAXChildrenAttribute as String
    public static let role = kAXRoleAttribute as String
    public static let subrole = kAXSubroleAttribute as String
    public static let identifier = kAXIdentifierAttribute as String
    public static let title = kAXTitleAttribute as String
    public static let description = kAXDescriptionAttribute as String
    public static let help = kAXHelpAttribute as String
    public static let value = kAXValueAttribute as String
    public static let valueDescription = kAXValueDescriptionAttribute as String
    public static let enabled = kAXEnabledAttribute as String
    public static let focused = kAXFocusedAttribute as String
    public static let selected = kAXSelectedAttribute as String
    public static let position = kAXPositionAttribute as String
    public static let size = kAXSizeAttribute as String
    public static let minimumValue = kAXMinValueAttribute as String
    public static let maximumValue = kAXMaxValueAttribute as String
    public static let verticalScrollBar = kAXVerticalScrollBarAttribute as String
}

public enum AXReadError: Error, Equatable, Sendable {
    case timedOut
    case invalidElement
    case unsupportedValue(String)
    case apiFailure(operation: String, code: Int32)
}

/// Read-only abstraction over the public macOS Accessibility API. It exposes
/// neither setters nor action execution, so synthetic adapters can exercise
/// the complete collector without granting Accessibility permission.
public protocol AXReadAdapter {
    associatedtype Element

    func isProcessTrusted() -> Bool
    func application(processIdentifier: Int32) -> Element
    func processIdentifier(of element: Element) throws -> Int32
    func setMessagingTimeout(_ timeoutSeconds: Double, for application: Element) throws
    func elements(for attribute: String, of element: Element) throws -> [Element]
    func value(for attribute: String, of element: Element) throws -> AXTypedValue?
    func childCount(of element: Element) throws -> Int
    func children(of element: Element, startingAt index: Int, count: Int) throws -> [Element]
    func actionNames(of element: Element) throws -> [String]
    func elementsEqual(_ lhs: Element, _ rhs: Element) -> Bool
}

public struct AXSystemReader: AXReadAdapter {
    public init() {}

    static func treatsGenericFailureAsMissing(errorCode: Int32, attribute: String) -> Bool {
        guard errorCode == AXError.failure.rawValue else { return false }
        return attribute == AXReadAttribute.identifier
            || attribute == AXReadAttribute.valueDescription
    }

    public func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func application(processIdentifier: Int32) -> AXUIElement {
        AXUIElementCreateApplication(pid_t(processIdentifier))
    }

    public func processIdentifier(of element: AXUIElement) throws -> Int32 {
        var processIdentifier: pid_t = 0
        try check(AXUIElementGetPid(element, &processIdentifier), operation: "AXUIElementGetPid")
        return Int32(processIdentifier)
    }

    public func setMessagingTimeout(_ timeoutSeconds: Double, for application: AXUIElement) throws {
        try check(
            AXUIElementSetMessagingTimeout(application, Float(timeoutSeconds)),
            operation: "AXUIElementSetMessagingTimeout"
        )
    }

    public func elements(for attribute: String, of element: AXUIElement) throws -> [AXUIElement] {
        guard let rawValue = try copyAttribute(attribute, of: element) else { return [] }
        if CFGetTypeID(rawValue) == AXUIElementGetTypeID() {
            return [unsafeDowncast(rawValue, to: AXUIElement.self)]
        }
        guard CFGetTypeID(rawValue) == CFArrayGetTypeID() else { return [] }
        let array = unsafeDowncast(rawValue, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { index in
            let pointer = CFArrayGetValueAtIndex(array, index)
            let value = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value, to: AXUIElement.self)
        }
    }

    public func value(for attribute: String, of element: AXUIElement) throws -> AXTypedValue? {
        guard let rawValue = try copyAttribute(attribute, of: element) else { return nil }
        return try decode(rawValue, attribute: attribute)
    }

    public func childCount(of element: AXUIElement) throws -> Int {
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(element, AXReadAttribute.children as CFString, &count)
        if error == .attributeUnsupported || error == .noValue { return 0 }
        try check(error, operation: "AXUIElementGetAttributeValueCount(\(AXReadAttribute.children))")
        guard count >= 0, count <= Int.max else {
            throw AXReadError.apiFailure(
                operation: "AXUIElementGetAttributeValueCount(\(AXReadAttribute.children))",
                code: AXError.illegalArgument.rawValue
            )
        }
        return Int(count)
    }

    public func children(
        of element: AXUIElement,
        startingAt index: Int,
        count: Int
    ) throws -> [AXUIElement] {
        guard index >= 0, count >= 0 else {
            throw AXReadError.apiFailure(
                operation: "AXUIElementCopyAttributeValues(\(AXReadAttribute.children))",
                code: AXError.illegalArgument.rawValue
            )
        }
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(
            element,
            AXReadAttribute.children as CFString,
            index,
            count,
            &values
        )
        if error == .attributeUnsupported || error == .noValue { return [] }
        try check(error, operation: "AXUIElementCopyAttributeValues(\(AXReadAttribute.children))")
        guard let values else { return [] }
        return (0..<CFArrayGetCount(values)).compactMap { valueIndex in
            let pointer = CFArrayGetValueAtIndex(values, valueIndex)
            let value = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value, to: AXUIElement.self)
        }
    }

    public func actionNames(of element: AXUIElement) throws -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        if error == .actionUnsupported || error == .noValue { return [] }
        try check(error, operation: "AXUIElementCopyActionNames")
        guard let names else { return [] }
        return (names as? [String]) ?? []
    }

    public func elementsEqual(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }

    private func copyAttribute(_ attribute: String, of element: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .attributeUnsupported || error == .noValue { return nil }
        // SwiftUI can return the generic AX failure when optional identifier
        // or value-description metadata is absent instead of returning
        // `noValue`. Required identifiers are still enforced by exact target
        // matching and semantic predicates; every other failure stays closed.
        if Self.treatsGenericFailureAsMissing(errorCode: error.rawValue, attribute: attribute) {
            return nil
        }
        try check(error, operation: "AXUIElementCopyAttributeValue(\(attribute))")
        return value
    }

    private func check(_ error: AXError, operation: String) throws {
        switch error {
        case .success:
            return
        case .cannotComplete:
            throw AXReadError.timedOut
        case .invalidUIElement, .invalidUIElementObserver:
            throw AXReadError.invalidElement
        default:
            throw AXReadError.apiFailure(operation: operation, code: error.rawValue)
        }
    }

    private func decode(_ value: CFTypeRef, attribute: String) throws -> AXTypedValue? {
        let typeID = CFGetTypeID(value)
        if typeID == AXUIElementGetTypeID() || typeID == CFArrayGetTypeID() { return nil }
        if typeID == CFStringGetTypeID() {
            return .string(unsafeDowncast(value, to: CFString.self) as String)
        }
        if typeID == CFBooleanGetTypeID() {
            return .boolean(CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self)))
        }
        if typeID == CFNumberGetTypeID() {
            let number = unsafeDowncast(value, to: CFNumber.self)
            if CFNumberIsFloatType(number) {
                var decoded = 0.0
                guard CFNumberGetValue(number, .doubleType, &decoded) else {
                    throw AXReadError.unsupportedValue(attribute)
                }
                return .number(decoded)
            }
            var decoded: Int64 = 0
            guard CFNumberGetValue(number, .sInt64Type, &decoded) else {
                throw AXReadError.unsupportedValue(attribute)
            }
            return .signedInteger(decoded)
        }
        if typeID == AXValueGetTypeID() {
            return try decodeAXValue(unsafeDowncast(value, to: AXValue.self), attribute: attribute)
        }
        throw AXReadError.unsupportedValue(attribute)
    }

    private func decodeAXValue(_ value: AXValue, attribute: String) throws -> AXTypedValue {
        switch AXValueGetType(value) {
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetValue(value, .cgPoint, &point) else { throw AXReadError.unsupportedValue(attribute) }
            return .point(AXPoint(x: point.x, y: point.y))
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetValue(value, .cgSize, &size) else { throw AXReadError.unsupportedValue(attribute) }
            return .size(AXSize(width: size.width, height: size.height))
        case .cgRect:
            var rectangle = CGRect.zero
            guard AXValueGetValue(value, .cgRect, &rectangle) else { throw AXReadError.unsupportedValue(attribute) }
            return .rectangle(AXRect(
                x: rectangle.origin.x,
                y: rectangle.origin.y,
                width: rectangle.size.width,
                height: rectangle.size.height
            ))
        case .cfRange:
            var range = CFRange()
            guard AXValueGetValue(value, .cfRange, &range) else { throw AXReadError.unsupportedValue(attribute) }
            return .range(AXRange(location: range.location, length: range.length))
        case .axError:
            var error = AXError.success
            guard AXValueGetValue(value, .axError, &error) else { throw AXReadError.unsupportedValue(attribute) }
            return .error(error.rawValue)
        case .illegal:
            throw AXReadError.unsupportedValue(attribute)
        @unknown default:
            throw AXReadError.unsupportedValue(attribute)
        }
    }
}
