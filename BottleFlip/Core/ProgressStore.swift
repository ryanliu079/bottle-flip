import Foundation

public struct ProgressStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    private struct Save: Codable { let version: Int; let player: PlayerProgress }
    public enum StoreError: Error { case unsupportedVersion }
    public func load() throws -> PlayerProgress? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let save = try JSONDecoder().decode(Save.self, from: Data(contentsOf: url))
        guard save.version == 1 else { throw StoreError.unsupportedVersion }
        return save.player
    }
    public func save(_ player: PlayerProgress) throws {
        let data = try JSONEncoder().encode(Save(version: 1, player: player))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
