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
        func modalValue(_ key: String) -> String? {
            let rows = data["components"] as? [[String: Any]] ?? []
            for row in rows {
                let components = row["components"] as? [[String: Any]] ?? []
                if let value = components.first(where: { ($0["custom_id"] as? String) == key })?["value"] as? String {
                    return value
                }
            }
            return nil
        }
        do {
            switch custom {
            case "screen:ticket:edit-panel":
                let settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                try await rest.respondKimiModal(
                    id, token, customID: "screen:ticket:save-panel", title: "Ticket panel",
                    inputs: [
                        KimiUI.textInput(id: "panel-title", label: "Panel title", value: settings.panelTitle),
                        KimiUI.textInput(
                            id: "panel-description", label: "Panel description",
                            value: settings.panelDescription, style: 2, maximum: 1000),
                    ])
                return true
            case "screen:welcome:edit-messages":
                let settings = await FoundationEngine(store: store, rest: rest, logger: logger).settings(guildID: guild)
                try await rest.respondKimiModal(
                    id, token, customID: "screen:welcome:save-messages", title: "Welcome messages",
                    inputs: [
                        KimiUI.textInput(id: "welcome-message", label: "Welcome message", value: settings.welcomeMessage),
                        KimiUI.textInput(
                            id: "goodbye-message", label: "Goodbye message",
                            value: settings.goodbyeMessage, style: 2, maximum: 1000),
                    ])
                return true
            case "screen:lock:keywords":
                let policy = await moderation.policy(guildID: guild)
                try await rest.respondKimiModal(
                    id, token, customID: "screen:lock:save-keywords", title: "Blocked keywords",
                    inputs: [
                        KimiUI.textInput(
                            id: "keywords", label: "One keyword or phrase per line",
                            value: policy.blockedPhrases.joined(separator: "\n"), style: 2,
                            required: false, maximum: 1000),
                    ])
                return true
            case "screen:role-picker:edit-name":
                let current = await store.get("screen.role-picker.name." + guild, as: String.self) ?? "roles"
                try await rest.respondKimiModal(
                    id, token, customID: "screen:role-picker:save-name", title: "Role menu name",
                    inputs: [KimiUI.textInput(id: "menu-name", label: "Menu name", value: current, maximum: 24)])
                return true
            case "screen:embeds:create":
                try await rest.respondKimiModal(
                    id, token, customID: "screen:embeds:save", title: "Create or edit embed",
                    inputs: [
                        KimiUI.textInput(id: "embed-name", label: "Name", maximum: 24),
                        KimiUI.textInput(id: "embed-title", label: "Title", maximum: 256),
                        KimiUI.textInput(id: "embed-description", label: "Description", style: 2, maximum: 4000),
                        KimiUI.textInput(id: "embed-color", label: "Color (decimal)", value: "8421504", required: false),
                    ])
                return true
            default:
                break
            }
        } catch {
            await logger.log("ERROR", "Could not open plugin settings editor: " + error.localizedDescription)
            return true
        }
        // Plugin Store navigation updates the existing ephemeral panel instead of
        // creating a second ephemeral response for every button/select interaction.
        if custom == "settings:plugins" || custom == "settings:apps" || custom.hasPrefix("store:") {
            do {
                try await rest.deferKimiComponentUpdate(id, token)
            } catch {
                await logger.log("WARN", "Plugin Store acknowledgement failed: " + error.localizedDescription)
                return true
            }
            await handlePluginStoreComponent(
                custom, data: data, guildID: guild, actorID: actorID,
                applicationID: app, interactionToken: token)
            return true
        }
        // A failed initial acknowledgement is terminal. Never try to edit an
        // interaction response after Discord has invalidated its token.
        do {
            try await rest.deferKimiInteraction(id, token)
        } catch {
            await logger.log("WARN", "Component acknowledgement failed: " + error.localizedDescription)
            return true
        }
        do {
            if let pluginName = ComponentRouter.plugin(for: custom) {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                guard installed.contains(pluginName.rawValue) else {
                    throw KimiError.configuration(pluginName.rawValue + " is not installed in this server.")
                }
            }
            if custom == "settings:plugins" || custom == "settings:apps" {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                let buttons = CommandCatalog.pluginNames().map { pluginName in
                    KimiUI.button(
                        id: "settings:plugin:" + pluginName,
                        label: pluginName + " · " + (installed.contains(pluginName) ? "Remove" : "Install"),
                        style: installed.contains(pluginName) ? 2 : 1)
                }
                let rows = KimiUI.buttonRows(buttons)
                try await rest.editKimiInteraction(
                    app, token, "Plugin Store · Manage Kimi plugins for this server.", rows)
            } else if custom.hasPrefix("settings:plugin:") || custom.hasPrefix("settings:app:") {
                let prefix = custom.hasPrefix("settings:plugin:") ? "settings:plugin:" : "settings:app:"
                let pluginName = String(custom.dropFirst(prefix.count))
                let owner = try await rest.ownerID(guild)
                guard owner == actorID else {
                    throw KimiError.configuration("Only the server owner can install or remove plugins.")
                }
                let manager = PluginManager(store: store)
                let installed = await manager.installed(guildID: guild)
                let result =
                    installed.contains(pluginName)
                    ? try await manager.uninstall(pluginName, guildID: guild)
                    : try await manager.install(pluginName, guildID: guild)
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
                try await rest.editKimiInteraction(app, token, pluginName + " updated.", rows)
            } else if custom.hasPrefix("screen:") {
                let owner = try await rest.ownerID(guild)
                let permissions = UInt64(member["permissions"] as? String ?? "") ?? 0
                guard owner == actorID || permissions & (1 << 5) != 0 else {
                    throw KimiError.configuration("Only the server owner or a member with Manage Server can change plugin settings.")
                }
                let selected = (data["values"] as? [String])?.first
                if custom == "screen:ticket:save-panel" {
                    var settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    if let title = modalValue("panel-title") {
                        settings.panelTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
                    }
                    if let description = modalValue("panel-description") {
                        settings.panelDescription = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
                    }
                    let service = SupportService(store: store, rest: rest, logger: logger)
                    try await service.configure(settings, guild: guild)
                    if let panelChannel = settings.panelChannelID {
                        try await service.publishPanel(guild: guild, channel: panelChannel)
                    }
                } else if custom == "screen:welcome:save-messages" {
                    let engine = FoundationEngine(store: store, rest: rest, logger: logger)
                    var settings = await engine.settings(guildID: guild)
                    if let message = modalValue("welcome-message") { settings.welcomeMessage = String(message.prefix(1800)) }
                    if let message = modalValue("goodbye-message") { settings.goodbyeMessage = String(message.prefix(1800)) }
                    try await engine.configure(guildID: guild, settings)
                } else if custom == "screen:lock:save-keywords" {
                    let engine = moderation
                    var policy = await engine.policy(guildID: guild)
                    let raw = modalValue("keywords") ?? ""
                    let words = raw.components(separatedBy: "\n").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }.filter { !$0.isEmpty }
                    guard words.count <= 100 else {
                        throw KimiError.configuration("A maximum of 100 blocked keywords is supported.")
                    }
                    policy.blockedPhrases = Array(Set(words).sorted().prefix(100))
                    try await engine.configure(policy, guildID: guild)
                } else if custom == "screen:role-picker:save-name" {
                    guard let name = modalValue("menu-name")?.trimmingCharacters(in: .whitespacesAndNewlines),
                        !name.isEmpty, name.count <= 24
                    else { throw KimiError.configuration("Enter a menu name between 1 and 24 characters.") }
                    try await store.setGuild(name, key: "screen.role-picker.name." + guild, guildID: guild)
                } else if custom == "screen:embeds:save" {
                    guard let name = modalValue("embed-name"), let title = modalValue("embed-title"),
                        let description = modalValue("embed-description")
                    else { throw KimiError.configuration("Complete the embed name, title and description.") }
                    let color = Int(modalValue("embed-color") ?? "8421504") ?? 8421504
                    guard (0...16_777_215).contains(color) else {
                        throw KimiError.configuration("Embed color must be a decimal value from 0 to 16777215.")
                    }
                    let saved = try await EmbedService(store: store, rest: rest).save(
                        guild: guild, name: name, title: title, description: description, color: color)
                    try await store.setGuild(saved.name, key: "screen.embeds.selected." + guild, guildID: guild)
                } else if custom == "screen:ticket:category" {
                    var settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    settings.categoryID = selected
                    try await SupportService(store: store, rest: rest, logger: logger).configure(settings, guild: guild)
                } else if custom == "screen:ticket:staff-role" {
                    var settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    settings.supportRoleID = selected
                    try await SupportService(store: store, rest: rest, logger: logger).configure(settings, guild: guild)
                } else if custom == "screen:ticket:panel" {
                    var settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    settings.panelChannelID = selected
                    try await SupportService(store: store, rest: rest, logger: logger).configure(settings, guild: guild)
                } else if custom == "screen:ticket:transcript" {
                    var settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    settings.transcriptChannelID = selected
                    try await SupportService(store: store, rest: rest, logger: logger).configure(settings, guild: guild)
                } else if custom == "screen:ticket:publish" {
                    let settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
                    guard let target = settings.panelChannelID else {
                        throw KimiError.configuration("Select a ticket panel channel first.")
                    }
                    try await SupportService(store: store, rest: rest, logger: logger).publishPanel(guild: guild, channel: target)
                } else if ["screen:lock:verification", "screen:lock:protection", "screen:lock:recovery"].contains(custom) {
                    let module = String(custom.dropFirst("screen:lock:".count))
                    var modules = await store.get("plugins.modules." + guild, as: [String: Bool].self) ?? [:]
                    modules[module] = !(await migratedModuleEnabled(module, guild: guild))
                    try await store.setGuild(modules, key: "plugins.modules." + guild, guildID: guild)
                } else if custom.hasPrefix("screen:lock:") {
                    let engine = moderation
                    var policy = await engine.policy(guildID: guild)
                    switch custom {
                    case "screen:lock:toggle": policy.enabled.toggle()
                    case "screen:lock:invites": policy.blockInvites.toggle()
                    case "screen:lock:mentions": policy.blockMassMentions.toggle()
                    case "screen:lock:caps": policy.blockExcessiveCaps.toggle()
                    case "screen:lock:advertising": policy.blockSelfAdvertising.toggle()
                    case "screen:lock:sanction":
                        guard let selected, ["delete", "timeout", "kick", "ban"].contains(selected) else {
                            throw KimiError.configuration("Choose a valid sanction.")
                        }
                        policy.sanction = selected
                    case "screen:lock:rate":
                        guard let selected, let limit = Int(selected), [10, 20, 30, 50].contains(limit) else {
                            throw KimiError.configuration("Choose a valid message threshold.")
                        }
                        policy.messagesPerMinute = limit
                    case "screen:lock:timeout":
                        guard let selected, let minutes = Int(selected), [5, 10, 30, 60].contains(minutes) else {
                            throw KimiError.configuration("Choose a valid timeout duration.")
                        }
                        policy.timeoutMinutes = minutes
                    default: throw KimiError.configuration("Unknown Kimi Lock setting.")
                    }
                    try await engine.configure(policy, guildID: guild)
                } else if custom == "screen:welcome:channel" || custom == "screen:welcome:goodbye" {
                    let engine = FoundationEngine(store: store, rest: rest, logger: logger)
                    var settings = await engine.settings(guildID: guild)
                    if custom == "screen:welcome:channel" { settings.welcomeChannel = selected }
                    else { settings.goodbyeChannel = selected }
                    try await engine.configure(guildID: guild, settings)
                } else if custom == "screen:auto-role:role" || custom == "screen:auto-role:disable" {
                    let engine = FoundationEngine(store: store, rest: rest, logger: logger)
                    var settings = await engine.settings(guildID: guild)
                    settings.autoRole = custom == "screen:auto-role:disable" ? nil : selected
                    try await engine.configure(guildID: guild, settings)
                } else if custom == "screen:role-picker:channel" {
                    guard let selected else { throw KimiError.configuration("Select a role-menu channel.") }
                    try await store.setGuild(selected, key: "screen.role-picker.channel." + guild, guildID: guild)
                } else if custom == "screen:role-picker:publish" {
                    guard let target = await store.get("screen.role-picker.channel." + guild, as: String.self) else {
                        throw KimiError.configuration("Select a role-menu channel first.")
                    }
                    let menuName = await store.get("screen.role-picker.name." + guild, as: String.self) ?? "roles"
                    _ = try await RolePickerService(store: store, rest: rest, logger: logger)
                        .publish(guild: guild, channel: target, name: menuName)
                } else if custom == "screen:embeds:select" {
                    guard let selected else { throw KimiError.configuration("Choose a saved embed.") }
                    try await store.setGuild(selected, key: "screen.embeds.selected." + guild, guildID: guild)
                } else if custom == "screen:embeds:channel" {
                    guard let selected else { throw KimiError.configuration("Choose a destination channel.") }
                    try await store.setGuild(selected, key: "screen.embeds.channel." + guild, guildID: guild)
                } else if custom == "screen:embeds:publish" {
                    guard let selected = await store.get("screen.embeds.selected." + guild, as: String.self),
                        let target = await store.get("screen.embeds.channel." + guild, as: String.self)
                    else {
                        throw KimiError.configuration("Choose both a saved embed and a destination channel.")
                    }
                    try await EmbedService(store: store, rest: rest).publish(guild: guild, name: selected, channel: target)
                } else {
                    throw KimiError.configuration("This plugin setting is not supported by the current screen.")
                }
                try await rest.editKimiInteraction(app, token, "Plugin settings saved.")
            } else if custom == "settings:status" {
                let installed = await PluginManager(store: store).installed(guildID: guild)
                let policy = await moderation.policy(guildID: guild)
                let open = await SupportTickets(store: store).all().filter { $0.guildID == guild && $0.isOpen }.count
                let report = await AnalyticsService(store: store).report(guild: guild)
                let message =
                    "Kimi system status\nPlugins: " + (installed.isEmpty ? "None" : installed.joined(separator: ", "))
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
                                    "type": 2, "style": 2,
                                    "custom_id": "ticket:confirm-close:" + ticketID,
                                ], ["type": 2, "style": 2, "label": "Cancel", "custom_id": "ticket:cancel-close"],
                            ],
                        ]
                    ] as [[String: Any]]
                _ = try await rest.call(
                    "PATCH", "webhooks/\(app)/\(token)/messages/@original",
                    body: [
                        "embeds": [KimiUI.embed(title: "Close support ticket", description: "Are you sure you want to close this ticket?")], "content": NSNull(), "components": controls,
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
                let transcriptRetained = await store.get(
                    "support.transcript." + guild + "." + ticketID, as: String.self) != nil
                let transcriptStatus = transcriptRetained
                    ? "Transcript retained in Kimi storage."
                    : "The ticket was closed, but local transcript retention failed."
                try await rest.editKimiInteraction(
                    app, token,
                    "Ticket closed. " + transcriptStatus + " Channel: <#" + closed.channelID + ">")
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
                let messageID = (event["message"] as? [String: Any])?["id"] as? String
                guard let expected = record.reviewMessageID, messageID == expected else {
                    throw KimiError.configuration("This review message is no longer active.")
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
