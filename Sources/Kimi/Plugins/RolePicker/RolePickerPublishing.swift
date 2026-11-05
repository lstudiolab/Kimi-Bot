import Foundation

extension RolePickerService {
        func publish(guild: String, channel: String, name: String = "roles") async throws -> Int {
            let safeName = String(name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(24))
            guard !safeName.isEmpty else { throw KimiError.configuration("Menu name must contain letters or numbers.") }
            let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
            let bot = try await rest.call("GET", "guilds/\(guild)/members/@me") as? [String: Any] ?? [:]
            let botIDs = Set(bot["roles"] as? [String] ?? [])
            let botRoles = roles.filter { botIDs.contains($0["id"] as? String ?? "") }
            let highest = botRoles.map { $0["position"] as? Int ?? 0 }.max() ?? 0
            let canManage = botRoles.contains { (UInt64($0["permissions"] as? String ?? "") ?? 0) & 268_435_464 != 0 }
            guard canManage else {
                throw KimiError.configuration("Kimi needs Manage Roles permission to publish role menus.")
            }
            let safe = roles.filter { item in
                guard let id = item["id"] as? String else { return false }
                let permissions = UInt64(item["permissions"] as? String ?? "") ?? 0
                return SecurityPolicy.isSafeRole(
                    roleID: id, guildID: guild, managed: item["managed"] as? Bool ?? false, permissions: permissions)
                    && (item["position"] as? Int ?? 0) < highest
            }.sorted { ($0["position"] as? Int ?? 0) < ($1["position"] as? Int ?? 0) }.suffix(25)
            let values = safe.compactMap { item -> Role? in
                guard let id = item["id"] as? String else { return nil }
                return Role(id: id, name: item["name"] as? String ?? "Role")
            }
            guard !values.isEmpty else { throw KimiError.configuration("No safe assignable roles were found.") }
            var menus = await store.get("rolepicker.menus." + guild, as: [String: Menu].self) ?? [:]
            let previous = menus[safeName]
            let options = values.map {
                ["label": DiscordText.prefixUTF16($0.name, limit: 100), "value": $0.id]
            }
            let customID = "rolepicker:select:" + safeName
            let components =
                [
                    [
                        "type": 1,
                        "components": [
                            [
                                "type": 3, "custom_id": customID, "placeholder": "Choose your roles", "min_values": 0,
                                "max_values": values.count, "options": options,
                            ]
                        ],
                    ]
                ] as [[String: Any]]
            let body = KimiUI.panel(title: name, description: "Choose the roles you want to have. You can update your selection at any time.", components: components)
            var messageID: String?
            if let oldMessage = previous?.messageID, previous?.channelID == channel {
                do {
                    _ = try await rest.call(
                        "PATCH", "channels/\(channel)/messages/\(oldMessage)", body: body)
                    messageID = oldMessage
                } catch KimiError.http(404, _) {
                    messageID = nil
                }
            }
            var createdMessageID: String?
            if messageID == nil {
                let response = try await rest.call("POST", "channels/\(channel)/messages", body: body) as? [String: Any] ?? [:]
                guard let created = response["id"] as? String, !created.isEmpty else {
                    throw KimiError.invalidResponse
                }
                messageID = created
                createdMessageID = created
            }
            let menu = Menu(
                id: safeName, name: name, guildID: guild, channelID: channel, messageID: messageID, roles: values)
            menus[safeName] = menu
            do {
                try await store.setGuild(menus, key: "rolepicker.menus." + guild, guildID: guild)
            } catch {
                if let createdMessageID {
                    _ = try? await rest.call("DELETE", "channels/\(channel)/messages/\(createdMessageID)")
                }
                throw error
            }
            if let previous, previous.channelID != channel, let oldMessage = previous.messageID {
                _ = try? await rest.call("DELETE", "channels/\(previous.channelID)/messages/\(oldMessage)")
            }
            await logger.log("INFO", "Role Picker menu " + safeName + " published in guild " + guild)
            return values.count
        }
}
