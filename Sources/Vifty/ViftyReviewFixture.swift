#if DEBUG
import AppKit
import Foundation
import SwiftUI
import ViftyBuildProvenance
import ViftyCore

enum ViftyReviewFixtureState: String, CaseIterable, Codable, Identifiable, Sendable {
    case healthyAuto = "healthy-auto"
    case divergentPerFanCurveDraft = "divergent-per-fan-curve-draft"
    case activeManual = "active-manual"
    case recoveryMixedOwnership = "recovery-mixed-ownership"
    case helperBlocked = "helper-blocked"
    case notificationDenied = "notification-denied"
    case editedProfile = "edited-profile"
    case selectedVersusHighestTemperature = "selected-vs-highest-temperature"
    case rawSpikeTelemetry = "raw-spike-telemetry"

    var id: String { rawValue }
}

enum ViftyReviewFixtureSurface: String, CaseIterable, Codable, Sendable {
    case main
    case settingsGeneral = "settings-general"
    case settingsMenuBar = "settings-menu-bar"
    case settingsNotifications = "settings-notifications"
    case settingsAgentWorkflows = "settings-agent-workflows"
    case menuPopover = "menu-popover"

    var settingsTab: ViftySettingsTab? {
        switch self {
        case .settingsGeneral: .general
        case .settingsMenuBar: .menuBar
        case .settingsNotifications: .notifications
        case .settingsAgentWorkflows: .agentWorkflows
        case .main, .menuPopover: nil
        }
    }

    var expectedContainerKind: String {
        switch self {
        case .main:
            "main-window"
        case .settingsGeneral, .settingsMenuBar, .settingsNotifications, .settingsAgentWorkflows:
            "settings-window"
        case .menuPopover:
            "popover"
        }
    }

    var provenance: String {
        switch self {
        case .main:
            "swiftui-main-window"
        case .settingsGeneral, .settingsMenuBar, .settingsNotifications, .settingsAgentWorkflows:
            "swiftui-settings-scene"
        case .menuPopover:
            "ns-popover-status-item"
        }
    }

    var defaultWindow: ViftyReviewFixtureWindow {
        switch self {
        case .main:
            .standard
        case .settingsGeneral, .settingsMenuBar, .settingsNotifications, .settingsAgentWorkflows:
            .native
        case .menuPopover:
            .popover
        }
    }
}

enum ViftyReviewFixtureRoute: Equatable, Sendable {
    case main
    case settings(ViftySettingsTab)
    case popover

    init(surface: ViftyReviewFixtureSurface) {
        switch surface {
        case .main:
            self = .main
        case .settingsGeneral:
            self = .settings(.general)
        case .settingsMenuBar:
            self = .settings(.menuBar)
        case .settingsNotifications:
            self = .settings(.notifications)
        case .settingsAgentWorkflows:
            self = .settings(.agentWorkflows)
        case .menuPopover:
            self = .popover
        }
    }
}

@MainActor
final class ViftyReviewFixtureLaunchCoordinator {
    private(set) var launchedRoute: ViftyReviewFixtureRoute?

    func launch(
        route: ViftyReviewFixtureRoute,
        openSettings: (ViftySettingsTab) -> Void,
        showPopover: () -> Void
    ) {
        guard launchedRoute == nil else { return }
        launchedRoute = route
        switch route {
        case .main:
            break
        case .settings(let tab):
            openSettings(tab)
        case .popover:
            showPopover()
        }
    }
}

enum ViftyReviewFixtureWindow: String, CaseIterable, Codable, Sendable {
    case compact = "780x480"
    case standard = "1180x820"
    case split = "1280x720"
    case wideWorkbench = "1500x900"
    case native
    case popover = "320xauto"

    var expectedContentSize: CGSize? {
        switch self {
        case .compact: CGSize(width: 780, height: 480)
        case .standard: CGSize(width: 1180, height: 820)
        case .split: CGSize(width: 1280, height: 720)
        case .wideWorkbench: CGSize(width: 1500, height: 900)
        case .native, .popover: nil
        }
    }

    var size: CGSize {
        if let expectedContentSize { return expectedContentSize }
        switch self {
        case .native:
            return CGSize(width: 600, height: 420)
        case .popover:
            return CGSize(width: 320, height: 1)
        case .compact, .standard, .split, .wideWorkbench:
            return CGSize(width: 1, height: 1)
        }
    }
}

enum ViftyReviewFixtureAppearance: String, CaseIterable, Codable, Sendable {
    case light
    case dark

    @MainActor
    func apply(to application: NSApplication = .shared) {
        application.appearance = nativeAppearance
    }

    @MainActor
    var resolvedWindowBackgroundColor: NSColor {
        var resolvedColor: NSColor?
        nativeAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor.windowBackgroundColor
                .usingColorSpace(.deviceRGB)?
                .withAlphaComponent(1)
        }
        guard let resolvedColor else {
            preconditionFailure("AppKit window background color must resolve to device RGB")
        }
        return resolvedColor
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    var nativeAppearance: NSAppearance {
        switch self {
        case .light:
            NSAppearance(named: .aqua)!
        case .dark:
            NSAppearance(named: .darkAqua)!
        }
    }
}

enum ViftyReviewFixtureContrast: String, CaseIterable, Codable, Sendable {
    case standard
    case increased

    var colorSchemeContrast: ColorSchemeContrast {
        switch self {
        case .standard: .standard
        case .increased: .increased
        }
    }
}

enum ViftyReviewFixtureTransparency: String, CaseIterable, Codable, Sendable {
    case standard
    case reduced

    var reducesTransparency: Bool { self == .reduced }
}

enum ViftyReviewFixtureTextSize: String, CaseIterable, Codable, Sendable {
    case standard
    case accessibility

    var viftyTextScale: ViftyTextScale {
        switch self {
        case .standard: .standard
        case .accessibility: .accessibility
        }
    }
}

enum ViftyReviewFixtureInteraction: String, CaseIterable, Codable, Sendable {
    case none
    case structuralScroll = "structural-scroll"
}

struct ViftyReviewFixtureRequest: Equatable, Sendable {
    static let fixtureFlag = "--ui-review-fixture"

    var state: ViftyReviewFixtureState
    var surface: ViftyReviewFixtureSurface
    var window: ViftyReviewFixtureWindow
    var appearance: ViftyReviewFixtureAppearance
    var contrast: ViftyReviewFixtureContrast
    var transparency: ViftyReviewFixtureTransparency
    var textSize: ViftyReviewFixtureTextSize
    var interaction: ViftyReviewFixtureInteraction
    var captureID: String
    var outputDirectory: URL
    var screenshotURL: URL?
    var completionFileURL: URL?
    var timeoutSeconds: Double
    var readinessDeadlineUptime: Double?
    var expectedExecutableSHA256: String?

