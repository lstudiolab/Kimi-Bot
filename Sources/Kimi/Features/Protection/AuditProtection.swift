import Foundation

actor AuditProtection {
    struct Incident: Codable, Sendable {
        let id: String
        let guildID: String
        let actorID: String
        let action: String
        let count: Int
        let reason: String
        let createdAt: Date
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func record(guildID: String, actorID: String, action: String, threshold: Int = 3, now: Date = Date()) async throws
        -> Incident?
    {
        let key = "\(guildID):\(actorID):\(action)"
        var events = (await store.get("security.activity." + key, as: [Date].self) ?? []).filter {
            now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 20
        }
        events.append(now)
        if events.count > 30 { events = Array(events.suffix(30)) }
        try await store.setGuild(events, key: "security.activity." + key, guildID: guildID)
        let sensitiveThreshold: Int
        switch action {
        case "12", "13", "14", "15", "32", "50", "51", "52": sensitiveThreshold = 2
        case "20", "22", "25", "30": sensitiveThreshold = 3
        case "1", "10", "11": sensitiveThreshold = 4
        default: sensitiveThreshold = threshold
        }
        guard events.count > max(1, min(threshold, sensitiveThreshold)) else { return nil }
        let item = Incident(
            id: UUID().uuidString, guildID: guildID, actorID: actorID, action: action, count: events.count,
            reason: "Repeated privileged audit action exceeded the rolling threshold.", createdAt: now)
        var all = await store.get("security.incidents", as: [Incident].self) ?? []
        all.append(item)
        all = Array(all.suffix(1000))
        try await store.set(all, key: "security.incidents")
        try await store.setGuild([], key: "security.activity." + key, guildID: guildID)
        return item
    }
}
