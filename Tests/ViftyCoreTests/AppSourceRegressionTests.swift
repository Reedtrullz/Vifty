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
        XCTAssertTrue(menuBarView.contains("if let helperRecoverySuggestion = model.helperRecoverySuggestion {\n                Label(helperRecoverySuggestion, systemImage: \"wrench.and.screwdriver\")\n                    .font(.caption)\n                    .foregroundStyle(.secondary)\n                    .lineLimit(4)"))
        XCTAssertEqual(menuBarView.components(separatedBy: "await model.pollOnce()").count - 1, 2)
        XCTAssertTrue(menuBarView.contains("helperRefreshTask?.cancel()"))
    }

    func testMainWindowHelperHealthShowsInstallerActionDescription() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("daemonInstaller.actionDescription"))
        XCTAssertTrue(contentView.contains("model.helperRepairActionAvailable ? daemonInstaller.actionDescription : nil"))
        XCTAssertTrue(contentView.contains("if model.helperRepairActionAvailable {\n                    Button(daemonInstaller.actionTitle)"))
        XCTAssertTrue(contentView.contains("if let suggestion = model.helperRecoverySuggestion {\n                        Text(suggestion)\n                            .font(.caption)\n                            .foregroundStyle(.secondary)\n                            .lineLimit(4)"))
    }

    func testMainWindowPanesAreIndependentlyScrollableAndFillAvailableHeight() throws {
        let contentView = try read("Sources/Vifty/ContentView.swift")

        XCTAssertTrue(contentView.contains("private var mainContent: some View"))
        XCTAssertTrue(contentView.contains("GeometryReader { proxy in"))
        XCTAssertTrue(contentView.contains("let compactTelemetry = proxy.size.height < 640 || proxy.size.width < 920"))
        XCTAssertTrue(contentView.contains("ScrollView(.vertical) {\n                    fanControlPane"))
        XCTAssertTrue(contentView.contains("ScrollView(.vertical) {\n                    sensorsPane(compact: compactTelemetry)"))
        XCTAssertTrue(contentView.contains(".scrollIndicators(.visible)"))
        XCTAssertTrue(contentView.contains(".frame(minWidth: 360, idealWidth: 400, maxWidth: 420, minHeight: proxy.size.height, maxHeight: proxy.size.height)"))
        XCTAssertTrue(contentView.contains("Divider()\n                    .frame(height: proxy.size.height)"))
        XCTAssertTrue(contentView.contains(".background(Color.secondary.opacity(0.035))"))
        XCTAssertTrue(contentView.contains("PowerPanel(snapshot: power, compact: compact)"))
        XCTAssertTrue(contentView.contains("HistoryPanel(history: model.telemetryHistory, compact: compact)"))
        XCTAssertTrue(contentView.contains("SensorRow(sensor: sensor, selected: sensor.id == model.selectedSensor?.id, compact: compact)"))
        XCTAssertTrue(contentView.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"))
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
        XCTAssertTrue(menuBarView.contains("if model.agentCoolingNeedsAttention {"))
        XCTAssertTrue(menuBarView.contains("Button(\"Auto\") {"))
        XCTAssertTrue(menuBarView.contains("Restore Auto before starting another agent workload"))
    }

    func testMenuBarPowerRowsAndStatusItemDisplayModeAreWired() throws {
        let menuBarView = try read("Sources/Vifty/MenuBarView.swift")
        let viftyApp = try read("Sources/Vifty/ViftyApp.swift")

        XCTAssertTrue(menuBarView.contains("Text(model.menuPanelTitle)"))
        XCTAssertFalse(menuBarView.contains("Text(model.menuTitle)"))
        XCTAssertTrue(menuBarView.contains("if let sensor = model.selectedSensor {"))
        XCTAssertFalse(menuBarView.contains("if let sensor = model.snapshot?.highestTemperature {"))
        XCTAssertTrue(menuBarView.contains("PowerDisplayFormatter.adapterDetail(for: adapter)"))
        XCTAssertFalse(menuBarView.contains("private func adapterDetail(_ adapter: PowerAdapter)"))
        XCTAssertTrue(menuBarView.contains("Picker(\"Menu bar\", selection: $model.menuBarDisplayMode)"))
        XCTAssertTrue(viftyApp.contains("MenuBarExtra {"))
        XCTAssertTrue(viftyApp.contains("MenuBarExtraLabel(model: model)"))
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
