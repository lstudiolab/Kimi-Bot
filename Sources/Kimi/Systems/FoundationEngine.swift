import Foundation
actor FoundationEngine {
 struct Welcome:Codable,Sendable {var welcomeChannel:String?;var goodbyeChannel:String?;var welcomeMessage:String="Welcome {user} to {server}!";var goodbyeMessage:String="{username} has left {server}.";var autoRole:String?}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func settings(guildID:String)async->Welcome{await store.get("foundation.\(guildID)",as:Welcome.self) ?? Welcome()}
 func configure(guildID:String,_ value:Welcome)async throws{try await store.set(value,key:"foundation.\(guildID)")}
 func memberJoined(guildID:String,userID:String,username:String,serverName:String,memberCount:Int)async{
  let value=await settings(guildID:guildID)
  if let role=value.autoRole{do{_ = try await rest.call("PUT","guilds/\(guildID)/members/\(userID)/roles/\(role)")}catch{await logger.log("WARN","Auto Role failed: \(error.localizedDescription)")}}
  if let channel=value.welcomeChannel{let body=value.welcomeMessage.replacingOccurrences(of:"{user}",with:"<@\(userID)>").replacingOccurrences(of:"{username}",with:username).replacingOccurrences(of:"{server}",with:serverName).replacingOccurrences(of:"{member_count}",with:String(memberCount));do{_ = try await rest.call("POST","channels/\(channel)/messages",body:["content":String(body.prefix(1900)),"allowed_mentions":["users":[userID],"parse":[]]])}catch{await logger.log("WARN","Welcome message failed: \(error.localizedDescription)")}}
 }
 func memberLeft(guildID:String,userID:String,username:String,serverName:String)async{
  let value=await settings(guildID:guildID);guard let channel=value.goodbyeChannel else{return}
  let body=value.goodbyeMessage.replacingOccurrences(of:"{user}",with:"<@\(userID)>").replacingOccurrences(of:"{username}",with:username).replacingOccurrences(of:"{server}",with:serverName)
  do{_ = try await rest.call("POST","channels/\(channel)/messages",body:["content":String(body.prefix(1900)),"allowed_mentions":["parse":[]]])}catch{await logger.log("WARN","Goodbye message failed: \(error.localizedDescription)")}
 }
}