    static func parse(
        arguments: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> ViftyReviewFixtureRequest? {
        guard let flagIndex = arguments.firstIndex(of: fixtureFlag) else { return nil }
        guard arguments.indices.contains(flagIndex + 1),
              let state = ViftyReviewFixtureState(rawValue: arguments[flagIndex + 1]) else {
            throw ViftyReviewFixtureError.invalidState
        }

        let surface = try value(
            for: "--ui-review-surface",
            in: arguments,
            default: ViftyReviewFixtureSurface.main
        )
        let window = try value(
            for: "--ui-review-window",
            in: arguments,
            default: surface.defaultWindow
        )
        let appearance = try value(
            for: "--ui-review-appearance",
            in: arguments,
            default: ViftyReviewFixtureAppearance.light
        )
        let contrast = try value(
            for: "--ui-review-contrast",
            in: arguments,
            default: ViftyReviewFixtureContrast.standard
        )
        let transparency = try value(
            for: "--ui-review-transparency",
            in: arguments,
            default: ViftyReviewFixtureTransparency.standard
        )
        let textSize = try value(
            for: "--ui-review-text-size",
            in: arguments,
            default: ViftyReviewFixtureTextSize.standard
        )
        let interaction = try value(
            for: "--ui-review-interaction",
            in: arguments,
            default: ViftyReviewFixtureInteraction.none
        )
        guard surface.accepts(window: window) else {
            throw ViftyReviewFixtureError.invalidSurfaceWindow(
                surface: surface.rawValue,
                window: window.rawValue
            )
        }
        guard let captureID = try stringValue(for: "--ui-review-capture-id", in: arguments) else {
            throw ViftyReviewFixtureError.missingOptionValue(flag: "--ui-review-capture-id")
        }
        guard validCaptureID(captureID) else {
            throw ViftyReviewFixtureError.invalidCaptureID(captureID)
        }
        let defaultOutput = currentDirectory
            .appendingPathComponent(".build/ui-review-runtime", isDirectory: true)
            .appendingPathComponent(captureID, isDirectory: true)
        let outputDirectory = try stringValue(
            for: "--ui-review-output",
            in: arguments
        ).map { URL(fileURLWithPath: $0, relativeTo: currentDirectory).standardizedFileURL }
            ?? defaultOutput
        let screenshotURL = try evidenceURL(
            for: "--ui-review-screenshot",
            in: arguments,
            currentDirectory: currentDirectory,
            outputDirectory: outputDirectory
        )
        let completionFileURL = try evidenceURL(
            for: "--ui-review-completion-file",
            in: arguments,
            currentDirectory: currentDirectory,
            outputDirectory: outputDirectory
        )
        let timeoutSeconds = try timeoutValue(in: arguments)
        let readinessDeadlineUptime = try readinessDeadlineValue(in: arguments)
        let expectedExecutableSHA256 = try stringValue(
            for: "--ui-review-executable-sha256",
            in: arguments
        )
        if let expectedExecutableSHA256,
           !expectedExecutableSHA256.isLowercaseSHA256 {
            throw ViftyReviewFixtureError.invalidExecutableSHA256
        }

        return ViftyReviewFixtureRequest(
            state: state,
            surface: surface,
            window: window,
            appearance: appearance,
            contrast: contrast,
            transparency: transparency,
            textSize: textSize,
            interaction: interaction,
            captureID: captureID,
            outputDirectory: outputDirectory,
            screenshotURL: screenshotURL,
            completionFileURL: completionFileURL,
            timeoutSeconds: timeoutSeconds,
            readinessDeadlineUptime: readinessDeadlineUptime,
            expectedExecutableSHA256: expectedExecutableSHA256
        )
    }

    var screenshotArtifactPath: String? {
        screenshotURL.flatMap { Self.relativeArtifactPath(for: $0, under: outputDirectory) }
    }

    var windowIdentifier: String {
        "vifty-ui-review-window-\(captureID)"
    }

    var windowAccessibilityIdentifier: String {
        "vifty-ui-review-ax-window-\(captureID)"
    }

    var rootAccessibilityIdentifier: String {
        "vifty.ax.fixture.root.\(captureID)"
    }

    private static func value<Value: RawRepresentable>(
        for flag: String,
        in arguments: [String],
        default defaultValue: Value
    ) throws -> Value where Value.RawValue == String {
        guard let rawValue = try stringValue(for: flag, in: arguments) else {
            return defaultValue
        }
        guard let value = Value(rawValue: rawValue) else {
            throw ViftyReviewFixtureError.invalidOption(flag: flag, value: rawValue)
        }
        return value
    }

    private static func stringValue(
        for flag: String,
        in arguments: [String]
    ) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw ViftyReviewFixtureError.missingOptionValue(flag: flag)
        }
        return arguments[index + 1]
    }

    private static func evidenceURL(
        for flag: String,
        in arguments: [String],
        currentDirectory: URL,
        outputDirectory: URL
    ) throws -> URL? {
        guard let rawValue = try stringValue(for: flag, in: arguments) else { return nil }
        let url = URL(fileURLWithPath: rawValue, relativeTo: currentDirectory).standardizedFileURL
        guard relativeArtifactPath(for: url, under: outputDirectory) != nil else {
            throw ViftyReviewFixtureError.outputPathEscapesRoot(flag: flag)
        }
        return url
    }

    private static func relativeArtifactPath(for url: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func timeoutValue(in arguments: [String]) throws -> Double {
        guard let rawValue = try stringValue(for: "--ui-review-timeout-seconds", in: arguments) else {
            return 60
        }
        guard let value = Double(rawValue), value.isFinite, (1...300).contains(value) else {
            throw ViftyReviewFixtureError.invalidTimeout(rawValue)
        }
        return value
    }

    private static func readinessDeadlineValue(in arguments: [String]) throws -> Double? {
        guard let rawValue = try stringValue(
            for: "--ui-review-readiness-deadline-uptime",
            in: arguments
        ) else { return nil }
        guard let value = Double(rawValue), value.isFinite, value > 0 else {
            throw ViftyReviewFixtureError.invalidReadinessDeadline(rawValue)
        }
        return value
    }

    private static func validCaptureID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128,
              let first = value.unicodeScalars.first,
              isASCIIAlphaNumeric(first) else { return false }
        return value.unicodeScalars.allSatisfy {
            isASCIIAlphaNumeric($0) || $0 == "." || $0 == "_" || $0 == "-"
        }
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(scalar.value)
            || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }
}

private extension ViftyReviewFixtureSurface {
    func accepts(window: ViftyReviewFixtureWindow) -> Bool {
        switch self {
        case .main:
            window.expectedContentSize != nil
        case .settingsGeneral, .settingsMenuBar, .settingsNotifications, .settingsAgentWorkflows:
            window == .native
        case .menuPopover:
            window == .popover
        }
    }
}

private extension String {
    var isLowercaseSHA256: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (97...102).contains($0.value)
        }
    }
}

enum ViftyReviewFixtureError: Error, Equatable, LocalizedError {
    case invalidState
    case invalidOption(flag: String, value: String)
    case missingOptionValue(flag: String)
    case invalidCaptureID(String)
    case invalidSurfaceWindow(surface: String, window: String)
    case outputPathEscapesRoot(flag: String)
    case invalidTimeout(String)
    case invalidReadinessDeadline(String)
    case invalidExecutableSHA256
    case executableUnavailable
    case executableHashMismatch
    case observationUnavailable
    case prohibitedOperation(String)
    case unsafeReport

