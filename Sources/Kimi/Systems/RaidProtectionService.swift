import Foundation

actor RaidProtectionService {
 struct Incident:Codable,Sendable {let guildID:String;let joinedAt:Date;let joinCount:Int;let quarantinedUserID:String?;let accountAgeDays:Int?;let action:String}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 private var joins:[String:[(user:String,date:Date)]]=[:]
 private var cooldown:[String:Date]=[:]
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func memberJoined(guild:String,userID:String,createdAt:Date,isBot:Bool,now:Date=Date())async{
  guard !isBot else{return}
  var recent=(joins[guild] ?? []).filter{now.timeIntervalSince($0.date)<=10}
  recent.append((userID,now));joins[guild]=recent
  guard recent.count>=8,(cooldown[guild].map{now.timeIntervalSince($0)>300} ?? true) else{return}
  cooldown[guild]=now
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
