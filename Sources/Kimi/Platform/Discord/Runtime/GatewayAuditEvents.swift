import Foundation

extension KimiRuntime {
    func handleGuildAuditEvent(_ eventName: String, _ data: [String: Any]) async {
        switch eventName {
        case "CHANNEL_CREATE", "CHANNEL_UPDATE":
            guard let guild = data["guild_id"] as? String else { return }
            let installed = await PluginManager(store: store).installed(guildID: guild)
            if installed.contains("Kimi Lock"), await migratedModuleEnabled("recovery", guild: guild) {
                await RecoveryService(store: store, logger: logger, rest: rest).captureChannel(guild, data)
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
            if action == 30 || action == 31 {
                let roles = (try? await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]]) ?? []
                if await migratedModuleEnabled("recovery", guild: guild) {
                    for role in roles { await recovery.captureRole(guild, role) }
                }
                let permissions = Dictionary(uniqueKeysWithValues: roles.compactMap { role -> (String, String)? in
                    guard let id = role["id"] as? String else { return nil }
                    return (id, role["permissions"] as? String ?? "0")
                })
                try? await store.setGuild(permissions, key: "security.role-permissions." + guild, guildID: guild)
                try? await store.setGuild(Date(), key: "security.role-permissions-updated." + guild, guildID: guild)
            }
            guard let owner = await cachedGuildOwnerID(guild), actor != owner else { return }
            let botID = await store.get("runtime.bot_id", as: String.self) ?? ""
            guard actor != botID else { return }
            let target = data["target_id"] as? String
            if action == 12, let target, await migratedModuleEnabled("recovery", guild: guild) {
                await recovery.queueDeletedChannel(guild, target)
            }
            let privilegedMask = SecurityPolicy.privilegedPermissionBits.reduce(UInt64(0), { $0 | $1 })
            if (action == 30 || action == 31), let target {
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
                            if var cached = await store.get(
                                "security.role-permissions." + guild, as: [String: String].self),
                                cached[target] != nil
                            {
                                cached[target] = String(safePermissions)
                                try? await store.setGuild(
                                    cached, key: "security.role-permissions." + guild, guildID: guild)
                                try? await store.setGuild(
                                    Date(), key: "security.role-permissions-updated." + guild, guildID: guild)
                            }
                            await logger.log("WARN", "Kimi Lock stripped elevated permissions from role " + target)
                        } catch {
                            await logger.log("ERROR", "Could not strip elevated role permissions: " + error.localizedDescription)
                        }
                    }
                }
            }
            if [13, 14, 15].contains(action) {
                let options = data["options"] as? [String: Any] ?? [:]
                let channelID = options["channel_id"] as? String
                let overwriteID = options["id"] as? String ?? target
                let overwriteType = options["type"] as? Int ?? Int(options["type"] as? String ?? "0") ?? 0
                let changes = data["changes"] as? [[String: Any]] ?? []
                func permissionValue(_ raw: Any?) -> UInt64? {
                    if let value = raw as? String { return UInt64(value) }
                    if let value = raw as? NSNumber { return value.uint64Value }
                    return nil
                }
                let oldAllow = permissionValue(changes.first(where: { ($0["key"] as? String) == "allow" })?["old_value"])
                let oldDeny = permissionValue(changes.first(where: { ($0["key"] as? String) == "deny" })?["old_value"])
                let newAllow = permissionValue(changes.first(where: { ($0["key"] as? String) == "allow" })?["new_value"])
                let newDeny = permissionValue(changes.first(where: { ($0["key"] as? String) == "deny" })?["new_value"])
                if let channelID, let overwriteID {
                    do {
                        if action == 13, let newAllow, newAllow & privilegedMask != 0 {
                            let newDeny = permissionValue(changes.first(where: { ($0["key"] as? String) == "deny" })?["new_value"]) ?? 0
                            _ = try await rest.call(
                                "PUT", "channels/" + channelID + "/permissions/" + overwriteID,
                                body: [
                                    "allow": String(newAllow & ~privilegedMask),
                                    "deny": String(newDeny | (newAllow & privilegedMask)),
                                    "type": overwriteType,
                                ],
                                auditReason: "Kimi Lock stripped privileged grants from a new channel overwrite"
                            )
                            await logger.log("WARN", "Kimi Lock stripped privileged permission grants from a new channel overwrite.")
                        } else if action == 14, let oldAllow, let oldDeny, let newAllow, let newDeny,
                            (newAllow & ~oldAllow & privilegedMask != 0 || oldDeny & ~newDeny & privilegedMask != 0)
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
            if action == 25, let target {
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
            if action == 22, let target {
                let key = "security.pending-bans." + guild + "." + actor
                var targets = await store.get(key, as: [String].self) ?? []
                if !targets.contains(target) { targets.append(target) }
                try? await store.setGuild(Array(targets.suffix(100)), key: key, guildID: guild)
            }
            if action == 32, let target, await migratedModuleEnabled("recovery", guild: guild) {
                await recovery.queueDeletedRole(guild, target)
            }
            do {
                if let incident = try await AuditProtection(store: store).record(
                    guildID: guild, actorID: actor, action: String(action))
                {
                    await logger.log("WARN", "Kimi Lock incident: " + incident.reason)
                    if ["12", "13", "14", "15", "20", "22", "25", "30", "31", "32", "50", "51", "52"].contains(incident.action) {
                        do {
                            _ = try await KimiGuardService(store: store, rest: rest, logger: logger).contain(
                                guild: guild, actor: actor, action: incident.action)
                        } catch {
                            await logger.log("ERROR", "Kimi Guard containment failed; continuing recovery: " + error.localizedDescription)
                        }
                    }
                    if incident.action == "12" {
                        await RecoveryService(store: store, logger: logger, rest: rest).restorePendingChannels(guild)
                    }
                    if incident.action == "32", await migratedModuleEnabled("recovery", guild: guild) {
                        await RecoveryService(store: store, logger: logger, rest: rest).restorePendingRoles(guild)
                    }
                    if incident.action == "22" {
                        let key = "security.pending-bans." + guild + "." + actor
                        let targets = await store.get(key, as: [String].self) ?? []
                        for userID in targets {
                            do {
                                _ = try await rest.call(
                                    "DELETE", "guilds/" + guild + "/bans/" + userID,
                                    auditReason: "Kimi Lock reversed a confirmed mass-ban incident"
                                )
                            } catch {
                                await logger.log("ERROR", "Could not reverse a mass-ban action for " + userID)
                            }
                        }
                        try? await store.setGuild([String](), key: key, guildID: guild)
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
        default: return
        }
    }
}
