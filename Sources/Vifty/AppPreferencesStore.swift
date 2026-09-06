import Foundation

struct AppPreferences: Codable, Equatable {
    var menuBarDisplayMode: MenuBarDisplayMode
    var menuBarCustomFields: [MenuBarField]
    var startupMode: ModeSelection
    var textScale: ViftyTextScale
    var notificationSettings: LocalNotificationSettings
    var usePerFanFixedRPM: Bool
    var fixedFanTargets: [FixedFanTarget]
    var codexUsageDisplayPreferences: CodexUsageDisplayPreferences

    static let defaults = AppPreferences(
        menuBarDisplayMode: .fanIcon,
        menuBarCustomFields: MenuBarField.defaultCustomFields,
        startupMode: .auto,
        textScale: .standard,
        notificationSettings: .disabled,
        usePerFanFixedRPM: false,
        fixedFanTargets: [],
        codexUsageDisplayPreferences: .defaults
    )

    init(
        menuBarDisplayMode: MenuBarDisplayMode,
        menuBarCustomFields: [MenuBarField] = MenuBarField.defaultCustomFields,
        startupMode: ModeSelection = .auto,
        textScale: ViftyTextScale = .standard,
        notificationSettings: LocalNotificationSettings,
        usePerFanFixedRPM: Bool = false,
        fixedFanTargets: [FixedFanTarget] = [],
        codexUsageDisplayPreferences: CodexUsageDisplayPreferences = .defaults
    ) {
        self.menuBarDisplayMode = menuBarDisplayMode
        self.menuBarCustomFields = MenuBarField.normalized(menuBarCustomFields)
        self.startupMode = startupMode
        self.textScale = textScale
        self.notificationSettings = notificationSettings
        self.usePerFanFixedRPM = usePerFanFixedRPM
        self.fixedFanTargets = fixedFanTargets
        self.codexUsageDisplayPreferences = codexUsageDisplayPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .fanIcon
        menuBarCustomFields = MenuBarField.normalized(
            try container.decodeIfPresent([MenuBarField].self, forKey: .menuBarCustomFields) ?? MenuBarField.defaultCustomFields
        )
        startupMode = try container.decodeIfPresent(ModeSelection.self, forKey: .startupMode) ?? .auto
        textScale = try container.decodeIfPresent(ViftyTextScale.self, forKey: .textScale) ?? .standard
        notificationSettings = try container.decodeIfPresent(LocalNotificationSettings.self, forKey: .notificationSettings) ?? .disabled
        usePerFanFixedRPM = try container.decodeIfPresent(Bool.self, forKey: .usePerFanFixedRPM) ?? false
        fixedFanTargets = try container.decodeIfPresent([FixedFanTarget].self, forKey: .fixedFanTargets) ?? []
        codexUsageDisplayPreferences = try container.decodeIfPresent(
            CodexUsageDisplayPreferences.self,
            forKey: .codexUsageDisplayPreferences
        ) ?? .defaults
    }
}

struct AppPreferencesLoadResult: Equatable {
    var preferences: AppPreferences
    var recoveryMessage: String?
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
        (try? loadResult().preferences) ?? migratedPreferences()
    }

    func loadResult() throws -> AppPreferencesLoadResult {
        switch decodePreferences(at: url) {
        case .success(let preferences):
            try? restrictDirectoryPermissions()
            try? restrictFilePermissions(at: url)
            return AppPreferencesLoadResult(preferences: preferences, recoveryMessage: nil)
        case .missing, .failure:
            break
        }

        switch decodePreferences(at: backupURL) {
        case .success(let preferences):
            try? restrictDirectoryPermissions()
            try? restrictFilePermissions(at: backupURL)
            if case .failure = decodePreferences(at: url) {
                quarantinePrimaryIfPossible()
            }
            return AppPreferencesLoadResult(
                preferences: preferences,
                recoveryMessage: "Vifty loaded its private app-preferences backup."
            )
        case .missing, .failure:
            let migrated = migratedPreferences()
            if migrated != .defaults {
                try saveThrowing(migrated)
            }
            return AppPreferencesLoadResult(preferences: migrated, recoveryMessage: nil)
        }
    }

    func save(_ preferences: AppPreferences) {
        try? saveThrowing(preferences)
    }

    func saveThrowing(_ preferences: AppPreferences) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: directory.path)

        if case .success = decodePreferences(at: url),
           let primaryData = try? Data(contentsOf: url) {
            replaceBackupIfPossible(with: primaryData)
        }

        let data = try JSONEncoder().encode(preferences)
        try data.write(to: url, options: .atomic)
        try restrictFilePermissions(at: url)

        if case .success = decodePreferences(at: backupURL) {
            try? restrictFilePermissions(at: backupURL)
        } else {
            replaceBackupIfPossible(with: data)
        }
    }

    private var backupURL: URL {
        url.appendingPathExtension("bak")
    }

    private enum DecodeResult {
        case success(AppPreferences)
        case missing
        case failure
    }

    private func decodePreferences(at fileURL: URL) -> DecodeResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            return .success(try JSONDecoder().decode(AppPreferences.self, from: Data(contentsOf: fileURL)))
        } catch {
            return .failure
        }
    }

    private func replaceBackupIfPossible(with data: Data) {
        let temporaryURL = backupURL.deletingLastPathComponent().appendingPathComponent(
            ".\(backupURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try restrictFilePermissions(at: temporaryURL)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    backupURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: backupURL)
            }
            try restrictFilePermissions(at: backupURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    private func quarantinePrimaryIfPossible() {
        let quarantineURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).corrupt.\(UUID().uuidString)"
        )
        do {
            try FileManager.default.moveItem(at: url, to: quarantineURL)
            try restrictFilePermissions(at: quarantineURL)
        } catch {
            // Recovery from a valid backup must not depend on quarantine I/O.
        }
    }

    private func restrictDirectoryPermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
    }

    private func migratedPreferences() -> AppPreferences {
        guard let legacyDefaults else {
            return .defaults
        }

        return AppPreferences(
            menuBarDisplayMode: Self.loadLegacyMenuBarDisplayMode(from: legacyDefaults),
            menuBarCustomFields: MenuBarField.defaultCustomFields,
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
