import Foundation

extension RecoveryService {
        func queueDeletedChannel(_ guild: String, _ channel: String) async {
            do {
                _ = try await store.updateGuild("recovery.pending-channels", guildID: guild, as: [String: [String]].self) { stored in
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
                    _ = try? await rest.call("DELETE", "channels/" + restored)
                    throw error
                }
                await logger.log(
                    "WARN", "Kimi Lock restored deleted channel " + channelID + " as " + restored + " in guild " + guild)
                return true
            } catch {
                await logger.log("ERROR", "Channel recovery failed for " + channelID + ": " + error.localizedDescription)
                return false
            }
        }
}
