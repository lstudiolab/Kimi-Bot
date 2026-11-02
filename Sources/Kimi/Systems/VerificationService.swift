import Foundation

actor VerificationService {
 struct Settings:Codable,Sendable {var channelID:String?;var roleID:String?;var reviewChannelID:String?;var minimumAgeDays:Int=0}
 private struct LegacySettings:Decodable {var channel_id:String?;var role_id:String?;var review_channel_id:String?;var min_age_days:Int?}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func settings(_ guild:String)async->Settings{
  if let value=await store.get("verification.settings."+guild,as:Settings.self){return value}
  let old=await store.getLegacy("verification",as:[String:LegacySettings].self)?[guild]
  return Settings(channelID:old?.channel_id,roleID:old?.role_id,reviewChannelID:old?.review_channel_id,minimumAgeDays:max(0,old?.min_age_days ?? 0))
 }
 func configure(_ value:Settings,guild:String)async throws{
  guard (0...3650).contains(value.minimumAgeDays) else{throw KimiError.configuration("Minimum account age must be between 0 and 3650 days.")}
  try await store.set(value,key:"verification.settings."+guild)
 }
 func memberJoined(guild:String,userID:String,username:String)async{
  let value=await settings(guild);guard let channel=value.channelID else{return}
  let message:[String:Any]=["content":"<@\(userID)> Please verify to access this server.","components":[["type":1,"components":[["type":2,"style":1,"label":"Verify","custom_id":"verify:start"]]]],"allowed_mentions":["users":[userID],"parse":[]]]
  do{
   let result=try await rest.call("POST","channels/\(channel)/messages",body:message)
   if let id=(result as? [String:Any])?["id"] as? String{try await store.set(id,key:"verification.prompt."+guild+"."+userID)}
  }catch{await logger.log("WARN","Verification prompt could not be posted: "+error.localizedDescription)}
 }
 func verify(guild:String,userID:String,username:String,applicationID:String,interactionToken:String)async{
  let record=await VerificationRecords(store:store).record(guildID:guild,userID:userID)
  if record.verifiedAt != nil{try? await rest.editKimiInteraction(applicationID,interactionToken,"You have already been verified.");return}
  _=try? await VerificationRecords(store:store).attempt(guildID:guild,userID:userID)
  let value=await settings(guild)
  let snowflake=Int64(userID) ?? 0
  let created=Date(timeIntervalSince1970:Double((snowflake >> 22)+1_420_070_400_000)/1000)
  let age=max(0,Int(Date().timeIntervalSince(created)/86400))
  if age<value.minimumAgeDays{
   if let review=value.reviewChannelID{
    let body="Verification review required for <@\(userID)>. Account age: \(age) days; minimum: \(value.minimumAgeDays) days."
    let components=[["type":1,"components":[["type":2,"style":3,"label":"Approve","custom_id":"verify:approve:"+userID],["type":2,"style":4,"label":"Reject","custom_id":"verify:reject:"+userID]]]] as [[String:Any]]
    do{_ = try await rest.call("POST","channels/\(review)/messages",body:["content":body,"components":components,"allowed_mentions":["parse":[]]])}catch{await logger.log("ERROR","Verification review could not be queued: "+error.localizedDescription)}
   }
   try? await rest.editKimiInteraction(applicationID,interactionToken,"Your account is younger than the server's minimum age. Your verification was sent for manual review.")
   return
  }
  if let role=value.roleID{
   do{
    let roles=try await rest.call("GET","guilds/\(guild)/roles") as? [[String:Any]] ?? []
    guard let target=roles.first(where:{($0["id"] as? String)==role}) else{throw KimiError.configuration("The verified role no longer exists.")}
    let permissions=UInt64(target["permissions"] as? String ?? "") ?? 0
    guard role != guild,permissions & (1<<3)==0,permissions & (1<<28)==0 else{throw KimiError.configuration("The verified role has unsafe permissions.")}
    _=try await rest.call("PUT","guilds/\(guild)/members/\(userID)/roles/\(role)")
   }catch{try? await rest.editKimiInteraction(applicationID,interactionToken,"Verification could not assign the configured role: "+error.localizedDescription);return}
  }
  try? await VerificationRecords(store:store).markVerified(guildID:guild,userID:userID)
  try? await rest.editKimiInteraction(applicationID,interactionToken,"Verification complete. You now have access to the server.")
 }
 func review(guild:String,userID:String,decision:String,reviewer:String,applicationID:String,interactionToken:String)async{
  do{
   let owner=try await rest.ownerID(guild);guard owner==reviewer else{throw KimiError.configuration("Only the server owner can decide this review.")}
   let value=await settings(guild)
   if decision=="approve"{
    guard let role=value.roleID else{throw KimiError.configuration("Configure a verified role before approving members.")}
    _=try await rest.call("PUT","guilds/\(guild)/members/\(userID)/roles/\(role)")
    try await VerificationRecords(store:store).markVerified(guildID:guild,userID:userID)
    try await rest.editKimiInteraction(applicationID,interactionToken,"Member approved and verified role assigned.")
   }else{
    _=try await rest.call("DELETE","guilds/\(guild)/members/\(userID)")
    try await rest.editKimiInteraction(applicationID,interactionToken,"Member rejected and removed from the server.")
   }
  }catch{try? await rest.editKimiInteraction(applicationID,interactionToken,"Verification review failed: "+error.localizedDescription)}
 }
}
