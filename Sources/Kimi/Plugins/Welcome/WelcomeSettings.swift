import Foundation

actor FoundationEngine {
    struct Welcome: Codable, Sendable {
        var welcomeChannel: String?
        var goodbyeChannel: String?
        var welcomeMessage: String
        var goodbyeMessage: String
        var autoRole: String?
        init(
            welcomeChannel: String? = nil, goodbyeChannel: String? = nil,
            welcomeMessage: String = "Welcome {user} to {server}!",
            goodbyeMessage: String = "{username} has left {server}.", autoRole: String? = nil
        ) {
            self.welcomeChannel = welcomeChannel
            self.goodbyeChannel = goodbyeChannel
            self.welcomeMessage = welcomeMessage
            self.goodbyeMessage = goodbyeMessage
            self.autoRole = autoRole
        }
    }
    struct LegacyWelcome: Decodable {
        var welcome_channel_id: String?
        var goodbye_channel_id: String?
        var welcome_message: String?
        var goodbye_message: String?
        var auto_role_id: String?
    }
    let store: PersistentStore
    let rest: DiscordREST
    let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func settings(guildID: String) async -> Welcome {
        if let value = await store.get("foundation.\(guildID)", as: Welcome.self) { return value }
        let legacy = await store.getLegacy("welcome", as: [String: LegacyWelcome].self)?[guildID]
        return Welcome(
            welcomeChannel: legacy?.welcome_channel_id, goodbyeChannel: legacy?.goodbye_channel_id,
            welcomeMessage: legacy?.welcome_message ?? "Welcome {user} to {server}!",
            goodbyeMessage: legacy?.goodbye_message ?? "{username} has left {server}.", autoRole: legacy?.auto_role_id)
    }
    func configure(guildID: String, _ value: Welcome) async throws {
        try await store.setGuild(value, key: "foundation.\(guildID)", guildID: guildID)
    }


}
