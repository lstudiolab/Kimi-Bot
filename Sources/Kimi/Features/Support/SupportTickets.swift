import Foundation

actor SupportTickets {
    struct Ticket: Codable, Sendable, Identifiable {
        let id: String
        let guildID: String
        let userID: String
        let channelID: String
        let openedAt: Date
        var closedAt: Date?
        var priority: String
        var staffThreadID: String?
        var isOpen: Bool { closedAt == nil }
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func all() async -> [Ticket] { await store.get("support.tickets", as: [Ticket].self) ?? [] }

    func open(guildID: String, userID: String, channelID: String) async throws -> Ticket {
        let ticket = Ticket(
            id: UUID().uuidString, guildID: guildID, userID: userID, channelID: channelID, openedAt: Date(),
            closedAt: nil, priority: "normal", staffThreadID: nil)
        _ = try await store.update("support.tickets", as: [Ticket].self) { stored in
            var tickets = stored ?? []
            guard !tickets.contains(where: { $0.guildID == guildID && $0.userID == userID && $0.isOpen }) else {
                throw TicketError.alreadyOpen
            }
            tickets.append(ticket)
            return tickets
        }
        return ticket
    }

    func setStaffThread(id: String, guildID: String, threadID: String) async throws -> Ticket {
        let tickets = try await store.update("support.tickets", as: [Ticket].self) { stored in
            var values = stored ?? []
            guard let index = values.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
                throw TicketError.notFound
            }
            values[index].staffThreadID = threadID
            return values
        }
        guard let ticket = tickets.first(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        return ticket
    }

    func setPriority(id: String, guildID: String, priority: String) async throws -> Ticket {
        guard ["low", "normal", "high", "urgent"].contains(priority) else {
            throw KimiError.configuration("Choose low, normal, high or urgent priority.")
        }
        let tickets = try await store.update("support.tickets", as: [Ticket].self) { stored in
            var values = stored ?? []
            guard let index = values.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
                throw TicketError.notFound
            }
            guard values[index].isOpen else { throw TicketError.alreadyClosed }
            values[index].priority = priority
            return values
        }
        guard let ticket = tickets.first(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        return ticket
    }

    func close(id: String, guildID: String) async throws -> Ticket {
        let tickets = try await store.update("support.tickets", as: [Ticket].self) { stored in
            var values = stored ?? []
            guard let index = values.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
                throw TicketError.notFound
            }
            guard values[index].isOpen else { throw TicketError.alreadyClosed }
            values[index].closedAt = Date()
            return values
        }
        guard let ticket = tickets.first(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        return ticket
    }
}
enum TicketError: Error { case alreadyOpen, notFound, alreadyClosed }
