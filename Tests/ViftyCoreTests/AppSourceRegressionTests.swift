import Foundation
import XCTest

final class AppSourceRegressionTests: XCTestCase {
    func testMenuBarHelperHealthOffersRepairAndRefreshesAfterAction() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")

        XCTAssertTrue(menuBarView.contains("@StateObject private var daemonInstaller = DaemonInstaller()"))
        XCTAssertTrue(menuBarView.contains("@State private var helperRefreshTask: Task<Void, Never>?"))
        XCTAssertTrue(menuBarView.contains("Button(daemonInstaller.actionTitle)"))
        XCTAssertTrue(menuBarView.contains("if model.helperRepairActionAvailable {"))
        XCTAssertTrue(menuBarView.contains(".disabled(!daemonInstaller.canInstall)"))
        XCTAssertTrue(menuBarView.contains("daemonInstaller.installOrOpenApproval()"))
        XCTAssertTrue(menuBarView.contains("try? await Task.sleep(for: .milliseconds(750))"))
        XCTAssertTrue(menuBarView.contains("daemonInstaller.refresh()"))
        XCTAssertTrue(menuBarView.contains("daemonInstaller.actionDescription"))
        XCTAssertTrue(menuBarView.contains("Text(daemonInstaller.helperStatusSummary)"))
        XCTAssertTrue(menuBarView.contains("if let context = model.helperInstallRuntimeContext"))
        XCTAssertTrue(menuBarView.contains("@State private var helperDiagnosticsCopied = false"))
        XCTAssertTrue(menuBarView.contains("model.helperHealthMenuSummary"))
        XCTAssertTrue(menuBarView.contains("model.helperMenuRecoverySuggestion"))
        XCTAssertFalse(menuBarView.contains("model.helperRecoverySuggestion"))
        XCTAssertTrue(menuBarView.contains("Button {\n                            copyHelperDiagnosticsCommand()\n                        } label: {\n                            Label(\"Copy Support Evidence\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(menuBarView.contains("HelperDiagnosticsSupport.copySupportEvidenceCommand(context: model.helperSupportEvidenceContext)"))
        XCTAssertTrue(menuBarView.contains(".help(HelperDiagnosticsSupport.copyHelp)"))
        XCTAssertTrue(menuBarView.contains("Text(HelperDiagnosticsSupport.copiedMessage)"))
        XCTAssertEqual(menuBarView.components(separatedBy: "await model.pollOnce()").count - 1, 2)
        XCTAssertTrue(menuBarView.contains("helperRefreshTask?.cancel()"))
    }

    func testOperatorSurfacesUseFilteredLastError() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")

        XCTAssertTrue(appModel.contains("var visibleLastError: String?"))
        XCTAssertTrue(appModel.contains("lastErrorIsCoveredByHelperRecovery"))
        XCTAssertTrue(menuBarView.contains("if let error = model.visibleLastError"))
        XCTAssertTrue(contentView.contains("if let error = model.visibleLastError"))
        XCTAssertFalse(menuBarView.contains("if let error = model.lastError"))
        XCTAssertFalse(contentView.contains("if let error = model.lastError"))
    }

