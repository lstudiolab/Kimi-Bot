import Foundation

extension DiscordREST {
 func registerGuildCommands(_ clientID:String,guildID:String,installed:[String]) async throws {
  _ = try await call("PUT","applications/\(clientID)/guilds/\(guildID)/commands",body:CommandCatalog.guildCommands(installed:installed))
 }
 func ownerID(_ guildID:String) async throws -> String {
  let data=try await call("GET","guilds/\(guildID)")
  guard let id=(data as? [String:Any])?["owner_id"] as? String else { throw KimiError.invalidResponse }
  return id
 }
 func createPrivateTextChannel(_ guildID:String,_ name:String,_ ownerID:String,_ botID:String,_ parentID:String?=nil) async throws -> String {
  var body:[String:Any]=["name":SecurityPolicy.channelName(name),"type":0,"permission_overwrites":[
   ["id":guildID,"type":0,"deny":"1024"],
   ["id":ownerID,"type":1,"allow":"68608"],
   ["id":botID,"type":1,"allow":"68608"]
  ]]
  if let parentID { body["parent_id"]=parentID }
  let data=try await call("POST","guilds/\(guildID)/channels",body:body)
  guard let id=(data as? [String:Any])?["id"] as? String else { throw KimiError.invalidResponse }
  return id
 }
 func deferKimiInteraction(_ id:String,_ token:String) async throws {
  _ = try await call("POST","interactions/\(id)/\(token)/callback",body:["type":5,"data":["flags":64]])
 }
 func editKimiInteraction(_ app:String,_ token:String,_ content:String) async throws {
  _ = try await call("PATCH","webhooks/\(app)/\(token)/messages/@original",body:["content":String(content.prefix(1900)),"allowed_mentions":["parse":[]]])
 }
 func deleteKimiMessage(_ channel:String,_ message:String) async throws {
  _ = try await call("DELETE","channels/\(channel)/messages/\(message)")
 }
 func timeoutKimiMember(_ guild:String,_ user:String,_ minutes:Int,_ reason:String) async throws {
  let until=ISO8601DateFormatter().string(from:Date().addingTimeInterval(Double(max(1,minutes))*60))
  _ = try await call("PATCH","guilds/\(guild)/members/\(user)",body:["communication_disabled_until":until,"reason":String(reason.prefix(400))])
 }
}

