import Foundation
actor Automation {
    struct Rule:Codable,Sendable,Identifiable {let id:String;let guildID:String;var name:String;var trigger:String;var action:String;var enabled:Bool;var createdAt:Date}
    private let store:JSONStore
    init(store:JSONStore){self.store=store}
    func list(guildID:String) async->[Rule] {guard let value=await store.value(for:"automation_rules"),let data=try? JSONEncoder().encode(value),let all=try? JSONDecoder().decode([String:Rule].self,from:data) else{return []};return all.values.filter{$0.guildID==guildID}}
    func add(guildID:String,name:String,trigger:String,action:String) async throws->Rule {
        var all:[String:Rule]=[:]
        if let value=await store.value(for:"automation_rules"),let data=try? JSONEncoder().encode(value){all=(try? JSONDecoder().decode([String:Rule].self,from:data)) ?? [:]}
        let rule=Rule(id:UUID().uuidString,guildID:guildID,name:String(name.prefix(80)),trigger:trigger,action:action,enabled:true,createdAt:Date())
        all[rule.id]=rule
        try await store.set(try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(all)),for:"automation_rules")
        return rule
    }
}
