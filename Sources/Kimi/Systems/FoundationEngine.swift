import Foundation
actor FoundationEngine {
 struct Welcome:Codable,Sendable {
  var welcomeChannel:String?;var goodbyeChannel:String?
  var welcomeMessage:String;var goodbyeMessage:String;var autoRole:String?
  init(welcomeChannel:String?=nil,goodbyeChannel:String?=nil,welcomeMessage:String="Welcome {user} to {server}!",goodbyeMessage:String="{username} has left {server}.",autoRole:String?=nil){self.welcomeChannel=welcomeChannel;self.goodbyeChannel=goodbyeChannel;self.welcomeMessage=welcomeMessage;self.goodbyeMessage=goodbyeMessage;self.autoRole=autoRole}
 }
 private struct LegacyWelcome:Decodable {
  var welcome_channel_id:String?;var goodbye_channel_id:String?;var welcome_message:String?;var goodbye_message:String?;var auto_role_id:String?
 }
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func settings(guildID:String)async->Welcome{
  if let value=await store.get("foundation.\(guildID)",as:Welcome.self){return value}
  let legacy=await store.getLegacy("welcome",as:[String:LegacyWelcome].self)?[guildID]
  return Welcome(welcomeChannel:legacy?.welcome_channel_id,goodbyeChannel:legacy?.goodbye_channel_id,welcomeMessage:legacy?.welcome_message ?? "Welcome {user} to {server}!",goodbyeMessage:legacy?.goodbye_message ?? "{username} has left {server}.",autoRole:legacy?.auto_role_id)
 }
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
