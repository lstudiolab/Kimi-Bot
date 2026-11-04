import Foundation

extension KimiRuntime {
    func handleMigratedComponent(_ event: [String: Any], data: [String: Any]) async -> Bool {
        guard let id = event["id"] as? String, let token = event["token"] as? String,
            let app = event["application_id"] as? String
        else { return true }
        let guild = event["guild_id"] as? String ?? ""
        let channel = event["channel_id"] as? String ?? ""
        let member = event["member"] as? [String: Any] ?? [:]
        let actor = member["user"] as? [String: Any] ?? [:]
        let actorID = actor["id"] as? String ?? ""
        let username = actor["username"] as? String ?? "member"
        let custom = data["custom_id"] as? String ?? ""
        // A failed initial acknowledgement is terminal. Never try to edit an
        // interaction response after Discord has invalidated its token.
        do {
            try await rest.deferKimiInteraction(id, token)
        } catch {
            await logger.log("WARN", "Component acknowledgement failed: " + error.localizedDescription)
            return true
        }
        do {
            if let appName = ComponentRouter.app(for: custom) {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                guard installed.contains(appName.rawValue) else {
                    throw KimiError.configuration(appName.rawValue + " is not installed in this server.")
                }
            }
            if custom == "settings:plugins" || custom == "settings:apps" {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                let buttons = CommandCatalog.pluginNames().map { appName in
                    KimiUI.button(
                        id: "settings:plugin:" + appName,
                        label: appName + " · " + (installed.contains(appName) ? "Remove" : "Install"),
                        style: installed.contains(appName) ? 2 : 1)
                }
                let rows = KimiUI.buttonRows(buttons)
                try await rest.editKimiInteraction(app, token, "Plugin Store · Manage Kimi plugins for this server.", rows)
            } else if custom.hasPrefix("settings:plugin:") || custom.hasPrefix("settings:app:") {
                let prefix = custom.hasPrefix("settings:plugin:") ? "settings:plugin:" : "settings:app:"
                let appName = String(custom.dropFirst(prefix.count))
                let owner = try await rest.ownerID(guild)
                guard owner == actorID else {
                    throw KimiError.configuration("Only the server owner can install or remove plugins.")
                }
                let manager = PluginManager(store: store)
                let installed = await manager.installed(guildID: guild)
                let result =
                    installed.contains(appName)
                    ? try await manager.uninstall(appName, guildID: guild)
                    : try await manager.install(appName, guildID: guild)
                guard result.ok else { throw KimiError.configuration(result.message) }
                let updated = await manager.installed(guildID: guild)
                try await rest.registerGuildCommands(app, guildID: guild, installed: updated)
                let buttons = CommandCatalog.pluginNames().map { value in
                    KimiUI.button(
                        id: "settings:plugin:" + value,
                        label: value + " · " + (updated.contains(value) ? "Remove" : "Install"),
                        style: updated.contains(value) ? 2 : 1)
                }
                let rows = KimiUI.buttonRows(buttons)
                try await rest.editKimiInteraction(app, token, appName + " updated.", rows)
            } else if custom == "settings:status" {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                let policy = await ModerationEngine(store: store).policy(guildID: guild)
                let open = await SupportTickets(store: store).all().filter { $0.guildID == guild && $0.isOpen }.count
                let report = await AnalyticsService(store: store).report(guild: guild)
                let message =
                    "Kimi system status\nApps: " + (installed.isEmpty ? "None" : installed.joined(separator: ", "))
                    + "\nKimi Lock: "
                    + (installed.contains("Kimi Lock")
                        ? (policy.enabled ? "Active" : "Installed · disabled") : "Not installed")
                    + "\nOpen Support tickets: " + String(open) + "\nMessages recorded: " + String(report.messages)
                let rows = [
                    KimiUI.row([
                        KimiUI.button(id: "settings:plugins", label: "Manage plugins"),
                        KimiUI.button(id: "settings:home", label: "Home"),
                    ])
                ]
                try await rest.editKimiInteraction(app, token, message, rows)
            } else if custom == "settings:preferences" {
                let options = KimiLocalization.locales.prefix(25).map {
                    ["label": String((KimiLocalization.names[$0] ?? $0).prefix(100)), "value": $0]
                }
                let rows = [
                    KimiUI.row([
                        KimiUI.stringSelect(id: "settings:language", placeholder: "Select language", options: options)
                    ])
                ]
                try await rest.editKimiInteraction(app, token, "Choose the server language.", rows)
            } else if custom == "settings:language" {
                guard let locale = (data["values"] as? [String])?.first, KimiLocalization.names[locale] != nil else {
                    throw KimiError.configuration("Choose a supported language.")
                }
                var languages = await store.get("languages", as: [String: String].self) ?? [:]
                languages[guild] = locale
                try await store.set(languages, key: "languages")
                try await rest.editKimiInteraction(
                    app, token, "Server language set to " + (KimiLocalization.names[locale] ?? locale) + ".")
            } else if custom == "settings:activity" {
                let entries = await logger.recent(limit: 100)
                let rows = entries.filter { $0.message.contains(guild) }.suffix(12)
                let body = rows.map {
                    ISO8601DateFormatter().string(from: $0.date) + " · " + $0.level + " · " + $0.message
                }.joined(separator: "\n")
                try await rest.editKimiInteraction(
                    app, token, body.isEmpty ? "No recent activity recorded." : String(body.prefix(1800)))
            } else if custom == "settings:home" {
                let rows = [
                    KimiUI.row([
                        KimiUI.button(id: "settings:plugins", label: "Plugin Store"),
                        KimiUI.button(id: "settings:status", label: "System Status"),
                    ]),
                    KimiUI.row([
                        KimiUI.button(id: "settings:preferences", label: "Preferences"),
                        KimiUI.button(id: "settings:activity", label: "Activity"),
                    ]),
                ]
                try await rest.editKimiInteraction(app, token, "Kimi server control centre.", rows)
            } else if custom == "ticket:open" {
                let settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                guard settings.panelChannelID == channel else {
                    throw KimiError.configuration("This ticket panel is no longer active.")
                }
                let me = try await rest.call("GET", "users/@me")
                guard let bot = (me as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
                let ticket = try await SupportService(store: store, rest: rest, logger: logger).open(
                    guild: guild, user: actorID, username: username, bot: bot)
                await AnalyticsService(store: store).record(guild: guild, event: "ticket_open")
                try await rest.editKimiInteraction(
                    app, token, "Your private ticket is ready: <#" + ticket.channelID + ">")
            } else if custom.hasPrefix("ticket:priority:") {
                let value = String(custom.dropFirst("ticket:priority:".count)).split(separator: ":").map(String.init)
                guard value.count == 2 else { throw KimiError.configuration("This priority control is invalid.") }
                let ticketID = value[0]
                let priority = value[1]
                let tickets = await SupportTickets(store: store).all()
                guard
                    let ticket = tickets.first(where: {
                        $0.id == ticketID && $0.guildID == guild && $0.channelID == channel && $0.isOpen
                    })
                else { throw KimiError.configuration("This ticket is no longer open.") }
                let owner = try await rest.ownerID(guild)
                let settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                let roles = Set((member["roles"] as? [String]) ?? [])
                let staff = settings.supportRoleID.map { roles.contains($0) } ?? false
                guard ticket.userID == actorID || owner == actorID || staff else {
                    throw KimiError.configuration(
                        "Only the ticket opener, support staff or server owner can change priority.")
                }
                let updated = try await SupportService(store: store, rest: rest, logger: logger).setPriority(
                    guild: guild, ticketID: ticketID, priority: priority)
                try await rest.editKimiInteraction(app, token, "Ticket priority changed to " + updated.priority + ".")
            } else if custom.hasPrefix("ticket:close:") {
                let ticketID = String(custom.dropFirst("ticket:close:".count))
                let tickets = await SupportTickets(store: store).all()
                guard
                    let ticket = tickets.first(where: {
                        $0.id == ticketID && $0.guildID == guild && $0.channelID == channel && $0.isOpen
                    })
                else { throw KimiError.configuration("This ticket control is no longer valid.") }
                let owner = try await rest.ownerID(guild)
                let supportSettings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                let staffRoles = Set((member["roles"] as? [String]) ?? [])
                let isStaff = supportSettings.supportRoleID.map { staffRoles.contains($0) } ?? false
                guard ticket.userID == actorID || owner == actorID || isStaff else {
                    throw KimiError.configuration(
                        "Only the ticket opener, support staff or server owner can close this ticket.")
                }
                let controls =
                    [
                        [
                            "type": 1,
                            "components": [
                                [
                                    "type": 2, "style": 4, "label": "Yes, close it",
                                    "custom_id": "ticket:confirm-close:" + ticketID,
                                ], ["type": 2, "style": 2, "label": "Cancel", "custom_id": "ticket:cancel-close"],
                            ],
                        ]
                    ] as [[String: Any]]
                _ = try await rest.call(
                    "PATCH", "webhooks/\(app)/\(token)/messages/@original",
                    body: [
                        "content": "Close this support ticket?", "components": controls,
                        "allowed_mentions": ["parse": []],
                    ])
            } else if custom.hasPrefix("ticket:confirm-close:") {
                let ticketID = String(custom.dropFirst("ticket:confirm-close:".count))
                let tickets = await SupportTickets(store: store).all()
                guard
                    let ticket = tickets.first(where: {
                        $0.id == ticketID && $0.guildID == guild && $0.channelID == channel && $0.isOpen
                    })
                else { throw KimiError.configuration("This ticket is no longer open.") }
                let owner = try await rest.ownerID(guild)
                let supportSettings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                let staffRoles = Set((member["roles"] as? [String]) ?? [])
                let isStaff = supportSettings.supportRoleID.map { staffRoles.contains($0) } ?? false
                guard ticket.userID == actorID || owner == actorID || isStaff else {
                    throw KimiError.configuration(
                        "Only the ticket opener, support staff or server owner can close this ticket.")
                }
                let closed = try await SupportService(store: store, rest: rest, logger: logger).close(
                    guild: guild, ticketID: ticketID)
                await AnalyticsService(store: store).record(guild: guild, event: "ticket_close")
                try await rest.editKimiInteraction(
                    app, token,
                    "Ticket closed. Transcript retained in Kimi storage. Channel: <#" + closed.channelID + ">")
            } else if custom == "ticket:cancel-close" {
                try await rest.editKimiInteraction(app, token, "Ticket remains open.")
            } else if custom == "verify:start" {
                let expected = await store.get("verification.prompt." + guild + "." + actorID, as: String.self)
                let message = (event["message"] as? [String: Any])?["id"] as? String
                guard expected == message else {
                    throw KimiError.configuration("This verification prompt is no longer valid.")
                }
                await VerificationService(store: store, rest: rest, logger: logger).verify(
                    guild: guild, userID: actorID, username: username, applicationID: app, interactionToken: token)
            } else if custom.hasPrefix("verify:approve:") || custom.hasPrefix("verify:reject:") {
                let approve = custom.hasPrefix("verify:approve:")
                let target = String(custom.dropFirst(approve ? "verify:approve:".count : "verify:reject:".count))
                let record = await VerificationRecords(store: store).record(guildID: guild, userID: target)
                if let expected = record.reviewMessageID {
                    let messageID = (event["message"] as? [String: Any])?["id"] as? String
                    guard messageID == expected else {
                        throw KimiError.configuration("This review message is no longer active.")
                    }
                }
                await VerificationService(store: store, rest: rest, logger: logger).review(
                    guild: guild, userID: target, decision: approve ? "approve" : "reject", reviewer: actorID,
                    applicationID: app, interactionToken: token)
            } else if custom.hasPrefix("botguard:") {
                let parts = custom.split(separator: ":").map(String.init)
                guard parts.count == 4, parts[2] == guild else {
                    throw KimiError.configuration("This bot approval request is invalid.")
                }
                let owner = try await rest.ownerID(guild)
                guard owner == actorID else {
                    throw KimiError.configuration("Only the server owner can approve or reject a bot.")
                }
                let target = parts[3]
                if parts[1] == "yes" {
                    let result = try await KimiGuardService(store: store, rest: rest, logger: logger).review(
                        guild: guild, actor: target, decision: "restore", reviewer: actorID)
                    try await rest.editKimiInteraction(app, token, "Bot approved. " + result)
                } else if parts[1] == "no" {
                    _ = try await KimiGuardService(store: store, rest: rest, logger: logger).review(
                        guild: guild, actor: target, decision: "keep", reviewer: actorID)
                    _ = try await rest.call("DELETE", "guilds/" + guild + "/members/" + target)
                    try await rest.editKimiInteraction(
                        app, token, "Bot rejected and removed from the server. The incident remains documented.")
                } else {
                    throw KimiError.configuration("Unknown bot approval decision.")
                }
            } else if custom.hasPrefix("rolepicker:select") {
                let selected = data["values"] as? [String] ?? []
                let parts = custom.split(separator: ":").map(String.init)
                let menuID = parts.count > 2 ? parts[2] : nil
                let count = try await RolePickerService(store: store, rest: rest, logger: logger).select(
                    guild: guild, user: actorID, selected: selected, menuID: menuID)
                try await rest.editKimiInteraction(
                    app, token, "Your role selection was updated. Active roles: " + String(count) + ".")
            } else {
                try await rest.editKimiInteraction(
                    app, token, "This Kimi control is unknown or expired. Reopen the panel to get a current control.")
            }
        } catch {
            try? await rest.editKimiInteraction(
                app, token, "Kimi could not complete this action: " + error.localizedDescription)
            await logger.log("ERROR", "Component " + custom + " failed: " + error.localizedDescription)
        }
        return true
    }
}
