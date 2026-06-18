import Foundation

public enum ViftyAppStartupMode: String, Codable, Equatable, Sendable, CaseIterable {
    case auto = "Auto"
    case curve = "Curve"
    case fixed = "Fixed"
}

public enum ViftyAppPreferencesSource: String, Codable, Equatable, Sendable {
    case persisted
    case defaultMissingFile
    case defaultMissingKey
    case unreadable
    case unavailable
}

public struct ViftyAppPreferencesDiagnostic: Codable, Equatable, Sendable {
    public var startupMode: ViftyAppStartupMode?
    public var startupModeSource: ViftyAppPreferencesSource
    public var readError: String?

    private enum CodingKeys: String, CodingKey {
        case startupMode
        case startupModeSource
        case readError
    }

    public init(
        startupMode: ViftyAppStartupMode?,
        startupModeSource: ViftyAppPreferencesSource,
        readError: String? = nil
    ) {
        self.startupMode = startupMode
        self.startupModeSource = startupModeSource
        self.readError = readError
    }

    public static let unavailable = ViftyAppPreferencesDiagnostic(
        startupMode: nil,
        startupModeSource: .unavailable
    )

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startupMode = try container.decodeIfPresent(ViftyAppStartupMode.self, forKey: .startupMode)
        startupModeSource = try container.decode(ViftyAppPreferencesSource.self, forKey: .startupModeSource)
        readError = try container.decodeIfPresent(String.self, forKey: .readError)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let startupMode {
            try container.encode(startupMode, forKey: .startupMode)
        } else {
            try container.encodeNil(forKey: .startupMode)
        }
        try container.encode(startupModeSource, forKey: .startupModeSource)
        if let readError {
            try container.encode(readError, forKey: .readError)
        } else {
            try container.encodeNil(forKey: .readError)
        }
    }
}

public struct ViftyAppPreferencesDiagnosticReader: Sendable {
    private struct StoredPreferences: Decodable {
        var startupMode: ViftyAppStartupMode?
    }

    private let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/app-preferences.json")
    }

    public func read() -> ViftyAppPreferencesDiagnostic {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ViftyAppPreferencesDiagnostic(
                startupMode: .auto,
                startupModeSource: .defaultMissingFile
            )
        }

        do {
            let data = try Data(contentsOf: url)
            let preferences = try JSONDecoder().decode(StoredPreferences.self, from: data)
            guard let startupMode = preferences.startupMode else {
                return ViftyAppPreferencesDiagnostic(
                    startupMode: .auto,
                    startupModeSource: .defaultMissingKey
                )
            }
            return ViftyAppPreferencesDiagnostic(
                startupMode: startupMode,
                startupModeSource: .persisted
            )
        } catch {
            return ViftyAppPreferencesDiagnostic(
                startupMode: nil,
                startupModeSource: .unreadable,
                readError: error.localizedDescription
            )
        }
    }
}
