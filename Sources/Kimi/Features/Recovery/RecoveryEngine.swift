import Foundation

actor RecoveryEngine {
    struct Snapshot: Codable, Sendable, Identifiable {
        let id: String
        let guildID: String
        let createdAt: Date
        let payload: [String: Data]
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func create(guildID: String, sections: [String: Data]) async throws -> Snapshot {
        let snapshot = Snapshot(id: UUID().uuidString, guildID: guildID, createdAt: Date(), payload: sections)
        _ = try await store.updateGuild("recovery.snapshots", guildID: guildID, as: [Snapshot].self) { stored in
            var all = stored ?? []
            all.append(snapshot)
            let guildSnapshots = all.filter { $0.guildID == guildID }
            if guildSnapshots.count > 50 {
                let retainedIDs = Set(guildSnapshots.sorted { $0.createdAt < $1.createdAt }.suffix(50).map { $0.id })
                all.removeAll { $0.guildID == guildID && !retainedIDs.contains($0.id) }
            }
            return all
        }
        return snapshot
    }
    func snapshots(guildID: String) async -> [Snapshot] {
        (await store.get("recovery.snapshots", as: [Snapshot].self) ?? []).filter { $0.guildID == guildID }
    }
}
