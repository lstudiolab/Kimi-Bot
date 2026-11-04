import Foundation

actor RolePickerService {
    struct Menu: Codable, Sendable {
        let id: String
        let name: String
        let guildID: String
        let channelID: String
        var messageID: String?
        let roles: [Role]
    }
    struct Role: Codable, Sendable {
        let id: String
        let name: String
    }
    let store: PersistentStore
    let rest: DiscordREST
    let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }


}
