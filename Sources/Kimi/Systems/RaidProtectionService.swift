import Foundation

actor RaidProtectionService {
 struct Incident:Codable,Sendable {let guildID:String;let joinedAt:Date;let joinCount:Int;let quarantinedUserID:String?;let accountAgeDays:Int?;let action:String}
 private struct Join:Codable,Sendable {let user:String;let date:Date}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func memberJoined(guild:String,userID:String,createdAt:Date,isBot:Bool,now:Date=Date())async{
  guard !isBot else{return}
  let key="security.raid-joins."+guild
  var recent=(await store.get(key,as:[Join].self) ?? []).filter{now.timeIntervalSince($0.date)<=10 && now >= $0.date}
  recent.append(Join(user:userID,date:now))
  try? await store.set(recent,key:key)
  guard recent.count>=8 else{return}
  let cooldownKey="security.raid-cooldown."+guild
  let last=await store.get(cooldownKey,as:Date.self)
  guard last.map({now.timeIntervalSince($0)>300}) ?? true else{return}
  try? await store.set(now,key:cooldownKey)
  let age=max(0,Int(now.timeIntervalSince(createdAt)/86400))
  var action="Raid burst detected; alert only."
  var quarantined:String?=nil
  if age<7 {
   let owner=(try? await rest.ownerID(guild)) ?? ""
   if userID != owner {
    do{try await rest.timeoutKimiMember(guild,userID,10,"Kimi Lock raid protection: newly created account joined during a join burst");action="New account temporarily timed out for 10 minutes.";quarantined=userID}
    catch{await logger.log("WARN","Raid protection could not timeout new member: "+error.localizedDescription)}
   }
  }
  let incident=Incident(guildID:guild,joinedAt:now,joinCount:recent.count,quarantinedUserID:quarantined,accountAgeDays:age,action:action)
  var records=await store.get("security.raid-incidents",as:[Incident].self) ?? []
  records.append(incident);records=Array(records.suffix(500));try? await store.set(records,key:"security.raid-incidents")
  await logger.log("WARN","Kimi Lock raid protection: "+String(recent.count)+" members joined within 10 seconds in guild "+guild+". "+action)
  let setup=await store.getLegacy("timi_setup",as:[String:[String:String]].self)
  if let channel=setup?[guild]?["log_channel_id"]{
   let report="**Kimi Lock · Join burst detected**\nMembers joined in 10 seconds: "+String(recent.count)+"\nNewest account age: "+String(age)+" days\nAutomatic action: "+action
   _=try? await rest.call("POST","channels/"+channel+"/messages",body:["content":report,"allowed_mentions":["parse":[]]])
  }
 }
}
