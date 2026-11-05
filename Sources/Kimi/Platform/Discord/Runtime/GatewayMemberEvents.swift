import Foundation

extension KimiRuntime {
    func handleGuildMemberEvent(_ eventName: String, _ data: [String: Any]) async {
        switch eventName {
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
                                                "type": 2, "style": 2, "label": "Approve",
                                                "custom_id": "botguard:yes:" + guild + ":" + id,
                                            ],
                                            [
                                                "type": 2, "style": 2, "label": "Reject",
                                                "custom_id": "botguard:no:" + guild + ":" + id,
                                            ],
                                        ],
                                    ]
                                ] as [[String: Any]]
                            _ = try await rest.call(
                                "POST", "channels/" + confirmation + "/messages",
                                body: KimiUI.panel(title: "New bot approval required", description: "Bot: <@" + id + ">\n" + warning + "\nContainment: " + String(containment?.removedCount ?? 0) + " role(s) removed.", components: controls))
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
                    (eventName == "GUILD_BAN_ADD" ? "Ban recorded for " : "Unban recorded for ") + user + " in guild "
                        + guild)
            }
        default: return
        }
    }
}
