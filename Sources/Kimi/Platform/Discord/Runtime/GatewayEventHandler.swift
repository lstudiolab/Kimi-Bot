import Foundation

extension KimiRuntime {
    private func markModerationDeleted(_ messageID: String) async {
        let now = Date()
        moderationDeletedMessageIDs[messageID] = now
        if moderationDeletedMessageIDs.count > 5000 {
            moderationDeletedMessageIDs = moderationDeletedMessageIDs.filter {
                now.timeIntervalSince($0.value) >= 0 && now.timeIntervalSince($0.value) < 7 * 86400
            }
        }
        do {
            _ = try await store.update("moderation.deleted", as: [String: Date].self) { stored in
                let now = Date()
                var entries = (stored ?? [:]).filter {
                    now.timeIntervalSince($0.value) >= 0 && now.timeIntervalSince($0.value) < 7 * 86400
                }
                entries[messageID] = now
                if entries.count > 5000 {
                    let oldest = entries.sorted { $0.value < $1.value }.prefix(entries.count - 5000)
                    for entry in oldest { entries.removeValue(forKey: entry.key) }
                }
                return entries
            }
        } catch {
            await logger.log("WARN", "Moderation deletion marker could not be saved: " + error.localizedDescription)
        }
    }

    private func wasModerationDeleted(_ messageID: String) async -> Bool {
        if let date = moderationDeletedMessageIDs[messageID] {
            return Date().timeIntervalSince(date) >= 0 && Date().timeIntervalSince(date) < 7 * 86400
        }
        let entries = await store.get("moderation.deleted", as: [String: Date].self) ?? [:]
        if let date = entries[messageID] {
            return Date().timeIntervalSince(date) >= 0 && Date().timeIntervalSince(date) < 7 * 86400
        }
        return await store.get("moderation.deleted." + messageID, as: Bool.self) == true
    }

