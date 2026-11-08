import Foundation

/// Coalesces the board, tracked-card and open-detail consumers of the same service.
actor DarwinResponseCache {
    static let shared = DarwinResponseCache()
    private struct Identity: Hashable { let url: URL; let key: String }
    private var entries: [Identity: (Date, Data)] = [:]
    private var pending: [Identity: Task<Data, Error>] = [:]

    func load(url: URL, key: String, lifetime: TimeInterval = 20, operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let identity = Identity(url: url, key: key)
        if let entry = entries[identity], Date() < entry.0 { return entry.1 }
        if let task = pending[identity] { return try await task.value }
        let task = Task { try await operation() }
        pending[identity] = task
        defer { pending[identity] = nil }
        let data = try await task.value
        entries = entries.filter { Date() < $0.value.0 }
        entries[identity] = (Date().addingTimeInterval(lifetime), data)
        return data
    }
}
