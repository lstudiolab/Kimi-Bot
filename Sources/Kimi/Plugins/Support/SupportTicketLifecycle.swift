import Foundation

extension SupportService {
        func setPriority(guild: String, ticketID: String, priority: String) async throws -> SupportTickets.Ticket {
            let tickets = SupportTickets(store: store)
            guard let previous = await tickets.all().first(where: { $0.id == ticketID && $0.guildID == guild }) else {
                throw TicketError.notFound
            }
            guard previous.isOpen else { throw TicketError.alreadyClosed }
            let updated = try await tickets.setPriority(id: ticketID, guildID: guild, priority: priority)
            do {
                _ = try await rest.call(
                    "PATCH", "channels/\(updated.channelID)",
                    body: ["name": SecurityPolicy.channelName(priority + "-ticket-" + String(updated.id.prefix(8)))])
                return updated
            } catch {
                do {
                    _ = try await tickets.setPriority(id: ticketID, guildID: guild, priority: previous.priority)
                } catch {
                    await logger.log("ERROR", "Ticket priority rollback failed: " + error.localizedDescription)
                }
                throw error
            }
        }

        func close(guild: String, ticketID: String) async throws -> SupportTickets.Ticket {
            let tickets = SupportTickets(store: store)
            guard let ticket = await tickets.all().first(where: { $0.id == ticketID && $0.guildID == guild }) else {
                throw TicketError.notFound
            }
            guard ticket.isOpen else { throw TicketError.alreadyClosed }
    
            var history: [[String: Any]] = []
            var before: String? = nil
            for _ in 0..<10 {
                let suffix = before.map { "&before=" + $0 } ?? ""
                let page = try await rest.call(
                    "GET", "channels/\(ticket.channelID)/messages?limit=100" + suffix) as? [[String: Any]] ?? []
                if page.isEmpty { break }
                history.append(contentsOf: page)
                before = page.last?["id"] as? String
                if page.count < 100 { break }
            }
    
            let transcript = history.reversed().map { item -> String in
                let author = (item["author"] as? [String: Any])?["username"] as? String ?? "Unknown"
                let body = item["content"] as? String ?? ""
                let files = (item["attachments"] as? [[String: Any]] ?? [])
                    .compactMap { $0["url"] as? String }.joined(separator: " ")
                return author + ": " + body + (files.isEmpty ? "" : " [attachments: " + files + "]")
            }.joined(separator: "\n")
            var transcriptSaved = false
            do {
                try await store.setGuild(
                    String(transcript.suffix(100_000)),
                    key: "support.transcript." + guild + "." + ticketID, guildID: guild)
                transcriptSaved = true
            } catch {
                await logger.log("WARN", "Ticket transcript could not be retained locally: " + error.localizedDescription)
            }
    
            _ = try await rest.call(
                "PATCH", "channels/\(ticket.channelID)",
                body: ["name": SecurityPolicy.channelName("closed-" + String(ticket.id.prefix(8)))])
            _ = try await rest.call(
                "PUT", "channels/\(ticket.channelID)/permissions/\(ticket.userID)",
                body: ["type": 1, "deny": "1024", "allow": "0"])
            if let thread = ticket.staffThreadID {
                do {
                    _ = try await rest.call("PATCH", "channels/" + thread, body: ["archived": true, "locked": true])
                } catch {
                    await logger.log("WARN", "Ticket closed but staff thread archival failed: " + error.localizedDescription)
                }
            }
    
            let closed = try await tickets.close(id: ticketID, guildID: guild)
            let settings = await self.settings(guild)
            if let destination = settings.transcriptChannelID {
                let retention = transcriptSaved
                    ? "The full transcript is retained in local Kimi storage."
                    : "Local transcript retention failed; only the Discord export may be available."
                let summary = "Ticket transcript for " + ticketID + ". Messages captured: " + String(history.count)
                    + ". " + retention + " Exported text is capped to 18,000 characters."
                do {
                    _ = try await rest.call(
                        "POST", "channels/\(destination)/messages",
                        body: KimiUI.message("Ticket transcript\n" + summary))
                    let exported = String(transcript.suffix(18_000))
                    var chunks: [String] = []
                    var current = ""
                    var utf16Count = 0
                    for scalar in exported.unicodeScalars {
                        let width = scalar.value > 0xFFFF ? 2 : 1
                        if utf16Count + width > 1700 {
                            chunks.append(current)
                            current = ""
                            utf16Count = 0
                        }
                        current.unicodeScalars.append(scalar)
                        utf16Count += width
                    }
                    if !current.isEmpty { chunks.append(current) }
                    for (index, chunk) in chunks.enumerated() {
                        _ = try await rest.call(
                            "POST", "channels/\(destination)/messages",
                            body: [
                                "embeds": [KimiUI.embed(title: "Transcript · part " + String(index + 1), description: chunk)],
                                "allowed_mentions": ["parse": []],
                            ])
                    }
                } catch {
                    await logger.log("ERROR", "Ticket closed, but transcript export failed: " + error.localizedDescription)
                }
            }
            await logger.log(
                "INFO", "Support ticket closed: " + ticketID + "; archived " + String(history.count) + " messages.")
            return closed
        }
}
