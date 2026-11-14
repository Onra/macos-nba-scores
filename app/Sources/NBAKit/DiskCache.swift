import Foundation

/// JSON files under ~/Library/Caches/nba-bar. A file's age is the time since it was written.
public struct DiskCache: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("nba-bar")
    }

    private func file(_ key: String) -> URL {
        directory.appendingPathComponent(key + ".json")
    }

    public func load<T: Decodable>(_ type: T.Type = T.self, _ key: String) -> (value: T, age: TimeInterval)? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return (value, written.map { Date().timeIntervalSince($0) } ?? .infinity)
    }

    /// The cached value, when it is younger than `maxAge` seconds.
    public func fresh<T: Decodable>(_ type: T.Type = T.self, _ key: String, maxAge: TimeInterval) -> T? {
        guard let hit = load(T.self, key), hit.age < maxAge else { return nil }
        return hit.value
    }

    public func save<T: Encodable>(_ value: T, _ key: String) {
        let url = file(key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
