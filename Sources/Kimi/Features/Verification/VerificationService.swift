import Foundation

actor VerificationService {
    struct Settings: Codable, Sendable {
        var channelID: String?
        var roleID: String?
        var requiredRoleID: String?
        var reviewChannelID: String?
        var minimumAgeDays: Int = 0
    }
    struct LegacySettings: Decodable {
        var channel_id: String?
        var role_id: String?
        var required_role_id: String?
        var review_channel_id: String?
        var min_age_days: Int?
    }
    let store: PersistentStore
    let rest: DiscordREST
    let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func settings(_ guild: String) async -> Settings {
        if let value = await store.get("verification.settings." + guild, as: Settings.self) { return value }
        let old = await store.getLegacy("verification", as: [String: LegacySettings].self)?[guild]
        return Settings(
            channelID: old?.channel_id, roleID: old?.role_id, requiredRoleID: old?.required_role_id,
            reviewChannelID: old?.review_channel_id, minimumAgeDays: max(0, old?.min_age_days ?? 0))
    }
    func configure(_ value: Settings, guild: String) async throws {
        guard (0...3650).contains(value.minimumAgeDays) else {
            throw KimiError.configuration("Minimum account age must be between 0 and 3650 days.")
        }
        try await store.setGuild(value, key: "verification.settings." + guild, guildID: guild)
    }



}