    var errorDescription: String? {
        switch self {
        case .invalidState:
            "The UI review fixture state is missing or unknown."
        case .invalidOption(let flag, let value):
            "Unknown UI review option \(flag) value: \(value)."
        case .missingOptionValue(let flag):
            "UI review option \(flag) requires a value."
        case .invalidCaptureID(let value):
            "UI review capture ID is invalid: \(value)."
        case .invalidSurfaceWindow(let surface, let window):
            "UI review surface \(surface) cannot use window geometry \(window)."
        case .outputPathEscapesRoot(let flag):
            "UI review option \(flag) must stay inside the output directory."
        case .invalidTimeout(let value):
            "UI review timeout must be between 1 and 300 seconds: \(value)."
        case .invalidReadinessDeadline(let value):
            "UI review readiness deadline must be a positive monotonic uptime value: \(value)."
        case .invalidExecutableSHA256:
            "UI review executable SHA-256 must be 64 lowercase hexadecimal characters."
        case .executableUnavailable:
            "UI review debug executable could not be read."
        case .executableHashMismatch:
            "UI review debug executable does not match the caller-supplied SHA-256."
        case .observationUnavailable:
            "UI review native container observation or screenshot target is unavailable."
        case .prohibitedOperation(let operation):
            "UI review fixture blocked prohibited operation: \(operation)."
        case .unsafeReport:
            "UI review fixture recorded a hardware command, external mutation, or real control-path construction."
        }
    }
}

final class ViftyReviewFixtureRecorder: @unchecked Sendable {
    struct Snapshot: Codable, Equatable, Sendable {
        var fixtureConstructions: [String]
        var readOperations: [String]
        var attemptedHardwareCommands: [String]
        var attemptedExternalMutations: [String]
        var realControlPathConstructions: [String]

        var isSafe: Bool {
            attemptedHardwareCommands.isEmpty
                && attemptedExternalMutations.isEmpty
                && realControlPathConstructions.isEmpty
        }
    }

    private let lock = NSLock()
    private var fixtureConstructions: [String] = []
    private var readOperations: [String] = []
    private var attemptedHardwareCommands: [String] = []
    private var attemptedExternalMutations: [String] = []
    private var realControlPathConstructions: [String] = []

    func recordFixtureConstruction(_ name: String) {
        withLock { fixtureConstructions.append(name) }
    }

    func recordRead(_ name: String) {
        withLock { readOperations.append(name) }
    }

    func recordHardwareCommand(_ name: String) {
        withLock { attemptedHardwareCommands.append(name) }
    }

    func recordExternalMutation(_ name: String) {
        withLock { attemptedExternalMutations.append(name) }
    }

    func recordRealControlPathConstruction(_ name: String) {
        withLock { realControlPathConstructions.append(name) }
    }

