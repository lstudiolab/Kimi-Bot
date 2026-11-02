import Foundation

actor AutomationEngine {
 struct Rule:Codable,Sendable,Identifiable {let id:String;let guildID:String;var name:String;var trigger:String;var action:String;var enabled:Bool;let createdAt:Date}
 private let store:PersistentStore
 init(store:PersistentStore){self.store=store}
 func rules(guildID:String)async->[Rule]{(await store.get("automation.rules",as:[Rule].self) ?? []).filter{$0.guildID==guildID}}
 func add(guildID:String,name:String,trigger:String,action:String)async throws->Rule{
  var values=await store.get("automation.rules",as:[Rule].self) ?? []
  let rule=Rule(id:UUID().uuidString,guildID:guildID,name:String(name.prefix(80)),trigger:trigger,action:action,enabled:true,createdAt:Date())
  values.append(rule);try await store.set(values,key:"automation.rules");return rule
 }
 func setEnabled(_ enabled:Bool,id:String,guildID:String)async throws->Bool{
  var values=await store.get("automation.rules",as:[Rule].self) ?? []
  guard let i=values.firstIndex(where:{$0.id==id && $0.guildID==guildID}) else{return false}
  values[i].enabled=enabled;try await store.set(values,key:"automation.rules");return true
 }
}
