import Foundation

actor RecoveryService {
    struct Attachment: Codable, Sendable {
        let name: String
        let url: String
        let contentType: String?
        let size: Int?
    }
    struct Message: Codable, Sendable {
        let id: String
        let channelID: String
        let authorID: String
        let content: String
        let createdAt: Date
        var authorName: String?
        var attachments: [Attachment]?
    }
    private let store: PersistentStore
    private let logger: Logger
    private let rest: DiscordREST
    private let week: TimeInterval = 7 * 86400
    private let maxMessages = 25_000
    private let maxArchiveBytes = 4 * 1024 * 1024
    init(store: PersistentStore, logger: Logger, rest: DiscordREST) {
        self.store = store
        self.logger = logger
        self.rest = rest
    }
    func captureChannel(_ guild: String, _ channel: [String: Any]) async {
        guard let id = channel["id"] as? String,
            let data = try? JSONSerialization.data(withJSONObject: channel, options: [.fragmentsAllowed])
        else { return }
        var all = await store.get("recovery.channels", as: [String: [String: Data]].self) ?? [:]
        all[guild, default: [:]][id] = data
        if all[guild, default: [:]].count > 1000 {
            all[guild] = Dictionary(
                uniqueKeysWithValues: all[guild, default: [:]].sorted { $0.key < $1.key }.suffix(1000))
        }
        try? await store.set(all, key: "recovery.channels")
    }
    func captureMessage(
        _ guild: String, _ channel: String, _ message: String, _ author: String, _ content: String,
        attachments: [Attachment] = [], authorName: String? = nil
    ) async {
        var all = await store.get("recovery.messages", as: [String: [Message]].self) ?? [:]
        let now = Date()
        let cutoff = now.addingTimeInterval(-week)
        var rows = (all[guild] ?? []).filter { $0.createdAt >= cutoff }
        rows.removeAll { $0.id == message }
        let value = Message(
            id: message, channelID: channel, authorID: author, content: String(content.prefix(4000)), createdAt: now,
            authorName: authorName, attachments: Array(attachments.prefix(10)))
        rows.append(value)
        rows.sort { $0.createdAt < $1.createdAt }
        func encodedSize(_ row: Message) -> Int { (try? JSONEncoder().encode(row).count) ?? row.content.utf8.count }
        var bytes = rows.reduce(0) { $0 + encodedSize($1) }
        while !rows.isEmpty && (rows.count > maxMessages || bytes > maxArchiveBytes) {
            bytes -= encodedSize(rows.removeFirst())
        }
        all[guild] = rows
        try? await store.set(all, key: "recovery.messages")
    }
    func savedMessage(_ guild: String, _ channel: String, _ message: String) async -> Message? {
        let rows = await store.get("recovery.messages", as: [String: [Message]].self) ?? [:]
        return rows[guild]?.first(where: { $0.id == message && $0.channelID == channel })
    }
    func deletedMessage(_ guild: String, _ channel: String, _ message: String) async -> Message? {
        let rows = await store.get("recovery.messages", as: [String: [Message]].self) ?? [:]
        guard let found = rows[guild]?.first(where: { $0.id == message && $0.channelID == channel }) else { return nil }
        await logger.log("INFO", "Recovery retained deleted message " + message + " from guild " + guild)
        return found
    }
    func queueDeletedChannel(_ guild: String, _ channel: String) async {
        var all = await store.get("recovery.pending-channels", as: [String: [String]].self) ?? [:]
        var values = all[guild] ?? []
        if !values.contains(channel) { values.append(channel) }
        all[guild] = Array(values.suffix(100))
        try? await store.set(all, key: "recovery.pending-channels")
    }
    func restorePendingChannels(_ guild: String) async {
        let all = await store.get("recovery.pending-channels", as: [String: [String]].self) ?? [:]
        let pending = all[guild] ?? []
        let snapshots = await store.get("recovery.channels", as: [String: [String: Data]].self) ?? [:]
        let ordered = pending.sorted { left, right in
            let a = (snapshots[guild]?[left]).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let b = (snapshots[guild]?[right]).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let aCategory = (a?["type"] as? Int) == 4
            let bCategory = (b?["type"] as? Int) == 4
            if aCategory != bCategory { return aCategory }
            return (a?["position"] as? Int ?? 0) < (b?["position"] as? Int ?? 0)
        }
        for channel in ordered { await restoreChannel(guild, channel) }
        var updated = all
        updated[guild] = []
        try? await store.set(updated, key: "recovery.pending-channels")
    }
    func restoreChannel(_ guild: String, _ channelID: String) async {
        let all = await store.get("recovery.channels", as: [String: [String: Data]].self) ?? [:]
        guard let data = all[guild]?[channelID],
            let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let allowed = [
            "name", "type", "topic", "nsfw", "rate_limit_per_user", "parent_id", "permission_overwrites", "bitrate",
            "user_limit", "position",
        ]
        var body: [String: Any] = [:]
        for key in allowed { if let value = source[key] { body[key] = value } }
        body["name"] = SecurityPolicy.channelName(source["name"] as? String ?? "restored-channel")
        do {
            let created = try await rest.call("POST", "guilds/\(guild)/channels", body: body)
            let restored = (created as? [String: Any])?["id"] as? String ?? "unknown"
            await logger.log(
                "WARN", "Kimi Lock restored deleted channel " + channelID + " as " + restored + " in guild " + guild)
        } catch {
            await logger.log("ERROR", "Channel recovery failed for " + channelID + ": " + error.localizedDescription)
        }
    }
    func restoreMessage(_ guild: String, _ channel: String, _ message: String) async {
        guard let saved = await deletedMessage(guild, channel, message),
            !saved.content.isEmpty || !(saved.attachments ?? []).isEmpty
        else { return }
        let date = ISO8601DateFormatter().string(from: saved.createdAt)
        let author = saved.authorName.map { " (" + $0 + ")" } ?? ""
        let files = (saved.attachments ?? []).map { item in
            "[Attachment: " + item.name + ", " + String(item.size ?? 0) + " bytes] " + item.url
        }.joined(separator: "\n")
        let body =
            "**Recovered message** · <@\(saved.authorID)>\(author) · \(date)\n" + String(saved.content.prefix(1300))
            + (files.isEmpty ? "" : "\n" + String(files.prefix(350)))
        do {
            _ = try await rest.call(
                "POST", "channels/\(channel)/messages",
                body: ["content": String(body.prefix(1900)), "allowed_mentions": ["parse": []]])
        } catch {
            await logger.log("ERROR", "Message recovery failed for " + message + ": " + error.localizedDescription)
        }
    }
}
