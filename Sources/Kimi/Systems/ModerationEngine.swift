import Foundation
actor ModerationEngine {
 struct Policy:Codable,Sendable {var enabled:Bool=true;var messagesPerMinute:Int=20;var timeoutMinutes:Int=10;var blockedPhrases:[String]=[]}
 struct Finding:Sendable {let guildID:String;let userID:String;let messageID:String;let reason:String;let score:Int}
 private struct Legacy:Decodable {var enabled:Bool?;var timeout_minutes:Int?;var max_message_count:Int?}
 private let store:PersistentStore
 private var policies:[String:Policy]=[:]
 private var history:[String:[Date]]=[:]
 init(store:PersistentStore){self.store=store}
 func policy(guildID:String)async->Policy {
  if let cached=policies[guildID]{return cached}
  var value=await store.get("moderation."+guildID,as:Policy.self) ?? Policy()
  if let legacy=await store.getLegacy("moderation",as:[String:Legacy].self)?[guildID]{
   value.enabled=legacy.enabled ?? value.enabled
   value.timeoutMinutes=max(1,min(40320,legacy.timeout_minutes ?? value.timeoutMinutes))
   value.messagesPerMinute=max(2,min(100,legacy.max_message_count ?? value.messagesPerMinute))
  }
  if let words=await store.getLegacy("automod_words",as:[String:[String]].self)?[guildID]{value.blockedPhrases=Array(words.prefix(100))}
  policies[guildID]=value;return value
 }
 func configure(_ policy:Policy,guildID:String)async throws {
  var value=policy;value.messagesPerMinute=max(2,min(100,value.messagesPerMinute));value.timeoutMinutes=max(1,min(40320,value.timeoutMinutes));value.blockedPhrases=Array(value.blockedPhrases.prefix(100))
  policies[guildID]=value;try await store.set(value,key:"moderation."+guildID)
 }
 func evaluate(guildID:String,userID:String,messageID:String,content:String,now:Date=Date())async->Finding? {
  let value=await policy(guildID:guildID);guard value.enabled else{return nil}
  let key=guildID+":"+userID
  var events=(history[key] ?? []).filter{now.timeIntervalSince($0)<60};events.append(now);history[key]=events
  let normalized=content.lowercased()
  let blocked=value.blockedPhrases.first{!$0.isEmpty && normalized.contains($0.lowercased())}
  let spam=events.count>max(1,value.messagesPerMinute)
  let excessive=content.count>1900
  let caps=content.count>40 && content.filter{$0.isUppercase}.count>content.count*8/10
  let mentions=content.components(separatedBy:"<@").count-1
  let massMention=mentions>=8
  guard blocked != nil || spam || excessive || caps || massMention else{return nil}
  let reason=blocked.map{"Blocked phrase: "+$0} ?? (spam ? "Message rate exceeded":(massMention ? "Mass mention pattern":(caps ? "Excessive capitals":"Message too long")))
  let score=(blocked == nil ? 0:90)+(spam ? 60:0)+(massMention ? 40:0)+(caps ? 20:0)+(excessive ? 30:0)
  return Finding(guildID:guildID,userID:userID,messageID:messageID,reason:reason,score:score)
 }
}
