import Foundation

extension KimiRuntime {
    func handleMessageEvent(_ eventName: String, _ data: [String: Any]) async {
        switch eventName {
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
            let hasKimiLock = installed.contains("Kimi Lock")
            let hasKimiGuard = installed.contains("Kimi Guard")
            let recoveryConfigured = await migratedModuleEnabled("recovery", guild: guild)
            let moderationConfigured = await migratedModuleEnabled("moderation", guild: guild)
            let recoveryEnabled = hasKimiLock && recoveryConfigured
            let moderationEnabled = (hasKimiLock || hasKimiGuard) && moderationConfigured
            guard recoveryEnabled || moderationEnabled else { return }
            let recovery = RecoveryService(store: store, logger: logger, rest: rest)
            let attachments = data["attachments"] as? [[String: Any]] ?? []
            let attachmentRecords = attachments.compactMap { item -> RecoveryService.Attachment? in
                guard let url = item["url"] as? String else { return nil }
                return RecoveryService.Attachment(
                    name: item["filename"] as? String ?? "attachment", url: url,
                    contentType: item["content_type"] as? String, size: item["size"] as? Int)
            }
            if recoveryEnabled {
                let messageCreatedAt = (data["timestamp"] as? String).flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
                await recovery.captureMessage(
                    guild, channel, message, user, content, attachments: attachmentRecords,
                    authorName: author["username"] as? String, createdAt: messageCreatedAt)
            }
            let mentionedUsers = (data["mentions"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let reference = (data["message_reference"] as? [String: Any])?["message_id"] as? String
            if moderationEnabled {
                await imageAnalysis.inspect(
                    guild: guild, channel: channel, messageID: message, content: content, attachments: attachments,
                    userID: user, mentionedUserIDs: mentionedUsers, referenceMessageID: reference)
            }
            guard moderationEnabled else { return }
            let owner = await cachedGuildOwnerID(guild)
            let member = data["member"] as? [String: Any] ?? [:]
            let memberRoles = Set(member["roles"] as? [String] ?? [])
            let rolePermissions = await cachedRolePermissions(guild)
            let canMentionEveryone = memberRoles.contains { roleID in
                ((UInt64(rolePermissions[roleID] ?? "0") ?? 0) & ((1 << 17) | (1 << 3))) != 0
            }
            if let owner, user != owner,
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
                await markModerationDeleted(message)
                try? await rest.deleteKimiMessage(channel, message)
                let effectiveSanction = finding.score >= 80 ? policy.sanction : "delete"
                do {
                    switch effectiveSanction {
                    case "timeout": try await rest.timeoutKimiMember(guild, user, policy.timeoutMinutes, finding.reason)
                    case "kick": _ = try await rest.call(
                        "DELETE", "guilds/" + guild + "/members/" + user, auditReason: finding.reason)
                    case "ban":
                        _ = try await rest.call(
                            "PUT", "guilds/" + guild + "/bans/" + user,
                            body: ["delete_message_seconds": policy.actionDurationSeconds],
                            auditReason: finding.reason)
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
                        body: KimiUI.panel(title: "Moderation action", description: "Kimi Lock removed a message from <@" + user + "> in <#" + channel + ">. Reason: " + finding.reason + ". Sanction: " + effectiveSanction + "."))
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
            let hasKimiLock = installed.contains("Kimi Lock")
            let hasKimiGuard = installed.contains("Kimi Guard")
            let recoveryEnabled = hasKimiLock && await migratedModuleEnabled("recovery", guild: guild)
            let moderationEnabled = (hasKimiLock || hasKimiGuard)
                && await migratedModuleEnabled("moderation", guild: guild)
            let editedContent = data["content"] as? String
            let recovery = RecoveryService(store: store, logger: logger, rest: rest)
            if recoveryEnabled, let editedContent {
                let attachments = (data["attachments"] as? [[String: Any]] ?? []).compactMap {
                    item -> RecoveryService.Attachment? in
                    guard let url = item["url"] as? String else { return nil }
                    return RecoveryService.Attachment(
                        name: item["filename"] as? String ?? "attachment", url: url,
                        contentType: item["content_type"] as? String, size: item["size"] as? Int)
                }
                let messageCreatedAt = (data["timestamp"] as? String).flatMap {
                    ISO8601DateFormatter().date(from: $0)
                }
                await recovery.captureMessage(
                    guild, channel, message, user, editedContent,
                    attachments: attachments, authorName: author["username"] as? String,
                    createdAt: messageCreatedAt)
            }
            if moderationEnabled, let editedContent {
                let member = data["member"] as? [String: Any] ?? [:]
                let memberRoles = Set(member["roles"] as? [String] ?? [])
                let rolePermissions = await cachedRolePermissions(guild)
                let canMentionEveryone = memberRoles.contains { roleID in
                    ((UInt64(rolePermissions[roleID] ?? "0") ?? 0) & ((1 << 17) | (1 << 3))) != 0
                }
                let finding = await moderation.evaluate(
                    guildID: guild,
                    userID: user,
                    messageID: message,
                    content: editedContent,
                    channelID: channel,
                    attachments: data["attachments"] as? [[String: Any]] ?? [],
                    stickerCount: (data["sticker_items"] as? [Any] ?? []).count,
                    mentionEveryone: data["mention_everyone"] as? Bool ?? false,
                    allowMassMentions: canMentionEveryone,
                    roleMentionCount: (data["mention_roles"] as? [String] ?? []).count,
                    userMentionCount: (data["mentions"] as? [[String: Any]] ?? []).count,
                    isEdit: true
                )
                if let owner = await cachedGuildOwnerID(guild), owner != user, let finding {
                    let policy = await moderation.policy(guildID: guild)
                    await markModerationDeleted(message)
                    try? await rest.deleteKimiMessage(channel, message)
                    let sanction = finding.score >= 80 ? policy.sanction : "delete"
                    do {
                        switch sanction {
                        case "timeout": try await rest.timeoutKimiMember(guild, user, policy.timeoutMinutes, finding.reason)
                        case "kick": _ = try await rest.call(
                        "DELETE", "guilds/" + guild + "/members/" + user, auditReason: finding.reason)
                        case "ban":
                            _ = try await rest.call(
                                "PUT", "guilds/" + guild + "/bans/" + user,
                                body: ["delete_message_seconds": policy.actionDurationSeconds],
                                auditReason: finding.reason)
                        default: break
                        }
                    } catch { await logger.log("ERROR", "Edited-message sanction failed: " + error.localizedDescription) }
                    await logger.log("WARN", "Kimi Lock removed edited content: " + finding.reason + "; sanction: " + sanction)
                }
            }
            if installed.contains("Kimi Lock"), recoveryEnabled {
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
            if await wasModerationDeleted(message) { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                await RecoveryService(store: store, logger: logger, rest: rest).restoreMessage(guild, channel, message)
            }
        case "MESSAGE_DELETE_BULK":
            guard let guild = data["guild_id"] as? String, let channel = data["channel_id"] as? String,
                let ids = data["ids"] as? [String]
            else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            guard installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) else {
                return
            }
            let recovery = RecoveryService(store: store, logger: logger, rest: rest)
            for id in ids {
                if await wasModerationDeleted(id) { continue }
                await recovery.restoreMessage(guild, channel, id)
            }
        }
    }
}
