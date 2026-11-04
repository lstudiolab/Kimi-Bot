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
        do {
            try await store.updateGuild("recovery.channels", guildID: guild, as: [String: [String: Data]].self) { stored in
                var all = stored ?? [:]
                all[guild, default: [:]][id] = data
                if all[guild, default: [:]].count > 1000 {
                    all[guild] = Dictionary(
                        uniqueKeysWithValues: all[guild, default: [:]].sorted { $0.key < $1.key }.suffix(1000))
                }
                return all
            }
        } catch {
            await logger.log("ERROR", "Recovery channel snapshot was not persisted: " + error.localizedDescription)
        }
    }
    func captureRole(_ guild: String, _ role: [String: Any]) async {
        guard let id = role["id"] as? String, id != guild,
            let data = try? JSONSerialization.data(withJSONObject: role, options: [.fragmentsAllowed])
        else { return }
        do {
            try await store.updateGuild("recovery.roles", guildID: guild, as: [String: [String: Data]].self) { stored in
                var all = stored ?? [:]
                all[guild, default: [:]][id] = data
                if all[guild, default: [:]].count > 500 {
                    all[guild] = Dictionary(
                        uniqueKeysWithValues: all[guild, default: [:]].sorted { $0.key < $1.key }.suffix(500))
                }
                return all
            }
        } catch {
            await logger.log("ERROR", "Recovery role snapshot was not persisted: " + error.localizedDescription)
        }
    }
    func queueDeletedRole(_ guild: String, _ role: String) async {
        guard role != guild else { return }
        do {
            try await store.updateGuild("recovery.pending-roles", guildID: guild, as: [String: [String]].self) { stored in
                var all = stored ?? [:]
                var pending = all[guild] ?? []
                if !pending.contains(role) { pending.append(role) }
                all[guild] = Array(pending.suffix(100))
                return all
            }
        } catch {
            await logger.log("ERROR", "Deleted-role recovery queue was not persisted: " + error.localizedDescription)
        }
    }
    func restorePendingRoles(_ guild: String) async {
        let pending = await store.get("recovery.pending-roles", as: [String: [String]].self) ?? [:]
        let snapshots = await store.get("recovery.roles", as: [String: [String: Data]].self) ?? [:]
        var restoredIDs = Set<String>()
        for roleID in pending[guild] ?? [] {
            guard let data = snapshots[guild]?[roleID],
                let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                await logger.log("WARN", "Role recovery retained an item without a snapshot: " + roleID)
                continue
            }
            let original = UInt64(source["permissions"] as? String ?? "") ?? 0
            var safePermissions = original
            for bit in SecurityPolicy.privilegedPermissionBits { safePermissions &= ~bit }
            var body: [String: Any] = [
                "name": String((source["name"] as? String ?? "restored-role").prefix(100)),
                "permissions": String(safePermissions),
                "color": source["color"] as? Int ?? 0,
                "hoist": source["hoist"] as? Bool ?? false,
                "mentionable": source["mentionable"] as? Bool ?? false,
            ]
            if let unicode = source["unicode_emoji"] as? String { body["unicode_emoji"] = unicode }
            do {
                let created = try await rest.call("POST", "guilds/" + guild + "/roles", body: body)
                guard let restored = (created as? [String: Any])?["id"] as? String else {
                    throw KimiError.invalidResponse
                }
                restoredIDs.insert(roleID)
                var roleMappings = await store.get("recovery.role-map." + guild, as: [String: String].self) ?? [:]
                roleMappings[roleID] = restored
                do {
                    try await store.setGuild(
                        roleMappings, key: "recovery.role-map." + guild, guildID: guild)
                } catch {
                    await logger.log("ERROR", "Restored role mapping could not be saved: " + error.localizedDescription)
                }
                await logger.log(
                    "WARN", "Kimi Lock restored deleted role " + roleID + " as " + restored
                        + " with elevated permissions stripped.")
            } catch {
                await logger.log("ERROR", "Role recovery failed for " + roleID + ": " + error.localizedDescription)
            }
        }
        let completedRoleIDs = restoredIDs
        do {
            _ = try await store.updateGuild("recovery.pending-roles", guildID: guild, as: [String: [String]].self) { stored in
                var updated = stored ?? [:]
                let current = updated[guild] ?? []
                updated[guild] = current.filter { !completedRoleIDs.contains($0) }
                return updated
            }
        } catch {
            await logger.log("ERROR", "Role recovery queue update failed: " + error.localizedDescription)
        }
    }
    func captureMessage(
        _ guild: String, _ channel: String, _ message: String, _ author: String, _ content: String,
        attachments: [Attachment] = [], authorName: String? = nil
    ) async {
        let now = Date()
        let cutoff = now.addingTimeInterval(-week)
        let value = Message(
            id: message, channelID: channel, authorID: author, content: String(content.prefix(4000)), createdAt: now,
            authorName: authorName, attachments: Array(attachments.prefix(10)))
        do {
            try await store.updateGuild("recovery.messages", guildID: guild, as: [String: [Message]].self) { stored in
                var all = stored ?? [:]
                var rows = (all[guild] ?? []).filter { $0.createdAt >= cutoff }
                rows.removeAll { $0.id == message }
                rows.append(value)
                rows.sort { $0.createdAt < $1.createdAt }
                func encodedSize(_ row: Message) -> Int {
                    (try? JSONEncoder().encode(row).count) ?? row.content.utf8.count
                }
                var bytes = rows.reduce(0) { $0 + encodedSize($1) }
                while !rows.isEmpty && (rows.count > maxMessages || bytes > maxArchiveBytes) {
                    bytes -= encodedSize(rows.removeFirst())
                }
                all[guild] = rows
                return all
            }
        } catch {
            await logger.log("ERROR", "Recovery message snapshot was not persisted: " + error.localizedDescription)
        }
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
        do {
            try await store.updateGuild("recovery.pending-channels", guildID: guild, as: [String: [String]].self) { stored in
                var all = stored ?? [:]
                var values = all[guild] ?? []
                if !values.contains(channel) { values.append(channel) }
                all[guild] = Array(values.suffix(100))
                return all
            }
        } catch {
            await logger.log("ERROR", "Deleted-channel recovery queue was not persisted: " + error.localizedDescription)
        }
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
        var restoredIDs = Set<String>()
        for channel in ordered {
            if await restoreChannel(guild, channel) { restoredIDs.insert(channel) }
        }
        let completedChannelIDs = restoredIDs
        do {
            _ = try await store.updateGuild("recovery.pending-channels", guildID: guild, as: [String: [String]].self) { stored in
                var updated = stored ?? [:]
                let current = updated[guild] ?? []
                updated[guild] = current.filter { !completedChannelIDs.contains($0) }
                return updated
            }
        } catch {
            await logger.log("ERROR", "Recovery queue update failed: " + error.localizedDescription)
        }
    }
    @discardableResult
    func restoreChannel(_ guild: String, _ channelID: String) async -> Bool {
        let all = await store.get("recovery.channels", as: [String: [String: Data]].self) ?? [:]
        guard let data = all[guild]?[channelID],
            let source = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        let allowed = [
            "name", "type", "topic", "nsfw", "rate_limit_per_user", "parent_id", "permission_overwrites", "bitrate",
            "user_limit", "position",
        ]
        var body: [String: Any] = [:]
        for key in allowed { if let value = source[key] { body[key] = value } }
        body["name"] = SecurityPolicy.channelName(source["name"] as? String ?? "restored-channel")
        if let parentID = source["parent_id"] as? String {
            let mappings = await store.get("recovery.channel-map." + guild, as: [String: String].self) ?? [:]
            body["parent_id"] = mappings[parentID] ?? parentID
        }
        if let overwrites = source["permission_overwrites"] as? [[String: Any]] {
            let privilegedMask = SecurityPolicy.privilegedPermissionBits.reduce(UInt64(0), { $0 | $1 })
            let roleMappings = await store.get("recovery.role-map." + guild, as: [String: String].self) ?? [:]
            body["permission_overwrites"] = overwrites.compactMap { original -> [String: Any]? in
                guard let id = original["id"] as? String,
                    let type = original["type"] as? Int, type == 0 || type == 1
                else { return nil }
                let allow = UInt64(original["allow"] as? String ?? "") ?? 0
                let deny = UInt64(original["deny"] as? String ?? "") ?? 0
                let blocked = allow & privilegedMask
                return [
                    "id": type == 0 ? (roleMappings[id] ?? id) : id,
                    "type": type,
                    "allow": String(allow & ~privilegedMask),
                    "deny": String(deny | blocked),
                ]
            }
        }
        do {
            let created = try await rest.call("POST", "guilds/\(guild)/channels", body: body)
            guard let restored = (created as? [String: Any])?["id"] as? String else {
                throw KimiError.invalidResponse
            }
            var mappings = await store.get("recovery.channel-map." + guild, as: [String: String].self) ?? [:]
            mappings[channelID] = restored
            do {
                try await store.setGuild(mappings, key: "recovery.channel-map." + guild, guildID: guild)
            } catch {
                await logger.log("ERROR", "Restored channel mapping could not be saved: " + error.localizedDescription)
            }
            await logger.log(
                "WARN", "Kimi Lock restored deleted channel " + channelID + " as " + restored + " in guild " + guild)
            return true
        } catch {
            await logger.log("ERROR", "Channel recovery failed for " + channelID + ": " + error.localizedDescription)
            return false
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
