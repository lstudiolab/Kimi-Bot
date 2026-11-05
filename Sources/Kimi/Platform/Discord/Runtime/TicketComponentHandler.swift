import Foundation

extension KimiRuntime {
    func handleTicketComponent(
        _ custom: String, applicationID: String, token: String, guildID guild: String,
        channelID channel: String, actorID: String, username: String, member: [String: Any]
    ) async throws {
        switch custom {
        case "ticket:open":
            let service = SupportService(store: store, rest: rest, logger: logger)
            let settings = await service.settings(guild)
            guard settings.panelChannelID == channel else {
                throw KimiError.configuration("This ticket panel is no longer active.")
            }
            let me = try await rest.call("GET", "users/@me")
            guard let bot = (me as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
            let ticket = try await service.open(guild: guild, user: actorID, username: username, bot: bot)
            await AnalyticsService(store: store).record(guild: guild, event: "ticket_open")
            try await editThemedInteraction(
                applicationID, token, "Your private ticket is ready: <#" + ticket.channelID + ">",
                guildID: guild)

        case let value where value.hasPrefix("ticket:priority:"):
            let parts = String(custom.dropFirst("ticket:priority:".count)).split(separator: ":").map(String.init)
            guard parts.count == 2 else { throw KimiError.configuration("This priority control is invalid.") }
            let ticketID = parts[0]
            let tickets = await SupportTickets(store: store).all()
            guard let ticket = tickets.first(where: {
                $0.id == ticketID && $0.guildID == guild && $0.channelID == channel && $0.isOpen
            }) else { throw KimiError.configuration("This ticket is no longer open.") }
            let owner = try await rest.ownerID(guild)
            let service = SupportService(store: store, rest: rest, logger: logger)
            let settings = await service.settings(guild)
            let roles = Set(member["roles"] as? [String] ?? [])
            let isStaff = settings.supportRoleID.map { roles.contains($0) } ?? false
            guard ticket.userID == actorID || owner == actorID || isStaff else {
                throw KimiError.configuration(
                    "Only the ticket opener, support staff or server owner can change priority.")
            }
            let updated = try await service.setPriority(guild: guild, ticketID: ticketID, priority: parts[1])
            try await editThemedInteraction(
                applicationID, token, "Ticket priority changed to " + updated.priority + ".", guildID: guild)

        case let value where value.hasPrefix("ticket:close:"):
            let ticketID = String(custom.dropFirst("ticket:close:".count))
            try await authorizeTicketClose(ticketID, guild: guild, channel: channel, actorID: actorID, member: member)
            let appearance = await KimiAppearance.load(store: store, guildID: guild)
            let controls = [KimiUI.row([
                KimiUI.button(id: "ticket:confirm-close:" + ticketID, label: "Yes, close it"),
                KimiUI.button(id: "ticket:cancel-close", label: "Cancel"),
            ])]
            _ = try await rest.call(
                "PATCH", "webhooks/\(applicationID)/\(token)/messages/@original",
                body: [
                    "embeds": [KimiUI.embed(
                        title: "Close support ticket", description: "Are you sure you want to close this ticket?",
                        color: appearance.embedColor)],
                    "content": NSNull(),
                    "components": KimiUI.themedComponents(controls, buttonStyle: appearance.buttonStyle),
                    "allowed_mentions": ["parse": []],
                ])

        case let value where value.hasPrefix("ticket:confirm-close:"):
            let ticketID = String(custom.dropFirst("ticket:confirm-close:".count))
            try await authorizeTicketClose(ticketID, guild: guild, channel: channel, actorID: actorID, member: member)
            let service = SupportService(store: store, rest: rest, logger: logger)
            let closed = try await service.close(guild: guild, ticketID: ticketID)
            await AnalyticsService(store: store).record(guild: guild, event: "ticket_close")
            let retained = await store.get("support.transcript." + guild + "." + ticketID, as: String.self) != nil
            let status = retained
                ? "Transcript retained in Kimi storage."
                : "The ticket was closed, but local transcript retention failed."
            try await editThemedInteraction(
                applicationID, token,
                "Ticket closed. " + status + " Channel: <#" + closed.channelID + ">", guildID: guild)

        case "ticket:cancel-close":
            try await editThemedInteraction(applicationID, token, "Ticket remains open.", guildID: guild)

        default:
            throw KimiError.configuration("This ticket control is unknown or expired.")
        }
    }

    private func authorizeTicketClose(
        _ ticketID: String, guild: String, channel: String, actorID: String, member: [String: Any]
    ) async throws {
        let tickets = await SupportTickets(store: store).all()
        guard let ticket = tickets.first(where: {
            $0.id == ticketID && $0.guildID == guild && $0.channelID == channel && $0.isOpen
        }) else { throw KimiError.configuration("This ticket control is no longer valid.") }
        let owner = try await rest.ownerID(guild)
        let settings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
        let roles = Set(member["roles"] as? [String] ?? [])
        let isStaff = settings.supportRoleID.map { roles.contains($0) } ?? false
        guard ticket.userID == actorID || owner == actorID || isStaff else {
            throw KimiError.configuration(
                "Only the ticket opener, support staff or server owner can close this ticket.")
        }
    }
}
