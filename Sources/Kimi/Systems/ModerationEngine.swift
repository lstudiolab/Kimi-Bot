import Foundation

actor ModerationEngine {
 struct Policy:Codable,Sendable {var enabled=true;var messagesPerMinute=20;var timeoutMinutes=10;var blockedPhrases:[String]=[]}
 struct Finding:Sendable {let guildID:String;let userID:String;let messageID:String;let reason:String;let score:Int}
 private let store:PersistentStore
 private var policies:[String:Policy]=[:]
 private var history:[String:[Date]]=[:]
 init(store:PersistentStore){self.store=store}
 func policy(guildID:String)async->Policy {
  if let cached=policies[guildID]{return cached}
  let loaded=await store.get("moderation.\(guildID)",as:Policy.self) ?? Policy()
  policies[guildID]=loaded;return loaded
 }
 func configure(_ policy:Policy,guildID:String)async throws {
  policies[guildID]=policy;try await store.set(policy,key:"moderation.\(guildID)")
 }
 func evaluate(guildID:String,userID:String,messageID:String,content:String,now:Date=Date())async->Finding? {
  let p=await policy(guildID:guildID);guard p.enabled else{return nil}
  let key=guildID+":"+userID
  var events=(history[key] ?? []).filter{now.timeIntervalSince($0)<60};events.append(now);history[key]=events
  let normalized=content.lowercased()
  let blocked=p.blockedPhrases.first{!$0.isEmpty && normalized.contains($0.lowercased())}
  let spam=events.count>max(1,p.messagesPerMinute)
  let excessive=content.count>1800
  guard blocked != nil || spam || excessive else{return nil}
  return Finding(guildID:guildID,userID:userID,messageID:messageID,reason:blocked.map{"Blocked phrase: \($0)"} ?? (spam ? "Message rate exceeded":"Message too long"),score:(blocked == nil ? 0:90)+(spam ? 60:0)+(excessive ? 30:0))
 }
}
