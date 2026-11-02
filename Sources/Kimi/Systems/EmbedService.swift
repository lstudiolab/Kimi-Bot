import Foundation

actor EmbedService {
 struct Field:Codable,Sendable {var name:String;var value:String;var inline:Bool=false}
 struct Saved:Codable,Sendable,Identifiable {
  let id:String;let name:String;var title:String;var description:String;var color:Int;var footer:String?
  var author:String?;var thumbnailURL:String?;var imageURL:String?;var url:String?;var fields:[Field]?
 }
 private let store:PersistentStore;private let rest:DiscordREST
 init(store:PersistentStore,rest:DiscordREST){self.store=store;self.rest=rest}
 func all(guild:String)async->[Saved]{let data=await store.get("embeds.saved",as:[String:[Saved]].self) ?? [:];return data[guild] ?? []}
 func save(guild:String,name:String,title:String,description:String,color:Int=8421504,footer:String?=nil,author:String?=nil,thumbnailURL:String?=nil,imageURL:String?=nil,url:String?=nil,fields:[Field]?=nil)async throws->Saved{
  guard !name.isEmpty,name.count<=24 else{throw KimiError.configuration("Embed names must be 1–24 characters.")}
  var data=await store.get("embeds.saved",as:[String:[Saved]].self) ?? [:]
  var list=data[guild]
  if list == nil{list=[]}
  let existing=list!.first(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame})
  let nextFields=fields ?? existing?.fields ?? []
  let validationFields=nextFields.map{EmbedValidator.Field(name:$0.name,value:$0.value)}
  let validator=EmbedValidator()
  let errors=validator.validate(.init(title:title,description:description,fields:validationFields,color:color,imageURL:imageURL ?? existing?.imageURL))
  guard errors.isEmpty else{throw KimiError.configuration(errors.joined(separator:" "))}
  if let author=author ?? existing?.author,author.count>256{throw KimiError.configuration("Embed author exceeds 256 characters.")}
  if let footer=footer ?? existing?.footer,footer.count>2048{throw KimiError.configuration("Embed footer exceeds 2048 characters.")}
  for candidate in [thumbnailURL ?? existing?.thumbnailURL,imageURL ?? existing?.imageURL,url ?? existing?.url].compactMap({$0}) {
   guard let parsed=URL(string:candidate),parsed.scheme=="https",parsed.host != nil else{throw KimiError.configuration("Embed image and title URLs must be valid HTTPS URLs.")}
  }
  let id=existing?.id ?? UUID().uuidString
  let value=Saved(id:id,name:name,title:title,description:description,color:color,footer:footer ?? existing?.footer,author:author ?? existing?.author,thumbnailURL:thumbnailURL ?? existing?.thumbnailURL,imageURL:imageURL ?? existing?.imageURL,url:url ?? existing?.url,fields:nextFields)
  if let index=list!.firstIndex(where:{$0.id == id}){list![index]=value}else{list!.append(value)}
  data[guild]=list;try await store.set(data,key:"embeds.saved");return value
 }
 func publish(guild:String,name:String,channel:String)async throws{
  guard let item=await all(guild:guild).first(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}) else{throw KimiError.configuration("Saved embed not found.")}
  var embed:[String:Any]=["title":item.title,"description":item.description,"color":item.color]
  if let footer=item.footer{embed["footer"]=["text":footer]}
  if let author=item.author{embed["author"]=["name":author]}
  if let url=item.url{embed["url"]=url}
  if let image=item.imageURL{embed["image"]=["url":image]}
  if let thumbnail=item.thumbnailURL{embed["thumbnail"]=["url":thumbnail]}
  if let fields=item.fields,!fields.isEmpty{embed["fields"]=fields.map{["name":$0.name,"value":$0.value,"inline":$0.inline] as [String:Any]}}
  _ = try await rest.call("POST","channels/\(channel)/messages",body:["embeds":[embed],"allowed_mentions":["parse":[]]])
 }
}
