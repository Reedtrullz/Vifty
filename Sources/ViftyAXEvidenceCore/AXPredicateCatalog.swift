import Foundation

public enum AXEvidenceIdentifier {
    public static let controlSession = "vifty.ax.control-session"
    public static let controlSessionTitle = "vifty.ax.control-session.title"
    public static let controlSessionSummary = "vifty.ax.control-session.summary"

    public static let fanStatus = "vifty.ax.fan-status"
    public static let leftFanDraftTarget = "vifty.ax.fan-status.fan-0.draft-target"
    public static let rightFanDraftTarget = "vifty.ax.fan-status.fan-1.draft-target"

    public static let curveChart = "vifty.ax.curve.chart"
    public static let curveSeparateFans = "vifty.ax.curve.separate-fans"
    public static let curveEffectiveSummaries = "vifty.ax.curve.effective-summaries"
    public static let leftFanEffectiveSummary = "vifty.ax.curve.fan-0.effective-summary"
    public static let rightFanEffectiveSummary = "vifty.ax.curve.fan-1.effective-summary"
    public static let curveEffectiveSummaryItems = [
        leftFanEffectiveSummary,
        rightFanEffectiveSummary
    ]
    public static let curveStartTemperature = "vifty.ax.curve.start.temperature"
    public static let curveStartRPM = "vifty.ax.curve.start.rpm"
    public static let curveRampTemperature = "vifty.ax.curve.ramp.temperature"
    public static let curveRampRPM = "vifty.ax.curve.ramp.rpm"
    public static let curveHighTemperature = "vifty.ax.curve.high.temperature"
    public static let curveHighRPM = "vifty.ax.curve.high.rpm"
    public static let curveControls = [
        curveStartTemperature,
        curveStartRPM,
        curveRampTemperature,
        curveRampRPM,
        curveHighTemperature,
        curveHighRPM
    ]

    public static let sensorList = "vifty.ax.sensors"
    public static let sensorCPU = "vifty.ax.sensor.cpu-efficiency"
    public static let sensorGPU = "vifty.ax.sensor.gpu-hotspot"
    public static let sensorPalm = "vifty.ax.sensor.palm"

    public static let temperatureMetrics = "vifty.ax.temperature.metrics"
    public static let curveSensorMetric = "vifty.ax.temperature.curve-sensor"
    public static let highestTemperatureMetric = "vifty.ax.temperature.highest"

    public static let notifications = "vifty.ax.notifications"
    public static let notificationOpenSettings = "vifty.ax.notifications.open-settings"
    public static let notificationSendTest = "vifty.ax.notifications.send-test"
    public static let notificationHelperFailure = "vifty.ax.notifications.event.helper-failure"
    public static let notificationThermalPressure = "vifty.ax.notifications.event.high-thermal-pressure"
    public static let notificationAutoRestore = "vifty.ax.notifications.event.auto-restore-failure"
    public static let notificationBatteryDrain = "vifty.ax.notifications.event.plugged-in-battery-drain"
    public static let notificationAgentCooling = "vifty.ax.notifications.event.agent-cooling-attention"
    public static let notificationEvents = [
        notificationHelperFailure,
        notificationThermalPressure,
        notificationAutoRestore,
        notificationBatteryDrain,
        notificationAgentCooling
    ]

    public static let settings = "vifty.ax.settings"
    public static let settingsTabs = "vifty.ax.settings.tabs"
    public static let settingsTabGeneral = "vifty.ax.settings.tab.general"
    public static let settingsTabMenuBar = "vifty.ax.settings.tab.menu-bar"
    public static let settingsTabNotifications = "vifty.ax.settings.tab.notifications"
    public static let settingsTabAgentWorkflows = "vifty.ax.settings.tab.agent-workflows"
    public static let settingsPaneGeneral = "vifty.ax.settings.pane.general"
    public static let settingsLaunchAtLogin = "vifty.ax.settings.general.launch-at-login"
    public static let settingsUpdateAutomatic = "vifty.ax.settings.general.update.automatic"
    public static let settingsUpdateStatus = "vifty.ax.settings.general.update.status"
    public static let settingsUpdateCheck = "vifty.ax.settings.general.update.check"
    public static let settingsUpdateLatest = "vifty.ax.settings.general.update.latest"

    public static let mainScroll = "vifty.ax.scroll.main"
    public static let mainScrollEnd = "vifty.ax.scroll.main.end"
    public static let settingsGeneralScroll = "vifty.ax.scroll.settings.general"
    public static let settingsGeneralScrollEnd = "vifty.ax.scroll.settings.general.end"
    public static let settingsMenuBarScroll = "vifty.ax.scroll.settings.menu-bar"
    public static let settingsMenuBarScrollEnd = "vifty.ax.scroll.settings.menu-bar.end"
    public static let settingsNotificationsScroll = "vifty.ax.scroll.settings.notifications"
    public static let settingsNotificationsScrollEnd = "vifty.ax.scroll.settings.notifications.end"
    public static let settingsAgentWorkflowsScroll = "vifty.ax.scroll.settings.agent-workflows"
    public static let settingsAgentWorkflowsScrollEnd = "vifty.ax.scroll.settings.agent-workflows.end"
}

public struct AXScrollPredicateContract: Equatable, Sendable {
    public let scrollIdentifier: String
    public let anchorIdentifier: String
    public let allowsCaptureRootScrollAreaFallback: Bool

    public init(
        scrollIdentifier: String,
        anchorIdentifier: String,
        allowsCaptureRootScrollAreaFallback: Bool = false
    ) {
        self.scrollIdentifier = scrollIdentifier
        self.anchorIdentifier = anchorIdentifier
        self.allowsCaptureRootScrollAreaFallback = allowsCaptureRootScrollAreaFallback
    }
}

public enum AXPredicateError: Error, Equatable {
    case unknownPredicate(String)
}

public enum AXPredicateCatalog {
    private static let updateLatestHelp =
        "Opens Vifty's fixed GitHub release page in your default browser. "
        + "Vifty does not download or install the update."
    private static let updateRefreshHelp =
        "Refreshes GitHub release availability without downloading or installing."

