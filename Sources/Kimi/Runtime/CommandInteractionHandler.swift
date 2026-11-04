import Foundation

extension KimiRuntime {
    func handleMigratedCommand(_ event: [String: Any]) async -> Bool {
        guard let interactionType = event["type"] as? Int, interactionType == 2 || interactionType == 3 else {
            return false
        }
        let started = Date()
        guard let id = event["id"] as? String, let token = event["token"] as? String,
            let app = event["application_id"] as? String
        else { return false }
        let guild = event["guild_id"] as? String ?? ""
        let memberUser = (event["member"] as? [String: Any])?["user"] as? [String: Any] ?? [:]
        let user = (event["user"] as? [String: Any])?["id"] as? String ?? memberUser["id"] as? String ?? ""
        let data = event["data"] as? [String: Any] ?? [:]
        let name = data["name"] as? String ?? ""
        let options = data["options"] as? [[String: Any]] ?? []
        func value(_ key: String) -> String? {
            if let v = options.first(where: { ($0["name"] as? String) == key })?["value"] as? String { return v }
            for option in options {
                if let nested = option["options"] as? [[String: Any]],
                    let v = nested.first(where: { ($0["name"] as? String) == key })?["value"] as? String
                {
                    return v
                }
            }
            return nil
        }
        if interactionType == 3 { return await handleMigratedComponent(event, data: data) }
        do { try await rest.deferKimiInteraction(id, token) } catch {
            await logger.log("WARN", "Interaction acknowledgement failed: " + error.localizedDescription)
            return true
        }
        var reply = "Command completed."
        var responseComponents: [[String: Any]] = []
        do {
            switch name {
            case "kimi":
                let installed = await AppManager(store: store).installed(guildID: guild)
                reply =
                    "Kimi server control centre\nInstalled apps: "
                    + (installed.isEmpty ? "None" : installed.joined(separator: ", "))
                responseComponents = [
                    KimiUI.row([
                        KimiUI.button(id: "settings:plugins", label: "Plugin Store"),
                        KimiUI.button(id: "settings:status", label: "System Status"),
                    ]),
                    KimiUI.row([
                        KimiUI.button(id: "settings:preferences", label: "Preferences"),
                        KimiUI.button(id: "settings:activity", label: "Activity"),
                    ]),
                ]
            case "plugins", "plugin-store":
                let installed = await AppManager(store: store).installed(guildID: guild)
                reply =
                    "Kimi Plugins\n"
                    + CommandCatalog.pluginNames().map {
                        $0 + " — " + (installed.contains($0) ? "Installed" : "Available")
                    }.joined(separator: "\n") + "\n\nUse /plugin-install to add a plugin."
            case "plugin-install", "plugin-remove":
                let owner = try await rest.ownerID(guild)
                guard owner == user else {
                    throw KimiError.configuration("Only the server owner can install or remove plugins.")
                }
                guard let appName = value("plugin") else { throw KimiError.configuration("Choose a plugin.") }
                let manager = AppManager(store: store)
                let result =
                    name == "plugin-install"
                    ? try await manager.install(appName, guildID: guild)
                    : try await manager.uninstall(appName, guildID: guild)
                guard result.ok else { throw KimiError.configuration(result.message) }
                let installed = await manager.installed(guildID: guild)
                try await rest.registerGuildCommands(app, guildID: guild, installed: installed)
                reply =
                    appName
                    + (name == "install"
                        ? " installed. Its commands are available in this server."
                        : " removed. Saved settings were preserved.")
            case "setup":
                let owner = try await rest.ownerID(guild)
                let me = try await rest.call("GET", "users/@me")
                guard let bot = (me as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
                let channels = try await rest.call("GET", "guilds/\(guild)/channels") as? [[String: Any]] ?? []
                func existing(_ name: String, _ type: Int) -> String? {
                    channels.first(where: { ($0["name"] as? String) == name && ($0["type"] as? Int) == type })?["id"]
                        as? String
                }
                let category: String
                if let found = existing("kimi", 4) {
                    category = found
                } else {
                    category = try await rest.createChannel(guild: guild, name: "kimi", type: 4)
                }
                let ticket: String
                if let found = existing("ticket", 4) {
                    ticket = found
                } else {
                    ticket = try await rest.createChannel(guild: guild, name: "ticket", type: 4)
                }
                let logs: String
                if let found = existing("kimi-logs", 0) {
                    logs = found
                } else {
                    logs = try await rest.createPrivateTextChannel(guild, "kimi-logs", owner, bot, category)
                }
                let confirmations: String
                if let found = existing("kimi-confirmation", 0) {
                    confirmations = found
                } else {
                    confirmations = try await rest.createPrivateTextChannel(
                        guild, "kimi-confirmation", owner, bot, category)
                }
                for privateChannel in [logs, confirmations] {
                    _ = try await rest.call(
                        "PUT", "channels/" + privateChannel + "/permissions/" + guild,
                        body: ["type": 0, "deny": "1024", "allow": "0"])
                    _ = try await rest.call(
                        "PUT", "channels/" + privateChannel + "/permissions/" + owner,
                        body: ["type": 1, "allow": "68608", "deny": "0"])
                    _ = try await rest.call(
                        "PUT", "channels/" + privateChannel + "/permissions/" + bot,
                        body: ["type": 1, "allow": "68608", "deny": "0"])
                }
                try await store.set(logs, key: "foundation.logs." + guild)
                try await store.set(confirmations, key: "foundation.confirmations." + guild)
                var policy = await ModerationEngine(store: store).policy(guildID: guild)
                policy.logChannelID = logs
                try await ModerationEngine(store: store).configure(policy, guildID: guild)
                reply =
                    "Foundation setup complete.\nPrivate logs: <#" + logs + ">\nPrivate confirmations: <#"
                    + confirmations + ">\nSupport category: <#" + ticket + ">"
            case "plan":
                let stored = await store.get("apps.installed", as: [String: [String]].self) ?? [:]
                let bytes = (try? JSONEncoder().encode(stored).count) ?? 0
                reply =
                    "Kimi Free\nAll built-in apps are free.\nConfiguration footprint: " + StorageQuota.format(bytes)
                    + "\nStorage allowance: " + StorageQuota.format(StorageQuota.freeLimit)
            case "welcome", "configure-welcome", "configure-foundation":
                let engine = FoundationEngine(store: store, rest: rest, logger: logger)
                var settings = await engine.settings(guildID: guild)
                if let x = value("welcome-channel") { settings.welcomeChannel = x }
                if let x = value("goodbye-channel") { settings.goodbyeChannel = x }
                if let x = value("welcome-message") { settings.welcomeMessage = String(x.prefix(1800)) }
                if let x = value("goodbye-message") { settings.goodbyeMessage = String(x.prefix(1800)) }
                try await engine.configure(guildID: guild, settings)
                reply = "Welcome and goodbye settings saved."
            case "autorole", "configure-auto-role":
                let engine = FoundationEngine(store: store, rest: rest, logger: logger)
                var settings = await engine.settings(guildID: guild)
                settings.autoRole = value("role")
                try await engine.configure(guildID: guild, settings)
                reply = settings.autoRole == nil ? "Automatic role assignment disabled." : "Automatic role saved."
            case "moderation", "configure-kimi-lock":
                let engine = ModerationEngine(store: store)
                var policy = await engine.policy(guildID: guild)
                if let enabled = options.first(where: { ($0["name"] as? String) == "enabled" })?["value"] as? Bool {
                    policy.enabled = enabled
                }
                if let sanction = value("sanction") { policy.sanction = sanction }
                if let duration = options.first(where: { ($0["name"] as? String) == "timeout-minutes" })?["value"]
                    as? Int
                {
                    policy.timeoutMinutes = duration
                }
                if let limit = options.first(where: { ($0["name"] as? String) == "messages-per-minute" })?["value"]
                    as? Int
                {
                    policy.messagesPerMinute = limit
                }
                if let invites = options.first(where: { ($0["name"] as? String) == "block-invites" })?["value"] as? Bool
                {
                    policy.blockInvites = invites
                }
                if let mentions = options.first(where: { ($0["name"] as? String) == "block-mentions" })?["value"]
                    as? Bool
                {
                    policy.blockMassMentions = mentions
                }
                if let caps = options.first(where: { ($0["name"] as? String) == "block-caps" })?["value"] as? Bool {
                    policy.blockExcessiveCaps = caps
                }
                if let channel = value("log-channel") { policy.logChannelID = channel }
                try await engine.configure(policy, guildID: guild)
                reply =
                    "Kimi Lock · AutoMod\nStatus: " + (policy.enabled ? "Enabled" : "Disabled") + "\nSanction: "
                    + policy.sanction + "\nMessages/minute: " + String(policy.messagesPerMinute) + "\nTimeout: "
                    + String(policy.timeoutMinutes) + " minutes\nBlocked phrases: "
                    + String(policy.blockedPhrases.count) + "\nInvite blocking: " + (policy.blockInvites ? "On" : "Off")
                    + "\nMass mention blocking: " + (policy.blockMassMentions ? "On" : "Off") + "\nExcessive caps: "
                    + (policy.blockExcessiveCaps ? "On" : "Off")
            case "filter":
                let engine = ModerationEngine(store: store)
                var policy = await engine.policy(guildID: guild)
                let sub = options.first?["name"] as? String ?? "list"
                let phrase = value("phrase") ?? ""
                if sub == "add" {
                    guard !phrase.isEmpty else { throw KimiError.configuration("Enter a phrase.") }
                    if !policy.blockedPhrases.contains(where: {
                        $0.caseInsensitiveCompare(phrase) == ComparisonResult.orderedSame
                    }) {
                        policy.blockedPhrases.append(String(phrase.prefix(100)))
                    }
                    try await engine.configure(policy, guildID: guild)
                    reply = "Blocked phrase added."
                } else if sub == "remove" {
                    policy.blockedPhrases.removeAll {
                        $0.caseInsensitiveCompare(phrase) == ComparisonResult.orderedSame
                    }
                    try await engine.configure(policy, guildID: guild)
                    reply = "Blocked phrase removed."
                } else {
                    reply =
                        policy.blockedPhrases.isEmpty
                        ? "No blocked phrases configured."
                        : "Blocked phrases\n" + policy.blockedPhrases.joined(separator: "\n")
                }
            case "security":
                let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
                let everyone = roles.first(where: { ($0["id"] as? String) == guild })
                let permissions = UInt64(everyone?["permissions"] as? String ?? "") ?? 0
                let findings = ServerAudit().evaluate(roles: roles, everyonePermissions: permissions)
                reply =
                    findings.isEmpty
                    ? "Kimi Lock security audit: no obvious elevated-role risks found."
                    : findings.map { $0.severity.uppercased() + " — " + $0.title + ": " + $0.detail }.joined(
                        separator: "\n")
            case "tickets", "ticket-panel", "ticket-config", "configure-support":
                let service = SupportService(store: store, rest: rest, logger: logger)
                if name == "tickets" {
                    let category = try await service.ensureCategory(guild)
                    reply = "Support category ready: <#" + category + ">"
                } else if name == "ticket-panel" {
                    guard let channel = event["channel_id"] as? String else {
                        throw KimiError.configuration("Run this command in a text channel.")
                    }
                    try await service.publishPanel(guild: guild, channel: channel)
                    reply = "Support panel published in <#" + channel + ">."
                } else {
                    var settings = await service.settings(guild)
                    if let role = value("support-role") { settings.supportRoleID = role }
                    if let channel = value("transcript-channel") { settings.transcriptChannelID = channel }
                    try await service.configure(settings, guild: guild)
                    reply = "Support settings saved."
                }
            case "automations":
                let owner = try await rest.ownerID(guild)
                guard owner == user else {
                    throw KimiError.configuration("Only the server owner can manage automations.")
                }
                let engine = AutomationEngine(store: store, rest: rest, logger: logger)
                let sub = options.first?["name"] as? String ?? "list"
                if sub == "create" {
                    guard let ruleName = value("name"), let trigger = value("trigger"), let action = value("action")
                    else { throw KimiError.configuration("Provide a name, trigger and action.") }
                    let rule = try await engine.add(
                        guildID: guild, name: ruleName, trigger: trigger, action: action, condition: value("condition"))
                    reply = "Automation created: " + rule.name + " (" + rule.id + ")."
                } else if sub == "remove" {
                    guard let ruleID = value("id"), try await engine.remove(id: ruleID, guildID: guild) else {
                        throw KimiError.configuration("Automation rule not found.")
                    }
                    reply = "Automation removed."
                } else if sub == "toggle" {
                    guard let ruleID = value("id"),
                        let enabled = options.first(where: { ($0["name"] as? String) == "enabled" })?["value"] as? Bool,
                        try await engine.setEnabled(enabled, id: ruleID, guildID: guild)
                    else { throw KimiError.configuration("Automation rule not found or invalid enabled value.") }
                    reply = enabled ? "Automation enabled." : "Automation disabled."
                } else {
                    let rules = await engine.rules(guildID: guild)
                    if rules.isEmpty {
                        reply = "No automation rules configured. Use /automations create to add one."
                    } else {
                        let rows = rules.map { rule in
                            rule.name + " · " + rule.trigger + " → " + rule.action + " · "
                                + (rule.enabled ? "Enabled" : "Disabled") + " · " + rule.id
                        }
                        reply = rows.joined(separator: "\n")
                    }
                }
            case "verify", "verify-config":
                let service = VerificationService(store: store, rest: rest, logger: logger)
                var settings = await service.settings(guild)
                if let role = value("role") { settings.roleID = role }
                if let requiredRole = value("required-role") { settings.requiredRoleID = requiredRole }
                if let channel = value("channel") { settings.channelID = channel }
                if let review = value("review-channel") { settings.reviewChannelID = review }
                if let age = options.first(where: { ($0["name"] as? String) == "min-age-days" })?["value"] as? Int {
                    settings.minimumAgeDays = age
                }
                try await service.configure(settings, guild: guild)
                reply =
                    "Kimi Lock verification settings saved. Minimum account age: " + String(settings.minimumAgeDays)
                    + " days. Review channel: " + (settings.reviewChannelID ?? "not configured")
            case "roles", "configure-roles":
                guard let channel = value("channel") ?? (event["channel_id"] as? String) else {
                    throw KimiError.configuration("Choose a text channel for this role menu.")
                }
                let menuName = value("name") ?? "roles"
                let count = try await RolePickerService(store: store, rest: rest, logger: logger).publish(
                    guild: guild, channel: channel, name: menuName)
                reply =
                    "Role Picker menu " + menuName + " published with " + String(count) + " safe roles in <#" + channel
                    + ">."
            case "embed-new", "embed-edit", "embed-post", "configure-embeds":
                let service = EmbedService(store: store, rest: rest)
                guard let embedName = value("name") else { throw KimiError.configuration("Enter an embed name.") }
                if name == "embed-post" {
                    guard let channel = event["channel_id"] as? String else {
                        throw KimiError.configuration("Run this command in a text channel.")
                    }
                    try await service.publish(guild: guild, name: embedName, channel: channel)
                    reply = "Embed published."
                } else {
                    let existing = await service.all(guild: guild).first(where: {
                        $0.name.caseInsensitiveCompare(embedName) == ComparisonResult.orderedSame
                    })
                    let title = value("title") ?? existing?.title ?? ""
                    let description = value("description") ?? existing?.description ?? ""
                    var fields = existing?.fields ?? []
                    let fieldName = value("field-name")
                    let fieldValue = value("field-value")
                    if fieldName != nil || fieldValue != nil {
                        guard let fieldName, !fieldName.isEmpty, let fieldValue, !fieldValue.isEmpty else {
                            throw KimiError.configuration("Provide both a field name and field value.")
                        }
                        let inline =
                            options.first(where: { ($0["name"] as? String) == "field-inline" })?["value"] as? Bool
                            ?? false
                        fields.append(EmbedService.Field(name: fieldName, value: fieldValue, inline: inline))
                    }
                    if let remove = options.first(where: { ($0["name"] as? String) == "remove-field" })?["value"]
                        as? Int
                    {
                        guard remove >= 1, remove <= fields.count else {
                            throw KimiError.configuration("Field number is outside the current field list.")
                        }
                        fields.remove(at: remove - 1)
                    }
                    let saved = try await service.save(
                        guild: guild, name: embedName, title: title, description: description,
                        color: options.first(where: { ($0["name"] as? String) == "color" })?["value"] as? Int
                            ?? existing?.color ?? 8_421_504, footer: value("footer") ?? existing?.footer,
                        author: value("author"), thumbnailURL: value("thumbnail"), imageURL: value("image"),
                        url: value("url"), fields: fields)
                    reply = "Embed **" + saved.name + "** saved."
                }
            case "guard-review":
                guard let target = value("bot"), let decision = value("decision") else {
                    throw KimiError.configuration("Choose an account and decision.")
                }
                reply = try await KimiGuardService(store: store, rest: rest, logger: logger).review(
                    guild: guild, actor: target, decision: decision, reviewer: user)
            case "web-token":
                let owner = try await rest.ownerID(guild)
                guard owner == user else {
                    throw KimiError.configuration("Only the server owner can open the dashboard link.")
                }
                guard let dashboardURL else {
                    throw KimiError.configuration("Configure DISCORD_OAUTH_REDIRECT_URI to enable the dashboard.")
                }
                reply =
                    "Open the Kimi dashboard and sign in with Discord: " + dashboardURL
                    + "/login. No email verification is used."
            case "analytics":
                let report = await AnalyticsService(store: store).report(guild: guild)
                reply =
                    "Activity report\nMessages: " + String(report.messages) + "\nCommands: " + String(report.commands)
                    + "\nJoins: " + String(report.joins) + "\nLeaves: " + String(report.leaves) + "\nModeration: "
                    + String(report.moderation) + "\nTickets opened: " + String(report.ticketsOpened)
                    + "\nTickets closed: " + String(report.ticketsClosed) + "\nActive days: "
                    + String(report.activeDays)
            case "performance":
                let samples = await performance.recent(limit: 2000)
                let commandSamples = samples.filter { $0.subsystem != "gateway" && !$0.subsystem.isEmpty }
                let count = commandSamples.count
                let ordered = commandSamples.map { $0.milliseconds }.sorted()
                let average = count == 0 ? 0 : ordered.reduce(0, +) / Double(count)
                let p95 = count == 0 ? 0 : ordered[min(count - 1, Int(Double(count - 1) * 0.95))]
                let failures = commandSamples.filter { !$0.success }.count
                reply =
                    "Kimi runtime performance\\nSamples: " + String(count) + "\\nAverage command latency: "
                    + String(format: "%.1f", average) + " ms\\nP95 latency: " + String(format: "%.1f", p95)
                    + " ms\\nFailed commands: " + String(failures)
                    + "\\nGateway and command processing continue independently."
            default:
                throw KimiError.configuration(
                    "Unknown Kimi command: " + name + ". Update Kimi and re-register its commands.")
            }
        } catch {
            reply = "Kimi could not complete the action: " + error.localizedDescription
            await logger.log("ERROR", "Command " + name + " failed: " + error.localizedDescription)
        }
        do {
            if responseComponents.isEmpty {
                try await rest.editKimiInteraction(app, token, reply)
            } else {
                try await rest.editKimiInteraction(app, token, reply, responseComponents)
            }
        } catch { await logger.log("ERROR", "Interaction response update failed: " + error.localizedDescription) }
        await AnalyticsService(store: store).record(guild: guild, event: "command")
        await performance.record(
            name, duration: Date().timeIntervalSince(started), success: !reply.hasPrefix("Kimi could not"))
        return true
    }
}
