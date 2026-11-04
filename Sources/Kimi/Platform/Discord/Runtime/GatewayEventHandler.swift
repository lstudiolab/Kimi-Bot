import Foundation

extension KimiRuntime {
    func migratedModuleEnabled(_ module: String, guild: String) async -> Bool {
        let modules = await store.getLegacy("modules", as: [String: [String: Bool]].self) ?? [:]
        return modules[guild]?[module] != false
    }
    func captureGuildStructure(_ guild: String) async {
        let installed = await PluginManager(store: store).installed(guildID: guild)
        guard installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) else { return }
        let recovery = RecoveryService(store: store, logger: logger, rest: rest)
        let channels = (try? await rest.call("GET", "guilds/" + guild + "/channels") as? [[String: Any]]) ?? []
        for channel in channels { await recovery.captureChannel(guild, channel) }
        let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
        for role in roles { await recovery.captureRole(guild, role) }
    }
    func dispatchMigratedEvent(_ name: String, _ data: [String: Any]) async {
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
            let installed = await PluginManager(store: store).installed(guildID: guild)
            try? await rest.registerGuildCommands(clientID, guildID: guild, installed: installed)
            await captureGuildStructure(guild)
        case "GUILD_MEMBER_ADD":
            guard let guild = data["guild_id"] as? String, let user = data["user"] as? [String: Any],
                let id = user["id"] as? String
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            let welcomeOn = await migratedModuleEnabled("welcome", guild: guild)
            let autoRoleOn = await migratedModuleEnabled("auto_role", guild: guild)
            if installed.contains("Welcome") && welcomeOn || installed.contains("Auto Role") && autoRoleOn {
                await FoundationEngine(store: store, rest: rest, logger: logger).memberJoined(
                    guildID: guild, userID: id, username: user["username"] as? String ?? "member",
                    serverName: "the server", memberCount: data["member_count"] as? Int ?? 0,
                    welcomeEnabled: installed.contains("Welcome") && welcomeOn,
                    autoRoleEnabled: installed.contains("Auto Role") && autoRoleOn)
            }
            if installed.contains("Kimi Lock") {
                let verificationOn = await migratedModuleEnabled("verification", guild: guild)
                let protectionOn = await migratedModuleEnabled("protection", guild: guild)
                if verificationOn {
                    await VerificationService(store: store, rest: rest, logger: logger).memberJoined(
                        guild: guild, userID: id, username: user["username"] as? String ?? "member")
                }
                if protectionOn {
                    let snowflake = Int64(id) ?? 0
                    let createdAt = Date(timeIntervalSince1970: Double((snowflake >> 22) + 1_420_070_400_000) / 1000)
                    await RaidProtectionService(store: store, rest: rest, logger: logger).memberJoined(
                        guild: guild, userID: id, createdAt: createdAt, isBot: user["bot"] as? Bool ?? false)
                    if user["bot"] as? Bool == true {
                        do {
                            let owner = try await rest.ownerID(guild)
                            let me = try await rest.call("GET", "users/@me") as? [String: Any] ?? [:]
                            guard let botID = me["id"] as? String else { throw KimiError.invalidResponse }
                            let key = "guard.confirmation." + guild
                            var confirmation = await store.get(key, as: String.self)
                            if let current = confirmation {
                                do { _ = try await rest.call("GET", "channels/" + current) } catch {
                                    confirmation = nil
                                }
                            }
                            if confirmation == nil {
                                confirmation = try await rest.createPrivateTextChannel(
                                    guild, "kimi-confirmations", owner, botID)
                                if let confirmation { try await store.set(confirmation, key: key) }
                            }
                            guard let confirmation else {
                                throw KimiError.configuration("Could not create the private bot approval channel.")
                            }
                            let containment = try await KimiGuardService(store: store, rest: rest, logger: logger)
                                .contain(guild: guild, actor: id, action: "new bot joined; awaiting owner approval")
                            let roles =
                                try await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]] ?? []
                            let member =
                                try await rest.call("GET", "guilds/" + guild + "/members/" + id) as? [String: Any]
                                ?? [:]
                            let memberRoles = Set(member["roles"] as? [String] ?? [])
                            let admin = roles.contains { role in
                                memberRoles.contains(role["id"] as? String ?? "")
                                    && ((UInt64(role["permissions"] as? String ?? "") ?? 0) & 8) != 0
                            }
                            let warning =
                                admin
                                ? "This bot has Administrator access. Discord Administrator bypasses channel restrictions; remove that permission before approving."
                                : "Kimi temporarily removed manageable bot roles while approval is pending."
                            let controls =
                                [
                                    [
                                        "type": 1,
                                        "components": [
                                            [
                                                "type": 2, "style": 3, "label": "Approve",
                                                "custom_id": "botguard:yes:" + guild + ":" + id,
                                            ],
                                            [
                                                "type": 2, "style": 4, "label": "Reject",
                                                "custom_id": "botguard:no:" + guild + ":" + id,
                                            ],
                                        ],
                                    ]
                                ] as [[String: Any]]
                            _ = try await rest.call(
                                "POST", "channels/" + confirmation + "/messages",
                                body: [
                                    "content": "**New bot approval required**\\nBot: <@" + id + ">\\n" + warning
                                        + "\\nContainment: " + String(containment?.removedCount ?? 0)
                                        + " role(s) removed.", "components": controls,
                                    "allowed_mentions": ["parse": []],
                                ])
                        } catch {
                            await logger.log("ERROR", "Kimi Guard bot approval failed: " + error.localizedDescription)
                        }
                    }
                }
            }
            await AnalyticsService(store: store).record(guild: guild, event: "join")
            await runAutomations(
                guild: guild, trigger: "member_join", userID: id, channelID: nil, messageID: nil, content: "",
                username: user["username"] as? String ?? "member")
        case "GUILD_MEMBER_REMOVE":
            guard let guild = data["guild_id"] as? String, let user = data["user"] as? [String: Any],
                let id = user["id"] as? String
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Welcome"), await migratedModuleEnabled("welcome", guild: guild) {
                await FoundationEngine(store: store, rest: rest, logger: logger).memberLeft(
                    guildID: guild, userID: id, username: user["username"] as? String ?? "member",
                    serverName: "the server")
            }
            await AnalyticsService(store: store).record(guild: guild, event: "leave")
            await runAutomations(
                guild: guild, trigger: "member_leave", userID: id, channelID: nil, messageID: nil, content: "",
                username: user["username"] as? String ?? "member")
        case "GUILD_MEMBER_UPDATE":
            guard let guild = data["guild_id"] as? String, let user = (data["user"] as? [String: Any])?["id"] as? String
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) {
                let key = "moderation.member-snapshot." + guild + "." + user
                let previous = Set(await store.get(key, as: [String].self) ?? [])
                let roles = data["roles"] as? [String] ?? []
                try? await store.set(roles, key: key)
                if previous != Set(roles) {
                    await logger.log("INFO", "Member role update recorded for " + user + " in guild " + guild)
                }
                let profile = data["user"] as? [String: Any] ?? [:]
                let nickname = data["nick"] as? String
                let profileName = nickname ?? profile["global_name"] as? String ?? profile["username"] as? String ?? ""
                if let violation = await moderation.profileViolation(profileName, guildID: guild) {
                    if nickname != nil {
                        do {
                            _ = try await rest.call(
                                "PATCH", "guilds/" + guild + "/members/" + user,
                                body: ["nick": NSNull()],
                                auditReason: "Kimi Lock: " + violation
                            )
                        } catch {
                            await logger.log("WARN", "Could not remove a violating server nickname: " + error.localizedDescription)
                        }
                    }
                    await logger.log("WARN", "Kimi Lock profile review for " + user + ": " + violation)
                }
            }
        case "GUILD_BAN_ADD", "GUILD_BAN_REMOVE":
            guard let guild = data["guild_id"] as? String, let user = (data["user"] as? [String: Any])?["id"] as? String
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild) {
                await logger.log(
                    "INFO",
                    (name == "GUILD_BAN_ADD" ? "Ban recorded for " : "Unban recorded for ") + user + " in guild "
                        + guild)
            }
        case "VOICE_STATE_UPDATE":
            guard let guild = data["guild_id"] as? String,
                let user = data["user_id"] as? String
            else { return }
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
        case "MESSAGE_CREATE":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let message = data["id"] as? String, let author = data["author"] as? [String: Any],
                let user = author["id"] as? String, author["bot"] as? Bool != true
            else { return }
            let content = data["content"] as? String ?? ""
            await AnalyticsService(store: store).record(guild: guild, event: "message")
            await runAutomations(
                guild: guild, trigger: "message_create", userID: user, channelID: channel, messageID: message,
                content: content, username: author["username"] as? String ?? "member")
            let installed = await PluginManager(store: store).installed(guildID: guild)
            let recoveryEnabled = await migratedModuleEnabled("recovery", guild: guild)
            let moderationEnabled = await migratedModuleEnabled("moderation", guild: guild)
            guard installed.contains("Kimi Lock"), recoveryEnabled || moderationEnabled else { return }
            let recovery = RecoveryService(store: store, logger: logger, rest: rest)
            let attachments = data["attachments"] as? [[String: Any]] ?? []
            let attachmentRecords = attachments.compactMap { item -> RecoveryService.Attachment? in
                guard let url = item["url"] as? String else { return nil }
                return RecoveryService.Attachment(
                    name: item["filename"] as? String ?? "attachment", url: url,
                    contentType: item["content_type"] as? String, size: item["size"] as? Int)
            }
            if recoveryEnabled {
                await recovery.captureMessage(
                    guild, channel, message, user, content, attachments: attachmentRecords,
                    authorName: author["username"] as? String)
            }
            let mentionedUsers = (data["mentions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let reference = (data["message_reference"] as? [String: Any])?["message_id"] as? String
            if moderationEnabled {
                await ImageAnalysisService(store: store, rest: rest, logger: logger).inspect(
                    guild: guild, channel: channel, messageID: message, content: content, attachments: attachments,
                    userID: user, mentionedUserIDs: mentionedUsers, referenceMessageID: reference)
            }
            guard moderationEnabled else { return }
            let owner = try? await rest.ownerID(guild)
            let member = data["member"] as? [String: Any] ?? [:]
            let memberRoles = Set(member["roles"] as? [String] ?? [])
            let guildRoles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
            let canMentionEveryone = guildRoles.contains { role in
                memberRoles.contains(role["id"] as? String ?? "")
                    && ((UInt64(role["permissions"] as? String ?? "") ?? 0) & (1 << 17)) != 0
            }
            if user != owner,
                let finding = await moderation.evaluate(
                    guildID: guild,
                    userID: user,
                    messageID: message,
                    content: content,
                    channelID: channel,
                    attachments: attachments,
                    stickerCount: (data["sticker_items"] as? [Any] ?? []).count,
                    mentionEveryone: data["mention_everyone"] as? Bool ?? false,
                    allowMassMentions: canMentionEveryone,
                    roleMentionCount: (data["mention_roles"] as? [String] ?? []).count,
                    userMentionCount: mentionedUsers.count
                )
            {
                let policy = await moderation.policy(guildID: guild)
                try? await store.set(true, key: "moderation.deleted." + message)
                try? await rest.deleteKimiMessage(channel, message)
                let effectiveSanction = finding.score >= 80 ? policy.sanction : "delete"
                do {
                    switch effectiveSanction {
                    case "timeout": try await rest.timeoutKimiMember(guild, user, policy.timeoutMinutes, finding.reason)
                    case "kick": _ = try await rest.call("DELETE", "guilds/" + guild + "/members/" + user, body: nil)
                    case "ban":
                        _ = try await rest.call(
                            "PUT", "guilds/" + guild + "/bans/" + user,
                            body: ["delete_message_seconds": policy.actionDurationSeconds, "reason": finding.reason])
                    default: break
                    }
                } catch { await logger.log("ERROR", "AutoMod sanction failed: " + error.localizedDescription) }
                var logChannel = policy.logChannelID
                if logChannel == nil {
                    let setup = await store.getLegacy("timi_setup", as: [String: [String: String]].self)
                    logChannel = setup?[guild]?["log_channel_id"]
                }
                if let logChannel {
                    _ = try? await rest.call(
                        "POST", "channels/" + logChannel + "/messages",
                        body: [
                            "content": "Kimi Lock removed a message from <@" + user + "> in <#" + channel
                                + ">. Reason: " + finding.reason + ". Sanction: " + policy.sanction + ".",
                            "allowed_mentions": ["parse": []],
                        ])
                }
                await AnalyticsService(store: store).record(guild: guild, event: "moderation")
                await logger.log("WARN", "Kimi Lock moderation: " + finding.reason + "; sanction: " + effectiveSanction)
            }
        case "MESSAGE_UPDATE":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let message = data["id"] as? String, let author = data["author"] as? [String: Any],
                let user = author["id"] as? String, author["bot"] as? Bool != true
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("moderation", guild: guild),
                let editedContent = data["content"] as? String
            {
                let finding = await moderation.evaluate(
                    guildID: guild,
                    userID: user,
                    messageID: message,
                    content: editedContent,
                    channelID: channel,
                    attachments: data["attachments"] as? [[String: Any]] ?? [],
                    stickerCount: (data["sticker_items"] as? [Any] ?? []).count,
                    mentionEveryone: data["mention_everyone"] as? Bool ?? false,
                    roleMentionCount: (data["mention_roles"] as? [String] ?? []).count,
                    userMentionCount: (data["mentions"] as? [[String: Any]] ?? []).count
                )
                if let finding, (try? await rest.ownerID(guild)) != user {
                    let policy = await moderation.policy(guildID: guild)
                    try? await store.set(true, key: "moderation.deleted." + message)
                    try? await rest.deleteKimiMessage(channel, message)
                    let sanction = finding.score >= 80 ? policy.sanction : "delete"
                    do {
                        switch sanction {
                        case "timeout": try await rest.timeoutKimiMember(guild, user, policy.timeoutMinutes, finding.reason)
                        case "kick": _ = try await rest.call("DELETE", "guilds/" + guild + "/members/" + user, body: nil)
                        case "ban":
                            _ = try await rest.call(
                                "PUT", "guilds/" + guild + "/bans/" + user,
                                body: ["delete_message_seconds": policy.actionDurationSeconds, "reason": finding.reason])
                        default: break
                        }
                    } catch { await logger.log("ERROR", "Edited-message sanction failed: " + error.localizedDescription) }
                    await logger.log("WARN", "Kimi Lock removed edited content: " + finding.reason + "; sanction: " + sanction)
                }
            }
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                let recovery = RecoveryService(store: store, logger: logger, rest: rest)
                let previous = await recovery.savedMessage(guild, channel, message)
                let updated = data["content"] as? String ?? ""
                if let previous, previous.content != updated {
                    await logger.log(
                        "INFO",
                        "Message edit recorded in guild " + guild + ", channel " + channel + ", message " + message
                            + ", author " + user + ". Previous length: " + String(previous.content.count)
                            + ", new length: " + String(updated.count))
                }
                let attachments = data["attachments"] as? [[String: Any]] ?? []
                let records = attachments.compactMap { item -> RecoveryService.Attachment? in
                    guard let url = item["url"] as? String else { return nil }
                    return RecoveryService.Attachment(
                        name: item["filename"] as? String ?? "attachment", url: url,
                        contentType: item["content_type"] as? String, size: item["size"] as? Int)
                }
                await recovery.captureMessage(
                    guild, channel, message, user, updated, attachments: records,
                    authorName: author["username"] as? String)
            }
        case "MESSAGE_DELETE":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let message = data["id"] as? String
            else { return }
            if await store.get("moderation.deleted." + message, as: Bool.self) == true { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                await RecoveryService(store: store, logger: logger, rest: rest).restoreMessage(guild, channel, message)
            }
        case "MESSAGE_DELETE_BULK":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let ids = data["ids"] as? [String]
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                for id in ids {
                    if await store.get("moderation.deleted." + id, as: Bool.self) != true {
                        await RecoveryService(store: store, logger: logger, rest: rest).restoreMessage(
                            guild, channel, id)
                    }
                }
            }
        case "CHANNEL_CREATE", "CHANNEL_UPDATE":
            guard let guild = data["guild_id"] as? String else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                await RecoveryService(store: store, logger: logger, rest: rest).captureChannel(guild, data)
            }
        case "CHANNEL_DELETE":
            guard let guild = data["guild_id"] as? String, let channel = data["id"] as? String else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                await RecoveryService(store: store, logger: logger, rest: rest).queueDeletedChannel(guild, channel)
            }
        case "GUILD_AUDIT_LOG_ENTRY_CREATE":
            guard let guild = data["guild_id"] as? String, let actor = data["user_id"] as? String,
                let action = data["action_type"] as? Int
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("protection", guild: guild) else {
                return
            }
            let recovery = RecoveryService(store: store, logger: logger, rest: rest)
            let owner = (try? await rest.ownerID(guild)) ?? ""
            let target = data["target_id"] as? String
            let privilegedMask = SecurityPolicy.privilegedPermissionBits.reduce(UInt64(0), { $0 | $1 })
            if let owner, actor != owner, (action == 30 || action == 31), let target {
                let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
                if let role = roles.first(where: { ($0["id"] as? String) == target }) {
                    let permissions = UInt64(role["permissions"] as? String ?? "") ?? 0
                    let elevated = permissions & privilegedMask
                    if elevated != 0 {
                        let safePermissions = permissions & ~privilegedMask
                        do {
                            _ = try await rest.call(
                                "PATCH", "guilds/" + guild + "/roles/" + target,
                                body: ["permissions": String(safePermissions)],
                                auditReason: "Kimi Lock removed unauthorized elevated role permissions"
                            )
                            await logger.log("WARN", "Kimi Lock stripped elevated permissions from role " + target)
                        } catch {
                            await logger.log("ERROR", "Could not strip elevated role permissions: " + error.localizedDescription)
                        }
                    }
                }
            }
            if let owner, actor != owner, [13, 14, 15].contains(action) {
                let options = data["options"] as? [String: Any] ?? [:]
                let channelID = options["channel_id"] as? String
                let overwriteID = options["id"] as? String ?? target
                let overwriteType = Int(options["type"] as? String ?? "0") ?? 0
                let changes = data["changes"] as? [[String: Any]] ?? []
                func permissionValue(_ raw: Any?) -> UInt64? {
                    if let value = raw as? String { return UInt64(value) }
                    if let value = raw as? NSNumber { return value.uint64Value }
                    return nil
                }
                let oldAllow = permissionValue(changes.first(where: { ($0["key"] as? String) == "allow" })?["old_value"])
                let oldDeny = permissionValue(changes.first(where: { ($0["key"] as? String) == "deny" })?["old_value"])
                let newAllow = permissionValue(changes.first(where: { ($0["key"] as? String) == "allow" })?["new_value"])
                if let channelID, let overwriteID {
                    do {
                        if action == 13, let newAllow, newAllow & privilegedMask != 0 {
                            _ = try await rest.call(
                                "DELETE", "channels/" + channelID + "/permissions/" + overwriteID,
                                auditReason: "Kimi Lock reverted an unauthorized privileged permission overwrite"
                            )
                            await logger.log("WARN", "Kimi Lock removed an unauthorized privileged channel overwrite.")
                        } else if action == 14, let oldAllow, let oldDeny, let newAllow,
                            newAllow & ~oldAllow & privilegedMask != 0
                        {
                            _ = try await rest.call(
                                "PUT", "channels/" + channelID + "/permissions/" + overwriteID,
                                body: ["allow": String(oldAllow), "deny": String(oldDeny), "type": overwriteType],
                                auditReason: "Kimi Lock reverted an unauthorized permission escalation"
                            )
                            await logger.log("WARN", "Kimi Lock reverted a privileged channel permission change.")
                        } else if action == 15, let oldAllow, let oldDeny {
                            _ = try await rest.call(
                                "PUT", "channels/" + channelID + "/permissions/" + overwriteID,
                                body: ["allow": String(oldAllow), "deny": String(oldDeny), "type": overwriteType],
                                auditReason: "Kimi Lock restored a deleted channel permission overwrite"
                            )
                            await logger.log("WARN", "Kimi Lock restored a deleted channel permission overwrite.")
                        }
                    } catch {
                        await logger.log("ERROR", "Permission overwrite recovery failed: " + error.localizedDescription)
                    }
                }
            }
            if let owner, actor != owner, action == 25, let target {
                let changes = data["changes"] as? [[String: Any]] ?? []
                let additions = changes.first(where: { ($0["key"] as? String) == "$add" })?["new_value"] as? [[String: Any]] ?? []
                let addedRoleIDs = additions.compactMap { $0["id"] as? String }
                if !addedRoleIDs.isEmpty {
                    let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
                    for roleID in addedRoleIDs {
                        let permissions = UInt64(roles.first(where: { ($0["id"] as? String) == roleID })?["permissions"] as? String ?? "") ?? 0
                        if permissions & privilegedMask != 0 {
                            do {
                                _ = try await rest.call(
                                    "DELETE", "guilds/" + guild + "/members/" + target + "/roles/" + roleID,
                                    auditReason: "Kimi Lock blocked an unauthorized elevated role grant"
                                )
                                await logger.log("WARN", "Kimi Lock removed an unauthorized elevated role grant from " + target)
                            } catch {
                                await logger.log("ERROR", "Could not remove an elevated role grant: " + error.localizedDescription)
                            }
                        }
                    }
                }
            }
            if action == 32, let target {
                await recovery.queueDeletedRole(guild, target)
            }
            if action == 30 || action == 31 {
                let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
                for role in roles { await recovery.captureRole(guild, role) }
            }
            do {
                if let incident = try await AuditProtection(store: store).record(
                    guildID: guild, actorID: actor, action: String(action))
                {
                    await logger.log("WARN", "Kimi Lock incident: " + incident.reason)
                    if ["12", "13", "14", "15", "20", "22", "25", "30", "31", "32", "50", "51", "52"].contains(incident.action) {
                        _ = try await KimiGuardService(store: store, rest: rest, logger: logger).contain(
                            guild: guild, actor: actor, action: incident.action)
                    }
                    if incident.action == "12" {
                        await RecoveryService(store: store, logger: logger, rest: rest).restorePendingChannels(guild)
                    }
                    if incident.action == "32" {
                        await RecoveryService(store: store, logger: logger, rest: rest).restorePendingRoles(guild)
                    }
                    if (incident.action == "50" || incident.action == "51"),
                        let webhook = data["target_id"] as? String
                    {
                        do {
                            _ = try await rest.call("DELETE", "webhooks/" + webhook)
                            await logger.log("WARN", "Kimi Lock removed a webhook involved in repeated suspicious changes.")
                        } catch {
                            await logger.log("ERROR", "Webhook containment failed: " + error.localizedDescription)
                        }
                    }
                }
            } catch { await logger.log("ERROR", "Audit incident containment failed: " + error.localizedDescription) }
        default: break
        }
    }
}
