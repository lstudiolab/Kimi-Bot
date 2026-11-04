import Foundation

extension KimiRuntime {
    func migratedModuleEnabled(_ module: String, guild: String) async -> Bool {
        let modules = await store.getLegacy("modules", as: [String: [String: Bool]].self) ?? [:]
        return modules[guild]?[module] != false
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
                }
            }
        case "GUILD_CREATE":
            guard let guild = data["id"] as? String else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            try? await rest.registerGuildCommands(clientID, guildID: guild, installed: installed)
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
            let owner = (try? await rest.ownerID(guild)) ?? ""
            let member = data["member"] as? [String: Any] ?? [:]
            let memberRoles = Set(member["roles"] as? [String] ?? [])
            let guildRoles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
            let protectedMask = UInt64((1 << 3) | (1 << 5) | (1 << 28) | (1 << 29) | (1 << 30) | (1 << 31) | (1 << 32))
            let privileged = guildRoles.contains { role in
                memberRoles.contains(role["id"] as? String ?? "")
                    && ((UInt64(role["permissions"] as? String ?? "") ?? 0) & protectedMask) != 0
            }
            if user != owner && !privileged,
                let finding = await ModerationEngine(store: store).evaluate(
                    guildID: guild, userID: user, messageID: message, content: content, channelID: channel, attachments: attachments, stickerCount: (data["sticker_items"] as? [Any] ?? []).count, mentionEveryone: data["mention_everyone"] as? Bool ?? false, roleMentionCount: (data["mention_roles"] as? [String] ?? []).count, userMentionCount: mentionedUsers.count)
            {
                let policy = await ModerationEngine(store: store).policy(guildID: guild)
                try? await store.set(true, key: "moderation.deleted." + message)
                try? await rest.deleteKimiMessage(channel, message)
                do {
                    switch policy.sanction {
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
                await logger.log("WARN", "Kimi Lock moderation: " + finding.reason + "; sanction: " + policy.sanction)
            }
        case "MESSAGE_UPDATE":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let message = data["id"] as? String, let author = data["author"] as? [String: Any],
                let user = author["id"] as? String
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
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
            do {
                if let incident = try await AuditProtection(store: store).record(
                    guildID: guild, actorID: actor, action: String(action))
                {
                    await logger.log("WARN", "Kimi Lock incident: " + incident.reason)
                    if ["12", "32", "50", "22", "20", "30", "10", "1"].contains(incident.action) {
                        _ = try await KimiGuardService(store: store, rest: rest, logger: logger).contain(
                            guild: guild, actor: actor, action: incident.action)
                    }
                    if incident.action == "12" {
                        await RecoveryService(store: store, logger: logger, rest: rest).restorePendingChannels(guild)
                    }
                }
            } catch { await logger.log("ERROR", "Audit incident containment failed: " + error.localizedDescription) }
        default: break
        }
    }
}