    func migratedModuleEnabled(_ module: String, guild: String) async -> Bool {
        let current = await store.get("plugins.modules." + guild, as: [String: Bool].self) ?? [:]
        if let enabled = current[module] { return enabled }
        let legacy = await store.getLegacy("modules", as: [String: [String: Bool]].self) ?? [:]
        return legacy[guild]?[module] != false
    }
    func cachedRolePermissions(_ guild: String) async -> [String: String] {
        let cacheKey = "security.role-permissions." + guild
        let dateKey = "security.role-permissions-updated." + guild
        let cached = await store.get(cacheKey, as: [String: String].self)
        if let updated = await store.get(dateKey, as: Date.self),
            Date().timeIntervalSince(updated) >= 0, Date().timeIntervalSince(updated) < 60,
            let cached
        {
            return cached
        }
        let roles: [[String: Any]]
        do {
            roles = try await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]] ?? []
        } catch {
            await logger.log("WARN", "Role-permission refresh failed; retaining the last known snapshot: " + error.localizedDescription)
            return cached ?? [:]
        }
        let values = Dictionary(uniqueKeysWithValues: roles.compactMap { role -> (String, String)? in
            guard let id = role["id"] as? String else { return nil }
            return (id, role["permissions"] as? String ?? "0")
        })
        do {
            try await store.setGuild(values, key: cacheKey, guildID: guild)
            try await store.setGuild(Date(), key: dateKey, guildID: guild)
        } catch {
            await logger.log("WARN", "Role-permission cache could not be saved: " + error.localizedDescription)
        }
        return values
    }
    func cachedGuildOwnerID(_ guild: String) async -> String? {
        let key = "runtime.guild-owner." + guild
        let updatedKey = "runtime.guild-owner-updated." + guild
        let cached = await store.get(key, as: String.self)
        if let cached, let updated = await store.get(updatedKey, as: Date.self),
            Date().timeIntervalSince(updated) >= 0,
            Date().timeIntervalSince(updated) < 300
        {
            return cached
        }

        do {
            let owner = try await rest.ownerID(guild)
            guard !owner.isEmpty else { return cached }
            do {
                try await store.set(owner, key: key)
                try await store.set(Date(), key: updatedKey)
            } catch {
                await logger.log("WARN", "Guild owner cache could not be saved: " + error.localizedDescription)
            }
            return owner
        } catch {
            await logger.log("WARN", "Guild owner refresh failed; retaining the last known owner: " + error.localizedDescription)
            return cached
        }
    }
    func captureGuildStructure(_ guild: String) async {
        let installed = await PluginManager(store: store).installed(guildID: guild)
        guard installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) else { return }
        let recovery = RecoveryService(store: store, logger: logger, rest: rest)
        let channels = (try? await rest.call("GET", "guilds/" + guild + "/channels") as? [[String: Any]]) ?? []
        for channel in channels { await recovery.captureChannel(guild, channel) }
        let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
        for role in roles { await recovery.captureRole(guild, role) }
        let permissions = Dictionary(uniqueKeysWithValues: roles.compactMap { role -> (String, String)? in
            guard let id = role["id"] as? String else { return nil }
            return (id, role["permissions"] as? String ?? "0")
        })
        try? await store.setGuild(permissions, key: "security.role-permissions." + guild, guildID: guild)
        try? await store.setGuild(Date(), key: "security.role-permissions-updated." + guild, guildID: guild)
    }
    func dispatchMigratedEvent(_ name: String, _ data: [String: Any]) async {
        if let guild = data["guild_id"] as? String,
            await store.get("control.enabled." + guild, as: Bool.self) == false
        {
            return
        }
        switch name {
        case "READY":
            if let bot = (data["user"] as? [String: Any])?["id"] as? String {
                try? await store.set(bot, key: "runtime.bot_id")
            }
            if let guilds = data["guilds"] as? [[String: Any]] {
                for item in guilds {
                    guard let guild = item["id"] as? String else { continue }
                    let installed = await PluginManager(store: store).installed(guildID: guild)
                    try? await rest.registerGuildCommands(clientID, guildID: guild, installed: installed)
                    await captureGuildStructure(guild)
                }
            }
        case "GUILD_CREATE":
            guard let guild = data["id"] as? String else { return }
            if let owner = data["owner_id"] as? String {
                try? await store.set(owner, key: "runtime.guild-owner." + guild)
                try? await store.set(Date(), key: "runtime.guild-owner-updated." + guild)
            }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            try? await rest.registerGuildCommands(clientID, guildID: guild, installed: installed)
            await captureGuildStructure(guild)
        case "GUILD_UPDATE":
            guard let guild = data["id"] as? String else { return }
            if let owner = data["owner_id"] as? String {
                try? await store.set(owner, key: "runtime.guild-owner." + guild)
                try? await store.set(Date(), key: "runtime.guild-owner-updated." + guild)
            }
        case "GUILD_MEMBER_ADD", "GUILD_MEMBER_REMOVE", "GUILD_MEMBER_UPDATE", "GUILD_BAN_ADD", "GUILD_BAN_REMOVE":
            await handleGuildMemberEvent(name, data)
        case "VOICE_STATE_UPDATE":
            guard let guild = data["guild_id"] as? String,
                let user = data["user_id"] as? String
            else { return }
            let botID = await store.get("runtime.bot_id", as: String.self) ?? ""
            guard user != botID else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) else {
                return
            }
            let channel = data["channel_id"] as? String ?? ""
            let stateKey = "moderation.voice-state." + guild + "." + user
            let previous = await store.get(stateKey, as: String.self) ?? ""
            guard previous != channel else { return }
            try? await store.set(channel, key: stateKey)
            let rateKey = "moderation.voice-hops." + guild + "." + user
            let now = Date()
            var events = (await store.get(rateKey, as: [Date].self) ?? []).filter {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 60
            }
            if !channel.isEmpty { events.append(now) }
            try? await store.setGuild(events, key: rateKey, guildID: guild)
            if events.count >= 12 {
                try? await rest.timeoutKimiMember(guild, user, 5, "Repeated voice channel hopping")
                await logger.log("WARN", "Kimi Lock contained repeated voice-channel hopping by " + user)
            }
        case "VOICE_CHANNEL_EFFECT_SEND":
            guard let guild = data["guild_id"] as? String,
                let user = data["user_id"] as? String
            else { return }
            let botID = await store.get("runtime.bot_id", as: String.self) ?? ""
            guard user != botID else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) else {
                return
            }
            let key = "moderation.soundboard." + guild + "." + user
            let now = Date()
            var events = (await store.get(key, as: [Date].self) ?? []).filter {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 10
            }
            events.append(now)
            try? await store.setGuild(events, key: key, guildID: guild)
            if events.count >= 10 {
                try? await rest.timeoutKimiMember(guild, user, 5, "Soundboard effect flooding")
                await logger.log("WARN", "Kimi Lock contained soundboard flooding by " + user)
            }
        case "MESSAGE_REACTION_ADD":
            guard let guild = data["guild_id"] as? String,
                let channel = data["channel_id"] as? String,
                let message = data["message_id"] as? String,
                let user = data["user_id"] as? String
            else { return }
            let botID = await store.get("runtime.bot_id", as: String.self) ?? ""
            guard user != botID else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) else {
                return
            }
            let member = data["member"] as? [String: Any] ?? [:]
            let userData = member["user"] as? [String: Any] ?? [:]
            guard userData["bot"] as? Bool != true else { return }
            let key = "moderation.reactions." + guild + "." + message + "." + user
            let now = Date()
            var events = (await store.get(key, as: [Date].self) ?? []).filter {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 10
            }
            events.append(now)
            try? await store.setGuild(events, key: key, guildID: guild)
            guard events.count >= 6 else { return }
            let emoji = data["emoji"] as? [String: Any] ?? [:]
            let emojiName = emoji["name"] as? String ?? ""
            let emojiID = emoji["id"] as? String
            let rawEmoji = emojiID.map { emojiName + ":" + $0 } ?? emojiName
            let safeEmoji = rawEmoji.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawEmoji
            do {
                _ = try await rest.call(
                    "DELETE",
                    "channels/" + channel + "/messages/" + message + "/reactions/" + safeEmoji + "/" + user
                )
                await logger.log("WARN", "Kimi Lock removed rapid reaction spam from " + user + " in guild " + guild)
                if events.count >= 12 {
                    try await rest.timeoutKimiMember(guild, user, 5, "Repeated reaction spam")
                }
            } catch {
                await logger.log("WARN", "Reaction spam containment failed: " + error.localizedDescription)
            }
        case "THREAD_CREATE":
            guard let guild = data["guild_id"] as? String,
                let thread = data["id"] as? String,
                let owner = data["owner_id"] as? String
            else { return }
            let botID = await store.get("runtime.bot_id", as: String.self) ?? ""
            guard owner != botID else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) else {
                return
            }
            let key = "moderation.threads." + guild + "." + owner
            let now = Date()
            var events = (await store.get(key, as: [Date].self) ?? []).filter {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 60
            }
            events.append(now)
            try? await store.setGuild(events, key: key, guildID: guild)
            if events.count >= 6 {
                do {
                    _ = try await rest.call("DELETE", "channels/" + thread)
                    await logger.log("WARN", "Kimi Lock removed a thread creation flood by " + owner)
                    if events.count >= 10 {
                        try await rest.timeoutKimiMember(guild, owner, 10, "Thread and forum flooding")
                    }
                } catch {
                    await logger.log("WARN", "Thread flood containment failed: " + error.localizedDescription)
                }
            }
        case "MESSAGE_CREATE", "MESSAGE_UPDATE", "MESSAGE_DELETE", "MESSAGE_DELETE_BULK":
            await handleMessageEvent(name, data)
        case "CHANNEL_CREATE", "CHANNEL_UPDATE", "GUILD_AUDIT_LOG_ENTRY_CREATE":
            await handleGuildAuditEvent(name, data)
        default: break
        }
    }
}
