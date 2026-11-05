import Foundation

actor RecoveryService {
    struct Attachment: Codable, Sendable {
        let name, url: String
        let contentType: String?
        let size: Int?
    }
    struct Message: Codable, Sendable {
        let id, channelID: String
        let authorID, content: String
        let createdAt: Date
        var authorName: String?
        var attachments: [Attachment]?
    }
    let store: PersistentStore
    let logger: Logger
    let rest: DiscordREST
    let week: TimeInterval = 7 * 86400
    let maxMessages = 25_000
    let maxArchiveBytes = 4 * 1024 * 1024
    init(store: PersistentStore, logger: Logger, rest: DiscordREST) {
        self.store = store
        self.logger = logger
        self.rest = rest
    }}
