import Foundation

actor EmbedService {
    struct Field: Codable, Sendable {
        var name: String
        var value: String
        var inline: Bool = false
    }
    struct Saved: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        var title: String
        var description: String
        var color: Int
        var footer: String?
        var author: String?
        var thumbnailURL: String?
        var imageURL: String?
        var url: String?
        var fields: [Field]?
    }
    let store: PersistentStore
    let rest: DiscordREST
    init(store: PersistentStore, rest: DiscordREST) {
        self.store = store
        self.rest = rest
    }
    func all(guild: String) async -> [Saved] {
        let data = await store.get("embeds.saved", as: [String: [Saved]].self) ?? [:]
        return data[guild] ?? []
    }


}
