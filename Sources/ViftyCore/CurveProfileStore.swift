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
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
