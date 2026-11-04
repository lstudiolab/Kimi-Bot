import Foundation

actor SupportService {
    struct Settings: Codable, Sendable {
        var categoryID: String?
        var supportRoleID: String?
        var transcriptChannelID: String?
        var panelChannelID: String?
        var panelTitle: String = "Contact Support"
        var panelDescription: String = "Open a private ticket with the support team."
    }
    private let store: PersistentStore
    private let rest: DiscordREST
    private let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func settings(_ guild: String) async -> Settings {
        await store.get("support.settings." + guild, as: Settings.self) ?? Settings()
    }
    func configure(_ value: Settings, guild: String) async throws {
        try await store.set(value, key: "support.settings." + guild)
    }
    func ensureCategory(_ guild: String) async throws -> String {
        let current = await settings(guild)
        if let id = current.categoryID { return id }
        let channels = try await rest.call("GET", "guilds/\(guild)/channels") as? [[String: Any]] ?? []
        if let found = channels.first(where: {
            ($0["type"] as? Int) == 4 && ($0["name"] as? String)?.lowercased() == "ticket"
        }), let id = found["id"] as? String {
            var next = current
            next.categoryID = id
            try await configure(next, guild: guild)
            return id
        }
        let created = try await rest.call("POST", "guilds/\(guild)/channels", body: ["name": "ticket", "type": 4])
        guard let id = (created as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
        var next = current
        next.categoryID = id
        try await configure(next, guild: guild)
        return id
    }
    func publishPanel(guild: String, channel: String) async throws {
        let value = await settings(guild)
        let components =
            [["type": 1, "components": [["type": 2, "style": 1, "label": "Open Ticket", "custom_id": "ticket:open"]]]]
            as [[String: Any]]
        _ = try await rest.call(
            "POST", "channels/\(channel)/messages",
            body: [
                "content": "**\(value.panelTitle)**\n\(value.panelDescription)", "components": components,
                "allowed_mentions": ["parse": []],
            ])
        var next = value
        next.panelChannelID = channel
        try await configure(next, guild: guild)
    }
    func open(guild: String, user: String, username: String, bot: String) async throws -> SupportTickets.Ticket {
        let existing = await SupportTickets(store: store).all()
        guard !existing.contains(where: { $0.guildID == guild && $0.userID == user && $0.isOpen }) else {
            throw TicketError.alreadyOpen
        }
        let openCount = existing.filter { $0.guildID == guild && $0.isOpen }.count
        guard openCount < 100 else {
            throw KimiError.configuration("The support queue is full. Please contact staff through the configured support channel.")
        }
        let cooldownKey = "support.ticket-cooldowns." + guild
        guard try await store.claimGuildCooldown(cooldownKey, subject: user, guildID: guild, interval: 60) else {
            throw KimiError.configuration("Please wait before opening another support ticket.")
        }
        let category = try await ensureCategory(guild)
        let value = await settings(guild)
        var overwrites: [[String: Any]] = [
            ["id": guild, "type": 0, "deny": "1024"], ["id": user, "type": 1, "allow": "68608"],
            ["id": bot, "type": 1, "allow": "68608"],
        ]
        if let role = value.supportRoleID { overwrites.append(["id": role, "type": 0, "allow": "68608"]) }
        let name = SecurityPolicy.channelName("ticket-" + username)
        let created = try await rest.call(
            "POST", "guilds/\(guild)/channels",
            body: ["name": name, "type": 0, "parent_id": category, "permission_overwrites": overwrites])
        guard let channel = (created as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
        let ticket = try await SupportTickets(store: store).open(guildID: guild, userID: user, channelID: channel)
        let controls =
            [
                [
                    "type": 1,
                    "components": [
                        ["type": 2, "style": 2, "label": "Low", "custom_id": "ticket:priority:" + ticket.id + ":low"],
                        [
                            "type": 2, "style": 2, "label": "Normal",
                            "custom_id": "ticket:priority:" + ticket.id + ":normal",
                        ],
                        [
                            "type": 2, "style": 1, "label": "High",
                            "custom_id": "ticket:priority:" + ticket.id + ":high",
                        ],
                        [
                            "type": 2, "style": 4, "label": "Urgent",
                            "custom_id": "ticket:priority:" + ticket.id + ":urgent",
                        ],
                        ["type": 2, "style": 4, "label": "Close", "custom_id": "ticket:close:" + ticket.id],
                    ],
                ]
            ] as [[String: Any]]
        _ = try await rest.call(
            "POST", "channels/\(channel)/messages",
            body: [
                "content": "Support ticket opened for <@\(user)>. A staff member will respond here.\nPriority: normal",
                "components": controls, "allowed_mentions": ["users": [user], "parse": []],
            ])
        if let threadResponse = try? await rest.call(
            "POST", "channels/" + channel + "/threads",
            body: ["name": "staff-handoff", "type": 11, "auto_archive_duration": 1440]),
            let threadID = (threadResponse as? [String: Any])?["id"] as? String
        {
            _ = try? await SupportTickets(store: store).setStaffThread(
                id: ticket.id, guildID: guild, threadID: threadID)
            let staffNotice = value.supportRoleID.map { "<@&" + $0 + "> " } ?? ""
            _ = try? await rest.call(
                "POST", "channels/" + threadID + "/messages",
                body: [
                    "content": staffNotice + "Staff handoff for ticket " + ticket.id
                        + ". Coordinate the response here; the ticket channel remains visible to its opener and support staff.",
                    "allowed_mentions": ["roles": value.supportRoleID.map { [$0] } ?? [], "parse": []],
                ])
        } else {
            await logger.log(
                "WARN",
                "Ticket " + ticket.id
                    + " opened without a staff handoff thread; check Create Public Threads permission.")
        }
        await logger.log("INFO", "Support ticket opened: " + ticket.id + " in guild " + guild)
        return ticket
    }
    func setPriority(guild: String, ticketID: String, priority: String) async throws -> SupportTickets.Ticket {
        let ticket = try await SupportTickets(store: store).setPriority(
            id: ticketID, guildID: guild, priority: priority)
        _ = try await rest.call(
            "PATCH", "channels/\(ticket.channelID)",
            body: ["name": SecurityPolicy.channelName(priority + "-ticket-" + String(ticket.id.prefix(8)))])
        return ticket
    }
    func close(guild: String, ticketID: String) async throws -> SupportTickets.Ticket {
        let ticket = try await SupportTickets(store: store).close(id: ticketID, guildID: guild)
        _ = try await rest.call(
            "PATCH", "channels/\(ticket.channelID)",
            body: ["name": SecurityPolicy.channelName("closed-" + String(ticket.id.prefix(8)))])
        if let thread = ticket.staffThreadID {
            _ = try? await rest.call("PATCH", "channels/" + thread, body: ["archived": true, "locked": true])
        }
        _ = try? await rest.call(
            "PUT", "channels/\(ticket.channelID)/permissions/\(ticket.userID)",
            body: ["type": 1, "deny": "1024", "allow": "0"])
        var history: [[String: Any]] = []
        var before: String? = nil
        for _ in 0..<10 {
            let suffix = before.map { "&before=" + $0 } ?? ""
            let page =
                try await rest.call("GET", "channels/\(ticket.channelID)/messages?limit=100" + suffix)
                as? [[String: Any]] ?? []
            if page.isEmpty { break }
            history.append(contentsOf: page)
            before = page.last?["id"] as? String
            if page.count < 100 { break }
        }
        let transcript = history.reversed().map { item -> String in
            let author = (item["author"] as? [String: Any])?["username"] as? String ?? "Unknown"
            let body = item["content"] as? String ?? ""
            let files = (item["attachments"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String }.joined(
                separator: " ")
            return author + ": " + body + (files.isEmpty ? "" : " [attachments: " + files + "]")
        }.joined(separator: "\n")
        try await store.set(String(transcript.suffix(100_000)), key: "support.transcript." + ticketID)
        let settings = await self.settings(guild)
        if let destination = settings.transcriptChannelID {
            let summary =
                "Ticket transcript for " + ticketID + ". Messages captured: " + String(history.count)
                + ". Full transcript is retained in local Kimi storage; exported text is capped to 18,000 characters."
            _ = try? await rest.call(
                "POST", "channels/\(destination)/messages",
                body: ["content": summary, "allowed_mentions": ["parse": []]])
            let exported = String(transcript.suffix(18_000))
            var cursor = exported.startIndex
            var part = 1
            while cursor < exported.endIndex {
                let next = exported.index(cursor, offsetBy: 1750, limitedBy: exported.endIndex) ?? exported.endIndex
                let chunk = String(exported[cursor..<next])
                _ = try? await rest.call(
                    "POST", "channels/\(destination)/messages",
                    body: [
                        "content": "Transcript part " + String(part) + "\n" + chunk, "allowed_mentions": ["parse": []],
                    ])
                cursor = next
                part += 1
            }
        }
        await logger.log(
            "INFO", "Support ticket closed: " + ticketID + "; archived " + String(history.count) + " messages.")
        return ticket
    }
}