    public static let ids = [
        "confirmed-owner-headline",
        "correct-per-fan-target",
        "six-adjustable-point-controls",
        "sensor-selected-trait-value",
        "explicit-temperature-role",
        "notification-actions",
        "settings-logical-traversal",
        "no-duplicate-chart-elements",
        "compact-main-scroll-reachable",
        "settings-general-scroll-reachable",
        "settings-menu-bar-scroll-reachable",
        "settings-notifications-scroll-reachable",
        "settings-agent-workflows-scroll-reachable"
    ]

    private static let requests: [String: AXSemanticRequest] = [
        "confirmed-owner-headline": request(state: "active-manual"),
        "correct-per-fan-target": request(state: "divergent-per-fan-curve-draft"),
        "six-adjustable-point-controls": request(state: "divergent-per-fan-curve-draft"),
        "sensor-selected-trait-value": request(state: "selected-vs-highest-temperature"),
        "explicit-temperature-role": request(state: "selected-vs-highest-temperature"),
        "notification-actions": request(
            state: "notification-denied",
            surface: "settings-notifications",
            window: "native"
        ),
        "settings-logical-traversal": request(
            state: "healthy-auto",
            surface: "settings-general",
            window: "native"
        ),
        "no-duplicate-chart-elements": request(state: "divergent-per-fan-curve-draft"),
        "compact-main-scroll-reachable": request(
            state: "healthy-auto",
            textSize: "accessibility",
            window: "780x480",
            interaction: "structural-scroll"
        ),
        "settings-general-scroll-reachable": request(
            state: "healthy-auto",
            surface: "settings-general",
            textSize: "accessibility",
            window: "native",
            interaction: "structural-scroll"
        ),
        "settings-menu-bar-scroll-reachable": request(
            state: "healthy-auto",
            surface: "settings-menu-bar",
            textSize: "accessibility",
            window: "native",
            interaction: "structural-scroll"
        ),
        "settings-notifications-scroll-reachable": request(
            state: "notification-denied",
            surface: "settings-notifications",
            textSize: "accessibility",
            window: "native",
            interaction: "structural-scroll"
        ),
        "settings-agent-workflows-scroll-reachable": request(
            state: "healthy-auto",
            surface: "settings-agent-workflows",
            textSize: "accessibility",
            window: "native",
            interaction: "structural-scroll"
        )
    ]

    private static let scrollContracts: [String: AXScrollPredicateContract] = [
        "compact-main-scroll-reachable": AXScrollPredicateContract(
            scrollIdentifier: AXEvidenceIdentifier.mainScroll,
            anchorIdentifier: AXEvidenceIdentifier.mainScrollEnd
        ),
        "settings-general-scroll-reachable": AXScrollPredicateContract(
            scrollIdentifier: AXEvidenceIdentifier.settingsGeneralScroll,
            anchorIdentifier: AXEvidenceIdentifier.settingsGeneralScrollEnd,
            allowsCaptureRootScrollAreaFallback: true
        ),
        "settings-menu-bar-scroll-reachable": AXScrollPredicateContract(
            scrollIdentifier: AXEvidenceIdentifier.settingsMenuBarScroll,
            anchorIdentifier: AXEvidenceIdentifier.settingsMenuBarScrollEnd,
            allowsCaptureRootScrollAreaFallback: true
        ),
        "settings-notifications-scroll-reachable": AXScrollPredicateContract(
            scrollIdentifier: AXEvidenceIdentifier.settingsNotificationsScroll,
            anchorIdentifier: AXEvidenceIdentifier.settingsNotificationsScrollEnd,
            allowsCaptureRootScrollAreaFallback: true
        ),
        "settings-agent-workflows-scroll-reachable": AXScrollPredicateContract(
            scrollIdentifier: AXEvidenceIdentifier.settingsAgentWorkflowsScroll,
            anchorIdentifier: AXEvidenceIdentifier.settingsAgentWorkflowsScrollEnd,
            allowsCaptureRootScrollAreaFallback: true
        )
    ]

    public static func expectedRequest(for id: String) -> AXSemanticRequest? {
        requests[id]
    }

    public static func scrollContract(for id: String) -> AXScrollPredicateContract? {
        scrollContracts[id]
    }

    public static func evaluate(id: String, capture: AXRawCapture) throws -> AXAssertion {
        guard let expectedRequest = requests[id] else {
            throw AXPredicateError.unknownPredicate(id)
        }

        var failures: [String] = []
        var paths: [String] = []
        validateCaptureContract(
            id: id,
            expectedRequest: expectedRequest,
            capture: capture,
            failures: &failures
        )

        switch id {
        case "confirmed-owner-headline":
            validateOwner(capture, paths: &paths, failures: &failures)
        case "correct-per-fan-target":
            validateFanTargets(capture, paths: &paths, failures: &failures)
        case "six-adjustable-point-controls":
            validateSeparateFanCurvesToggle(capture, paths: &paths, failures: &failures)
            validateCurveControls(capture, paths: &paths, failures: &failures)
            validateEffectiveCurveSummaries(capture, paths: &paths, failures: &failures)
            validateNoDuplicateChartElements(capture, failures: &failures)
        case "sensor-selected-trait-value":
            validateSensors(capture, paths: &paths, failures: &failures)
        case "explicit-temperature-role":
            validateTemperatureRoles(capture, paths: &paths, failures: &failures)
        case "notification-actions":
            validateNotifications(capture, paths: &paths, failures: &failures)
        case "settings-logical-traversal":
            validateSettingsTraversal(capture, paths: &paths, failures: &failures)
        case "no-duplicate-chart-elements":
            validateCurveControls(capture, paths: &paths, failures: &failures)
            validateNoDuplicateChartElements(capture, failures: &failures)
        default:
            if let contract = scrollContracts[id] {
                validateScroll(capture, contract: contract, paths: &paths, failures: &failures)
            }
        }

        return AXAssertion(
            id: id,
            passed: failures.isEmpty,
            observationPaths: paths,
            facts: [
                "requestSHA256": expectedRequest.canonicalSHA256,
                "source": capture.source
            ],
            failures: failures
        )
    }

    private static func request(
        state: String,
        surface: String = "main",
        textSize: String = "standard",
        window: String = "1180x820",
        interaction: String = "none"
    ) -> AXSemanticRequest {
        AXSemanticRequest(
            interaction: interaction,
            state: state,
            surface: surface,
            textSize: textSize,
            window: window
        )
    }