    func snapshot() -> Snapshot {
        withLock {
            Snapshot(
                fixtureConstructions: fixtureConstructions,
                readOperations: readOperations,
                attemptedHardwareCommands: attemptedHardwareCommands,
                attemptedExternalMutations: attemptedExternalMutations,
                realControlPathConstructions: realControlPathConstructions
            )
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

struct ViftyReviewFixtureSemanticRequest: Codable, Equatable, Sendable {
    var state: String
    var surface: String
    var window: String
    var appearance: String
    var contrast: String
    var transparency: String
    var textSize: String
    var interaction: String

    init(_ request: ViftyReviewFixtureRequest) {
        state = request.state.rawValue
        surface = request.surface.rawValue
        window = request.window.rawValue
        appearance = request.appearance.rawValue
        contrast = request.contrast.rawValue
        transparency = request.transparency.rawValue
        textSize = request.textSize.rawValue
        interaction = request.interaction.rawValue
    }
}

struct ViftyReviewFixtureEnvironmentObservation: Codable, Equatable, Sendable {
    var source: String
    var appearance: String
    var contrast: String
    var transparency: String
    var textSize: String
}

struct ViftyReviewExecutableIdentity: Codable, Equatable, Sendable {
    var processIdentifier: Int32
    var executablePath: String
    var executableSHA256: String
}

struct ViftyReviewWindowSample: Codable, Equatable, Sendable {
    var source: String
    var provenance: String
    var windowIdentifier: String
    var accessibilityIdentifier: String
    var windowNumber: Int
    var windowClass: String
    var containerKind: String
    var isVisible: Bool
    var contentWidth: Int
    var contentHeight: Int
    var backingScaleFactor: Double

    func matches(_ request: ViftyReviewFixtureRequest) -> Bool {
        guard source == "nswindow-content-layout-rect",
              provenance == request.surface.provenance,
              windowIdentifier == request.windowIdentifier,
              accessibilityIdentifier == request.windowAccessibilityIdentifier,
              windowNumber > 0,
              !windowClass.isEmpty,
              containerKind == request.surface.expectedContainerKind,
              isVisible,
              contentWidth > 0,
              contentHeight > 0,
              backingScaleFactor.isFinite,
              backingScaleFactor > 0,
              backingScaleFactor <= 4 else { return false }

        switch request.window {
        case .compact, .standard, .split, .wideWorkbench:
            guard let size = request.window.expectedContentSize else { return false }
            return contentWidth == Int(size.width.rounded())
                && contentHeight == Int(size.height.rounded())
        case .native:
            return contentWidth == 600 && contentHeight == 420
        case .popover:
            return contentWidth == 320 && contentHeight > 0
        }
    }
}

struct ViftyReviewGeometryStabilizer: Sendable {
    private var previousValidSample: ViftyReviewWindowSample?

    mutating func consume(
        _ sample: ViftyReviewWindowSample,
        request: ViftyReviewFixtureRequest
    ) -> ViftyReviewWindowSample? {
        guard sample.matches(request) else {
            previousValidSample = nil
            return nil
        }
        defer { previousValidSample = sample }
        return previousValidSample == sample ? sample : nil
    }

    mutating func reset() {
        previousValidSample = nil
    }
}

struct ViftyReviewRuntimeIdentity: Codable, Equatable, Sendable {
    var processIdentifier: Int32
    var executablePath: String
    var executableSHA256: String
    var windowNumber: Int
    var windowIdentifier: String
    var accessibilityIdentifier: String
    var windowClass: String
    var containerKind: String
    var provenance: String
    var isVisible: Bool
    var contentWidth: Int
    var contentHeight: Int
    var backingScaleFactor: Double

    init(executable: ViftyReviewExecutableIdentity, window: ViftyReviewWindowSample) {
        processIdentifier = executable.processIdentifier
        executablePath = executable.executablePath
        executableSHA256 = executable.executableSHA256
        windowNumber = window.windowNumber
        windowIdentifier = window.windowIdentifier
        accessibilityIdentifier = window.accessibilityIdentifier
        windowClass = window.windowClass
        containerKind = window.containerKind
        provenance = window.provenance
        isVisible = window.isVisible
        contentWidth = window.contentWidth
        contentHeight = window.contentHeight
        backingScaleFactor = window.backingScaleFactor
    }
}

struct ViftyReviewFixtureObservation: Codable, Equatable, Sendable {
    var environment: ViftyReviewFixtureEnvironmentObservation
    var window: ViftyReviewWindowSample

    func matches(_ request: ViftyReviewFixtureRequest) -> Bool {
        environment.source == "swiftui-environment"
            && environment.appearance == request.appearance.rawValue
            && environment.contrast == request.contrast.rawValue
            && environment.transparency == request.transparency.rawValue
            && environment.textSize == request.textSize.rawValue
            && window.matches(request)
    }
}

struct ViftyReviewFixtureReport: Codable, Equatable, Sendable {
    static let schemaVersion = 3

    var schemaVersion: Int
    var captureID: String
    var request: ViftyReviewFixtureSemanticRequest
    var requestSHA256: String
    var debugExecutablePath: String
    var debugExecutableSHA256: String
    var debugBuildProvenance: ViftyBuildProvenance
    var runtimeIdentity: ViftyReviewRuntimeIdentity?
    var observed: ViftyReviewFixtureObservation?
    var screenshot: ViftyReviewScreenshotObservation?
    var phase: String
    var modelStartSkipped: Bool
    var recorder: ViftyReviewFixtureRecorder.Snapshot
    var runtimeFailure: String?
    var passed: Bool
}

@MainActor
final class ViftyReviewFixtureRuntime {
    let request: ViftyReviewFixtureRequest
    let route: ViftyReviewFixtureRoute
    let model: AppModel
    let recorder: ViftyReviewFixtureRecorder
    let daemonInstaller: DaemonInstaller
    let launchCoordinator = ViftyReviewFixtureLaunchCoordinator()

    private let definition: ViftyReviewFixtureDefinition
    private let semanticRequest: ViftyReviewFixtureSemanticRequest
    private let requestSHA256: String
    private let executableIdentity: ViftyReviewExecutableIdentity
    private let buildProvenance: ViftyBuildProvenance
    private var preparationTask: Task<Void, Error>?
    private var completionWaitTask: Task<Void, Never>?
    private var isPrepared = false
    private var isReady = false
    private var geometryStabilizer = ViftyReviewGeometryStabilizer()
    private var observed: ViftyReviewFixtureObservation?
    private var runtimeIdentity: ViftyReviewRuntimeIdentity?
    private var screenshot: ViftyReviewScreenshotObservation?
    private var runtimeFailure: String?
    private var popoverPresenter: ViftyReviewPopoverPresenter?
    private weak var launcherWindow: NSWindow?

    init(
        request: ViftyReviewFixtureRequest,
        executableURL: URL? = Bundle.main.executableURL,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        guard let executableURL else {
            throw ViftyReviewFixtureError.executableUnavailable
        }
        let standardizedExecutableURL = executableURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let executableSHA256: String
        do {
            executableSHA256 = try ViftyReviewFileHash.sha256(at: standardizedExecutableURL)
        } catch {
            throw ViftyReviewFixtureError.executableUnavailable
        }
        if let expected = request.expectedExecutableSHA256,
           expected != executableSHA256 {
            throw ViftyReviewFixtureError.executableHashMismatch
        }
        let embeddedProvenance: ViftyBuildProvenance
        do {
            embeddedProvenance = try ViftyBuildProvenanceReader.read(
                at: standardizedExecutableURL,
                expectedRole: "debug-fixture-app",
                expectedConfiguration: "debug"
            )
        } catch {
            throw ViftyReviewFixtureError.executableUnavailable
        }

        self.request = request
        route = ViftyReviewFixtureRoute(surface: request.surface)
        semanticRequest = ViftyReviewFixtureSemanticRequest(request)
        requestSHA256 = try ViftyReviewCanonicalRequest.sha256(semanticRequest)
        executableIdentity = ViftyReviewExecutableIdentity(
            processIdentifier: processIdentifier,
            executablePath: standardizedExecutableURL.path,
            executableSHA256: executableSHA256
        )
        buildProvenance = embeddedProvenance
        recorder = ViftyReviewFixtureRecorder()
        definition = ViftyReviewFixtureDefinition.resolve(request.state)

        let hardware = ViftyReviewHardware(
            snapshot: definition.snapshot,
            ownership: definition.ownership,
            recorder: recorder
        )
        recorder.recordFixtureConstruction("hardware")
        let coordinator = FanControlCoordinator(
            hardware: hardware,
            uncleanMarker: ManualControlMarker(
                url: request.outputDirectory.appendingPathComponent("manual-control-marker")
            )
        )
        let notificationDeliverer = ViftyReviewNotificationDeliverer(
            authorization: definition.notificationAuthorization,
            recorder: recorder
        )
        recorder.recordFixtureConstruction("notification-center")
        let launchAtLogin = ViftyReviewLaunchAtLoginManager(recorder: recorder)
        recorder.recordFixtureConstruction("login-item")
        let daemonBackend = ViftyReviewDaemonInstallerBackend(
            status: definition.daemonResponding ? .enabled : .notRegistered,
            recorder: recorder
        )
        let daemonInstallService = ViftyReviewDaemonInstallService(recorder: recorder)
        recorder.recordFixtureConstruction("helper-installer")
        daemonInstaller = DaemonInstaller(
            backend: daemonBackend,
            installService: daemonInstallService,
            bundleURL: request.outputDirectory.appendingPathComponent("Vifty.app"),
            lifecycleScriptURL: request.outputDirectory.appendingPathComponent("vifty-helper-lifecycle.sh")
        )

        let fixedNow = definition.capturedAt
        let fixedPower = definition.power
        let fixedThermalPressure = definition.thermalPressure
        let daemonResponding = definition.daemonResponding
        let outputDirectory = request.outputDirectory
        let fixtureModel = AppModel(
            coordinator: coordinator,
            powerReader: { [recorder] in
                recorder.recordRead("power")
                return fixedPower
            },
            thermalReader: { [recorder] in
                recorder.recordRead("thermal-pressure")
                return fixedThermalPressure
            },
            codexUsageReader: { [recorder] in
                recorder.recordRead("codex-usage")
                return nil
            },
            now: { fixedNow },
            notificationDeliverer: notificationDeliverer,
            notificationHistoryStore: LocalNotificationHistoryStore(
                url: outputDirectory.appendingPathComponent("notification-history.json")
            ),
            daemonPing: { [recorder] in
                recorder.recordRead("daemon-ping")
                return daemonResponding
            },
            agentStatusReader: { [recorder] in
                recorder.recordRead("agent-status")
                return nil
            },
            agentRestore: { [recorder] _ in
                recorder.recordHardwareCommand("agent-restore-auto")
                throw ViftyReviewFixtureError.prohibitedOperation("agent-restore-auto")
            },
            profileStore: CurveProfileStore(
                url: outputDirectory.appendingPathComponent("curve-profiles.json")
            ),
            preferencesStore: AppPreferencesStore(
                url: outputDirectory.appendingPathComponent("app-preferences.json"),
                legacyDefaults: nil
            ),
            launchAtLoginManager: launchAtLogin
        )
        fixtureModel.textScale = request.textSize.viftyTextScale
        model = fixtureModel
        recorder.recordFixtureConstruction("daemon-client")
        recorder.recordFixtureConstruction("power-client")
    }

    static func parse(
        arguments: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        executableURL: URL? = Bundle.main.executableURL,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws -> ViftyReviewFixtureRuntime? {
        guard let request = try ViftyReviewFixtureRequest.parse(
            arguments: arguments,
            currentDirectory: currentDirectory
        ) else { return nil }
        return try ViftyReviewFixtureRuntime(
            request: request,
            executableURL: executableURL,
            processIdentifier: processIdentifier
        )
    }

    func prepare() async throws {
        if let preparationTask {
            try await preparationTask.value
            return
        }
        let task = Task { @MainActor [unowned self] in
            try await performPreparation()
        }
        preparationTask = task
        do {
            try await task.value
        } catch {
            preparationTask = nil
            throw error
        }
    }

    private func performPreparation() async throws {
        await model.refreshNotificationAuthorization()
        await model.pollOnce()
        definition.configure(model)
        daemonInstaller.refresh()
        isPrepared = true

        let report = report(phase: "prepared")
        try write(report)
        guard !model.isRunning, report.recorder.isSafe else {
            throw ViftyReviewFixtureError.unsafeReport
        }
    }

    @discardableResult
    func recordObservation(
        _ observation: ViftyReviewFixtureObservation,
        window: NSWindow? = nil
    ) throws -> Bool {
        guard isPrepared else {
            geometryStabilizer.reset()
            return false
        }
        guard !isReady else { return true }
        guard observation.environment.source == "swiftui-environment",
              observation.environment.appearance == request.appearance.rawValue,
              observation.environment.contrast == request.contrast.rawValue,
              observation.environment.transparency == request.transparency.rawValue,
              observation.environment.textSize == request.textSize.rawValue else {
            geometryStabilizer.reset()
            return false
        }
        guard let stableWindow = geometryStabilizer.consume(
            observation.window,
            request: request
        ) else { return false }

        let stableObservation = ViftyReviewFixtureObservation(
            environment: observation.environment,
            window: stableWindow
        )
        var capturedScreenshot: ViftyReviewScreenshotObservation?
        if let screenshotURL = request.screenshotURL {
            guard let window, let contentView = window.contentView else {
                throw ViftyReviewFixtureError.observationUnavailable
            }
            var capture = try ViftyReviewPNGWriter.capture(
                contentView: contentView,
                window: window,
                to: screenshotURL
            )
            guard capture.pointWidth == stableWindow.contentWidth,
                  capture.pointHeight == stableWindow.contentHeight,
                  capture.backingScaleFactor == stableWindow.backingScaleFactor else {
                throw ViftyReviewFixtureError.observationUnavailable
            }
            capture.artifactPath = request.screenshotArtifactPath ?? screenshotURL.lastPathComponent
            capturedScreenshot = capture
        }

        observed = stableObservation
        runtimeIdentity = ViftyReviewRuntimeIdentity(
            executable: executableIdentity,
            window: stableWindow
        )
        screenshot = capturedScreenshot
        isReady = true
        try write(report(phase: "ready"))
        hideLauncherWindowForTargetContainer()
        beginCompletionWaitIfNeeded()
        return true
    }

    func finalize() throws {
        defer {
            popoverPresenter?.dispose()
            popoverPresenter = nil
        }
        let report = report(phase: "final")
        try write(report)
        guard report.passed else { throw ViftyReviewFixtureError.unsafeReport }
    }

    func report(phase: String = "current") -> ViftyReviewFixtureReport {
        let recorderSnapshot = recorder.snapshot()
        return ViftyReviewFixtureReport(
            schemaVersion: ViftyReviewFixtureReport.schemaVersion,
            captureID: request.captureID,
            request: semanticRequest,
            requestSHA256: requestSHA256,
            debugExecutablePath: executableIdentity.executablePath,
            debugExecutableSHA256: executableIdentity.executableSHA256,
            debugBuildProvenance: buildProvenance,
            runtimeIdentity: runtimeIdentity,
            observed: observed,
            screenshot: screenshot,
            phase: phase,
            modelStartSkipped: !model.isRunning,
            recorder: recorderSnapshot,
            runtimeFailure: runtimeFailure,
            passed: isPrepared
                && isReady
                && !model.isRunning
                && recorderSnapshot.isSafe
                && runtimeFailure == nil
                && runtimeIdentity != nil
                && observed?.matches(request) == true
                && (request.screenshotURL == nil || screenshot != nil)
        )
    }

    private func beginCompletionWaitIfNeeded() {
        guard completionWaitTask == nil,
              let completionFileURL = request.completionFileURL else { return }
        let attemptCount = max(1, Int((request.timeoutSeconds / 0.05).rounded(.up)))
        completionWaitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<attemptCount {
                if FileManager.default.fileExists(atPath: completionFileURL.path) {
                    NSApplication.shared.terminate(nil)
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
            self.runtimeFailure = "completion-timeout"
            try? self.write(self.report(phase: "final"))
            NSApplication.shared.terminate(nil)
        }
    }

    func recordFailure(_ error: Error) {
        runtimeFailure = error.localizedDescription
        try? write(report(phase: "final"))
    }

    var hasReadyObservation: Bool {
        isReady
    }

    func registerLauncherWindow(_ window: NSWindow) {
        ViftyReviewFixtureWindowConfigurator.isolatePersistentState(window)
        launcherWindow = window
    }

    func showReviewPopover() {
        if popoverPresenter == nil {
            popoverPresenter = ViftyReviewPopoverPresenter(runtime: self)
        }
        popoverPresenter?.show()
    }

    private func hideLauncherWindowForTargetContainer() {
        switch route {
        case .main:
            break
        case .settings, .popover:
            guard launcherWindow !== observedWindow else {
                launcherWindow = nil
                return
            }
            launcherWindow?.orderOut(nil)
        }
    }

    private var observedWindow: NSWindow? {
        guard let windowNumber = runtimeIdentity?.windowNumber else { return nil }
        return NSApplication.shared.windows.first { $0.windowNumber == windowNumber }
    }

    private func write(_ report: ViftyReviewFixtureReport) throws {
        try FileManager.default.createDirectory(
            at: request.outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        try data.write(
            to: request.outputDirectory.appendingPathComponent("fixture-report.json"),
            options: .atomic
        )
    }
}

@MainActor
struct ViftyReviewFixtureSceneHost<Content: View>: View {
    @State private var observationGeneration = 0
    @State private var observationEnabled = false
    let runtime: ViftyReviewFixtureRuntime
    let provenance: String
    private let content: Content

    init(
        runtime: ViftyReviewFixtureRuntime,
        provenance: String,
        @ViewBuilder content: () -> Content
    ) {
        self.runtime = runtime
        self.provenance = provenance
        self.content = content()
    }

    var body: some View {
        sizedContent
            .environmentObject(runtime.model)
            .preferredColorScheme(runtime.request.appearance.colorScheme)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(runtime.request.rootAccessibilityIdentifier)
            .background {
                if observationEnabled {
                    ViftyReviewFixtureObservationBridge(
                        request: runtime.request,
                        provenance: provenance,
                        generation: observationGeneration
                    ) { observation, window in
                        do {
                            try runtime.recordObservation(observation, window: window)
                        } catch {
                            runtime.recordFailure(error)
                        }
                    }
                    .id(observationGeneration)
                }
            }
            // Keep Vifty's app-owned scale outside the observation background
            // so the reviewed content and observer resolve the same value.
            .viftyTextScale(runtime.model.textScale)
            .task {
                do {
                    try await runtime.prepare()
                    if runtime.route == .popover {
                        // A newly ordered _NSPopoverWindow can expose final AppKit
                        // geometry before WindowServer can capture its native surface.
                        try await Task.sleep(for: .milliseconds(250))
                    }
                    observationEnabled = true
                    observationGeneration &+= 1
                } catch {
                    runtime.recordFailure(error)
                }
            }
    }

    @ViewBuilder
    private var sizedContent: some View {
        switch runtime.request.window {
        case .compact, .standard, .split, .wideWorkbench:
            if let size = runtime.request.window.expectedContentSize {
                content.frame(width: size.width, height: size.height)
            }
        case .native:
            content.frame(width: 600, height: 420)
        case .popover:
            content.frame(width: 320)
        }
    }
}

@MainActor
struct ViftyReviewFixtureLaunchBridge: View {
    @Environment(\.openSettings) private var openSettings
    let runtime: ViftyReviewFixtureRuntime

    var body: some View {
        Color.clear
            .frame(
                width: ViftyReviewFixtureWindow.native.size.width,
                height: ViftyReviewFixtureWindow.native.size.height
            )
            .background {
                ViftyReviewLauncherWindowBridge { window in
                    runtime.registerLauncherWindow(window)
                }
            }
            .task {
                do {
                    try await runtime.prepare()
                    runtime.launchCoordinator.launch(
                        route: runtime.route,
                        openSettings: { _ in openSettings() },
                        showPopover: { runtime.showReviewPopover() }
                    )
                } catch {
                    runtime.recordFailure(error)
                }
            }
    }
}

@MainActor
private struct ViftyReviewLauncherWindowBridge: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ViftyReviewLauncherWindowView {
        let view = ViftyReviewLauncherWindowView(frame: .zero)
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ViftyReviewLauncherWindowView, context: Context) {
        nsView.onWindow = onWindow
        nsView.scheduleRegistration()
    }
}

@MainActor
private final class ViftyReviewLauncherWindowView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var registrationScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleRegistration()
    }

    func scheduleRegistration() {
        guard !registrationScheduled else { return }
        registrationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            registrationScheduled = false
            if let window {
                onWindow?(window)
            }
        }
    }
}

@MainActor
private struct ViftyReviewFixtureObservationBridge: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.viftyTextScale) private var textScale

