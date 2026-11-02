import Foundation

actor RolePickerService {
 struct Menu:Codable,Sendable {let guildID:String;let channelID:String;let roles:[Role]}
 struct Role:Codable,Sendable {let id:String;let name:String}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func publish(guild:String,channel:String)async throws->Int{
  let roles=try await rest.call("GET","guilds/\(guild)/roles") as? [[String:Any]] ?? []
  let safe=roles.filter{item in
   guard let id=item["id"] as? String,id != guild else{return false}
   let permissions=UInt64(item["permissions"] as? String ?? "") ?? 0
   let elevated=(1<<3)|(1<<5)|(1<<28)|(1<<29)|(1<<30)|(1<<31)|(1<<32)
   return permissions & UInt64(elevated)==0 && item["managed"] as? Bool != true
  }.sorted{($0["position"] as? Int ?? 0)<($1["position"] as? Int ?? 0)}.suffix(25)
  let values=safe.compactMap{item->Role? in guard let id=item["id"] as? String else{return nil};return Role(id:id,name:item["name"] as? String ?? "Role")}
  guard !values.isEmpty else{throw KimiError.configuration("No safe assignable roles were found.")}
  let menu=Menu(guildID:guild,channelID:channel,roles:values)
  try await store.set(menu,key:"rolepicker.menu."+guild)
  let options=values.map{["label":String($0.name.prefix(100)),"value":$0.id]}
  let components=[["type":1,"components":[["type":3,"custom_id":"rolepicker:select","placeholder":"Choose your roles","min_values":0,"max_values":values.count,"options":options]]]] as [[String:Any]]
  _ = try await rest.call("POST","channels/\(channel)/messages",body:["content":"Choose the roles you want to have. You can update your selection at any time.","components":components,"allowed_mentions":["parse":[]]])
  return values.count
 }
 func select(guild:String,user:String,selected:[String])async throws->Int{
  guard let menu=await store.get("rolepicker.menu."+guild,as:Menu.self) else{throw KimiError.configuration("This role menu is no longer active.")}
  let allowed=Set(menu.roles.map{$0.id}),chosen=Set(selected)
  guard chosen.isSubset(of:allowed) else{throw KimiError.configuration("The selection contains an invalid role.")}
  let key="rolepicker.selection."+guild+"."+user
  let previous=Set(await store.get(key,as:[String].self) ?? [])
  for role in previous.subtracting(chosen){_ = try await rest.call("DELETE","guilds/\(guild)/members/\(user)/roles/\(role)")}
  for role in chosen.subtracting(previous){_ = try await rest.call("PUT","guilds/\(guild)/members/\(user)/roles/\(role)")}
  try await store.set(Array(chosen),key:key)
  return chosen.count
 }
}
