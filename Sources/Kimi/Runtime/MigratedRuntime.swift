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
 func editKimiInteraction(_ app:String,_ token:String,_ content:String,_ components:[[String:Any]]) async throws {
  _ = try await call("PATCH","webhooks/\\(app)/\\(token)/messages/@original",body:["content":String(content.prefix(1900)),"components":components,"allowed_mentions":["parse":[]]])
 }
 func deleteKimiMessage(_ channel:String,_ message:String) async throws {
  _ = try await call("DELETE","channels/\(channel)/messages/\(message)")
 }
 func timeoutKimiMember(_ guild:String,_ user:String,_ minutes:Int,_ reason:String) async throws {
  let until=ISO8601DateFormatter().string(from:Date().addingTimeInterval(Double(max(1,minutes))*60))
  _ = try await call("PATCH","guilds/\(guild)/members/\(user)",body:["communication_disabled_until":until],auditReason:String(reason.prefix(400)))
 }
}

extension KimiRuntime {
 func handleMigratedCommand(_ event:[String:Any]) async -> Bool {
  guard let interactionType=event["type"] as? Int,interactionType==2 || interactionType==3 else { return false }
  let started=Date()
  guard let id=event["id"] as? String,let token=event["token"] as? String,let app=event["application_id"] as? String else { return false }
  let guild=event["guild_id"] as? String ?? ""
  let memberUser=(event["member"] as? [String:Any])?["user"] as? [String:Any] ?? [:]
  let user=(event["user"] as? [String:Any])?["id"] as? String ?? memberUser["id"] as? String ?? ""
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
  if interactionType==3 { return await handleMigratedComponent(event,data:data) }
  do { try await rest.deferKimiInteraction(id,token) }
  catch { await logger.log("WARN","Interaction acknowledgement failed: "+error.localizedDescription);return true }
  var reply="Command completed."
  var responseComponents:[[String:Any]]=[]
  do {
   switch name {
   case "kimi":
    let installed=await AppManager(store:store).installed(guildID:guild)
    reply="Kimi server control centre\nInstalled apps: "+(installed.isEmpty ? "None":installed.joined(separator:", "))
    responseComponents=[KimiUI.row([KimiUI.button(id:"settings:apps",label:"App Store"),KimiUI.button(id:"settings:status",label:"System Status")]),KimiUI.row([KimiUI.button(id:"settings:preferences",label:"Preferences"),KimiUI.button(id:"settings:activity",label:"Activity")])]
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
    let me=try await rest.call("GET","users/@me")
    guard let bot=(me as? [String:Any])?["id"] as? String else { throw KimiError.invalidResponse }
    let channels=try await rest.call("GET","guilds/\(guild)/channels") as? [[String:Any]] ?? []
    func existing(_ name:String,_ type:Int)->String?{channels.first(where:{($0["name"] as? String)==name && ($0["type"] as? Int)==type})?["id"] as? String}
    let category:String
    if let found=existing("kimi",4){category=found}else{category=try await rest.createChannel(guild:guild,name:"kimi",type:4)}
    let ticket:String
    if let found=existing("ticket",4){ticket=found}else{ticket=try await rest.createChannel(guild:guild,name:"ticket",type:4)}
    let logs:String
    if let found=existing("kimi-logs",0){logs=found}else{logs=try await rest.createPrivateTextChannel(guild,"kimi-logs",owner,bot,category)}
    let confirmations:String
    if let found=existing("kimi-confirmation",0){confirmations=found}else{confirmations=try await rest.createPrivateTextChannel(guild,"kimi-confirmation",owner,bot,category)}
    try await store.set(logs,key:"foundation.logs."+guild)
    try await store.set(confirmations,key:"foundation.confirmations."+guild)
    var policy=await ModerationEngine(store:store).policy(guildID:guild);policy.logChannelID=logs;try await ModerationEngine(store:store).configure(policy,guildID:guild)
    reply="Foundation setup complete.\nPrivate logs: <#"+logs+">\nPrivate confirmations: <#"+confirmations+">\nSupport category: <#"+ticket+">"
   case "plan":
    let stored=await store.get("apps.installed",as:[String:[String]].self) ?? [:]
    let bytes=(try? JSONEncoder().encode(stored).count) ?? 0
    reply="Kimi Free\nAll built-in apps are free.\nConfiguration footprint: "+StorageQuota.format(bytes)+"\nStorage allowance: "+StorageQuota.format(StorageQuota.freeLimit)
   case "welcome","configure-welcome","configure-foundation":
    let engine=FoundationEngine(store:store,rest:rest,logger:logger)
    var settings=await engine.settings(guildID:guild)
    if let x=value("welcome-channel"){settings.welcomeChannel=x}
    if let x=value("goodbye-channel"){settings.goodbyeChannel=x}
    if let x=value("welcome-message"){settings.welcomeMessage=String(x.prefix(1800))}
    if let x=value("goodbye-message"){settings.goodbyeMessage=String(x.prefix(1800))}
    try await engine.configure(guildID:guild,settings)
    reply="Welcome and goodbye settings saved."
   case "autorole","configure-auto-role":
    let engine=FoundationEngine(store:store,rest:rest,logger:logger)
    var settings=await engine.settings(guildID:guild);settings.autoRole=value("role")
    try await engine.configure(guildID:guild,settings)
    reply=settings.autoRole == nil ? "Automatic role assignment disabled.":"Automatic role saved."
   case "moderation","configure-kimi-lock":
    let engine=ModerationEngine(store:store)
    var policy=await engine.policy(guildID:guild)
    if let enabled=options.first(where:{($0["name"] as? String)=="enabled"})?["value"] as? Bool { policy.enabled=enabled }
    if let sanction=value("sanction") { policy.sanction=sanction }
    if let duration=options.first(where:{($0["name"] as? String)=="timeout-minutes"})?["value"] as? Int { policy.timeoutMinutes=duration }
    if let limit=options.first(where:{($0["name"] as? String)=="messages-per-minute"})?["value"] as? Int { policy.messagesPerMinute=limit }
    if let invites=options.first(where:{($0["name"] as? String)=="block-invites"})?["value"] as? Bool { policy.blockInvites=invites }
    if let mentions=options.first(where:{($0["name"] as? String)=="block-mentions"})?["value"] as? Bool { policy.blockMassMentions=mentions }
    if let caps=options.first(where:{($0["name"] as? String)=="block-caps"})?["value"] as? Bool { policy.blockExcessiveCaps=caps }
    if let channel=value("log-channel") { policy.logChannelID=channel }
    try await engine.configure(policy,guildID:guild)
    reply="Kimi Lock · AutoMod\nStatus: "+(policy.enabled ? "Enabled":"Disabled")+"\nSanction: "+policy.sanction+"\nMessages/minute: "+String(policy.messagesPerMinute)+"\nTimeout: "+String(policy.timeoutMinutes)+" minutes\nBlocked phrases: "+String(policy.blockedPhrases.count)+"\nInvite blocking: "+(policy.blockInvites ? "On":"Off")+"\nMass mention blocking: "+(policy.blockMassMentions ? "On":"Off")+"\nExcessive caps: "+(policy.blockExcessiveCaps ? "On":"Off")
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
   case "tickets","ticket-panel","ticket-config","configure-support":
    let service=SupportService(store:store,rest:rest,logger:logger)
    if name=="tickets" {
     let category=try await service.ensureCategory(guild)
     reply="Support category ready: <#"+category+">"
    } else if name=="ticket-panel" {
     guard let channel=event["channel_id"] as? String else{throw KimiError.configuration("Run this command in a text channel.")}
     try await service.publishPanel(guild:guild,channel:channel)
     reply="Support panel published in <#"+channel+">."
    } else {
     var settings=await service.settings(guild)
     if let role=value("support-role"){settings.supportRoleID=role}
     if let channel=value("transcript-channel"){settings.transcriptChannelID=channel}
     try await service.configure(settings,guild:guild)
     reply="Support settings saved."
    }
   case "automations":
    let owner=try await rest.ownerID(guild)
    guard owner == user else { throw KimiError.configuration("Only the server owner can manage automations.") }
    let engine=AutomationEngine(store:store,rest:rest,logger:logger)
    let sub=options.first?["name"] as? String ?? "list"
    if sub=="create" {
     guard let ruleName=value("name"),let trigger=value("trigger"),let action=value("action") else{throw KimiError.configuration("Provide a name, trigger and action.")}
     let rule=try await engine.add(guildID:guild,name:ruleName,trigger:trigger,action:action)
     reply="Automation created: "+rule.name+" ("+rule.id+")."
    } else if sub=="remove" {
     guard let ruleID=value("id"),try await engine.remove(id:ruleID,guildID:guild) else{throw KimiError.configuration("Automation rule not found.")}
     reply="Automation removed."
    } else if sub=="toggle" {
     guard let ruleID=value("id"),let enabled=options.first(where:{($0["name"] as? String)=="enabled"})?["value"] as? Bool,try await engine.setEnabled(enabled,id:ruleID,guildID:guild) else{throw KimiError.configuration("Automation rule not found or invalid enabled value.")}
     reply=enabled ? "Automation enabled.":"Automation disabled."
    } else {
     let rules=await engine.rules(guildID:guild)
     if rules.isEmpty { reply="No automation rules configured. Use /automations create to add one." }
     else {
      let rows=rules.map{rule in rule.name+" · "+rule.trigger+" → "+rule.action+" · "+(rule.enabled ? "Enabled":"Disabled")+" · "+rule.id}
      reply=rows.joined(separator:"\n")
     }
    }
   case "verify","verify-config":
    let service=VerificationService(store:store,rest:rest,logger:logger)
    var settings=await service.settings(guild)
    if let role=value("role"){settings.roleID=role}
    if let channel=value("channel"){settings.channelID=channel}
    if let review=value("review-channel"){settings.reviewChannelID=review}
    if let age=options.first(where:{($0["name"] as? String)=="min-age-days"})?["value"] as? Int{settings.minimumAgeDays=age}
    try await service.configure(settings,guild:guild)
    reply="Kimi Lock verification settings saved. Minimum account age: "+String(settings.minimumAgeDays)+" days. Review channel: "+(settings.reviewChannelID ?? "not configured")
   case "roles","configure-roles":
    guard let channel=value("channel") ?? (event["channel_id"] as? String) else{throw KimiError.configuration("Choose a text channel for this role menu.")}
    let menuName=value("name") ?? "roles"
    let count=try await RolePickerService(store:store,rest:rest,logger:logger).publish(guild:guild,channel:channel,name:menuName)
    reply="Role Picker menu "+menuName+" published with "+String(count)+" safe roles in <#"+channel+">."
   case "embed-new","embed-edit","embed-post","configure-embeds":
    let service=EmbedService(store:store,rest:rest)
    guard let embedName=value("name") else{throw KimiError.configuration("Enter an embed name.")}
    if name=="embed-post" {
     guard let channel=event["channel_id"] as? String else{throw KimiError.configuration("Run this command in a text channel.")}
     try await service.publish(guild:guild,name:embedName,channel:channel)
     reply="Embed published."
    } else {
     let existing=await service.all(guild:guild).first(where:{$0.name.caseInsensitiveCompare(embedName)==ComparisonResult.orderedSame})
     let title=value("title") ?? existing?.title ?? ""
     let description=value("description") ?? existing?.description ?? ""
     var fields=existing?.fields ?? []
     let fieldName=value("field-name"),fieldValue=value("field-value")
     if fieldName != nil || fieldValue != nil {
      guard let fieldName,!fieldName.isEmpty,let fieldValue,!fieldValue.isEmpty else{throw KimiError.configuration("Provide both a field name and field value.")}
      let inline=options.first(where:{($0["name"] as? String)=="field-inline"})?["value"] as? Bool ?? false
      fields.append(EmbedService.Field(name:fieldName,value:fieldValue,inline:inline))
     }
     if let remove=options.first(where:{($0["name"] as? String)=="remove-field"})?["value"] as? Int {
      guard remove>=1,remove<=fields.count else{throw KimiError.configuration("Field number is outside the current field list.")}
      fields.remove(at:remove-1)
     }
     let saved=try await service.save(guild:guild,name:embedName,title:title,description:description,color:existing?.color ?? 8421504,footer:value("footer") ?? existing?.footer,author:value("author"),thumbnailURL:value("thumbnail"),imageURL:value("image"),url:value("url"),fields:fields)
     reply="Embed **"+saved.name+"** saved."
    }
   case "guard-review":
    guard let target=value("bot"),let decision=value("decision") else{throw KimiError.configuration("Choose an account and decision.")}
    reply=try await KimiGuardService(store:store,rest:rest,logger:logger).review(guild:guild,actor:target,decision:decision,reviewer:user)
   case "web-token":
    let owner=try await rest.ownerID(guild)
    guard owner==user else{throw KimiError.configuration("Only the server owner can open the dashboard link.")}
    guard let dashboardURL else{throw KimiError.configuration("Configure DISCORD_OAUTH_REDIRECT_URI to enable the dashboard.")}
    reply="Open the Kimi dashboard and sign in with Discord: "+dashboardURL+"/login. No email verification is used."
   case "analytics":
    let report=await AnalyticsService(store:store).report(guild:guild)
    reply="Activity report\nMessages: "+String(report.messages)+"\nCommands: "+String(report.commands)+"\nJoins: "+String(report.joins)+"\nLeaves: "+String(report.leaves)+"\nModeration: "+String(report.moderation)+"\nTickets opened: "+String(report.ticketsOpened)+"\nTickets closed: "+String(report.ticketsClosed)+"\nActive days: "+String(report.activeDays)
   default:throw KimiError.configuration("Unknown Kimi command: "+name+". Update Kimi and re-register its commands.")
   }
  } catch { reply="Kimi could not complete the action: "+error.localizedDescription;await logger.log("ERROR","Command "+name+" failed: "+error.localizedDescription) }
  do {
   if responseComponents.isEmpty{try await rest.editKimiInteraction(app,token,reply)}
   else{try await rest.editKimiInteraction(app,token,reply,responseComponents)}
  } catch { await logger.log("ERROR","Interaction response update failed: "+error.localizedDescription) }
  await AnalyticsService(store:store).record(guild:guild,event:"command")
  await performance.record(name,duration:Date().timeIntervalSince(started),success:!reply.hasPrefix("Kimi could not"))
  return true
 }
 func handleMigratedComponent(_ event:[String:Any],data:[String:Any]) async -> Bool {
  guard let id=event["id"] as? String,let token=event["token"] as? String,let app=event["application_id"] as? String else{return true}
  let guild=event["guild_id"] as? String ?? "",channel=event["channel_id"] as? String ?? ""
  let member=event["member"] as? [String:Any] ?? [:],actor=member["user"] as? [String:Any] ?? [:]
  let actorID=actor["id"] as? String ?? "",username=actor["username"] as? String ?? "member"
  let custom=data["custom_id"] as? String ?? ""
  do {
   try await rest.deferKimiInteraction(id,token)
   if let appName=ComponentRouter.app(for:custom) {
    let installed=await AppManager(store:store).installed(guildID:guild)
    guard installed.contains(appName.rawValue) else{throw KimiError.configuration(appName.rawValue+" is not installed in this server.")}
   }
   if custom=="settings:apps" {
    let installed=await AppManager(store:store).installed(guildID:guild)
    let rows=CommandCatalog.appNames().map{appName in KimiUI.row([KimiUI.button(id:"settings:app:"+appName,label:appName+" · "+(installed.contains(appName) ? "Remove":"Install"),style:installed.contains(appName) ? 2:1)])}
    try await rest.editKimiInteraction(app,token,"App Store · Manage Kimi apps for this server.",rows)
   } else if custom.hasPrefix("settings:app:") {
    let appName=String(custom.dropFirst("settings:app:".count))
    let owner=try await rest.ownerID(guild)
    guard owner==actorID else{throw KimiError.configuration("Only the server owner can install or remove apps.")}
    let manager=AppManager(store:store),installed=await manager.installed(guildID:guild)
    let result=installed.contains(appName) ? try await manager.uninstall(appName,guildID:guild):try await manager.install(appName,guildID:guild)
    guard result.ok else{throw KimiError.configuration(result.message)}
    let updated=await manager.installed(guildID:guild)
    try await rest.registerGuildCommands(app,guildID:guild,installed:updated)
    let rows=CommandCatalog.appNames().map{value in KimiUI.row([KimiUI.button(id:"settings:app:"+value,label:value+" · "+(updated.contains(value) ? "Remove":"Install"),style:updated.contains(value) ? 2:1)])}
    try await rest.editKimiInteraction(app,token,appName+" updated.",rows)
   } else if custom=="settings:status" {
    let installed=await AppManager(store:store).installed(guildID:guild)
    let policy=await ModerationEngine(store:store).policy(guildID:guild)
    let open=await SupportTickets(store:store).all().filter{$0.guildID==guild && $0.isOpen}.count
    let report=await AnalyticsService(store:store).report(guild:guild)
    let message="Kimi system status\nApps: "+(installed.isEmpty ? "None":installed.joined(separator:", "))+"\nKimi Lock: "+(installed.contains("Kimi Lock") ? (policy.enabled ? "Active":"Installed · disabled"):"Not installed")+"\nOpen Support tickets: "+String(open)+"\nMessages recorded: "+String(report.messages)
    let rows=[KimiUI.row([KimiUI.button(id:"settings:apps",label:"Manage apps"),KimiUI.button(id:"settings:home",label:"Home")])]
    try await rest.editKimiInteraction(app,token,message,rows)
   } else if custom=="settings:preferences" {
    let options=KimiLocalization.locales.prefix(25).map{["label":String((KimiLocalization.names[$0] ?? $0).prefix(100)),"value":$0]}
    let rows=[KimiUI.row([KimiUI.stringSelect(id:"settings:language",placeholder:"Select language",options:options)])]
    try await rest.editKimiInteraction(app,token,"Choose the server language.",rows)
   } else if custom=="settings:language" {
    guard let locale=(data["values"] as? [String])?.first,KimiLocalization.names[locale] != nil else{throw KimiError.configuration("Choose a supported language.")}
    var languages=await store.get("languages",as:[String:String].self) ?? [:]
    languages[guild]=locale;try await store.set(languages,key:"languages")
    try await rest.editKimiInteraction(app,token,"Server language set to "+(KimiLocalization.names[locale] ?? locale)+".")
   } else if custom=="settings:activity" {
    let entries=await logger.recent(limit:100)
    let rows=entries.filter{$0.message.contains(guild)}.suffix(12)
    let body=rows.map{ISO8601DateFormatter().string(from:$0.date)+" · "+$0.level+" · "+$0.message}.joined(separator:"\n")
    try await rest.editKimiInteraction(app,token,body.isEmpty ? "No recent activity recorded.":String(body.prefix(1800)))
   } else if custom=="settings:home" {
    let rows=[KimiUI.row([KimiUI.button(id:"settings:apps",label:"App Store"),KimiUI.button(id:"settings:status",label:"System Status")]),KimiUI.row([KimiUI.button(id:"settings:preferences",label:"Preferences"),KimiUI.button(id:"settings:activity",label:"Activity")])]
    try await rest.editKimiInteraction(app,token,"Kimi server control centre.",rows)
   } else if custom=="ticket:open" {
    let settings=await SupportService(store:store,rest:rest,logger:logger).settings(guild)
    guard settings.panelChannelID==channel else{throw KimiError.configuration("This ticket panel is no longer active.")}
    let me=try await rest.call("GET","users/@me")
    guard let bot=(me as? [String:Any])?["id"] as? String else{throw KimiError.invalidResponse}
    let ticket=try await SupportService(store:store,rest:rest,logger:logger).open(guild:guild,user:actorID,username:username,bot:bot)
    await AnalyticsService(store:store).record(guild:guild,event:"ticket_open")
    try await rest.editKimiInteraction(app,token,"Your private ticket is ready: <#"+ticket.channelID+">")
   } else if custom.hasPrefix("ticket:priority:") {
    let value=String(custom.dropFirst("ticket:priority:".count)).split(separator:":").map(String.init)
    guard value.count==2 else{throw KimiError.configuration("This priority control is invalid.")}
    let ticketID=value[0],priority=value[1]
    let tickets=await SupportTickets(store:store).all()
    guard let ticket=tickets.first(where:{$0.id==ticketID && $0.guildID==guild && $0.channelID==channel && $0.isOpen}) else{throw KimiError.configuration("This ticket is no longer open.")}
    let owner=try await rest.ownerID(guild)
    let settings=await SupportService(store:store,rest:rest,logger:logger).settings(guild)
    let roles=Set((member["roles"] as? [String]) ?? [])
    let staff=settings.supportRoleID.map{roles.contains($0)} ?? false
    guard ticket.userID==actorID || owner==actorID || staff else{throw KimiError.configuration("Only the ticket opener, support staff or server owner can change priority.")}
    let updated=try await SupportService(store:store,rest:rest,logger:logger).setPriority(guild:guild,ticketID:ticketID,priority:priority)
    try await rest.editKimiInteraction(app,token,"Ticket priority changed to "+updated.priority+".")
   } else if custom.hasPrefix("ticket:close:") {
    let ticketID=String(custom.dropFirst("ticket:close:".count))
    let tickets=await SupportTickets(store:store).all()
    guard let ticket=tickets.first(where:{$0.id==ticketID && $0.guildID==guild && $0.channelID==channel && $0.isOpen}) else{throw KimiError.configuration("This ticket control is no longer valid.")}
    let owner=try await rest.ownerID(guild)
    let supportSettings=await SupportService(store:store,rest:rest,logger:logger).settings(guild)
    let staffRoles=Set((member["roles"] as? [String]) ?? [])
    let isStaff=supportSettings.supportRoleID.map{staffRoles.contains($0)} ?? false
    guard ticket.userID==actorID || owner==actorID || isStaff else{throw KimiError.configuration("Only the ticket opener, support staff or server owner can close this ticket.")}
    let controls=[["type":1,"components":[["type":2,"style":4,"label":"Yes, close it","custom_id":"ticket:confirm-close:"+ticketID],["type":2,"style":2,"label":"Cancel","custom_id":"ticket:cancel-close"]]]] as [[String:Any]]
    _ = try await rest.call("PATCH","webhooks/\\(app)/\\(token)/messages/@original",body:["content":"Close this support ticket?","components":controls,"allowed_mentions":["parse":[]]])
   } else if custom.hasPrefix("ticket:confirm-close:") {
    let ticketID=String(custom.dropFirst("ticket:confirm-close:".count))
    let tickets=await SupportTickets(store:store).all()
    guard let ticket=tickets.first(where:{$0.id==ticketID && $0.guildID==guild && $0.channelID==channel && $0.isOpen}) else{throw KimiError.configuration("This ticket is no longer open.")}
    let owner=try await rest.ownerID(guild)
    let supportSettings=await SupportService(store:store,rest:rest,logger:logger).settings(guild)
    let staffRoles=Set((member["roles"] as? [String]) ?? [])
    let isStaff=supportSettings.supportRoleID.map{staffRoles.contains($0)} ?? false
    guard ticket.userID==actorID || owner==actorID || isStaff else{throw KimiError.configuration("Only the ticket opener, support staff or server owner can close this ticket.")}
    let closed=try await SupportService(store:store,rest:rest,logger:logger).close(guild:guild,ticketID:ticketID)
    await AnalyticsService(store:store).record(guild:guild,event:"ticket_close")
    try await rest.editKimiInteraction(app,token,"Ticket closed. Transcript retained in Kimi storage. Channel: <#"+closed.channelID+">")
   } else if custom=="ticket:cancel-close" {
    try await rest.editKimiInteraction(app,token,"Ticket remains open.")
   } else if custom=="verify:start" {
    let expected=await store.get("verification.prompt."+guild+"."+actorID,as:String.self)
    let message=(event["message"] as? [String:Any])?["id"] as? String
    guard expected==message else{throw KimiError.configuration("This verification prompt is no longer valid.")}
    await VerificationService(store:store,rest:rest,logger:logger).verify(guild:guild,userID:actorID,username:username,applicationID:app,interactionToken:token)
   } else if custom.hasPrefix("verify:approve:") || custom.hasPrefix("verify:reject:") {
    let approve=custom.hasPrefix("verify:approve:")
    let target=String(custom.dropFirst(approve ? "verify:approve:".count:"verify:reject:".count))
    await VerificationService(store:store,rest:rest,logger:logger).review(guild:guild,userID:target,decision:approve ? "approve":"reject",reviewer:actorID,applicationID:app,interactionToken:token)
   } else if custom.hasPrefix("botguard:") {
    let parts=custom.split(separator:":").map(String.init)
    guard parts.count==4,parts[2]==guild else{throw KimiError.configuration("This bot approval request is invalid.")}
    let owner=try await rest.ownerID(guild)
    guard owner==actorID else{throw KimiError.configuration("Only the server owner can approve or reject a bot.")}
    let target=parts[3]
    if parts[1]=="yes" {
     let result=try await KimiGuardService(store:store,rest:rest,logger:logger).review(guild:guild,actor:target,decision:"restore",reviewer:actorID)
     try await rest.editKimiInteraction(app,token,"Bot approved. "+result)
    } else if parts[1]=="no" {
     _ = try await KimiGuardService(store:store,rest:rest,logger:logger).review(guild:guild,actor:target,decision:"keep",reviewer:actorID)
     _ = try await rest.call("DELETE","guilds/"+guild+"/members/"+target)
     try await rest.editKimiInteraction(app,token,"Bot rejected and removed from the server. The incident remains documented.")
    } else { throw KimiError.configuration("Unknown bot approval decision.") }
   } else if custom.hasPrefix("rolepicker:select") {
    let selected=data["values"] as? [String] ?? []
    let parts=custom.split(separator:":").map(String.init)
    let menuID=parts.count>2 ? parts[2]:nil
    let count=try await RolePickerService(store:store,rest:rest,logger:logger).select(guild:guild,user:actorID,selected:selected,menuID:menuID)
    try await rest.editKimiInteraction(app,token,"Your role selection was updated. Active roles: "+String(count)+".")
   } else {
    try await rest.editKimiInteraction(app,token,"This Kimi control is unknown or expired. Reopen the panel to get a current control.")
   }
  } catch {
   try? await rest.editKimiInteraction(app,token,"Kimi could not complete this action: "+error.localizedDescription)
   await logger.log("ERROR","Component "+custom+" failed: "+error.localizedDescription)
  }
  return true
 }
 func dispatchMigratedEvent(_ name:String,_ data:[String:Any]) async {
  switch name {
  case "READY":
   if let bot=(data["user"] as? [String:Any])?["id"] as? String{try? await store.set(bot,key:"runtime.bot_id")}
   if let guilds=data["guilds"] as? [[String:Any]] {
    for item in guilds {
     guard let guild=item["id"] as? String else{continue}
     let installed=await AppManager(store:store).installed(guildID:guild)
     try? await rest.registerGuildCommands(clientID,guildID:guild,installed:installed)
    }
   }
  case "GUILD_CREATE":
   guard let guild=data["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   try? await rest.registerGuildCommands(clientID,guildID:guild,installed:installed)
  case "GUILD_MEMBER_ADD":
   guard let guild=data["guild_id"] as? String,let user=data["user"] as? [String:Any],let id=user["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Welcome") || installed.contains("Auto Role") {
    await FoundationEngine(store:store,rest:rest,logger:logger).memberJoined(guildID:guild,userID:id,username:user["username"] as? String ?? "member",serverName:"the server",memberCount:data["member_count"] as? Int ?? 0,welcomeEnabled:installed.contains("Welcome"),autoRoleEnabled:installed.contains("Auto Role"))
   }
   if installed.contains("Kimi Lock") {
    await VerificationService(store:store,rest:rest,logger:logger).memberJoined(guild:guild,userID:id,username:user["username"] as? String ?? "member")
    let snowflake=Int64(id) ?? 0
    let createdAt=Date(timeIntervalSince1970:Double((snowflake >> 22)+1_420_070_400_000)/1000)
    await RaidProtectionService(store:store,rest:rest,logger:logger).memberJoined(guild:guild,userID:id,createdAt:createdAt,isBot:user["bot"] as? Bool ?? false)
    if user["bot"] as? Bool == true {
     do {
      let owner=try await rest.ownerID(guild)
      let me=try await rest.call("GET","users/@me") as? [String:Any] ?? [:]
      guard let botID=me["id"] as? String else { throw KimiError.invalidResponse }
      let key="guard.confirmation."+guild
      var confirmation=await store.get(key,as:String.self)
      if let current=confirmation { _ = try? await rest.call("GET","channels/"+current) }
      if confirmation == nil { confirmation=try await rest.createPrivateTextChannel(guild,"kimi-confirmations",owner,botID); if let confirmation { try await store.set(confirmation,key:key) } }
      guard let confirmation else { throw KimiError.configuration("Could not create the private bot approval channel.") }
      let containment=try await KimiGuardService(store:store,rest:rest,logger:logger).contain(guild:guild,actor:id,action:"new bot joined; awaiting owner approval")
      let roles=try await rest.call("GET","guilds/"+guild+"/roles") as? [[String:Any]] ?? []
      let member=try await rest.call("GET","guilds/"+guild+"/members/"+id) as? [String:Any] ?? [:]
      let memberRoles=Set(member["roles"] as? [String] ?? [])
      let admin=roles.contains{role in memberRoles.contains(role["id"] as? String ?? "") && ((UInt64(role["permissions"] as? String ?? "") ?? 0) & 8) != 0}
      let warning=admin ? "This bot has Administrator access. Discord Administrator bypasses channel restrictions; remove that permission before approving." : "Kimi temporarily removed manageable bot roles while approval is pending."
      let controls=[["type":1,"components":[["type":2,"style":3,"label":"Approve","custom_id":"botguard:yes:"+guild+":"+id],["type":2,"style":4,"label":"Reject","custom_id":"botguard:no:"+guild+":"+id]]]] as [[String:Any]]
      _ = try await rest.call("POST","channels/"+confirmation+"/messages",body:["content":"**New bot approval required**\\nBot: <@"+id+">\\n"+warning+"\\nContainment: "+String(containment?.removedCount ?? 0)+" role(s) removed.","components":controls,"allowed_mentions":["parse":[]]])
     } catch { await logger.log("ERROR","Kimi Guard bot approval failed: "+error.localizedDescription) }
    }
   }
   await AnalyticsService(store:store).record(guild:guild,event:"join")
   await runAutomations(guild:guild,trigger:"member_join",userID:id,channelID:nil,messageID:nil,content:"")
  case "GUILD_MEMBER_REMOVE":
   guard let guild=data["guild_id"] as? String,let user=data["user"] as? [String:Any],let id=user["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Welcome"){await FoundationEngine(store:store,rest:rest,logger:logger).memberLeft(guildID:guild,userID:id,username:user["username"] as? String ?? "member",serverName:"the server")}
   await AnalyticsService(store:store).record(guild:guild,event:"leave")
   await runAutomations(guild:guild,trigger:"member_leave",userID:id,channelID:nil,messageID:nil,content:"")
  case "GUILD_MEMBER_UPDATE":
   guard let guild=data["guild_id"] as? String,let user=(data["user"] as? [String:Any])?["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){
    let key="moderation.member-snapshot."+guild+"."+user
    let previous=Set(await store.get(key,as:[String].self) ?? [])
    let roles=data["roles"] as? [String] ?? []
    try? await store.set(roles,key:key)
    if previous != Set(roles){await logger.log("INFO","Member role update recorded for "+user+" in guild "+guild)}
   }
  case "GUILD_BAN_ADD","GUILD_BAN_REMOVE":
   guard let guild=data["guild_id"] as? String,let user=(data["user"] as? [String:Any])?["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){await logger.log("INFO",(name=="GUILD_BAN_ADD" ? "Ban recorded for ":"Unban recorded for ")+user+" in guild "+guild)}
  case "MESSAGE_CREATE":
   guard let guild=data["guild_id"] as? String,let channel=data["channel_id"] as? String,let message=data["id"] as? String,let author=data["author"] as? [String:Any],let user=author["id"] as? String,(author["bot"] as? Bool != true) else{return}
   let content=data["content"] as? String ?? ""
   await AnalyticsService(store:store).record(guild:guild,event:"message")
   await runAutomations(guild:guild,trigger:"message_create",userID:user,channelID:channel,messageID:message,content:content)
   let installed=await AppManager(store:store).installed(guildID:guild)
   guard installed.contains("Kimi Lock") else{return}
   let recovery=RecoveryService(store:store,logger:logger,rest:rest)
   await recovery.captureMessage(guild,channel,message,user,content)
   let attachments=data["attachments"] as? [[String:Any]] ?? []
   await ImageAnalysisService(store:store,rest:rest,logger:logger).inspect(guild:guild,channel:channel,messageID:message,content:content,attachments:attachments)
   let owner=(try? await rest.ownerID(guild)) ?? ""
   let member=data["member"] as? [String:Any] ?? [:]
   let memberRoles=Set(member["roles"] as? [String] ?? [])
   let guildRoles=(try? await rest.call("GET","guilds/"+guild+"/roles") as? [[String:Any]]) ?? []
   let protectedMask=UInt64((1<<3)|(1<<5)|(1<<28)|(1<<29)|(1<<30)|(1<<31)|(1<<32))
   let privileged=guildRoles.contains{role in memberRoles.contains(role["id"] as? String ?? "") && ((UInt64(role["permissions"] as? String ?? "") ?? 0) & protectedMask) != 0}
   if user != owner && !privileged,let finding=await ModerationEngine(store:store).evaluate(guildID:guild,userID:user,messageID:message,content:content,channelID:channel) {
    let policy=await ModerationEngine(store:store).policy(guildID:guild)
    try? await store.set(true,key:"moderation.deleted."+message)
    try? await rest.deleteKimiMessage(channel,message)
    do {
     switch policy.sanction {
     case "timeout": try await rest.timeoutKimiMember(guild,user,policy.timeoutMinutes,finding.reason)
     case "kick": _ = try await rest.call("DELETE","guilds/"+guild+"/members/"+user,body:nil)
     case "ban": _ = try await rest.call("PUT","guilds/"+guild+"/bans/"+user,body:["delete_message_seconds":policy.actionDurationSeconds,"reason":finding.reason])
     default: break
     }
    } catch { await logger.log("ERROR","AutoMod sanction failed: "+error.localizedDescription) }
    var logChannel=policy.logChannelID
    if logChannel == nil { let setup=await store.getLegacy("timi_setup",as:[String:[String:String]].self); logChannel=setup?[guild]?["log_channel_id"] }
    if let logChannel { _ = try? await rest.call("POST","channels/"+logChannel+"/messages",body:["content":"Kimi Lock removed a message from <@"+user+"> in <#"+channel+">. Reason: "+finding.reason+". Sanction: "+policy.sanction+".","allowed_mentions":["parse":[]]]) }
    await AnalyticsService(store:store).record(guild:guild,event:"moderation")
    await logger.log("WARN","Kimi Lock moderation: "+finding.reason+"; sanction: "+policy.sanction)
   }
  case "MESSAGE_UPDATE":
   guard let guild=data["guild_id"] as? String,let channel=data["channel_id"] as? String,let message=data["id"] as? String,let author=data["author"] as? [String:Any],let user=author["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){
    let recovery=RecoveryService(store:store,logger:logger,rest:rest)
    let previous=await recovery.savedMessage(guild,channel,message)
    let updated=data["content"] as? String ?? ""
    if let previous,previous.content != updated{await logger.log("INFO","Message edit recorded in guild "+guild+", channel "+channel+", message "+message+", author "+user+". Previous length: "+String(previous.content.count)+", new length: "+String(updated.count))}
    await recovery.captureMessage(guild,channel,message,user,updated)
   }
  case "MESSAGE_DELETE":
   guard let guild=data["guild_id"] as? String,let channel=data["channel_id"] as? String,let message=data["id"] as? String else{return}
   if await store.get("moderation.deleted."+message,as:Bool.self) == true{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){await RecoveryService(store:store,logger:logger,rest:rest).restoreMessage(guild,channel,message)}
  case "MESSAGE_DELETE_BULK":
   guard let guild=data["guild_id"] as? String,let channel=data["channel_id"] as? String,let ids=data["ids"] as? [String] else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){for id in ids{if await store.get("moderation.deleted."+id,as:Bool.self) != true{await RecoveryService(store:store,logger:logger,rest:rest).restoreMessage(guild,channel,id)}}}
  case "CHANNEL_CREATE","CHANNEL_UPDATE":
   guard let guild=data["guild_id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){await RecoveryService(store:store,logger:logger,rest:rest).captureChannel(guild,data)}
  case "CHANNEL_DELETE":
   guard let guild=data["guild_id"] as? String,let channel=data["id"] as? String else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   if installed.contains("Kimi Lock"){await RecoveryService(store:store,logger:logger,rest:rest).queueDeletedChannel(guild,channel)}
  case "GUILD_AUDIT_LOG_ENTRY_CREATE":
   guard let guild=data["guild_id"] as? String,let actor=data["user_id"] as? String,let action=data["action_type"] as? Int else{return}
   let installed=await AppManager(store:store).installed(guildID:guild)
   guard installed.contains("Kimi Lock") else{return}
   do {
    if let incident=try await AuditProtection(store:store).record(guildID:guild,actorID:actor,action:String(action)){
     await logger.log("WARN","Kimi Lock incident: "+incident.reason)
     if ["12","32","50","22","20","30","10","1"].contains(incident.action){
      _ = try await KimiGuardService(store:store,rest:rest,logger:logger).contain(guild:guild,actor:actor,action:incident.action)
     }
     if incident.action=="12"{await RecoveryService(store:store,logger:logger,rest:rest).restorePendingChannels(guild)}
    }
   } catch {await logger.log("ERROR","Audit incident containment failed: "+error.localizedDescription)}
  default:break
  }
 }

}

extension KimiRuntime {
 func runAutomations(guild:String,trigger:String,userID:String,channelID:String?,messageID:String?,content:String)async {
  let engine=AutomationEngine(store:store)
  var rules=await engine.matching(guildID:guild,trigger:trigger,content:content)
  if trigger=="message_create" && !content.isEmpty{rules += await engine.matching(guildID:guild,trigger:"message_contains",content:content)}
  for rule in rules {
   let parts=rule.action.split(separator:":",maxSplits:2).map(String.init)
   guard let kind=parts.first else{continue}
   var success=true,detail="Action completed."
   do {
    switch kind {
    case "send_message":
     guard parts.count==3 else{throw KimiError.configuration("Invalid send_message action.")}
     _ = try await rest.call("POST","channels/"+parts[1]+"/messages",body:["content":String(parts[2].prefix(1900)),"allowed_mentions":["parse":[]]])
    case "delete_message":
     guard let channelID,let messageID else{throw KimiError.configuration("delete_message requires a message event.")}
     try await rest.deleteKimiMessage(channelID,messageID)
    case "timeout":
     guard parts.count>1,let minutes=Int(parts[1]) else{throw KimiError.configuration("Invalid timeout action.")}
     try await rest.timeoutKimiMember(guild,userID,minutes,"Kimi automation: "+rule.name)
    case "add_role":
     guard parts.count>1 else{throw KimiError.configuration("Invalid add_role action.")}
     _ = try await rest.call("PUT","guilds/"+guild+"/members/"+userID+"/roles/"+parts[1])
    default:throw KimiError.configuration("Unknown automation action.")
    }
   } catch {success=false;detail=error.localizedDescription;await logger.log("ERROR","Automation "+rule.id+" failed: "+detail)}
   await engine.record(.init(ruleID:rule.id,guildID:guild,trigger:trigger,success:success,detail:detail,createdAt:Date()))
  }
 }
}