    let request: ViftyReviewFixtureRequest
    let provenance: String
    let generation: Int
    let onObservation: (ViftyReviewFixtureObservation, NSWindow) -> Void

    func makeNSView(context: Context) -> ViftyReviewFixtureWindowObserverView {
        let view = ViftyReviewFixtureWindowObserverView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(
        _ nsView: ViftyReviewFixtureWindowObserverView,
        context: Context
    ) {
        configure(nsView)
        nsView.scheduleObservationPair()
    }

    private func configure(_ view: ViftyReviewFixtureWindowObserverView) {
        let environment = ViftyReviewFixtureEnvironmentObservation(
            source: "swiftui-environment",
            appearance: colorScheme == .dark ? "dark" : "light",
            contrast: colorSchemeContrast == .increased ? "increased" : "standard",
            transparency: reducesTransparency ? "reduced" : "standard",
            textSize: observedTextSize
        )
        view.onWindowObservation = { window in
            ViftyReviewFixtureWindowConfigurator.configure(
                window,
                for: request
            )
            let contentSize = window.contentLayoutRect.size
            onObservation(ViftyReviewFixtureObservation(
                environment: environment,
                window: ViftyReviewWindowSample(
                    source: "nswindow-content-layout-rect",
                    provenance: provenance,
                    windowIdentifier: window.identifier?.rawValue ?? "",
                    accessibilityIdentifier: window.accessibilityIdentifier(),
                    windowNumber: window.windowNumber,
                    windowClass: NSStringFromClass(type(of: window)),
                    containerKind: request.surface.expectedContainerKind,
                    isVisible: window.isVisible,
                    contentWidth: Int(contentSize.width.rounded()),
                    contentHeight: Int(contentSize.height.rounded()),
                    backingScaleFactor: window.backingScaleFactor
                )
            ), window)
        }
    }

    private var observedTextSize: String {
        switch textScale {
        case .standard:
            "standard"
        case .accessibility:
            "accessibility"
        case .large:
            "large"
        }
    }
}

@MainActor
enum ViftyReviewFixtureWindowConfigurator {
    static func isolatePersistentState(_ window: NSWindow) {
        window.isRestorable = false
        _ = window.setFrameAutosaveName("")
    }