    private static func validateCaptureContract(
        id: String,
        expectedRequest: AXSemanticRequest,
        capture: AXRawCapture,
        failures: inout [String]
    ) {
        require(capture.schemaVersion == AXRawCapture.schemaVersion, "raw capture schema mismatch", &failures)
        require(capture.schemaID == AXRawCapture.schemaID, "raw capture schema ID mismatch", &failures)
        require(capture.request.checkID == id, "check ID mismatch", &failures)
        require(capture.request.semanticRequest == expectedRequest, "canonical semantic request mismatch", &failures)
        require(capture.request.requestSHA256 == expectedRequest.canonicalSHA256, "canonical request hash mismatch", &failures)
        require(!capture.request.captureID.isEmpty, "capture ID is missing", &failures)
        require(capture.request.processIdentifier > 0, "process identifier is invalid", &failures)
        require(
            capture.request.windowIdentifier == "vifty-ui-review-ax-window-\(capture.request.captureID)",
            "window identifier does not bind the capture ID",
            &failures
        )
        require(
            capture.request.rootIdentifier == "vifty.ax.fixture.root.\(capture.request.captureID)",
            "root identifier does not bind the capture ID",
            &failures
        )
        require(capture.source == "macos-accessibility-api", "capture source is invalid", &failures)
        require(capture.permissionTrusted, "Accessibility permission is not trusted", &failures)
        require(!capture.promptRequested, "Accessibility permission prompt was requested", &failures)

        let expectedIdentity = AXTargetIdentity(
            processIdentifier: capture.request.processIdentifier,
            windowIdentifier: capture.request.windowIdentifier,
            rootIdentifier: capture.request.rootIdentifier
        )
        require(capture.initialTarget == expectedIdentity, "initial target identity mismatch", &failures)
        require(capture.finalTarget == expectedIdentity, "final target identity mismatch", &failures)
        require(capture.initialTarget == capture.finalTarget, "target changed during traversal", &failures)

        require(capture.traversal.complete, "Accessibility traversal is incomplete", &failures)
        require(capture.traversal.truncationReasons.isEmpty, "Accessibility traversal was truncated", &failures)
        require(capture.traversal.nodeCount == capture.observations.count, "traversal node count mismatch", &failures)
        require(capture.traversal.maximumNodeCount > 0, "maximum node count is invalid", &failures)
        require(capture.traversal.maximumDepth > 0, "maximum depth is invalid", &failures)
        require(capture.traversal.maximumNodeCount <= 16_384, "maximum node count exceeds the collector contract", &failures)
        require(capture.traversal.maximumDepth <= 128, "maximum depth exceeds the collector contract", &failures)
        require(
            capture.traversal.nodeCount <= capture.traversal.maximumNodeCount,
            "traversal exceeds its maximum node count",
            &failures
        )
        require(capture.actionsPerformed.isEmpty, "Accessibility actions were performed", &failures)
        require(capture.readErrors.isEmpty, "capture contains read errors", &failures)

        let roots = nodes(capture.request.rootIdentifier, in: capture)
        require(roots.count == 1, "capture root marker must occur exactly once", &failures)
        if let root = roots.only {
            let allowsScrollAreaRoot = scrollContracts[id]?.allowsCaptureRootScrollAreaFallback == true
            require(
                root.role == "AXGroup" || (allowsScrollAreaRoot && root.role == "AXScrollArea"),
                "capture root marker role mismatch",
                &failures
            )
            require(root.order == 0, "capture root marker must be first", &failures)
            require(
                capture.observations.allSatisfy { $0.path == root.path || isDescendant($0, of: root) },
                "observation is outside the capture root marker",
                &failures
            )
        }

        let paths = capture.observations.map(\.path)
        let orders = capture.observations.map(\.order)
        require(Set(paths).count == paths.count, "observation paths are not unique", &failures)
        require(Set(orders).count == orders.count, "observation orders are not unique", &failures)
        require(orders == orders.sorted(), "observations are not in traversal order", &failures)
        require(orders == Array(0..<orders.count), "observation orders are not contiguous", &failures)
        require(capture.observations.allSatisfy { $0.readErrors.isEmpty }, "observation contains read errors", &failures)
        require(capture.observations.allSatisfy(isFinite), "observation geometry or value is non-finite", &failures)

        if let root = roots.only {
            validateTraversalTopology(capture, root: root, failures: &failures)
        }
    }

