import Foundation

actor VerificationService {
 struct Settings:Codable,Sendable {var channelID:String?;var roleID:String?;var requiredRoleID:String?;var reviewChannelID:String?;var minimumAgeDays:Int=0}
 private struct LegacySettings:Decodable {var channel_id:String?;var role_id:String?;var required_role_id:String?;var review_channel_id:String?;var min_age_days:Int?}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func settings(_ guild:String)async->Settings{
  if let value=await store.get("verification.settings."+guild,as:Settings.self){return value}
  let old=await store.getLegacy("verification",as:[String:LegacySettings].self)?[guild]
  return Settings(channelID:old?.channel_id,roleID:old?.role_id,requiredRoleID:old?.required_role_id,reviewChannelID:old?.review_channel_id,minimumAgeDays:max(0,old?.min_age_days ?? 0))
 }
 func configure(_ value:Settings,guild:String)async throws{
  guard (0...3650).contains(value.minimumAgeDays) else{throw KimiError.configuration("Minimum account age must be between 0 and 3650 days.")}
  try await store.setGuild(value,key:"verification.settings."+guild,guildID:guild)
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
  let records=VerificationRecords(store:store)
  _=try? await records.attempt(guildID:guild,userID:userID)
  let record=await records.record(guildID:guild,userID:userID)
  let value=await settings(guild)
  if let required=value.requiredRoleID {
   let member=(try? await rest.call("GET","guilds/"+guild+"/members/"+userID)) as? [String:Any] ?? [:]
   let memberRoles=Set(member["roles"] as? [String] ?? [])
   guard memberRoles.contains(required) else{try? await rest.editKimiInteraction(applicationID,interactionToken,"You need the required server role before verification.");return}
  }
  let snowflake=Int64(userID) ?? 0
  let created=Date(timeIntervalSince1970:Double((snowflake >> 22)+1_420_070_400_000)/1000)
  let profile=(try? await rest.call("GET","users/"+userID)) as? [String:Any] ?? [:]
  let defaultAvatar=(profile["avatar"] as? String)==nil
  let result=VerificationEngine().evaluate(createdAt:created,defaultAvatar:defaultAvatar,suspiciousBehavior:record.failures>0,attempts:record.attempts,minimumAgeDays:value.minimumAgeDays)
  let age=max(0,Int(Date().timeIntervalSince(created)/86400))
  if result.decision != .approve{
   if result.decision == .reject {
    try? await records.markFailed(guildID:guild,userID:userID,reason:result.reasons.joined(separator:"; "))
    do {
     _ = try await rest.call("DELETE","guilds/"+guild+"/members/"+userID)
     try? await rest.editKimiInteraction(applicationID,interactionToken,"Verification score: "+String(result.score)+"/100. The account did not meet the minimum safety score and was removed.")
     await logger.log("WARN","Verification automatically removed member "+userID+" from guild "+guild+"; score "+String(result.score))
     return
    } catch { await logger.log("ERROR","Automatic verification removal failed: "+error.localizedDescription) }
   }
   var queued=false
   if let review=value.reviewChannelID{
    let details=result.reasons.isEmpty ? "No additional risk signals." : result.reasons.joined(separator:"; ")
    let body="Verification review required for <@\(userID)>. Score: "+String(result.score)+"/100. Account age: "+String(age)+" days. "+details
    let components=[["type":1,"components":[["type":2,"style":3,"label":"Approve","custom_id":"verify:approve:"+userID],["type":2,"style":4,"label":"Reject","custom_id":"verify:reject:"+userID]]]] as [[String:Any]]
    do{
     let posted=try await rest.call("POST","channels/\(review)/messages",body:["content":body,"components":components,"allowed_mentions":["parse":[]]])
     if let messageID=(posted as? [String:Any])?["id"] as? String{try await records.setReviewMessage(guildID:guild,userID:userID,messageID:messageID)}
     queued=true
    }catch{await logger.log("ERROR","Verification review could not be queued: "+error.localizedDescription)}
   }
   let response=queued ? "Verification score: "+String(result.score)+"/100. Your request was sent for manual review." : "Verification score: "+String(result.score)+"/100. Manual review is required, but the review channel is not configured."
   try? await rest.editKimiInteraction(applicationID,interactionToken,response)
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
   let owner=try await rest.ownerID(guild)
   guard owner==reviewer else{throw KimiError.configuration("Only the server owner can decide this review.")}
   let value=await settings(guild)
   let records=VerificationRecords(store:store)
   if decision=="approve"{
    if let role=value.roleID{
     let roles=try await rest.call("GET","guilds/"+guild+"/roles") as? [[String:Any]] ?? []
     let bot=try await rest.call("GET","guilds/"+guild+"/members/@me") as? [String:Any] ?? [:]
     let botIDs=Set(bot["roles"] as? [String] ?? [])
     let highest=roles.filter{botIDs.contains($0["id"] as? String ?? "")}.map{$0["position"] as? Int ?? 0}.max() ?? 0
     let canManage=roles.contains{botIDs.contains($0["id"] as? String ?? "") && ((UInt64($0["permissions"] as? String ?? "") ?? 0) & (1<<28) != 0)}
     guard let target=roles.first(where:{($0["id"] as? String)==role}) else{throw KimiError.configuration("The verified role no longer exists.")}
     let permissions=UInt64(target["permissions"] as? String ?? "") ?? 0
     let dangerous=UInt64((1<<3)|(1<<5)|(1<<28)|(1<<29)|(1<<30)|(1<<31)|(1<<32))
     guard canManage,role != guild,(target["position"] as? Int ?? 0)<highest,permissions & dangerous == 0,target["managed"] as? Bool != true else{throw KimiError.configuration("The verified role is unsafe or above Kimi's highest role.")}
     _ = try await rest.call("PUT","guilds/"+guild+"/members/"+userID+"/roles/"+role)
    }
    try await records.markVerified(guildID:guild,userID:userID)
    try await rest.editKimiInteraction(applicationID,interactionToken,"Member approved and verified.")
   }else if decision=="reject"{
    _ = try await rest.call("DELETE","guilds/"+guild+"/members/"+userID)
    try await records.markFailed(guildID:guild,userID:userID,reason:"Rejected by server owner during verification review.")
    try await rest.editKimiInteraction(applicationID,interactionToken,"Member rejected and removed from the server.")
   }else{throw KimiError.configuration("Choose approve or reject.")}
  }catch{try? await rest.editKimiInteraction(applicationID,interactionToken,"Verification review failed: "+error.localizedDescription)}
 }
}}