    func testMainWindowHelperHealthShowsRepairAndReadOnlyDiagnosticsActions() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("daemonInstaller.actionDescription"))
        XCTAssertTrue(contentView.contains("Text(daemonInstaller.helperStatusSummary)"))
        XCTAssertTrue(contentView.contains("if let context = model.helperInstallRuntimeContext"))
        XCTAssertTrue(contentView.contains("@State private var helperDiagnosticsCopied = false"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable || model.helperHealthNeedsAttention {"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable {\n                            Button(daemonInstaller.actionTitle)"))
        XCTAssertTrue(contentView.contains("Button {\n                            copyHelperDiagnosticsCommand()\n                        } label: {\n                            Label(\"Copy Support Evidence\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(contentView.contains("HelperDiagnosticsSupport.copySupportEvidenceCommand(context: model.helperSupportEvidenceContext)"))
        XCTAssertTrue(contentView.contains(".help(HelperDiagnosticsSupport.copyHelp)"))
        XCTAssertTrue(contentView.contains("Text(HelperDiagnosticsSupport.copiedMessage)"))
        XCTAssertTrue(contentView.contains("Text(suggestion)"))
        XCTAssertTrue(contentView.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    func testMainWindowHeaderAndEmptyFanFallbackGateRepairActions() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable {\n                Button {\n                    performHelperAction()"))
        XCTAssertTrue(contentView.contains("Label(\"Diagnostics only\", systemImage: \"doc.text.magnifyingglass\")"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable {\n                        Button {\n                            performHelperAction()"))
        XCTAssertTrue(contentView.contains("} else {\n                        Button {\n                            copyHelperDiagnosticsCommand()"))
        XCTAssertTrue(contentView.contains("Label(\"Copy Support Evidence\", systemImage: \"doc.on.doc\")\n                                .frame(maxWidth: 260)"))
    }

    func testMainWindowPanesAreIndependentlyScrollableAndFillAvailableHeight() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("private var mainContent: some View"))
        XCTAssertTrue(contentView.contains("GeometryReader { proxy in"))
        XCTAssertTrue(contentView.contains("let layout = MainWindowLayout.resolve(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue(contentView.contains("switch layout.mode"))
        XCTAssertTrue(contentView.contains("case .stacked:"))
        XCTAssertTrue(contentView.contains("VStack(alignment: .leading, spacing: 0)"))
        XCTAssertTrue(contentView.contains("sensorsPane(compact: layout.compactTelemetry)"))
        XCTAssertTrue(contentView.contains("case .split:"))
        XCTAssertTrue(contentView.contains("HStack(alignment: .top, spacing: 0)"))
        XCTAssertTrue(contentView.contains(".scrollIndicators(.visible)"))
        XCTAssertTrue(contentView.contains(".frame(minWidth: 360, idealWidth: 400, maxWidth: 420, minHeight: proxy.size.height, maxHeight: proxy.size.height)"))
        XCTAssertTrue(contentView.contains("Divider()\n                            .frame(height: proxy.size.height)"))
        XCTAssertTrue(contentView.contains(".background(Color.secondary.opacity(0.035))"))
        XCTAssertTrue(contentView.contains("TelemetryOverviewPanel(power: model.powerSnapshot, history: model.telemetryHistory, compact: compact)"))
        XCTAssertFalse(contentView.contains("PowerPanel(snapshot: power, compact: compact)"))
        XCTAssertFalse(contentView.contains("HistoryPanel(history: model.telemetryHistory, compact: compact)"))
        XCTAssertTrue(contentView.contains("topTemperatureSensors(from: sensors, selectedID: model.selectedSensor?.id, limit: compact ? 3 : 4)"))
        XCTAssertTrue(contentView.contains("DisclosureGroup(\"All sensors\")"))
        XCTAssertTrue(contentView.contains("SensorRow(sensor: sensor, selected: sensor.id == model.selectedSensor?.id, compact: true)"))
        XCTAssertTrue(contentView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
        XCTAssertTrue(contentView.contains("PowerDisplayFormatter.panelHeadline(for: power)"))
        XCTAssertTrue(contentView.contains("PowerDetailDisclosure(snapshot: power, compact: compact)"))
        XCTAssertTrue(contentView.contains("PowerDisplayFormatter.adapterDescription(for: adapter)"))
        XCTAssertFalse(contentView.contains("if let sensors = model.snapshot?.temperatureSensors, !sensors.isEmpty {\n                ScrollView {"))
    }

    func testHistoryPanelShowsLocalSparklineVisualization() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("TelemetryHistorySummary("))
        XCTAssertTrue(contentView.contains("TelemetryHistoryChart(summary: summary, compact: compact)"))
        XCTAssertTrue(contentView.contains("private struct TelemetryHistoryChart: View"))
        XCTAssertTrue(contentView.contains("summary.sampleWindowText"))
        XCTAssertTrue(contentView.contains("parts.append(\"\\(summary.sampleCountText) · last \\(sampleWindowText)\")"))
        XCTAssertTrue(contentView.contains("title: \"Temp\""))
        XCTAssertTrue(contentView.contains("title: summary.fanRPMSparklineTitle"))
        XCTAssertFalse(contentView.contains("title: \"Fan\""))
        XCTAssertTrue(contentView.contains("title: \"Power\""))
        XCTAssertTrue(contentView.contains("changeText: summary.temperatureChangeText"))
        XCTAssertTrue(contentView.contains("changeText: summary.fanRPMChangeText"))
        XCTAssertTrue(contentView.contains("changeText: summary.batteryPowerChangeText"))
        XCTAssertTrue(contentView.contains("summaryText: summary.thermalPressureSummaryText"))
        XCTAssertTrue(contentView.contains("private struct SparklinePath: View"))
        XCTAssertTrue(contentView.contains("private func smoothedValues(_ rawValues: [Double]) -> [Double]"))
        XCTAssertTrue(contentView.contains("path.addQuadCurve(to: midPoint, control: previousPoint)"))
        XCTAssertFalse(contentView.contains("import Charts"))
        XCTAssertFalse(contentView.contains("private func signedWattRangeText"))
        XCTAssertFalse(contentView.contains("UserDefaults.standard.set(history"))
    }

    func testMenuBarShowsReadOnlyRecentTelemetryTrend() throws {
        let appModel = try read("Sources/Vifty/AppModel.swift")
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")

        XCTAssertTrue(appModel.contains("var recentTelemetryTrendSummary: String?"))
        XCTAssertTrue(appModel.contains("TelemetryHistorySummary("))
        XCTAssertTrue(appModel.contains("sampleLimit: 90"))
        XCTAssertTrue(appModel.contains("thermalPressureLimit: 24"))
        XCTAssertTrue(menuBarView.contains("if let recentTelemetryTrendSummary = model.recentTelemetryTrendSummary"))
        XCTAssertTrue(menuBarView.contains("Label(recentTelemetryTrendSummary, systemImage: \"chart.xyaxis.line\")"))
        XCTAssertFalse(appModel.contains("UserDefaults.standard.set(telemetryHistory"))
    }

    func testPrivateIOKitBridgeOnlyExportsHIDTemperatureReader() throws {
        let header = try read("Sources/ViftyPrivateIOKit/include/ViftyPrivateIOKit.h")
        let implementation = try read("Sources/ViftyPrivateIOKit/ViftyPrivateIOKit.c")

        XCTAssertTrue(header.contains("ViftyHIDTemperature"))
        XCTAssertTrue(header.contains("ViftyCopyHIDTemperatures"))
        XCTAssertTrue(implementation.contains("int ViftyCopyHIDTemperatures"))
        XCTAssertFalse(header.contains("ViftyOpenSMC"))
        XCTAssertFalse(implementation.contains("ViftyOpenSMC"))
        XCTAssertFalse(implementation.contains("IOServiceOpen"))
        XCTAssertFalse(implementation.contains("AppleSMCKeysEndpoint"))
        XCTAssertFalse(implementation.contains("SMCEndpoint1"))
    }

    func testAppBundleIsDockVisibleAndHasAppIcon() throws {
        let plist = try read("Resources/Info.plist")
        let makefile = try read("Makefile")
        let iconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/ViftyIcon.icns")

        XCTAssertTrue(plist.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(plist.contains("<string>ViftyIcon</string>"))
        XCTAssertFalse(plist.contains("<key>LSUIElement</key>"))
        XCTAssertTrue(makefile.contains("APP_ICON := Resources/ViftyIcon.icns"))
        XCTAssertTrue(makefile.contains("cp \"$(APP_ICON)\" \"$(CONTENTS)/Resources/ViftyIcon.icns\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
    }

    func testMenuBarAgentCoolingSurfaceShowsTitleRecoveryAndContextualAuto() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")

        XCTAssertTrue(menuBarView.contains("Label(model.agentCoolingPanelTitle, systemImage: \"cpu\")"))
        XCTAssertTrue(menuBarView.contains("if let agentCoolingRecoverySuggestion = model.agentCoolingRecoverySuggestion"))
        XCTAssertTrue(menuBarView.contains("Label(agentCoolingRecoverySuggestion, systemImage: \"exclamationmark.triangle\")"))
        XCTAssertTrue(menuBarView.contains("if model.agentCoolingNeedsAttention, model.agentCoolingRestoreActionAvailable {"))
        XCTAssertTrue(menuBarView.contains("Button(model.agentCoolingRestoreActionTitle) {"))
        XCTAssertTrue(menuBarView.contains(".help(model.agentCoolingRestoreActionHelp)"))
    }

    func testMenuBarPowerRowsAndStatusItemDisplayModeAreWired() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let viftyApp = try read("Sources/Vifty/ViftyApp.swift")
        let statusItemController = try read("Sources/Vifty/ViftyStatusItemController.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")
        let appPreferencesStore = try read("Sources/Vifty/AppPreferencesStore.swift")

        XCTAssertTrue(menuBarView.contains("Text(model.menuPanelTitle)"))
        XCTAssertFalse(menuBarView.contains("Text(model.menuTitle)"))
        XCTAssertTrue(menuBarView.contains("if let sensor = model.selectedSensor {"))
        XCTAssertFalse(menuBarView.contains("if let sensor = model.snapshot?.highestTemperature {"))
        XCTAssertTrue(menuBarView.contains("PowerDisplayFormatter.adapterDetail(for: adapter)"))
        XCTAssertFalse(menuBarView.contains("private func adapterDetail(_ adapter: PowerAdapter)"))
        XCTAssertTrue(menuBarView.contains("Picker(\"Default mode\", selection: $model.startupMode)"))
        XCTAssertTrue(menuBarView.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(contentView.contains("private var menuBarDisplaySettings: some View"))
        XCTAssertTrue(contentView.contains("private var startupModeSettings: some View"))
        XCTAssertTrue(contentView.contains("Picker(\"Default mode\", selection: $model.startupMode)"))
        XCTAssertTrue(contentView.contains("Label(\"Menu bar\", systemImage: \"menubar.rectangle\")"))
        XCTAssertTrue(contentView.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(contentView.contains("ForEach(MenuBarDisplayMode.allCases)"))
        XCTAssertTrue(contentView.contains(".labelsHidden()"))
        XCTAssertFalse(viftyApp.contains("MenuBarExtra {"))
        XCTAssertFalse(viftyApp.contains("MenuBarExtraLabel"))
        XCTAssertTrue(viftyApp.contains("@NSApplicationDelegateAdaptor(ViftyAppDelegate.self) private var appDelegate"))
        XCTAssertTrue(viftyApp.contains("@StateObject private var model: AppModel"))
        XCTAssertTrue(viftyApp.contains("@MainActor\n    init()"))
        XCTAssertTrue(viftyApp.contains("_model = StateObject(wrappedValue: model)"))
        XCTAssertTrue(viftyApp.contains("appDelegate.model = model"))
        XCTAssertTrue(viftyApp.contains("appDelegate.openMainWindowHandler = { openWindow(id: \"main\") }"))
        XCTAssertTrue(viftyApp.contains("model.start()"))
        XCTAssertTrue(viftyApp.contains("Task { @MainActor in\n            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)\n        }"))
        XCTAssertTrue(viftyApp.contains("final class ViftyAppDelegate: NSObject, NSApplicationDelegate"))
        XCTAssertTrue(viftyApp.contains("func applicationDidFinishLaunching(_ notification: Notification)"))
        XCTAssertTrue(viftyApp.contains("model.start()\n        Task { @MainActor in\n            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)\n        }"))
        XCTAssertTrue(viftyApp.contains("await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)"))
        XCTAssertTrue(viftyApp.contains("statusItemController = ViftyStatusItemController("))
        XCTAssertTrue(viftyApp.contains("statusItemController?.openMainWindow = { [weak self] in"))
        XCTAssertTrue(statusItemController.contains("NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)"))
        XCTAssertTrue(statusItemController.contains("model.objectWillChange"))
        XCTAssertTrue(statusItemController.contains("updateStatusItem()"))
        XCTAssertTrue(statusItemController.contains("private static let launchPrimeAttempts = 120"))
        XCTAssertTrue(statusItemController.contains("private static let launchPrimeRetryDelay: Duration = .milliseconds(750)"))
        XCTAssertTrue(statusItemController.contains("scheduleTelemetryPrimeIfNeeded()"))
        XCTAssertTrue(statusItemController.contains("model.$menuBarStatusItemRevision"))
        XCTAssertTrue(statusItemController.contains("primeStatusItemUntilTelemetryResolved("))
        XCTAssertTrue(statusItemController.contains("await model.primeMenuBarStatusItemTelemetry(maxAttempts: 1)"))
        XCTAssertTrue(statusItemController.contains("guard model.menuBarLabelNeedsTelemetryPrime else { return }"))
        XCTAssertTrue(statusItemController.contains("await Task.yield()"))
        XCTAssertTrue(statusItemController.contains("MenuBarView(openMainWindow: { [weak self] in"))
        XCTAssertTrue(statusItemController.contains("let statusItemText = resolvedStatusItemText"))
        XCTAssertTrue(statusItemController.contains("enum ViftyStatusItemPresentation"))
        XCTAssertTrue(statusItemController.contains("guard !labelNeedsTelemetryPrime else { return nil }"))
        XCTAssertTrue(statusItemController.contains("guard let statusItemText, !statusItemText.contains(\"--\") else { return nil }"))
        XCTAssertTrue(statusItemController.contains("ViftyStatusItemPresentation.resolvedText("))
        XCTAssertTrue(statusItemController.contains("button.title = statusItemText ?? \"\""))
        XCTAssertTrue(statusItemController.contains("statusItem.length = NSStatusItem.variableLength"))
        XCTAssertTrue(statusItemController.contains("button.window?.displayIfNeeded()"))
        XCTAssertTrue(statusItemController.contains("NSImage(systemSymbolName: \"fan\""))
        XCTAssertTrue(appModel.contains("private let preferencesStore: AppPreferencesStore"))
        XCTAssertTrue(appModel.contains("private var activePollTask: Task<Void, Never>?"))
        XCTAssertTrue(appModel.contains("@Published private(set) var menuBarStatusItemRevision = 0"))
        XCTAssertTrue(appModel.contains("refreshMenuBarStatusItemIfNeeded(previousLabel: previousMenuBarLabel)"))
        XCTAssertTrue(appModel.contains("private func performPollOnce() async"))
        XCTAssertTrue(appModel.contains("if let activePollTask {\n            await activePollTask.value\n            return\n        }"))
        XCTAssertFalse(appModel.contains("pollingTask = Task { [weak self]"))
        XCTAssertTrue(appModel.contains("func primeMenuBarStatusItemTelemetry("))
        XCTAssertTrue(appModel.contains("var menuBarStatusItemText: String?"))
        XCTAssertTrue(appModel.contains("var menuBarLabelNeedsTelemetryPrime: Bool"))
        XCTAssertTrue(appModel.contains("func applyStartupModePreferenceIfNeeded() async"))
        XCTAssertTrue(appModel.contains("persistAppPreferences()"))
        XCTAssertTrue(appPreferencesStore.contains("var startupMode: ModeSelection"))
        XCTAssertTrue(appPreferencesStore.contains("app-preferences.json"))
        XCTAssertTrue(appPreferencesStore.contains("legacyDefaults: UserDefaults?"))
        XCTAssertTrue(appPreferencesStore.contains(".posixPermissions: NSNumber(value: 0o700)"))
        XCTAssertTrue(appPreferencesStore.contains(".posixPermissions: NSNumber(value: 0o600)"))
        XCTAssertFalse(appModel.contains("preferences.set("))
    }

    func testLocalInstallerRestartsRunningAppBeforeCopyingBundle() throws {
        let installScript = try read("scripts/install-vifty.sh")
        let readme = try read("README.md")

        XCTAssertTrue(installScript.contains("QUIT_RUNNING_APP=\"${QUIT_RUNNING_APP:-1}\""))
        XCTAssertTrue(installScript.contains("WAS_RUNNING=0"))
        XCTAssertTrue(installScript.contains("/usr/bin/pgrep -x \"${APP_NAME}\""))
        XCTAssertTrue(installScript.contains("tell application id \"tech.reidar.vifty\" to quit"))
        XCTAssertTrue(installScript.contains("/usr/bin/pkill -x \"${APP_NAME}\""))
        XCTAssertTrue(installScript.contains("quit_running_app_if_needed"))
        XCTAssertTrue(installScript.contains("\"${OPEN_AFTER_INSTALL}\" == \"1\" || \"${WAS_RUNNING}\" == \"1\""))
        XCTAssertTrue(readme.contains("the installer quits and relaunches it from the newly installed bundle"))
    }

    func testMenuBarCurveProfileSelectorUsesSavedProfiles() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")

        XCTAssertTrue(menuBarView.contains("@State private var selectedMenuCurveProfileID: UUID?"))
        XCTAssertTrue(menuBarView.contains("if !model.savedProfiles.isEmpty"))
        XCTAssertTrue(menuBarView.contains("Picker(\"Curve profile\", selection: $selectedMenuCurveProfileID)"))
        XCTAssertTrue(menuBarView.contains("ForEach(model.savedProfiles)"))
        XCTAssertTrue(menuBarView.contains("_ = model.selectCurveProfile(id: newID)"))
        XCTAssertTrue(appModel.contains("func selectCurveProfile(id profileID: CurveProfile.ID?) -> Bool"))
        XCTAssertTrue(appModel.contains("selectedMode = .curve\n        loadProfile(profile)"))
    }

    func testMenuBarHighTemperatureAttentionIsWired() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")

        XCTAssertTrue(appModel.contains("static let highTemperatureAttentionThreshold = 90.0"))
        XCTAssertTrue(appModel.contains("var temperatureAttentionSummary: String?"))
        XCTAssertTrue(appModel.contains("return sensor.celsius >= Self.highTemperatureAttentionThreshold ? \"High temp\" : nil"))
        XCTAssertTrue(appModel.contains("var fanWriteBlockedWhileHotSummary: String?"))
        XCTAssertTrue(appModel.contains("var fanWriteBlockedWhileHotRecoverySuggestion: String?"))
        XCTAssertTrue(appModel.contains("parts.append(\"Fan writes blocked\")"))
        XCTAssertTrue(menuBarView.contains("if let fanWriteBlockedWhileHotSummary = model.fanWriteBlockedWhileHotSummary"))
        XCTAssertTrue(menuBarView.contains("if let recovery = model.fanWriteBlockedWhileHotRecoverySuggestion"))
        XCTAssertTrue(menuBarView.contains("if let temperatureAttentionSummary = model.temperatureAttentionSummary"))
        XCTAssertTrue(menuBarView.contains("Label(temperatureAttentionSummary, systemImage: \"thermometer.high\")"))
        XCTAssertTrue(menuBarView.contains(".foregroundStyle(.orange)"))
    }

    func testMainWindowHotBlockedHelperAttentionIsWired() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("if let fanWriteBlockedWhileHotSummary = model.fanWriteBlockedWhileHotSummary"))
        XCTAssertTrue(contentView.contains("Text(fanWriteBlockedWhileHotSummary)"))
        XCTAssertTrue(contentView.contains("if let recovery = model.fanWriteBlockedWhileHotRecoverySuggestion"))
        XCTAssertTrue(contentView.contains("Text(recovery)"))
        XCTAssertTrue(contentView.contains(".background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))"))
    }

    func testMainWindowManualPendingHelperAttentionIsWired() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")

        XCTAssertTrue(appModel.contains("var manualControlAttentionSummary: String?"))
        XCTAssertTrue(appModel.contains("request pending · fan writes blocked"))
        XCTAssertTrue(appModel.contains("Use \\(autoRestoreActionTitle) to stop retries; copy support evidence if repair does not clear it."))
        XCTAssertTrue(appModel.contains("var modeSelectionActionRestoresAuto: Bool"))
        XCTAssertTrue(appModel.contains("selectedMode == .auto || manualControlAttentionSummary != nil"))
        XCTAssertTrue(appModel.contains("var modeSelectionActionDisabled: Bool"))
        XCTAssertTrue(appModel.contains("var helperSupportEvidenceContext: HelperSupportEvidenceContext"))
        XCTAssertTrue(appModel.contains("hotFanWrites="))
        XCTAssertTrue(appModel.contains("controlOwner="))
        XCTAssertTrue(contentView.contains("if let manualControlAttentionSummary = model.manualControlAttentionSummary"))
        XCTAssertTrue(contentView.contains("hourglass.badge.exclamationmark"))
        XCTAssertTrue(contentView.contains("model.performModeSelectionAction()"))
        XCTAssertTrue(contentView.contains(".disabled(model.modeSelectionActionDisabled)"))
        XCTAssertTrue(contentView.contains("if let recovery = model.manualControlAttentionRecoverySuggestion"))
        XCTAssertTrue(contentView.contains("Text(recovery)"))
    }

    func testFixedRPMPerFanEditorShowsFanSpecificRanges() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("Toggle(\"Per-fan targets\", isOn: $model.usePerFanFixedRPM)"))
        XCTAssertTrue(contentView.contains(".accessibilityLabel(\"Per-fan fixed RPM targets\")"))
        XCTAssertTrue(contentView.contains(".accessibilityHint(\"Set separate fixed RPM targets for each fan.\")"))
        XCTAssertTrue(contentView.contains("let controllableFans = fans.filter(\\.controllable)"))
        XCTAssertTrue(contentView.contains("if controllableFans.count > 1"))
        XCTAssertTrue(contentView.contains("model.ensureFixedFanTargets(for: controllableFans)"))
        XCTAssertTrue(contentView.contains("let targetRPM = model.fixedFanTargetRPM(for: fan)"))
        XCTAssertTrue(contentView.contains("let targetPercent = model.fixedFanTargetPercent(for: fan)"))
        XCTAssertTrue(contentView.contains("Text(\"\\(targetRPM) RPM · \\(targetPercent)%\")"))
        XCTAssertFalse(contentView.contains("Text(\"Range \\(fan.minimumRPM)-\\(fan.maximumRPM) RPM\")"))
        XCTAssertTrue(contentView.contains("in: Double(fan.minimumRPM)...Double(fan.maximumRPM)"))
        XCTAssertTrue(contentView.contains(".help(\"\\(fan.name) fixed target. Range \\(fan.minimumRPM)-\\(fan.maximumRPM) RPM; currently \\(targetPercent)% of that fan's range.\")"))
        XCTAssertTrue(contentView.contains(".accessibilityLabel(\"\\(fan.name) fixed RPM target\")"))
        XCTAssertTrue(contentView.contains(".accessibilityValue(\"\\(targetRPM) RPM, \\(targetPercent)%\")"))
        XCTAssertTrue(contentView.contains(".accessibilityHint(\"\\(fan.name) target is clamped to \\(fan.minimumRPM)-\\(fan.maximumRPM) RPM.\")"))
        XCTAssertTrue(contentView.contains(".accessibilityLabel(\"Fixed RPM target\")"))
        XCTAssertTrue(contentView.contains(".accessibilityHint(\"Sets one fixed target for every controllable fan.\")"))
        XCTAssertTrue(contentView.contains("private struct CompactFanOverrideEditor: View"))
        XCTAssertTrue(contentView.contains("Stepper(value: startBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50)"))
        XCTAssertTrue(contentView.contains("Stepper(value: midBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50)"))
        XCTAssertTrue(contentView.contains("Stepper(value: maxBinding, in: fan.minimumRPM...fan.maximumRPM, step: 50)"))
        XCTAssertFalse(contentView.contains("Text(\"Fan \\(fan.id): \\(fan.name)\")"))
    }

    func testMenuBarNotificationSettingsAreWired() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")
        let notifications = try read("Sources/Vifty/LocalNotifications.swift")

        XCTAssertTrue(menuBarView.contains("Label(\"Notifications\", systemImage: \"bell\")"))
        XCTAssertTrue(menuBarView.contains("Toggle(\"Helper failure\", isOn: $model.notificationSettings.helperFailure)"))
        XCTAssertTrue(menuBarView.contains("Toggle(\"High thermal pressure\", isOn: $model.notificationSettings.elevatedThermalPressure)"))
        XCTAssertTrue(menuBarView.contains("Toggle(\"Auto restore failure\", isOn: $model.notificationSettings.autoRestoreFailure)"))
        XCTAssertTrue(menuBarView.contains("Toggle(\"Plugged-in battery drain\", isOn: $model.notificationSettings.pluggedInBatteryDrain)"))
        XCTAssertTrue(menuBarView.contains("Toggle(\"Agent cooling attention\", isOn: $model.notificationSettings.agentCoolingAttention)"))
        XCTAssertTrue(appModel.contains("notificationMinimumInterval: TimeInterval = 10 * 60"))
        XCTAssertTrue(appModel.contains("previousAgentCoolingNeedsAttention"))
        XCTAssertTrue(appModel.contains("sustainedThermalPressureInterval: TimeInterval = 60"))
        XCTAssertTrue(notifications.contains("UNUserNotificationCenter"))
        XCTAssertTrue(notifications.contains("XCTestConfigurationFilePath"))
        XCTAssertTrue(notifications.contains("processName == \"xctest\""))
        XCTAssertTrue(notifications.contains("static let disabled = LocalNotificationSettings()"))
    }

    func testGlobalAutoActionsUseContextualRequestCopy() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let appModel = try read("Sources/Vifty/AppModel.swift")

        XCTAssertTrue(appModel.contains("var autoRestoreActionTitle: String"))
        XCTAssertTrue(appModel.contains("var modeSelectionActionTitle: String"))
        XCTAssertTrue(appModel.contains("helperWritePathBlockedSummary == nil ? \"Auto\" : \"Request Auto\""))
        XCTAssertTrue(appModel.contains("Request Auto restore; the write cannot be confirmed until the helper responds"))
        XCTAssertTrue(contentView.contains("Label(model.modeSelectionActionTitle"))
        XCTAssertTrue(contentView.contains(".help(model.modeSelectionActionHelp)"))
        XCTAssertFalse(contentView.contains("Label(\"Apply\""))
        XCTAssertTrue(menuBarView.contains("Button(model.autoRestoreActionTitle)"))
        XCTAssertTrue(menuBarView.contains(".help(model.autoRestoreActionHelp)"))
        XCTAssertFalse(menuBarView.contains("Button(\"Auto\")"))
    }

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
