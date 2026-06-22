import Foundation

struct AppPreferences: Codable, Equatable {
    var menuBarDisplayMode: MenuBarDisplayMode
    var startupMode: ModeSelection
    var notificationSettings: LocalNotificationSettings
    var usePerFanFixedRPM: Bool
    var fixedFanTargets: [FixedFanTarget]
    var codexUsageDisplayPreferences: CodexUsageDisplayPreferences

    static let defaults = AppPreferences(
        menuBarDisplayMode: .fanIcon,
        startupMode: .auto,
        notificationSettings: .disabled,
        usePerFanFixedRPM: false,
        fixedFanTargets: [],
        codexUsageDisplayPreferences: .defaults
    )

    init(
        menuBarDisplayMode: MenuBarDisplayMode,
        startupMode: ModeSelection = .auto,
        notificationSettings: LocalNotificationSettings,
        usePerFanFixedRPM: Bool = false,
        fixedFanTargets: [FixedFanTarget] = [],
        codexUsageDisplayPreferences: CodexUsageDisplayPreferences = .defaults
    ) {
        self.menuBarDisplayMode = menuBarDisplayMode
        self.startupMode = startupMode
        self.notificationSettings = notificationSettings
        self.usePerFanFixedRPM = usePerFanFixedRPM
        self.fixedFanTargets = fixedFanTargets
        self.codexUsageDisplayPreferences = codexUsageDisplayPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .fanIcon
        startupMode = try container.decodeIfPresent(ModeSelection.self, forKey: .startupMode) ?? .auto
        notificationSettings = try container.decodeIfPresent(LocalNotificationSettings.self, forKey: .notificationSettings) ?? .disabled
        usePerFanFixedRPM = try container.decodeIfPresent(Bool.self, forKey: .usePerFanFixedRPM) ?? false
        fixedFanTargets = try container.decodeIfPresent([FixedFanTarget].self, forKey: .fixedFanTargets) ?? []
        codexUsageDisplayPreferences = try container.decodeIfPresent(
            CodexUsageDisplayPreferences.self,
            forKey: .codexUsageDisplayPreferences
        ) ?? .defaults
    }
}

final class AppPreferencesStore: @unchecked Sendable {
    static let legacyMenuBarDisplayModeDefaultsKey = "menuBarDisplayMode"
    static let legacyNotificationHelperFailureDefaultsKey = "notification.helperFailure"
    static let legacyNotificationThermalPressureDefaultsKey = "notification.elevatedThermalPressure"
    static let legacyNotificationAutoRestoreDefaultsKey = "notification.autoRestoreFailure"
    static let legacyNotificationPluggedInDrainDefaultsKey = "notification.pluggedInBatteryDrain"
    static let legacyNotificationAgentCoolingAttentionDefaultsKey = "notification.agentCoolingAttention"

    private let url: URL
    private let legacyDefaults: UserDefaults?

    init(url: URL? = nil, legacyDefaults: UserDefaults? = .standard) {
        self.url = url ?? Self.defaultURL()
        self.legacyDefaults = legacyDefaults
    }

    func load() -> AppPreferences {
        if let data = try? Data(contentsOf: url),
           let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            return preferences
        }

        let migrated = migratedPreferences()
        if migrated != .defaults {
            try? saveThrowing(migrated)
        }
        return migrated
    }

    func save(_ preferences: AppPreferences) {
        try? saveThrowing(preferences)
    }

    func saveThrowing(_ preferences: AppPreferences) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directory.path)

        let data = try JSONEncoder().encode(preferences)
        try data.write(to: url, options: .atomic)
        try restrictFilePermissions(at: url)
    }

    private func migratedPreferences() -> AppPreferences {
        guard let legacyDefaults else {
            return .defaults
        }

        return AppPreferences(
            menuBarDisplayMode: Self.loadLegacyMenuBarDisplayMode(from: legacyDefaults),
            notificationSettings: Self.loadLegacyNotificationSettings(from: legacyDefaults)
        )
    }

    private static func loadLegacyMenuBarDisplayMode(from defaults: UserDefaults) -> MenuBarDisplayMode {
        guard let rawValue = defaults.string(forKey: legacyMenuBarDisplayModeDefaultsKey),
              let displayMode = MenuBarDisplayMode(rawValue: rawValue)
        else {
            return .fanIcon
        }
        return displayMode
    }

    private static func loadLegacyNotificationSettings(from defaults: UserDefaults) -> LocalNotificationSettings {
        LocalNotificationSettings(
            helperFailure: defaults.bool(forKey: legacyNotificationHelperFailureDefaultsKey),
            elevatedThermalPressure: defaults.bool(forKey: legacyNotificationThermalPressureDefaultsKey),
            autoRestoreFailure: defaults.bool(forKey: legacyNotificationAutoRestoreDefaultsKey),
            pluggedInBatteryDrain: defaults.bool(forKey: legacyNotificationPluggedInDrainDefaultsKey),
            agentCoolingAttention: defaults.bool(forKey: legacyNotificationAgentCoolingAttentionDefaultsKey)
        )
    }

    private func restrictFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    }

    private static func defaultURL() -> URL {
        if isRunningUnderXCTest {
            return FileManager.default
                .temporaryDirectory
                .appendingPathComponent("vifty-app-preferences-xctest")
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("app-preferences.json")
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/app-preferences.json")
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}