    static func configure(
        _ window: NSWindow,
        for request: ViftyReviewFixtureRequest
    ) {
        let identifier = NSUserInterfaceItemIdentifier(request.windowIdentifier)
        window.identifier = identifier
        window.setAccessibilityIdentifier(request.windowAccessibilityIdentifier)
        isolatePersistentState(window)

        switch request.window {
        case .compact, .standard, .split, .wideWorkbench, .native:
            let observedSize = window.contentLayoutRect.size
            let requestedSize = request.window.size
            guard Int(observedSize.width.rounded()) != Int(requestedSize.width.rounded())
                    || Int(observedSize.height.rounded()) != Int(requestedSize.height.rounded()) else {
                return
            }
            window.setContentSize(requestedSize)
            window.contentView?.layoutSubtreeIfNeeded()
        case .popover:
            break
        }
    }
}

@MainActor
private final class ViftyReviewFixtureWindowObserverView: NSView {
    var onWindowObservation: ((NSWindow) -> Void)?
    private var observationPairScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleObservationPair()
    }

    override func layout() {
        super.layout()
        scheduleObservationPair()
    }

    func scheduleObservationPair() {
        guard !observationPairScheduled else { return }
        observationPairScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.emitObservation()
            DispatchQueue.main.async { [weak self] in
                self?.emitObservation()
                self?.observationPairScheduled = false
            }
        }
    }

    private func emitObservation() {
        guard let window else { return }
        onWindowObservation?(window)
    }
}

private struct ViftyReviewFixtureDefinition: Sendable {
    let state: ViftyReviewFixtureState
    let capturedAt: Date
    let snapshot: HardwareSnapshot
    let ownership: FanControlOwnershipStatus
    let power: PowerSnapshot
    let thermalPressure: ThermalPressure
    let daemonResponding: Bool
    let notificationAuthorization: LocalNotificationAuthorization