    private static func validateOwner(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.controlSession, in: capture, failures: &failures)
        let title = unique(AXEvidenceIdentifier.controlSessionTitle, in: capture, failures: &failures)
        let summary = unique(AXEvidenceIdentifier.controlSessionSummary, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)
        requireNode(title, role: "AXStaticText", label: "Vifty manual control active", value: nil, failures: &failures)
        requireNode(summary, role: "AXStaticText", label: "Owner: Vifty manual control", value: nil, failures: &failures)
        requireDescendant(title, of: scope, failures: &failures)
        requireDescendant(summary, of: scope, failures: &failures)
        if let title, let summary {
            require(title.order < summary.order, "owner title must precede owner summary", &failures)
        }
        paths.append(contentsOf: [scope, title, summary].compactMap { $0?.path })
    }

    private static func validateFanTargets(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.fanStatus, in: capture, failures: &failures)
        let left = unique(AXEvidenceIdentifier.leftFanDraftTarget, in: capture, failures: &failures)
        let right = unique(AXEvidenceIdentifier.rightFanDraftTarget, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)
        requireNode(left, role: "AXStaticText", label: "Left Fan draft target", value: "Draft 2493 RPM", failures: &failures)
        requireNode(right, role: "AXStaticText", label: "Right Fan draft target", value: "Draft 3080 RPM", failures: &failures)
        requireDescendant(left, of: scope, failures: &failures)
        requireDescendant(right, of: scope, failures: &failures)
        if let left, let right {
            require(left.value != right.value, "left and right draft targets must be distinct", &failures)
            require(left.order < right.order, "left draft target must precede right draft target", &failures)
        }
        paths.append(contentsOf: [scope, left, right].compactMap { $0?.path })
    }

    private static let curveControlContracts = [
        (AXEvidenceIdentifier.curveStartTemperature, "Start temperature", "55 °C"),
        (AXEvidenceIdentifier.curveStartRPM, "Start RPM", "1200 RPM"),
        (AXEvidenceIdentifier.curveRampTemperature, "Ramp temperature", "70 °C"),
        (AXEvidenceIdentifier.curveRampRPM, "Ramp RPM", "3500 RPM"),
        (AXEvidenceIdentifier.curveHighTemperature, "High temperature", "85 °C"),
        (AXEvidenceIdentifier.curveHighRPM, "High RPM", "6200 RPM")
    ]

    private static let effectiveCurveSummaryContracts = [
        (
            AXEvidenceIdentifier.leftFanEffectiveSummary,
            "Left Fan effective curve",
            "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5700 RPM"
        ),
        (
            AXEvidenceIdentifier.rightFanEffectiveSummary,
            "Right Fan effective curve",
            "Start 55 °C, 2100 RPM; Ramp 70 °C, 4200 RPM; High 85 °C, 6400 RPM"
        )
    ]

    private static func validateCurveControls(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.curveChart, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)
        paths.append(contentsOf: [scope].compactMap { $0?.path })

        var controls: [AXObservation] = []
        for contract in curveControlContracts {
            let node = unique(contract.0, in: capture, failures: &failures)
            requireNode(node, role: "AXSlider", label: contract.1, value: contract.2, failures: &failures)
            require(node?.enabled == true, "\(contract.0) must be enabled", &failures)
            require(Set(node?.actions ?? []) == ["AXIncrement", "AXDecrement"], "\(contract.0) action set mismatch", &failures)
            requireDescendant(node, of: scope, failures: &failures)
            if let node {
                controls.append(node)
                paths.append(node.path)
            }
        }
        require(controls.map(\.order) == controls.map(\.order).sorted(), "curve controls are not in canonical order", &failures)
    }

    private static func validateSeparateFanCurvesToggle(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let toggle = unique(AXEvidenceIdentifier.curveSeparateFans, in: capture, failures: &failures)
        let chart = unique(AXEvidenceIdentifier.curveChart, in: capture, failures: &failures)
        let root = nodes(capture.request.rootIdentifier, in: capture).only

        requireNode(toggle, role: "AXCheckBox", label: "Separate fan curves", value: nil, failures: &failures)
        require(toggle?.enabled == true, "separate fan curves toggle must be enabled", &failures)
        require(toggle?.selected == true, "separate fan curves toggle must be on", &failures)
        require(Set(toggle?.actions ?? []) == ["AXPress"], "separate fan curves toggle action set mismatch", &failures)
        require(toggle?.childCount == 0, "separate fan curves toggle must not expose children", &failures)

        if let toggle, let chart {
            require(toggle.order < chart.order, "separate fan curves toggle must precede the curve chart", &failures)
            require(!isDescendant(toggle, of: chart), "separate fan curves toggle must remain outside the curve chart", &failures)
        }

        if let toggleFrame = toggle.flatMap(frame),
           let chartFrame = chart.flatMap(frame),
           let rootFrame = root.flatMap(frame) {
            require(toggleFrame.width > 0 && toggleFrame.height > 0, "separate fan curves toggle frame must be positive", &failures)
            require(
                contains(rootFrame, toggleFrame, tolerance: 0.5),
                "separate fan curves toggle must be fully visible inside the capture root",
                &failures
            )
            require(
                toggleFrame.y + toggleFrame.height <= chartFrame.y + 0.5,
                "separate fan curves toggle must be visually above the curve chart",
                &failures
            )
        } else {
            require(false, "separate fan curves toggle, chart, and capture root must expose frames", &failures)
        }

        paths.append(contentsOf: [toggle, chart].compactMap { $0?.path })
    }

    private static func validateEffectiveCurveSummaries(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.curveEffectiveSummaries, in: capture, failures: &failures)
        let chart = unique(AXEvidenceIdentifier.curveChart, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)

        var summaries: [AXObservation] = []
        for (index, contract) in effectiveCurveSummaryContracts.enumerated() {
            let node = unique(contract.0, in: capture, failures: &failures)
            requireNode(node, role: "AXStaticText", label: contract.1, value: contract.2, failures: &failures)
            require(node?.childCount == 0, "\(contract.0) must be a leaf summary", &failures)
            requireDescendant(node, of: scope, failures: &failures)
            if let scope, let node {
                require(
                    node.path == "\(scope.path)/\(index)",
                    "\(contract.0) must be direct summary child \(index)",
                    &failures
                )
                summaries.append(node)
            }
        }

        if let scope {
            let summaryDescendants = descendants(of: scope, in: capture)
            require(
                scope.childCount == effectiveCurveSummaryContracts.count &&
                    summaryDescendants.count == effectiveCurveSummaryContracts.count &&
                    summaryDescendants.allSatisfy { $0.role == "AXStaticText" },
                "effective curve summaries must expose exactly two direct static-text children",
                &failures
            )
        }

        if let chart, let scope {
            let chartLastOrder = descendants(of: chart, in: capture).map(\.order).max() ?? chart.order
            require(chartLastOrder < scope.order, "effective curve summaries must follow the curve chart", &failures)
            require(!isDescendant(scope, of: chart), "effective curve summaries must remain outside the curve chart", &failures)
            for summary in summaries {
                require(!isDescendant(summary, of: chart), "\(summary.identifier ?? summary.path) must remain outside the curve chart", &failures)
            }
        }

        require(
            summaries.map(\.order) == summaries.map(\.order).sorted(),
            "effective curve summaries are not in fan order",
            &failures
        )
        paths.append(contentsOf: [scope, chart].compactMap { $0?.path })
        paths.append(contentsOf: summaries.map(\.path))
    }

    private static func validateSensors(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.sensorList, in: capture, failures: &failures)
        let contracts: [(identifier: String, label: String, value: String, selected: Bool)] = [
            (AXEvidenceIdentifier.sensorCPU, "CPU Efficiency", "64.0 degrees Celsius, SMC", true),
            (AXEvidenceIdentifier.sensorGPU, "GPU Hotspot", "83.0 degrees Celsius, HID", false),
            (AXEvidenceIdentifier.sensorPalm, "Palm Rest", "37.0 degrees Celsius, HID", false)
        ]
        requireNode(scope, role: "AXOpaqueProviderGroup", label: nil, value: nil, failures: &failures)
        paths.append(contentsOf: [scope].compactMap { $0?.path })

        if let scope {
            require(
                scope.actions == ["AXScrollToBottom", "AXScrollToTop"],
                "sensor list action set mismatch",
                &failures
            )
            require(scope.childCount == contracts.count, "sensor list must expose exactly three direct children", &failures)
            let directChildren = capture.observations.filter { observation in
                let prefix = scope.path + "/"
                guard observation.path.hasPrefix(prefix) else { return false }
                return !observation.path.dropFirst(prefix.count).contains("/")
            }
            require(directChildren.count == contracts.count, "sensor list direct-child count mismatch", &failures)
            require(
                directChildren.compactMap(\.identifier) == contracts.map(\.identifier),
                "sensor list direct-child order mismatch",
                &failures
            )
        }

        var selectedCount = 0
        for (index, contract) in contracts.enumerated() {
            let node = unique(contract.identifier, in: capture, failures: &failures)
            requireNode(node, role: "AXButton", label: contract.label, value: contract.value, failures: &failures)
            require(node?.enabled == true, "\(contract.identifier) must be enabled", &failures)
            if contract.selected {
                require(node?.selected == true, "\(contract.identifier) must expose the selected trait", &failures)
            } else {
                require(node?.selected != true, "\(contract.identifier) must not expose the selected trait", &failures)
            }
            require(
                node?.actions == ["AXPress", "AXScrollToVisible"],
                "\(contract.identifier) action set mismatch",
                &failures
            )
            require(node?.childCount == 0, "\(contract.identifier) must be a leaf sensor button", &failures)
            if let scope {
                require(
                    node?.path == "\(scope.path)/\(index)",
                    "\(contract.identifier) must be direct sensor child \(index)",
                    &failures
                )
            }
            if node?.selected == true { selectedCount += 1 }
            if let node { paths.append(node.path) }
        }
        require(selectedCount == 1, "exactly one sensor must be selected", &failures)
    }

    private static func validateTemperatureRoles(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.temperatureMetrics, in: capture, failures: &failures)
        let curve = unique(AXEvidenceIdentifier.curveSensorMetric, in: capture, failures: &failures)
        let highest = unique(AXEvidenceIdentifier.highestTemperatureMetric, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)
        requireNode(curve, role: "AXStaticText", label: "Curve sensor", value: "Curve sensor · CPU Efficiency", failures: &failures)
        requireNode(highest, role: "AXStaticText", label: "Highest temperature", value: "Highest 83.0 °C", failures: &failures)
        requireDescendant(curve, of: scope, failures: &failures)
        requireDescendant(highest, of: scope, failures: &failures)
        if let curve, let highest {
            require(curve.order < highest.order, "curve sensor metric must precede highest metric", &failures)
            require(curve.path != highest.path, "temperature roles must use separate nodes", &failures)
        }
        if let scope {
            require(
                descendants(of: scope, in: capture).filter { $0.role == "AXStaticText" }.count == 2,
                "temperature metrics must expose exactly two text roles",
                &failures
            )
        }
        paths.append(contentsOf: [scope, curve, highest].compactMap { $0?.path })
    }

    private static func validateNotifications(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let scope = unique(AXEvidenceIdentifier.notifications, in: capture, failures: &failures)
        let openSettings = unique(AXEvidenceIdentifier.notificationOpenSettings, in: capture, failures: &failures)
        requireNode(scope, role: "AXGroup", label: nil, value: nil, failures: &failures)
        requireNode(openSettings, role: "AXButton", label: "Open Notification Settings", value: nil, failures: &failures)
        require(openSettings?.enabled == true, "Open Notification Settings must be enabled", &failures)
        require(openSettings?.actions == ["AXPress"], "Open Notification Settings action set mismatch", &failures)
        requireDescendant(openSettings, of: scope, failures: &failures)
        require(nodes(AXEvidenceIdentifier.notificationSendTest, in: capture).isEmpty, "Send Test Notification must be absent when permission is denied", &failures)
        if let scope {
            require(
                !descendants(of: scope, in: capture).contains {
                    $0.role == "AXButton" && $0.label == "Send Test Notification"
                },
                "Send Test Notification action must be absent when permission is denied",
                &failures
            )
        }
        paths.append(contentsOf: [scope, openSettings].compactMap { $0?.path })

        let labels = [
            "Helper failure",
            "High thermal pressure",
            "Auto restore failure",
            "Plugged-in battery drain",
            "Agent cooling attention"
        ]
        for (identifier, label) in zip(AXEvidenceIdentifier.notificationEvents, labels) {
            let node = unique(identifier, in: capture, failures: &failures)
            requireNode(node, role: "AXCheckBox", label: label, value: nil, failures: &failures)
            require(node?.enabled == true, "\(identifier) must be enabled", &failures)
            require(node?.selected == true, "\(identifier) must be selected", &failures)
            require(node?.actions == ["AXPress"], "\(identifier) action set mismatch", &failures)
            requireDescendant(node, of: scope, failures: &failures)
            if let node { paths.append(node.path) }
        }
        if let scope {
            require(
                descendants(of: scope, in: capture).filter { $0.role == "AXCheckBox" }.count == labels.count,
                "notification settings must expose exactly five event checkboxes",
                &failures
            )
        }
    }

    private static func validateSettingsTraversal(
        _ capture: AXRawCapture,
        paths: inout [String],
        failures: inout [String]
    ) {
        let root = unique(capture.request.rootIdentifier, in: capture, failures: &failures)
        let tabGroup = unique(AXEvidenceIdentifier.settingsTabs, in: capture, failures: &failures)
        let pane = unique(AXEvidenceIdentifier.settingsPaneGeneral, in: capture, failures: &failures)
        requireNode(root, role: "AXGroup", label: nil, value: nil, failures: &failures)
        requireNode(tabGroup, role: "AXGroup", label: "Settings sections", value: nil, failures: &failures)
        requireNode(pane, role: "AXGroup", label: "General settings", value: nil, failures: &failures)
        if let root {
            require(root.childCount == 2, "Settings capture root must expose exactly the tab group and selected pane", &failures)
            require(tabGroup?.path == "\(root.path)/0", "Settings tab group must be the first direct child of the capture root", &failures)
            require(pane?.path == "\(root.path)/1", "selected Settings pane must be the second direct child of the capture root", &failures)
        }
        paths.append(contentsOf: [root, tabGroup, pane].compactMap { $0?.path })

        let contracts: [(identifier: String, label: String, value: String, selected: Bool)] = [
            (AXEvidenceIdentifier.settingsTabGeneral, "General", "Selected", true),
            (AXEvidenceIdentifier.settingsTabMenuBar, "Menu Bar", "Not selected", false),
            (AXEvidenceIdentifier.settingsTabNotifications, "Notifications", "Not selected", false),
            (AXEvidenceIdentifier.settingsTabAgentWorkflows, "Agent Workflows", "Not selected", false)
        ]
        var tabs: [AXObservation] = []
        for (index, contract) in contracts.enumerated() {
            let node = unique(contract.identifier, in: capture, failures: &failures)
            requireNode(node, role: "AXButton", label: contract.label, value: nil, failures: &failures)
            require(node?.value == .string(contract.value), "\(contract.identifier) typed string value mismatch", &failures)
            require(node?.enabled == true, "\(contract.identifier) must be enabled", &failures)
            if contract.selected {
                require(node?.selected == true, "\(contract.identifier) must expose the selected trait", &failures)
            } else {
                require(node?.selected != true, "\(contract.identifier) must not expose the selected trait", &failures)
            }
            require(node?.actions == ["AXPress"], "\(contract.identifier) action set mismatch", &failures)
            if let tabGroup {
                require(
                    node?.path == "\(tabGroup.path)/\(index)",
                    "\(contract.identifier) must be direct child \(index) of the Settings tab group",
                    &failures
                )
            }
            if let node {
                tabs.append(node)
                paths.append(node.path)
            }
        }
        require(tabs.map(\.order) == tabs.map(\.order).sorted(), "Settings tabs are not in logical order", &failures)
        if let tabGroup {
            let tabDescendants = descendants(of: tabGroup, in: capture)
            require(
                tabGroup.childCount == contracts.count &&
                    tabDescendants.count == contracts.count &&
                    tabDescendants.allSatisfy { $0.role == "AXButton" },
                "Settings must expose exactly four direct tab buttons",
                &failures
            )
        }
        if let pane, let lastTab = tabs.last {
            require(lastTab.order < pane.order, "selected Settings pane must follow tab controls", &failures)
        }
        validateSoftwareUpdateControls(
            capture,
            root: root,
            pane: pane,
            paths: &paths,
            failures: &failures
        )
    }

    private static func validateSoftwareUpdateControls(
        _ capture: AXRawCapture,
        root: AXObservation?,
        pane: AXObservation?,
        paths: inout [String],
        failures: inout [String]
    ) {
        let automatic = unique(
            AXEvidenceIdentifier.settingsUpdateAutomatic,
            in: capture,
            failures: &failures
        )
        let status = unique(
            AXEvidenceIdentifier.settingsUpdateStatus,
            in: capture,
            failures: &failures
        )
        let latest = unique(
            AXEvidenceIdentifier.settingsUpdateLatest,
            in: capture,
            failures: &failures
        )
        let refresh = unique(
            AXEvidenceIdentifier.settingsUpdateCheck,
            in: capture,
            failures: &failures
        )
        let launchAtLogin = unique(
            AXEvidenceIdentifier.settingsLaunchAtLogin,
            in: capture,
            failures: &failures
        )

        requireNode(
            automatic,
            role: "AXCheckBox",
            label: "Automatically check for updates",
            value: nil,
            failures: &failures
        )
        require(automatic?.enabled == true, "automatic update checks must be enabled", &failures)
        require(automatic?.selected == true, "automatic update checks must be on", &failures)
        require(automatic?.actions == ["AXPress"], "automatic update check action set mismatch", &failures)

        requireNode(
            status,
            role: "AXStaticText",
            label: "Vifty 1.3.3 is available.",
            value: nil,
            failures: &failures
        )
        requireNode(
            latest,
            role: "AXButton",
            label: "Update to latest version",
            value: nil,
            failures: &failures
        )
        require(latest?.enabled == true, "Update to latest version must be enabled", &failures)
        require(latest?.actions == ["AXPress"], "Update to latest version action set mismatch", &failures)
        require(latest?.help == updateLatestHelp, "Update to latest version help mismatch", &failures)

        requireNode(
            refresh,
            role: "AXButton",
            label: "Check now",
            value: nil,
            failures: &failures
        )
        require(refresh?.enabled == true, "Check now must be enabled", &failures)
        require(refresh?.actions == ["AXPress"], "Check now action set mismatch", &failures)
        require(refresh?.help == updateRefreshHelp, "Check now help mismatch", &failures)

        requireNode(
            launchAtLogin,
            role: "AXCheckBox",
            label: "Start Vifty at startup",
            value: nil,
            failures: &failures
        )
        require(launchAtLogin?.selected != true, "fixture launch-at-login control must be off", &failures)

        let updateNodes = [automatic, status, latest, refresh].compactMap { $0 }
        for node in updateNodes {
            requireDescendant(node, of: pane, failures: &failures)
        }
        requireDescendant(launchAtLogin, of: pane, failures: &failures)
        if updateNodes.count == 4 {
            require(
                updateNodes.map(\.order) == updateNodes.map(\.order).sorted(),
                "software update controls are not in logical order",
                &failures
            )
        }
        if let refresh, let launchAtLogin {
            require(
                refresh.order < launchAtLogin.order,
                "software update controls must precede Login settings",
                &failures
            )
        }

        if let latestFrame = latest.flatMap(frame),
           let refreshFrame = refresh.flatMap(frame),
           let rootFrame = root.flatMap(frame) {
            require(
                latestFrame.width > 0 && latestFrame.height > 0
                    && refreshFrame.width > 0 && refreshFrame.height > 0,
                "software update buttons must have positive frames",
                &failures
            )
            require(
                contains(rootFrame, latestFrame, tolerance: 0.5)
                    && contains(rootFrame, refreshFrame, tolerance: 0.5),
                "software update buttons must be visible inside the capture root",
                &failures
            )
            require(
                latestFrame.x + latestFrame.width <= refreshFrame.x + 0.5,
                "Update to latest version must be visually left of Check now",
                &failures
            )
        } else {
            require(
                false,
                "software update buttons and capture root must expose frames",
                &failures
            )
        }

        paths.append(contentsOf: [automatic, status, latest, refresh, launchAtLogin]
            .compactMap { $0?.path })
    }

    private static func validateNoDuplicateChartElements(
        _ capture: AXRawCapture,
        failures: inout [String]
    ) {
        guard let scope = nodes(AXEvidenceIdentifier.curveChart, in: capture).only else { return }
        let chartDescendants = descendants(of: scope, in: capture)
        require(
            chartDescendants.count == curveControlContracts.count,
            "chart must expose exactly the six canonical slider descendants",
            &failures
        )
        require(
            chartDescendants.allSatisfy { $0.role == "AXSlider" },
            "chart exposes a non-slider descendant",
            &failures
        )
        require(
            Set(chartDescendants.compactMap(\.identifier)) == Set(AXEvidenceIdentifier.curveControls),
            "chart descendant identifiers do not match the canonical controls",
            &failures
        )
    }

    private static func validateScroll(
        _ capture: AXRawCapture,
        contract: AXScrollPredicateContract,
        paths: inout [String],
        failures: inout [String]
    ) {
        let area = resolveScrollArea(capture, contract: contract, failures: &failures)
        let anchor = unique(contract.anchorIdentifier, in: capture, failures: &failures)
        requireNode(area, role: "AXScrollArea", label: nil, value: nil, failures: &failures)
        requireNode(anchor, role: "AXStaticText", label: "End of content", value: nil, failures: &failures)
        requireDescendant(anchor, of: area, failures: &failures)
        paths.append(contentsOf: [area, anchor].compactMap { $0?.path })

        guard let area else { return }
        require(
            area.actions.contains("AXScrollUpByPage") && area.actions.contains("AXScrollDownByPage"),
            "scroll area must expose page-up and page-down actions",
            &failures
        )
        let evidence = capture.scrollEvidence.filter { $0.scrollAreaPath == area.path }
        require(evidence.count == 1, "scroll area must have exactly one evidence record", &failures)
        guard let scroll = evidence.only else { return }
        require(
            scroll.verticalScrollBarPath.hasPrefix(area.path + "/"),
            "vertical scrollbar is not structurally linked to its scroll area",
            &failures
        )
        let bar = capture.observations.filter { $0.path == scroll.verticalScrollBarPath }
        require(bar.count == 1, "scroll evidence must reference one vertical scrollbar", &failures)
        require(bar.only?.role == "AXScrollBar", "vertical scrollbar role mismatch", &failures)
        require(scroll.currentValue.isFinite, "scroll value is non-finite", &failures)
        require(
            (scroll.minimumValue == nil) == (scroll.maximumValue == nil),
            "scrollbar bounds must be both present or both unavailable",
            &failures
        )
        if let minimumValue = scroll.minimumValue, let maximumValue = scroll.maximumValue {
            require(minimumValue.isFinite, "scroll minimum is non-finite", &failures)
            require(maximumValue.isFinite, "scroll maximum is non-finite", &failures)
            require(maximumValue > minimumValue, "scrollbar range is empty", &failures)
            require(
                scroll.currentValue >= minimumValue && scroll.currentValue <= maximumValue,
                "scrollbar value is outside its range",
                &failures
            )
            require(
                numericallyEqual(scroll.currentValue, minimumValue),
                "scrollbar must be captured at its initial value",
                &failures
            )
        }
        require(scroll.viewportHeight.isFinite && scroll.viewportHeight > 0, "scroll viewport height is invalid", &failures)
        require(scroll.contentHeight.isFinite && scroll.contentHeight > scroll.viewportHeight, "scroll content does not overflow", &failures)
        if let bar = bar.only {
            require(
                bar.value?.numericValue.map { numericallyEqual($0, scroll.currentValue) } == true,
                "scrollbar typed value does not match structural evidence",
                &failures
            )
        }
        validateScrollGeometry(area: area, anchor: anchor, scroll: scroll, failures: &failures)
        if let bar = bar.only { paths.append(bar.path) }
    }

    private static func resolveScrollArea(
        _ capture: AXRawCapture,
        contract: AXScrollPredicateContract,
        failures: inout [String]
    ) -> AXObservation? {
        let canonicalMatches = nodes(contract.scrollIdentifier, in: capture)
        if canonicalMatches.count == 1 {
            return canonicalMatches.only
        }
        if canonicalMatches.isEmpty, contract.allowsCaptureRootScrollAreaFallback {
            let roots = nodes(capture.request.rootIdentifier, in: capture)
            require(
                roots.count == 1 && roots.only?.role == "AXScrollArea",
                "settings scroll fallback must be the unique exact capture-root AXScrollArea",
                &failures
            )
            return roots.count == 1 && roots.only?.role == "AXScrollArea" ? roots.only : nil
        }
        require(false, "\(contract.scrollIdentifier) must occur exactly once", &failures)
        return nil
    }

    private static func validateScrollGeometry(
        area: AXObservation,
        anchor: AXObservation?,
        scroll: AXScrollEvidence,
        failures: inout [String]
    ) {
        guard
            let areaPosition = area.position,
            let areaSize = area.size,
            areaSize.width > 0,
            areaSize.height > 0
        else {
            failures.append("scroll area geometry is missing or empty")
            return
        }
        require(
            approximatelyEqual(areaSize.height, scroll.viewportHeight),
            "scroll viewport height does not match the scroll area frame",
            &failures
        )

        guard
            let anchor,
            let anchorPosition = anchor.position,
            let anchorSize = anchor.size,
            anchorSize.width > 0,
            anchorSize.height > 0
        else {
            failures.append("scroll end-anchor geometry is missing or empty")
            return
        }

        let areaMinimumY = areaPosition.y
        let areaMaximumY = areaPosition.y + areaSize.height
        let anchorMinimumY = anchorPosition.y
        let anchorMaximumY = anchorPosition.y + anchorSize.height
        require(
            anchorMaximumY <= areaMinimumY || anchorMinimumY >= areaMaximumY,
            "scroll end anchor is already inside the initial viewport",
            &failures
        )

        let structuralSpan = max(areaMaximumY, anchorMaximumY) - min(areaMinimumY, anchorMinimumY)
        require(
            scroll.contentHeight + 0.5 >= structuralSpan,
            "declared scroll content height cannot contain the observed end anchor",
            &failures
        )
    }

    private static func validateTraversalTopology(
        _ capture: AXRawCapture,
        root: AXObservation,
        failures: inout [String]
    ) {
        var observationsByPath: [String: AXObservation] = [:]
        for observation in capture.observations where observationsByPath[observation.path] == nil {
            observationsByPath[observation.path] = observation
        }
        for observation in capture.observations {
            guard let components = relativePathComponents(observation.path, rootPath: root.path) else {
                failures.append("observation path is not canonical: \(observation.path)")
                continue
            }
            require(observation.depth == components.count, "observation depth does not match its path: \(observation.path)", &failures)
            require(observation.depth <= capture.traversal.maximumDepth, "observation exceeds maximum traversal depth: \(observation.path)", &failures)
            require(observation.childCount != nil, "observation child count is missing: \(observation.path)", &failures)
            require((observation.childCount ?? -1) >= 0, "observation child count is invalid: \(observation.path)", &failures)

            if observation.path != root.path {
                let parentPath = observation.path.split(separator: "/").dropLast().joined(separator: "/")
                let parent = observationsByPath[parentPath]
                require(parent != nil, "observation parent is missing: \(observation.path)", &failures)
                require((parent?.order ?? Int.max) < observation.order, "observation precedes its parent: \(observation.path)", &failures)
            }

            let prefix = observation.path + "/"
            let numericChildren = capture.observations.compactMap { candidate -> Int? in
                guard candidate.path.hasPrefix(prefix) else { return nil }
                let suffix = candidate.path.dropFirst(prefix.count)
                guard !suffix.contains("/") else { return nil }
                return Int(suffix)
            }.sorted()
            let childCount = observation.childCount ?? -1
            require(numericChildren.count == childCount, "observation child count mismatch: \(observation.path)", &failures)
            if childCount >= 0 {
                require(numericChildren == Array(0..<childCount), "observation child indexes are not contiguous: \(observation.path)", &failures)
            }
        }

        var expectedPreorderPaths: [String] = []
        var visitedPaths: Set<String> = []
        func appendSubtree(_ path: String) {
            guard let observation = observationsByPath[path], visitedPaths.insert(path).inserted else { return }
            expectedPreorderPaths.append(path)
            guard let childCount = observation.childCount,
                  childCount >= 0,
                  childCount <= capture.observations.count else { return }
            for index in 0..<childCount {
                appendSubtree("\(path)/\(index)")
            }
            let syntheticScrollBarPath = "\(path)/@vertical"
            if observationsByPath[syntheticScrollBarPath] != nil {
                appendSubtree(syntheticScrollBarPath)
            }
        }
        appendSubtree(root.path)
        require(
            expectedPreorderPaths == capture.observations.map(\.path),
            "observations are not in strict depth-first pre-order",
            &failures
        )
    }

    private static func relativePathComponents(_ path: String, rootPath: String) -> [String]? {
        if path == rootPath { return [] }
        let prefix = rootPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let components = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else { return nil }
        for (index, component) in components.enumerated() {
            if component == "@vertical" {
                guard index == components.count - 1 else { return nil }
            } else {
                guard let value = Int(component), value >= 0, component == String(value) else { return nil }
            }
        }
        return components
    }


    private static func nodes(_ identifier: String, in capture: AXRawCapture) -> [AXObservation] {
        capture.observations.filter { $0.identifier == identifier }
    }

    private static func descendants(of parent: AXObservation, in capture: AXRawCapture) -> [AXObservation] {
        capture.observations.filter { isDescendant($0, of: parent) }
    }

    private static func unique(
        _ identifier: String,
        in capture: AXRawCapture,
        failures: inout [String]
    ) -> AXObservation? {
        let matches = nodes(identifier, in: capture)
        require(matches.count == 1, "\(identifier) must occur exactly once", &failures)
        return matches.only
    }

    private static func requireNode(
        _ node: AXObservation?,
        role: String,
        label: String?,
        value: String?,
        failures: inout [String]
    ) {
        guard let node else { return }
        require(node.role == role, "\(node.identifier ?? node.path) role mismatch", &failures)
        if let label {
            require(node.label == label, "\(node.identifier ?? node.path) label mismatch", &failures)
        }
        if let value {
            let observedValue = node.valueDescription ?? node.value?.stringValue
            require(observedValue == value, "\(node.identifier ?? node.path) value mismatch", &failures)
        }
    }

    private static func requireDescendant(
        _ child: AXObservation?,
        of parent: AXObservation?,
        failures: inout [String]
    ) {
        guard let child, let parent else { return }
        require(isDescendant(child, of: parent), "\(child.identifier ?? child.path) is outside its required scope", &failures)
    }

    private static func isDescendant(_ child: AXObservation, of parent: AXObservation) -> Bool {
        child.path.hasPrefix(parent.path + "/")
    }

    private static func frame(_ observation: AXObservation) -> AXRect? {
        guard let position = observation.position, let size = observation.size else { return nil }
        return AXRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    private static func contains(_ outer: AXRect, _ inner: AXRect, tolerance: Double) -> Bool {
        inner.x >= outer.x - tolerance
            && inner.y >= outer.y - tolerance
            && inner.x + inner.width <= outer.x + outer.width + tolerance
            && inner.y + inner.height <= outer.y + outer.height + tolerance
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String, _ failures: inout [String]) {
        if !condition() { failures.append(message) }
    }

    private static func isFinite(_ observation: AXObservation) -> Bool {
        if let value = observation.value, !isFinite(value) { return false }
        if let point = observation.position, !point.x.isFinite || !point.y.isFinite { return false }
        if let size = observation.size,
           !size.width.isFinite || !size.height.isFinite || size.width < 0 || size.height < 0 {
            return false
        }
        return true
    }

    private static func isFinite(_ value: AXTypedValue) -> Bool {
        switch value {
        case let .number(number):
            number.isFinite
        case let .point(point):
            point.x.isFinite && point.y.isFinite
        case let .size(size):
            size.width.isFinite && size.height.isFinite && size.width >= 0 && size.height >= 0
        case let .rectangle(rectangle):
            rectangle.x.isFinite
                && rectangle.y.isFinite
                && rectangle.width.isFinite
                && rectangle.height.isFinite
                && rectangle.width >= 0
                && rectangle.height >= 0
        case let .range(range):
            range.location >= 0 && range.length >= 0
        default:
            true
        }
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= 0.5
    }

    private static func numericallyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        let scale = max(1, abs(lhs), abs(rhs))
        return abs(lhs - rhs) <= Double.ulpOfOne * 8 * scale
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
