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
        var tickets = await all()
        guard !tickets.contains(where: { $0.guildID == guildID && $0.userID == userID && $0.isOpen }) else {
            throw TicketError.alreadyOpen
        }
        let t = Ticket(
            id: UUID().uuidString, guildID: guildID, userID: userID, channelID: channelID, openedAt: Date(),
            closedAt: nil, priority: "normal", staffThreadID: nil)
        tickets.append(t)
        try await store.set(tickets, key: "support.tickets")
        return t
    }
    func setStaffThread(id: String, guildID: String, threadID: String) async throws -> Ticket {
        var tickets = await all()
        guard let index = tickets.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        tickets[index].staffThreadID = threadID
        try await store.set(tickets, key: "support.tickets")
        return tickets[index]
    }
    func setPriority(id: String, guildID: String, priority: String) async throws -> Ticket {
        guard ["low", "normal", "high", "urgent"].contains(priority) else {
            throw KimiError.configuration("Choose low, normal, high or urgent priority.")
        }
        var tickets = await all()
        guard let index = tickets.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        guard tickets[index].isOpen else { throw TicketError.alreadyClosed }
        tickets[index].priority = priority
        try await store.set(tickets, key: "support.tickets")
        return tickets[index]
    }
    func close(id: String, guildID: String) async throws -> Ticket {
        var tickets = await all()
        guard let index = tickets.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else {
            throw TicketError.notFound
        }
        guard tickets[index].isOpen else { throw TicketError.alreadyClosed }
        tickets[index].closedAt = Date()
        try await store.set(tickets, key: "support.tickets")
        return tickets[index]
    }
}
enum TicketError: Error { case alreadyOpen, notFound, alreadyClosed }