    static func resolve(_ state: ViftyReviewFixtureState) -> ViftyReviewFixtureDefinition {
        let capturedAt = Date(timeIntervalSince1970: 1_789_387_200)
        let baseSensors = [
            TemperatureSensor(id: "cpu", name: "CPU Proximity", celsius: 62, source: .smc),
            TemperatureSensor(id: "gpu", name: "GPU Hotspot", celsius: 68, source: .hid),
            TemperatureSensor(id: "palm", name: "Palm Rest", celsius: 36, source: .hid)
        ]
        let automaticFans = fans(
            leftRPM: 2_250,
            rightRPM: 2_350,
            leftMode: .automatic,
            rightMode: .automatic,
            leftTarget: nil,
            rightTarget: nil
        )
        let power = PowerSnapshot(
            percent: 78,
            isCharging: true,
            isPluggedIn: true,
            batteryVoltageVolts: 12.1,
            batteryCurrentAmps: 1.4,
            batteryPowerWatts: 16.9,
            cycleCount: 84,
            temperatureCelsius: 31.2,
            healthPercent: 96,
            condition: "Normal",
            adapter: PowerAdapter(
                name: "USB-C Power Adapter",
                manufacturer: "Apple",
                ratedWatts: 96,
                negotiatedVoltageVolts: 20,
                negotiatedCurrentAmps: 4.8
            ),
            capturedAt: capturedAt
        )

        var snapshot = HardwareSnapshot(
            fans: automaticFans,
            temperatureSensors: baseSensors,
            modelIdentifier: "MacBookPro18,3 · UI Review Fixture",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: capturedAt
        )
        var ownership = FanControlOwnershipStatus.osManaged
        var daemonResponding = true
        var notificationAuthorization = LocalNotificationAuthorization.authorized
        var thermalPressure = ThermalPressure.nominal

        switch state {
        case .activeManual:
            snapshot.fans = fans(
                leftRPM: 3_800,
                rightRPM: 4_400,
                leftMode: .forced,
                rightMode: .forced,
                leftTarget: 3_800,
                rightTarget: 4_400
            )
            ownership = FanControlOwnershipStatus(
                owner: .manual(sessionID: "fixture-manual-session"),
                phase: .active,
                transactionID: "fixture-manual-transaction",
                expectedFanIDs: [0, 1],
                recoveryPending: false
            )
        case .recoveryMixedOwnership:
            snapshot.fans = fans(
                leftRPM: 2_200,
                rightRPM: 4_100,
                leftMode: .automatic,
                rightMode: .forced,
                leftTarget: nil,
                rightTarget: 4_100
            )
            ownership = FanControlOwnershipStatus(
                owner: .recovery,
                phase: .restorePending,
                transactionID: "fixture-recovery-transaction",
                expectedFanIDs: [0, 1],
                confirmedOSManagedFanIDs: [0],
                recoveryPending: true,
                errorCode: "right-fan-still-forced"
            )
            thermalPressure = .serious
        case .helperBlocked:
            daemonResponding = false
        case .notificationDenied:
            notificationAuthorization = .denied
        case .selectedVersusHighestTemperature:
            snapshot.temperatureSensors = [
                TemperatureSensor(id: "cpu-efficiency", name: "CPU Efficiency", celsius: 64, source: .smc),
                TemperatureSensor(id: "gpu-hotspot", name: "GPU Hotspot", celsius: 83, source: .hid),
                TemperatureSensor(id: "palm", name: "Palm Rest", celsius: 37, source: .hid)
            ]
        case .editedProfile:
            snapshot.fans = fans(
                leftRPM: 2_250,
                rightRPM: 2_350,
                leftMode: .automatic,
                rightMode: .automatic,
                leftTarget: nil,
                rightTarget: nil,
                leftMinimumRPM: 1_499,
                leftMaximumRPM: 4_296,
                rightMinimumRPM: 1_499,
                rightMaximumRPM: 4_744
            )
        case .rawSpikeTelemetry:
            snapshot.temperatureSensors = [
                TemperatureSensor(id: "cpu", name: "CPU Proximity", celsius: 50, source: .smc),
                TemperatureSensor(id: "gpu", name: "GPU Hotspot", celsius: 68, source: .hid),
                TemperatureSensor(id: "palm", name: "Palm Rest", celsius: 36, source: .hid)
            ]
            snapshot.fans = fans(
                leftRPM: 2_400,
                rightRPM: 2_500,
                leftMode: .automatic,
                rightMode: .automatic,
                leftTarget: nil,
                rightTarget: nil
            )
        case .healthyAuto, .divergentPerFanCurveDraft:
            break
        }

        return ViftyReviewFixtureDefinition(
            state: state,
            capturedAt: capturedAt,
            snapshot: snapshot,
            ownership: ownership,
            power: power,
            thermalPressure: thermalPressure,
            daemonResponding: daemonResponding,
            notificationAuthorization: notificationAuthorization
        )
    }

    @MainActor
    func configure(_ model: AppModel) {
        model.menuBarDisplayMode = .compactSummary

        switch state {
        case .healthyAuto:
            break
        case .divergentPerFanCurveDraft:
            model.selectedMode = .curve
            model.selectedSensorID = "cpu"
            model.usePerFanOverrides = true
            model.fanOverrides = [
                FanCurveOverride(fanID: 0, startRPM: 1_700, midRPM: 3_400, maxRPM: 5_700),
                FanCurveOverride(fanID: 1, startRPM: 2_100, midRPM: 4_200, maxRPM: 6_400)
            ]
            model.markFanControlDraftPending()
        case .activeManual:
            model.selectedMode = .fixed
            model.fixedRPM = 3_800
            model.usePerFanFixedRPM = true
            model.fixedFanTargets = [
                FixedFanTarget(fanID: 0, rpm: 3_800),
                FixedFanTarget(fanID: 1, rpm: 4_400)
            ]
            model.controlState = ControlState(
                mode: .fixedRPM(3_800),
                lastAppliedRPM: [0: 3_800, 1: 4_400],
                statusMessage: "Fixed per-fan RPM",
                manualControlActive: true
            )
            model.manualSessionExpiresAt = capturedAt.addingTimeInterval(30 * 60)
            model.configureReviewFixtureAppliedFanControlDraft()
        case .recoveryMixedOwnership:
            model.controlState = ControlState(
                mode: .auto,
                statusMessage: "Auto recovery pending",
                manualControlActive: true
            )
            model.lastError = "Right fan still requires Auto confirmation."
        case .helperBlocked:
            model.lastError = "Fan helper unavailable in this deterministic fixture."
        case .notificationDenied:
            model.notificationSettings = LocalNotificationSettings(
                helperFailure: true,
                elevatedThermalPressure: true,
                autoRestoreFailure: true,
                pluggedInBatteryDrain: true,
                agentCoolingAttention: true
            )
        case .editedProfile:
            let profile = CurveProfile(
                id: UUID(uuidString: "68B59C23-06DA-4B06-A727-4BFD14DC12A1")!,
                name: "Quiet Build",
                sensorID: "cpu",
                startTemp: 54,
                startRPM: 1_600,
                midTemp: 69,
                midRPM: 3_300,
                maxTemp: 84,
                maxRPM: 5_800
            )
            model.savedProfiles = [profile]
            model.selectedCurveProfileID = profile.id
            model.selectedMode = .curve
            model.selectedSensorID = "cpu"
            model.curveStartTemp = 52
            model.curveStartRPM = 1_750
            model.curveMidTemp = 67
            model.curveMidRPM = 3_600
            model.curveMaxTemp = 82
            model.curveMaxRPM = 6_000
            model.markFanControlDraftPending()
        case .selectedVersusHighestTemperature:
            model.selectedMode = .curve
            model.selectedSensorID = "cpu-efficiency"
            var history = TelemetryHistory(limit: 5)
            history.append(TelemetrySample(
                capturedAt: capturedAt,
                selectedTemperatureID: "cpu-efficiency",
                selectedTemperatureName: "CPU Efficiency",
                selectedTemperatureCelsius: 64,
                temperatureWasUserSelected: true,
                temperatureRole: .curveSensor,
                highestTemperatureCelsius: 83,
                firstFanRPM: 2_250,
                averageFanRPM: 2_300,
                batteryPowerWatts: 16.9,
                thermalPressure: .nominal
            ))
            model.telemetryHistory = history
            model.markFanControlDraftPending()
        case .rawSpikeTelemetry:
            var history = TelemetryHistory(limit: 5)
            let temperatures = [50.0, 50.0, 100.0, 50.0, 50.0]
            let latestFirstFanRPM = snapshot.fans.first?.currentRPM
            let latestAverageFanRPM = snapshot.fans.isEmpty
                ? nil
                : Double(snapshot.fans.reduce(0) { $0 + $1.currentRPM })
                    / Double(snapshot.fans.count)
            let currentHighestTemperature = snapshot.highestTemperature?.celsius
            for (index, temperature) in temperatures.enumerated() {
                let samplesUntilCurrent = temperatures.count - 1 - index
                history.append(TelemetrySample(
                    capturedAt: capturedAt.addingTimeInterval(-Double(samplesUntilCurrent)),
                    selectedTemperatureID: "cpu",
                    selectedTemperatureName: "CPU Proximity",
                    selectedTemperatureCelsius: temperature,
                    temperatureRole: .automaticCPU,
                    highestTemperatureCelsius: max(currentHighestTemperature ?? temperature, temperature),
                    firstFanRPM: latestFirstFanRPM.map { $0 - (samplesUntilCurrent * 100) },
                    averageFanRPM: latestAverageFanRPM.map { $0 - Double(samplesUntilCurrent * 100) },
                    batteryPowerWatts: power.batteryPowerWatts,
                    thermalPressure: index == 2 ? .serious : .nominal
                ))
            }
            model.telemetryHistory = history
        }
    }

