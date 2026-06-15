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
        XCTAssertTrue(menuBarView.contains("@State private var helperDiagnosticsCopied = false"))
        XCTAssertTrue(menuBarView.contains("model.helperHealthMenuSummary"))
        XCTAssertTrue(menuBarView.contains("model.helperMenuRecoverySuggestion"))
        XCTAssertFalse(menuBarView.contains("model.helperRecoverySuggestion"))
        XCTAssertTrue(menuBarView.contains("Button {\n                            copyHelperDiagnosticsCommand()\n                        } label: {\n                            Label(\"Copy Support Evidence\", systemImage: \"doc.on.doc\")"))
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
        XCTAssertTrue(contentView.contains("@State private var helperDiagnosticsCopied = false"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable || model.helperHealthNeedsAttention {"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable {\n                            Button(daemonInstaller.actionTitle)"))
        XCTAssertTrue(contentView.contains("Button {\n                            copyHelperDiagnosticsCommand()\n                        } label: {\n                            Label(\"Copy Support Evidence\", systemImage: \"doc.on.doc\")"))
        XCTAssertTrue(contentView.contains(".help(HelperDiagnosticsSupport.copyHelp)"))
        XCTAssertTrue(contentView.contains("Text(HelperDiagnosticsSupport.copiedMessage)"))
        XCTAssertTrue(contentView.contains("Text(suggestion)"))
        XCTAssertTrue(contentView.contains(".fixedSize(horizontal: false, vertical: true)"))
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
        XCTAssertTrue(contentView.contains("PowerPanel(snapshot: power, compact: compact)"))
        XCTAssertTrue(contentView.contains("HistoryPanel(history: model.telemetryHistory, compact: compact)"))
        XCTAssertTrue(contentView.contains("SensorRow(sensor: sensor, selected: sensor.id == model.selectedSensor?.id, compact: compact)"))
        XCTAssertTrue(contentView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
        XCTAssertTrue(contentView.contains("PowerDisplayFormatter.panelHeadline(for: snapshot)"))
        XCTAssertTrue(contentView.contains("if let adapter = snapshot.adapter, adapter.powerWatts >= 0.5, adapterLine == nil"))
        XCTAssertTrue(contentView.contains("PowerDisplayFormatter.adapterDescription(for: adapter)"))
        XCTAssertFalse(contentView.contains("if let sensors = model.snapshot?.temperatureSensors, !sensors.isEmpty {\n                ScrollView {"))
    }

    func testHistoryPanelShowsLocalSparklineVisualization() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("TelemetryHistoryChart(samples: history.samples, compact: compact)"))
        XCTAssertTrue(contentView.contains("private struct TelemetryHistoryChart: View"))
        XCTAssertTrue(contentView.contains("title: \"Temp\""))
        XCTAssertTrue(contentView.contains("title: \"Fan\""))
        XCTAssertTrue(contentView.contains("title: \"Power\""))
        XCTAssertTrue(contentView.contains("ThermalPressureTrail(samples: recentSamples, compact: compact)"))
        XCTAssertTrue(contentView.contains("private struct SparklinePath: View"))
        XCTAssertFalse(contentView.contains("UserDefaults.standard.set(history"))
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
        let appModel = try read("Sources/Vifty/AppModel.swift")
        let appPreferencesStore = try read("Sources/Vifty/AppPreferencesStore.swift")

        XCTAssertTrue(menuBarView.contains("Text(model.menuPanelTitle)"))
        XCTAssertFalse(menuBarView.contains("Text(model.menuTitle)"))
        XCTAssertTrue(menuBarView.contains("if let sensor = model.selectedSensor {"))
        XCTAssertFalse(menuBarView.contains("if let sensor = model.snapshot?.highestTemperature {"))
        XCTAssertTrue(menuBarView.contains("PowerDisplayFormatter.adapterDetail(for: adapter)"))
        XCTAssertFalse(menuBarView.contains("private func adapterDetail(_ adapter: PowerAdapter)"))
        XCTAssertTrue(menuBarView.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(contentView.contains("private var menuBarDisplaySettings: some View"))
        XCTAssertTrue(contentView.contains("Label(\"Menu bar\", systemImage: \"menubar.rectangle\")"))
        XCTAssertTrue(contentView.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(contentView.contains("ForEach(MenuBarDisplayMode.allCases)"))
        XCTAssertTrue(contentView.contains(".labelsHidden()"))
        XCTAssertTrue(viftyApp.contains("MenuBarExtra {"))
        XCTAssertTrue(viftyApp.contains("MenuBarExtraLabel(model: model)"))
        XCTAssertTrue(appModel.contains("private let preferencesStore: AppPreferencesStore"))
        XCTAssertTrue(appModel.contains("persistAppPreferences()"))
        XCTAssertTrue(appPreferencesStore.contains("app-preferences.json"))
        XCTAssertTrue(appPreferencesStore.contains("legacyDefaults: UserDefaults?"))
        XCTAssertTrue(appPreferencesStore.contains(".posixPermissions: NSNumber(value: 0o700)"))
        XCTAssertTrue(appPreferencesStore.contains(".posixPermissions: NSNumber(value: 0o600)"))
        XCTAssertFalse(appModel.contains("preferences.set("))
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

    private func read(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
