import Foundation

public final class CurveProfileStore: @unchecked Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/curve-profiles.json")
    }

    public func load() -> [CurveProfile] {
        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([CurveProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    public func save(_ profiles: [CurveProfile]) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var attr: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o700)]
        try? FileManager.default.setAttributes(attr, ofItemAtPath: directory.path)

        // Write a backup before overwriting the main file.
        if FileManager.default.fileExists(atPath: url.path) {
            let backupURL = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: url, to: backupURL)
        }

        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
        attr = [.posixPermissions: NSNumber(value: 0o600)]
        try? FileManager.default.setAttributes(attr, ofItemAtPath: url.path)

        // Always ensure a backup copy exists after saving.
        let backupURL = url.appendingPathExtension("bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: url, to: backupURL)
        }
    }
}
