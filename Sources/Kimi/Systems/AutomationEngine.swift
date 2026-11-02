import Foundation
actor AutomationEngine {
 struct Rule:Codable,Sendable,Identifiable {let id:String;let guildID:String;var name:String;var trigger:String;var action:String;var enabled:Bool;let createdAt:Date}
 struct Execution:Codable,Sendable {let ruleID:String;let guildID:String;let trigger:String;let success:Bool;let detail:String;let createdAt:Date}
 private let store:PersistentStore
 private let triggers:Set<String>=["message_create","member_join","member_leave","message_contains"]
 private let actions:Set<String>=["delete_message","send_message","timeout","add_role"]
 init(store:PersistentStore){self.store=store}
 func rules(guildID:String)async->[Rule]{(await store.get("automation.rules",as:[Rule].self) ?? []).filter{$0.guildID==guildID}}
 func add(guildID:String,name:String,trigger:String,action:String)async throws->Rule{
  guard triggers.contains(trigger) else{throw KimiError.configuration("Unsupported trigger. Choose message_create, message_contains, member_join or member_leave.")}
  let parts=action.split(separator:":",maxSplits:2).map(String.init)
  guard let kind=parts.first,actions.contains(kind) else{throw KimiError.configuration("Unsupported action. Choose delete_message, send_message, timeout or add_role.")}
  if kind=="send_message" && (parts.count<3 || !parts[1].range(of:#"^\d{15,22}$"#,options:.regularExpression).map({!$0.isEmpty})!){throw KimiError.configuration("send_message action format: send_message:CHANNEL_ID:message")}
  if kind=="timeout" && (parts.count<2 || Int(parts[1]) == nil || !(1...40320).contains(Int(parts[1]) ?? 0)){throw KimiError.configuration("timeout action format: timeout:MINUTES")}
  if kind=="add_role" && (parts.count<2 || parts[1].range(of:#"^\d{15,22}$"#,options:.regularExpression)==nil){throw KimiError.configuration("add_role action format: add_role:ROLE_ID")}
  var values=await store.get("automation.rules",as:[Rule].self) ?? []
  guard values.filter({$0.guildID==guildID}).count<100 else{throw KimiError.configuration("This server has reached the 100-rule limit.")}
  let rule=Rule(id:UUID().uuidString,guildID:guildID,name:String(name.prefix(80)),trigger:trigger,action:action,enabled:true,createdAt:Date())
  values.append(rule);try await store.set(values,key:"automation.rules");return rule
 }
 func setEnabled(_ enabled:Bool,id:String,guildID:String)async throws->Bool{
  var values=await store.get("automation.rules",as:[Rule].self) ?? []
  guard let i=values.firstIndex(where:{$0.id==id && $0.guildID==guildID}) else{return false}
  values[i].enabled=enabled;try await store.set(values,key:"automation.rules");return true
 }
 func remove(id:String,guildID:String)async throws->Bool{
  var values=await store.get("automation.rules",as:[Rule].self) ?? []
  let before=values.count;values.removeAll{$0.id==id && $0.guildID==guildID}
  guard values.count != before else{return false}
  try await store.set(values,key:"automation.rules");return true
 }
 func matching(guildID:String,trigger:String,content:String="")async->[Rule]{
  await rules(guildID:guildID).filter{$0.enabled && ($0.trigger==trigger || ($0.trigger=="message_contains" && !content.isEmpty))}
 }
 func record(_ execution:Execution)async{
  var values=await store.get("automation.executions",as:[Execution].self) ?? []
  values.append(execution);values=Array(values.suffix(1000));try? await store.set(values,key:"automation.executions")
 }
 func executions(guildID:String)async->[Execution]{
  (await store.get("automation.executions",as:[Execution].self) ?? []).filter{$0.guildID==guildID}
 }
}
