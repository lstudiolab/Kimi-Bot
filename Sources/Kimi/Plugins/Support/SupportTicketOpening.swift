import Foundation

extension SupportService {
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
            let ticket: SupportTickets.Ticket
            do {
                ticket = try await SupportTickets(store: store).open(guildID: guild, userID: user, channelID: channel)
            } catch {
                _ = try? await rest.call("DELETE", "channels/" + channel)
                throw error
            }
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
                                "type": 2, "style": 2, "label": "High",
                                "custom_id": "ticket:priority:" + ticket.id + ":high",
                            ],
                            [
                                "type": 2, "style": 2, "label": "Urgent",
                                "custom_id": "ticket:priority:" + ticket.id + ":urgent",
                            ],
                            ["type": 2, "style": 2, "label": "Close", "custom_id": "ticket:close:" + ticket.id],
                        ],
                    ]
                ] as [[String: Any]]
            do {
                _ = try await rest.call(
                    "POST", "channels/\(channel)/messages",
                    body: KimiUI.panel(title: "Support ticket", description: "Opened for <@\(user)>. A staff member will respond here.\nPriority: normal", components: controls).merging(["allowed_mentions": ["users": [user], "parse": []]]) { _, new in new })
            } catch {
                var recordClosed = false
                do {
                    _ = try await SupportTickets(store: store).close(id: ticket.id, guildID: guild)
                    recordClosed = true
                } catch {
                    await logger.log("ERROR", "Failed to roll back the ticket record: " + error.localizedDescription)
                }
                if recordClosed {
                    do {
                        _ = try await rest.call("DELETE", "channels/" + channel)
                    } catch {
                        await logger.log("ERROR", "Failed to remove an incomplete ticket channel: " + error.localizedDescription)
                    }
                } else {
                    await logger.log(
                        "ERROR",
                        "The incomplete ticket channel was retained because its active record could not be rolled back: "
                            + channel)
                }
                throw KimiError.configuration(
                    recordClosed
                        ? "The ticket channel was created, but its opening message could not be sent. The incomplete ticket was rolled back."
                        : "The ticket channel was created, but its opening message failed and its record could not be rolled back. Staff should inspect the retained channel.")
            }
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
                    body: KimiUI.panel(title: "Staff handoff", description: staffNotice + "Ticket " + ticket.id + ". Coordinate the response here; the ticket channel remains visible to its opener and support staff.").merging(["allowed_mentions": ["roles": value.supportRoleID.map { [$0] } ?? [], "parse": []]]) { _, new in new })
            } else {
                await logger.log(
                    "WARN",
                    "Ticket " + ticket.id
                        + " opened without a staff handoff thread; check Create Public Threads permission.")
            }
            await logger.log("INFO", "Support ticket opened: " + ticket.id + " in guild " + guild)
            return ticket
        }
}
