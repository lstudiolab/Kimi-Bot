import Foundation

actor SupportService {
    struct Settings: Codable, Sendable {
        var categoryID: String?
        var supportRoleID: String?
        var transcriptChannelID: String?
        var panelChannelID: String?
        var panelMessageID: String?
        var panelTitle: String = "Contact Support"
        var panelDescription: String = "Open a private ticket with the support team."
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
        await store.get("support.settings." + guild, as: Settings.self) ?? Settings()
    }
    func configure(_ value: Settings, guild: String) async throws {
        try await store.setGuild(value, key: "support.settings." + guild, guildID: guild)
    }
    func ensureCategory(_ guild: String) async throws -> String {
        let current = await settings(guild)
        let channels = try await rest.call("GET", "guilds/\(guild)/channels") as? [[String: Any]] ?? []
        if let id = current.categoryID,
            channels.contains(where: { ($0["id"] as? String) == id && ($0["type"] as? Int) == 4 })
        {
            return id
        }
        if let found = channels.first(where: {
            ($0["type"] as? Int) == 4 && ($0["name"] as? String)?.lowercased() == "ticket"
        }), let id = found["id"] as? String {
            var next = current
            next.categoryID = id
            try await configure(next, guild: guild)
            return id
        }
        let created = try await rest.call("POST", "guilds/\(guild)/channels", body: ["name": "ticket", "type": 4])
        guard let id = (created as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
        var next = current
        next.categoryID = id
        try await configure(next, guild: guild)
        return id
    }
    func panelComponents() -> [[String: Any]] {
        [
            [
                "type": 1,
                "components": [
                    ["type": 2, "style": 1, "label": "Open Ticket", "custom_id": "ticket:open"]
                ],
            ]
        ]
    }

    func panelBody(_ settings: Settings) -> [String: Any] {
        [
            "content": DiscordText.prefixUTF16("**\(settings.panelTitle)**\n\(settings.panelDescription)", limit: 1900),
            "components": panelComponents(),
            "allowed_mentions": ["parse": []],
        ]
    }







}
