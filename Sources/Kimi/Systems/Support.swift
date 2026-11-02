import Foundation
actor Support {
    struct Ticket:Codable,Sendable,Identifiable {let id:String;let guildID:String;let userID:String;let channelID:String;var status:String;let openedAt:Date;var closedAt:Date?}
    private let store:JSONStore,logger:KimiLogger
    init(store:JSONStore,logger:KimiLogger){self.store=store;self.logger=logger}
    func list(guildID:String) async->[Ticket]{await load().values.filter{$0.guildID==guildID}.sorted{$0.openedAt>$1.openedAt}}
    func open(guildID:String,userID:String,channelID:String) async throws->Ticket {
        var all=await load()
        guard !all.values.contains(where:{$0.guildID==guildID && $0.userID==userID && $0.status=="open"}) else{throw NSError(domain:"Kimi.Support",code:1,userInfo:[NSLocalizedDescriptionKey:"An open ticket already exists."])}
        let ticket=Ticket(id:UUID().uuidString,guildID:guildID,userID:userID,channelID:channelID,status:"open",openedAt:Date(),closedAt:nil)
        all[ticket.id]=ticket;try await save(all);await logger.info("Support ticket opened: \(ticket.id)");return ticket
    }
    func close(id:String,guildID:String) async throws->Bool {
        var all=await load();guard var ticket=all[id],ticket.guildID==guildID,ticket.status=="open" else{return false}
        ticket.status="closed";ticket.closedAt=Date();all[id]=ticket;try await save(all);await logger.info("Support ticket closed: \(id)");return true
    }
    private func load() async->[String:Ticket] {
        guard let value=await store.value(for:"support_tickets"),let data=try? JSONEncoder().encode(value) else{return [:]}
        return (try? JSONDecoder().decode([String:Ticket].self,from:data)) ?? [:]
    }
    private func save(_ all:[String:Ticket]) async throws {try await store.set(try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(all)),for:"support_tickets")}
}
