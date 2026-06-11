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
        try? saveThrowing(profiles)
    }

    public func saveThrowing(_ profiles: [CurveProfile]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let attr: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o700)]
        try FileManager.default.setAttributes(attr, ofItemAtPath: directory.path)

        // Write a backup before overwriting the main file.
        if FileManager.default.fileExists(atPath: url.path) {
            let backupURL = url.appendingPathExtension("bak")
            copyBackupIfPossible(from: url, to: backupURL)
        }

        let data = try JSONEncoder().encode(profiles)
        try data.write(to: url, options: .atomic)
        try restrictFilePermissions(at: url)

        // Always ensure a backup copy exists after saving.
        let backupURL = url.appendingPathExtension("bak")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            copyBackupIfPossible(from: url, to: backupURL)
        }
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? restrictFilePermissions(at: backupURL)
        }
    }

    private func copyBackupIfPossible(from sourceURL: URL, to backupURL: URL) {
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: backupURL)
            try restrictFilePermissions(at: backupURL)
        } catch {
            // Backups are best-effort; saving the primary profile file is what
            // should report success or failure to the caller.
        }
    }

    private func restrictFilePermissions(at url: URL) throws {
        let attr: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: 0o600)]
        try FileManager.default.setAttributes(attr, ofItemAtPath: url.path)
    }
}