extension KimiRuntime {
 func handleMigratedCommand(_ event:[String:Any]) async -> Bool {
  guard (event["type"] as? Int)==2 else { return false }
  guard let id=event["id"] as? String,let token=event["token"] as? String,let app=event["application_id"] as? String else { return false }
  let guild=event["guild_id"] as? String ?? ""
  let user=(event["user"] as? [String:Any])?["id"] as? String ?? (event["member"] as? [String:Any])?["user"] as? [String:Any] as? String ?? ""
  let data=event["data"] as? [String:Any] ?? [:]
  let name=data["name"] as? String ?? ""
  let options=data["options"] as? [[String:Any]] ?? []
  func value(_ key:String)->String? {
   if let v=options.first(where:{($0["name"] as? String)==key})?["value"] as? String { return v }
   for option in options {
    if let nested=option["options"] as? [[String:Any]],let v=nested.first(where:{($0["name"] as? String)==key})?["value"] as? String { return v }
   }
   return nil
  }
  do { try await rest.deferKimiInteraction(id,token) }
  catch { await logger.log("WARN","Interaction acknowledgement failed: "+error.localizedDescription);return true }
  var reply="Command completed."
  do {
   switch name {
   case "kimi":
    let installed=await AppManager(store:store).installed(guildID:guild)
    reply="Kimi server control centre\nInstalled apps: "+(installed.isEmpty ? "None":installed.joined(separator:", "))
   case "apps","app-store":
    let installed=await AppManager(store:store).installed(guildID:guild)
    reply="Kimi Apps\n"+CommandCatalog.appNames().map{ $0+" — "+(installed.contains($0) ? "Installed":"Available") }.joined(separator:"\n")+"\n\nUse /install to add an app."
   case "install","uninstall":
    let owner=try await rest.ownerID(guild)
    guard owner==user else { throw KimiError.configuration("Only the server owner can install or remove apps.") }
    guard let appName=value("app") else { throw KimiError.configuration("Choose an app.") }
    let manager=AppManager(store:store)
    let result = name=="install" ? try await manager.install(appName,guildID:guild) : try await manager.uninstall(appName,guildID:guild)
    guard result.ok else { throw KimiError.configuration(result.message) }
    let installed=await manager.installed(guildID:guild)
    try await rest.registerGuildCommands(app,guildID:guild,installed:installed)
    reply=appName+(name=="install" ? " installed. Its commands are available in this server.":" removed. Saved settings were preserved.")
   case "setup":
    let owner=try await rest.ownerID(guild)
    let categoryData=try await rest.call("POST","guilds/\(guild)/channels",body:["name":"kimi","type":4])
    let category=(categoryData as? [String:Any])?["id"] as? String
    let me=try await rest.call("GET","users/@me")
    guard let bot=(me as? [String:Any])?["id"] as? String else { throw KimiError.invalidResponse }
    let logs=try await rest.createPrivateTextChannel(guild,"kimi-logs",owner,bot,category)
    let confirmations=try await rest.createPrivateTextChannel(guild,"kimi-confirmation",owner,bot,category)
    let ticketData=try await rest.call("POST","guilds/\(guild)/channels",body:["name":"ticket","type":4])
    let ticket=(ticketData as? [String:Any])?["id"] as? String ?? ""
    reply="Foundation setup complete.\nPrivate logs: <#"+logs+">\nPrivate confirmations: <#"+confirmations+">\nSupport category: <#"+ticket+">"
   case "plan":
    let stored=await store.get("apps.installed",as:[String:[String]].self) ?? [:]
    let bytes=(try? JSONEncoder().encode(stored).count) ?? 0
    reply="Kimi Free\nAll built-in apps are free.\nConfiguration footprint: "+StorageQuota.format(bytes)+"\nStorage allowance: "+StorageQuota.format(StorageQuota.freeLimit)
   case "welcome":
    let engine=FoundationEngine(store:store,rest:rest,logger:logger)
    var settings=await engine.settings(guildID:guild)
    if let x=value("welcome-channel"){settings.welcomeChannel=x}
    if let x=value("goodbye-channel"){settings.goodbyeChannel=x}
    if let x=value("welcome-message"){settings.welcomeMessage=String(x.prefix(1800))}
    if let x=value("goodbye-message"){settings.goodbyeMessage=String(x.prefix(1800))}
    try await engine.configure(guildID:guild,settings)
    reply="Welcome and goodbye settings saved."
   case "autorole":
    let engine=FoundationEngine(store:store,rest:rest,logger:logger)
    var settings=await engine.settings(guildID:guild);settings.autoRole=value("role")
    try await engine.configure(guildID:guild,settings)
    reply=settings.autoRole == nil ? "Automatic role assignment disabled.":"Automatic role saved."
   case "moderation":
    let policy=await ModerationEngine(store:store).policy(guildID:guild)
    reply="Kimi Lock · Moderation\nStatus: "+(policy.enabled ? "Enabled":"Disabled")+"\nMessages/minute: "+String(policy.messagesPerMinute)+"\nTimeout: "+String(policy.timeoutMinutes)+" minutes\nBlocked phrases: "+String(policy.blockedPhrases.count)
   case "filter":
    let engine=ModerationEngine(store:store);var policy=await engine.policy(guildID:guild)
    let sub=options.first?["name"] as? String ?? "list",phrase=value("phrase") ?? ""
    if sub=="add" {
     guard !phrase.isEmpty else { throw KimiError.configuration("Enter a phrase.") }
     if !policy.blockedPhrases.contains(where:{$0.caseInsensitiveCompare(phrase)==ComparisonResult.orderedSame}){policy.blockedPhrases.append(String(phrase.prefix(100)))}
     try await engine.configure(policy,guildID:guild);reply="Blocked phrase added."
    } else if sub=="remove" {
     policy.blockedPhrases.removeAll{$0.caseInsensitiveCompare(phrase)==ComparisonResult.orderedSame};try await engine.configure(policy,guildID:guild);reply="Blocked phrase removed."
    } else { reply=policy.blockedPhrases.isEmpty ? "No blocked phrases configured.":"Blocked phrases\n"+policy.blockedPhrases.joined(separator:"\n") }
   case "security":
    let roles=try await rest.call("GET","guilds/\(guild)/roles") as? [[String:Any]] ?? []
    let everyone=roles.first(where:{($0["id"] as? String)==guild})
    let permissions=UInt64(everyone?["permissions"] as? String ?? "") ?? 0
    let findings=ServerAudit().evaluate(roles:roles,everyonePermissions:permissions)
    reply=findings.isEmpty ? "Kimi Lock security audit: no obvious elevated-role risks found.":findings.map{$0.severity.uppercased()+" — "+$0.title+": "+$0.detail}.joined(separator:"\n")
   case "tickets","ticket-panel","ticket-config":
    let channels=try await rest.call("GET","guilds/\(guild)/channels") as? [[String:Any]] ?? []
    let category=channels.first(where:{($0["type"] as? Int)==4 && ($0["name"] as? String)=="ticket"})
    if name=="tickets" && category==nil {
     let created=try await rest.call("POST","guilds/\(guild)/channels",body:["name":"ticket","type":4])
     reply="Support category created: <#"+((created as? [String:Any])?["id"] as? String ?? "")+">"
    } else {
     let all=await SupportTickets(store:store).all()
     let count=all.filter{$0.guildID==guild && $0.isOpen}.count
     reply="Support\nTicket category: "+(category?["id"] as? String ?? "not configured")+"\nOpen ticket records: "+String(count)
    }
   case "automations":
    let rules=await AutomationEngine(store:store).rules(guildID:guild)
    reply="Automations\nSaved rules: "+String(rules.count)
   case "verify","verify-config":
    let records=VerificationRecords(store:store)
    let record=await records.record(guildID:guild,userID:user)
    reply="Kimi Lock verification\nRecorded attempts: "+String(record.attempts)+"\nConfigure account age and a review channel before publishing a verification panel."
   case "roles":reply="Role Picker is installed as a server app. The menu editor is being migrated."
   case "embed-new","embed-edit","embed-post":reply="Embed validation is available. The editor and publishing interactions are being migrated."
   case "guard-review":reply="Kimi Guard incident review is being migrated."
   case "web-token":reply="Dashboard authentication is being migrated to Swift. No email verification is required."
   default:reply="This command is not available in the current Swift runtime."
   }
  } catch { reply="Kimi could not complete the action: "+error.localizedDescription;await logger.log("ERROR","Command "+name+" failed: "+error.localizedDescription) }
  do { try await rest.editKimiInteraction(app,token,reply) }
  catch { await logger.log("ERROR","Interaction response update failed: "+error.localizedDescription) }
  return true
 }
 func handleMigratedComponent(_ event:[String:Any],data:[String:Any]) async -> Bool {
  guard let id=event["id"] as? String,let token=event["token"] as? String else{return true}
  do {try await rest.respond(id,token,"This control is not yet available in the Swift interaction router.")}
  catch {await logger.log("WARN","Component acknowledgement failed: "+error.localizedDescription)}
  return true
 }
 func dispatchMigratedEvent(_ name:String,_ data:[String:Any]) async {
  switch name {
  case "READY":
   if let guilds=data["guilds"] as? [[String:Any]] {
    for item in guilds {
     guard let guild=item["id"] as? String else{continue}
     let installed=await AppManager(store:store).installed(guildID:guild)
     try? await rest.registerGuildCommands(ProcessInfo.processInfo.environment["CLIENT_ID"] ?? "",guildID:guild,installed:installed)
    }
   }
  case "GUILD_MEMBER_ADD":
   guard let guild=data["guild_id"] as? String,let user=data["user"] as? [String:Any],let id=user["id"] as? String else{return}
   await FoundationEngine(store:store,rest:rest,logger:logger).memberJoined(guildID:guild,userID:id,username:user["username"] as? String ?? "member",serverName:"the server",memberCount:data["member_count"] as? Int ?? 0)
  case "GUILD_MEMBER_REMOVE":
   guard let guild=data["guild_id"] as? String,let user=data["user"] as? [String:Any],let id=user["id"] as? String else{return}
   await FoundationEngine(store:store,rest:rest,logger:logger).memberLeft(guildID:guild,userID:id,username:user["username"] as? String ?? "member",serverName:"the server")
  case "MESSAGE_CREATE":
   guard let guild=data["guild_id"] as? String,let channel=data["channel_id"] as? String,let message=data["id"] as? String,let author=data["author"] as? [String:Any],let user=author["id"] as? String,(author["bot"] as? Bool != true) else{return}
   if let finding=await ModerationEngine(store:store).evaluate(guildID:guild,userID:user,messageID:message,content:data["content"] as? String ?? "") {
    try? await rest.deleteKimiMessage(channel,message)
    if finding.reason=="Message rate exceeded" {
     let policy=await ModerationEngine(store:store).policy(guildID:guild)
     try? await rest.timeoutKimiMember(guild,user,policy.timeoutMinutes,finding.reason)
    }
    await logger.log("WARN","Kimi Lock moderation: "+finding.reason)
   }
  case "GUILD_AUDIT_LOG_ENTRY_CREATE":
   guard let guild=data["guild_id"] as? String,let actor=data["user_id"] as? String,let action=data["action_type"] as? Int else{return}
   do {if let incident=try await AuditProtection(store:store).record(guildID:guild,actorID:actor,action:String(action)){await logger.log("WARN","Kimi Lock incident: "+incident.reason)}}
   catch {await logger.log("ERROR","Audit incident save failed: "+error.localizedDescription)}
  default:break
  }
 }
}
