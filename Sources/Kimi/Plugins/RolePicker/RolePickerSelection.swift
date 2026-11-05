import Foundation

extension RolePickerService {
        func select(guild: String, user: String, selected: [String], menuID: String? = nil) async throws -> Int {
            let menu: Menu?
            if let menuID {
                let menus = await store.get("rolepicker.menus." + guild, as: [String: Menu].self) ?? [:]
                menu = menus[menuID]
            } else {
                menu = await store.get("rolepicker.menu." + guild, as: Menu.self)
            }
            guard let menu else { throw KimiError.configuration("This role menu is no longer active.") }
            let allowed = Set(menu.roles.map { $0.id })
            let chosen = Set(selected)
            guard chosen.isSubset(of: allowed) else {
                throw KimiError.configuration("The selection contains an invalid role.")
            }
            let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
            let bot = try await rest.call("GET", "guilds/\(guild)/members/@me") as? [String: Any] ?? [:]
            let botRoleIDs = Set(bot["roles"] as? [String] ?? [])
            let botRoles = roles.filter { botRoleIDs.contains($0["id"] as? String ?? "") }
            let highest = botRoles.map { $0["position"] as? Int ?? 0 }.max() ?? 0
            let canManage = botRoles.contains {
                (UInt64($0["permissions"] as? String ?? "") ?? 0) & ((1 << 28) | (1 << 3)) != 0
            }
            guard canManage else {
                throw KimiError.configuration("Kimi needs Manage Roles permission to update role selections.")
            }
            for roleID in chosen {
                guard let role = roles.first(where: { ($0["id"] as? String) == roleID }) else {
                    throw KimiError.configuration("A selected role no longer exists.")
                }
                let permissions = UInt64(role["permissions"] as? String ?? "") ?? 0
                guard
                    SecurityPolicy.isSafeRole(
                        roleID: roleID, guildID: guild, managed: role["managed"] as? Bool ?? false, permissions: permissions
                    ), (role["position"] as? Int ?? 0) < highest
                else { throw KimiError.configuration("A selected role is no longer safe or assignable.") }
            }
            let key = "rolepicker.selection." + guild + "." + user + "." + (menuID ?? "default")
            let member = try await rest.call("GET", "guilds/\(guild)/members/\(user)") as? [String: Any] ?? [:]
            let currentRoles = Set(member["roles"] as? [String] ?? [])
            let removed = currentRoles.intersection(allowed).subtracting(chosen).sorted()
            let added = chosen.subtracting(currentRoles).sorted()
            var appliedRemovals: [String] = []
            var appliedAdditions: [String] = []
            do {
                for role in removed {
                    _ = try await rest.call("DELETE", "guilds/\(guild)/members/\(user)/roles/\(role)")
                    appliedRemovals.append(role)
                }
                for role in added {
                    _ = try await rest.call("PUT", "guilds/\(guild)/members/\(user)/roles/\(role)")
                    appliedAdditions.append(role)
                }
                try await store.setGuild(chosen.sorted(), key: key, guildID: guild)
            } catch {
                for role in appliedAdditions.reversed() {
                    do {
                        _ = try await rest.call("DELETE", "guilds/\(guild)/members/\(user)/roles/\(role)")
                    } catch {
                        await logger.log("ERROR", "Role selection rollback could not remove " + role + ": " + error.localizedDescription)
                    }
                }
                for role in appliedRemovals.reversed() {
                    do {
                        _ = try await rest.call("PUT", "guilds/\(guild)/members/\(user)/roles/\(role)")
                    } catch {
                        await logger.log("ERROR", "Role selection rollback could not restore " + role + ": " + error.localizedDescription)
                    }
                }
                throw error
            }
            return chosen.count
        }
}
