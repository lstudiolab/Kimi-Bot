import Foundation

actor AnalyticsService {
    struct Day: Codable, Sendable {
        let date: String
        var messages = 0
        var joins = 0
        var leaves = 0
        var commands = 0
        var moderation = 0
        var ticketsOpened = 0
        var ticketsClosed = 0
    }
    struct Summary: Sendable {
        let messages, joins: Int
        let leaves, commands: Int
        let moderation, ticketsOpened: Int
        let ticketsClosed, activeDays: Int
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func record(guild: String, event: String, at date: Date = Date()) async {
        do {
            _ = try await store.updateGuild("analytics.daily", guildID: guild, as: [String: [Day]].self) { stored in
                var all = stored ?? [:]
                let parts = Calendar(identifier: .gregorian).dateComponents(
                    in: TimeZone(secondsFromGMT: 0)!, from: date)
                let day = String(
                    format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                var rows = all[guild] ?? []
                var value = rows.first(where: { $0.date == day }) ?? Day(date: day)
                switch event {
                case "message": value.messages += 1
                case "join": value.joins += 1
                case "leave": value.leaves += 1
                case "command": value.commands += 1
                case "moderation": value.moderation += 1
                case "ticket_open": value.ticketsOpened += 1
                case "ticket_close": value.ticketsClosed += 1
                default: break
                }
                rows.removeAll { $0.date == day }
                rows.append(value)
                all[guild] = Array(rows.sorted { $0.date < $1.date }.suffix(30))
                return all
            }
        } catch {
            // Analytics must never interrupt moderation or command handling.
        }
    }
    func report(guild: String) async -> Summary {
        let rows = (await store.get("analytics.daily", as: [String: [Day]].self) ?? [:])[guild] ?? []
        return Summary(
            messages: rows.reduce(0) { $0 + $1.messages }, joins: rows.reduce(0) { $0 + $1.joins },
            leaves: rows.reduce(0) { $0 + $1.leaves }, commands: rows.reduce(0) { $0 + $1.commands },
            moderation: rows.reduce(0) { $0 + $1.moderation }, ticketsOpened: rows.reduce(0) { $0 + $1.ticketsOpened },
            ticketsClosed: rows.reduce(0) { $0 + $1.ticketsClosed }, activeDays: rows.count)
    }
    func days(guild: String) async -> [Day] {
        (await store.get("analytics.daily", as: [String: [Day]].self) ?? [:])[guild] ?? []
    }
}