    private static func fans(
        leftRPM: Int,
        rightRPM: Int,
        leftMode: FanHardwareMode,
        rightMode: FanHardwareMode,
        leftTarget: Int?,
        rightTarget: Int?,
        leftMinimumRPM: Int = 1_200,
        leftMaximumRPM: Int = 6_200,
        rightMinimumRPM: Int = 1_300,
        rightMaximumRPM: Int = 6_600
    ) -> [Fan] {
        [
            Fan(
                id: 0,
                name: "Left Fan",
                currentRPM: leftRPM,
                minimumRPM: leftMinimumRPM,
                maximumRPM: leftMaximumRPM,
                controllable: true,
                hardwareMode: leftMode,
                hardwareModeKey: "F0Md",
                targetRPM: leftTarget
            ),
            Fan(
                id: 1,
                name: "Right Fan",
                currentRPM: rightRPM,
                minimumRPM: rightMinimumRPM,
                maximumRPM: rightMaximumRPM,
                controllable: true,
                hardwareMode: rightMode,
                hardwareModeKey: "F1md",
                targetRPM: rightTarget
            )
        ]
    }
}

private actor ViftyReviewHardware: HardwareService {
    private let fixtureSnapshot: HardwareSnapshot
    private let ownership: FanControlOwnershipStatus
    private let recorder: ViftyReviewFixtureRecorder

    init(
        snapshot: HardwareSnapshot,
        ownership: FanControlOwnershipStatus,
        recorder: ViftyReviewFixtureRecorder
    ) {
        fixtureSnapshot = snapshot
        self.ownership = ownership
        self.recorder = recorder
    }

    func snapshot() async throws -> HardwareSnapshot {
        recorder.recordRead("hardware-snapshot")
        return fixtureSnapshot
    }

    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        recorder.recordRead("fan-control-ownership")
        return ownership
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        recorder.recordHardwareCommand("apply-fan-\(fan.id)")
        throw ViftyReviewFixtureError.prohibitedOperation("apply-fan-\(fan.id)")
    }

    func restoreAuto(fan: Fan) async throws {
        recorder.recordHardwareCommand("restore-auto-fan-\(fan.id)")
        throw ViftyReviewFixtureError.prohibitedOperation("restore-auto-fan-\(fan.id)")
    }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        recorder.recordHardwareCommand("apply-manual-transaction")
        throw ViftyReviewFixtureError.prohibitedOperation("apply-manual-transaction")
    }

    func applyAgentFanControl(
        _ request: AgentFanControlRequest
    ) async throws -> FanControlTransactionResult {
        recorder.recordHardwareCommand("apply-agent-transaction")
        throw ViftyReviewFixtureError.prohibitedOperation("apply-agent-transaction")
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        recorder.recordHardwareCommand("restore-all-auto")
        throw ViftyReviewFixtureError.prohibitedOperation("restore-all-auto")
    }
}

@MainActor
private final class ViftyReviewNotificationDeliverer: LocalNotificationDelivering {
    private let authorization: LocalNotificationAuthorization
    private let recorder: ViftyReviewFixtureRecorder

    init(
        authorization: LocalNotificationAuthorization,
        recorder: ViftyReviewFixtureRecorder
    ) {
        self.authorization = authorization
        self.recorder = recorder
    }

    func deliver(_ notification: LocalNotification) async -> Bool {
        recorder.recordExternalMutation("notification-delivery")
        return false
    }

    func authorizationStatus() async -> LocalNotificationAuthorization {
        recorder.recordRead("notification-authorization")
        return authorization
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        recorder.recordExternalMutation("notification-authorization-request")
        return authorization
    }

    func deliverTestNotification() async -> Bool {
        recorder.recordExternalMutation("notification-test")
        return false
    }

    func openNotificationSettings() async -> Bool {
        recorder.recordExternalMutation("notification-settings")
        return false
    }
}

@MainActor
private final class ViftyReviewLaunchAtLoginManager: LaunchAtLoginManaging {
    private let recorder: ViftyReviewFixtureRecorder

    init(recorder: ViftyReviewFixtureRecorder) {
        self.recorder = recorder
    }

    var status: LaunchAtLoginStatus {
        recorder.recordRead("login-item-status")
        return .disabled
    }

    func setEnabled(_ enabled: Bool) throws {
        recorder.recordExternalMutation("login-item-change")
        throw ViftyReviewFixtureError.prohibitedOperation("login-item-change")
    }

    func openLoginItemsSettings() {
        recorder.recordExternalMutation("login-item-settings")
    }
}

@MainActor
private final class ViftyReviewDaemonInstallerBackend: DaemonInstallerBackend {
    let status: DaemonInstallerBackendStatus
    let requiresBundledDaemonResources = false
    private let recorder: ViftyReviewFixtureRecorder

    init(
        status: DaemonInstallerBackendStatus,
        recorder: ViftyReviewFixtureRecorder
    ) {
        self.status = status
        self.recorder = recorder
    }

    func register() throws {
        recorder.recordExternalMutation("helper-service-register")
        throw ViftyReviewFixtureError.prohibitedOperation("helper-service-register")
    }

    func openLoginItemsSettings() {
        recorder.recordExternalMutation("helper-login-items-settings")
    }
}

private actor ViftyReviewDaemonInstallService: DaemonInstallServicing {
    private let recorder: ViftyReviewFixtureRecorder

    init(recorder: ViftyReviewFixtureRecorder) {
        self.recorder = recorder
    }

    func perform(
        operation: DaemonInstallOperation,
        appBundleURL: URL,
        lifecycleScriptURL: URL
    ) async -> DaemonInstallResult {
        recorder.recordExternalMutation("helper-lifecycle-\(operation.rawValue)")
        return DaemonInstallResult(
            outcome: .blocked,
            operatorMessage: "Fixture helper lifecycle blocked."
        )
    }
}
#endif
