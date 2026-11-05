import Foundation

extension RecoveryService {
        func queueDeletedRole(_ guild: String, _ role: String) async {
            guard role != guild else { return }
            do {
                _ = try await store.updateGuild("recovery.pending-roles", guildID: guild, as: [String: [String]].self) { stored in
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
                    var roleMappings = await store.get("recovery.role-map." + guild, as: [String: String].self) ?? [:]
                    roleMappings[roleID] = restored
                    do {
                        try await store.setGuild(
                            roleMappings, key: "recovery.role-map." + guild, guildID: guild)
                    } catch {
                        _ = try? await rest.call("DELETE", "guilds/" + guild + "/roles/" + restored)
                        throw error
                    }
                    restoredIDs.insert(roleID)
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
}
