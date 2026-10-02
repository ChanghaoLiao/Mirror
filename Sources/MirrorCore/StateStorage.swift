import Foundation

public protocol StateStorage {
    func load() throws -> SavedState
    func save(_ state: SavedState) throws
}

public enum StorageError: Error, LocalizedError {
    case unsupportedVersion
    case invalidState
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This state file belongs to a newer Mirror version."
        case .invalidState: return "Mirror state is invalid. The existing file has been preserved."
        }
    }
}

public struct JSONStateStorage: StateStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw StorageError.unsupportedVersion }
        let ids = Set(state.workspaces.map(\.id))
        guard ids.count == state.workspaces.count,
            Set(state.references.map(\.id)).count == state.references.count,
            state.references.allSatisfy({
                ids.contains($0.workspaceID) && $0.frame.width.isFinite && $0.frame.height.isFinite
                    && $0.frame.x.isFinite && $0.frame.y.isFinite
                    && $0.frame.width >= 280 && $0.frame.height >= 240
                    && (11...26).contains($0.settings.fontSize)
                    && ($0.anchor.map { $0.block >= 0 && $0.character >= 0 && $0.offset.isFinite } ?? true)
            })
        else { throw StorageError.invalidState }
        return state
    }
    public func save(_ state: SavedState) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
