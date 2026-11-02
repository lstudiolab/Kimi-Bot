import Foundation

actor EmbedService {
 struct Saved:Codable,Sendable,Identifiable {let id:String;let name:String;var title:String;var description:String;var color:Int;var footer:String?}
 private let store:PersistentStore;private let rest:DiscordREST
 init(store:PersistentStore,rest:DiscordREST){self.store=store;self.rest=rest}
 func all(guild:String)async->[Saved]{let data=await store.get("embeds.saved",as:[String:[Saved]].self) ?? [:];return data[guild] ?? []}
 func save(guild:String,name:String,title:String,description:String,color:Int=8421504,footer:String?=nil)async throws->Saved{
  guard !name.isEmpty,name.count<=24 else{throw KimiError.configuration("Embed names must be 1–24 characters.")}
  let validator=EmbedValidator()
  let errors=validator.validate(.init(title:title,description:description,fields:[],color:color,imageURL:nil))
  guard errors.isEmpty else{throw KimiError.configuration(errors.joined(separator:" "))}
  var data=await store.get("embeds.saved",as:[String:[Saved]].self) ?? [:]
  var list=data[guild] ?? []
  let id=list.first(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame})?.id ?? UUID().uuidString
  let value=Saved(id:id,name:name,title:title,description:description,color:color,footer:footer)
  if let index=list.firstIndex(where:{$0.id == id}){list[index]=value}else{list.append(value)}
  data[guild]=list;try await store.set(data,key:"embeds.saved");return value
 }
 func publish(guild:String,name:String,channel:String)async throws{
  guard let item=await all(guild:guild).first(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) else{throw KimiError.configuration("Saved embed not found.")}
  var embed:[String:Any]=["title":item.title,"description":item.description,"color":item.color]
  if let footer=item.footer{embed["footer"]=["text":footer]}
  _ = try await rest.call("POST","channels/\(channel)/messages",body:["embeds":[embed],"allowed_mentions":["parse":[]]])
 }
}
