import Foundation

actor SupportService {
 struct Settings:Codable,Sendable {var categoryID:String?;var supportRoleID:String?;var transcriptChannelID:String?;var panelChannelID:String?;var panelTitle:String="Contact Support";var panelDescription:String="Open a private ticket with the support team."}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func settings(_ guild:String)async->Settings{await store.get("support.settings."+guild,as:Settings.self) ?? Settings()}
 func configure(_ value:Settings,guild:String)async throws{try await store.set(value,key:"support.settings."+guild)}
 func ensureCategory(_ guild:String)async throws->String{
  let current=await settings(guild);if let id=current.categoryID{return id}
  let channels=try await rest.call("GET","guilds/\(guild)/channels") as? [[String:Any]] ?? []
  if let found=channels.first(where:{($0["type"] as? Int)==4 && ($0["name"] as? String)?.lowercased()=="ticket"}),let id=found["id"] as? String{
   var next=current;next.categoryID=id;try await configure(next,guild:guild);return id
  }
  let created=try await rest.call("POST","guilds/\(guild)/channels",body:["name":"ticket","type":4])
  guard let id=(created as? [String:Any])?["id"] as? String else{throw KimiError.invalidResponse}
  var next=current;next.categoryID=id;try await configure(next,guild:guild);return id
 }
 func publishPanel(guild:String,channel:String)async throws{
  let value=await settings(guild)
  let components=[["type":1,"components":[["type":2,"style":1,"label":"Open Ticket","custom_id":"ticket:open"]]]] as [[String:Any]]
  _=try await rest.call("POST","channels/\(channel)/messages",body:["content":"**\(value.panelTitle)**\n\(value.panelDescription)","components":components,"allowed_mentions":["parse":[]]])
  var next=value;next.panelChannelID=channel;try await configure(next,guild:guild)
 }
 func open(guild:String,user:String,username:String,bot:String)async throws->SupportTickets.Ticket{
  let category=try await ensureCategory(guild),value=await settings(guild)
  var overwrites:[[String:Any]]=[
   ["id":guild,"type":0,"deny":"1024"],
   ["id":user,"type":1,"allow":"68608"],
   ["id":bot,"type":1,"allow":"68608"]
  ]
  if let role=value.supportRoleID{overwrites.append(["id":role,"type":0,"allow":"68608"])}
  let name=SecurityPolicy.channelName("ticket-"+username)
  let created=try await rest.call("POST","guilds/\(guild)/channels",body:["name":name,"type":0,"parent_id":category,"permission_overwrites":overwrites])
  guard let channel=(created as? [String:Any])?["id"] as? String else{throw KimiError.invalidResponse}
  let ticket=try await SupportTickets(store:store).open(guildID:guild,userID:user,channelID:channel)
  let controls=[["type":1,"components":[["type":2,"style":4,"label":"Close Ticket","custom_id":"ticket:close:"+ticket.id]]]] as [[String:Any]]
  _=try await rest.call("POST","channels/\(channel)/messages",body:["content":"Support ticket opened for <@\(user)>. A staff member will respond here.","components":controls,"allowed_mentions":["users":[user],"parse":[]]])
  await logger.log("INFO","Support ticket opened: "+ticket.id+" in guild "+guild)
  return ticket
 }
 func close(guild:String,ticketID:String)async throws->SupportTickets.Ticket{
  let ticket=try await SupportTickets(store:store).close(id:ticketID,guildID:guild)
  _=try await rest.call("PATCH","channels/\(ticket.channelID)",body:["name":SecurityPolicy.channelName("closed-"+ticket.channelID.suffix(8))])
  let history=try await rest.call("GET","channels/\(ticket.channelID)/messages?limit=100") as? [[String:Any]] ?? []
  let transcript=history.reversed().map{item in
   let author=(item["author"] as? [String:Any])?["username"] as? String ?? "Unknown"
   let body=item["content"] as? String ?? ""
   return author+": "+body
  }.joined(separator:"\n")
  try await store.set(String(transcript.suffix(100_000)),key:"support.transcript."+ticketID)
  let settings=await self.settings(guild)
  if let destination=settings.transcriptChannelID{
   let summary="Ticket transcript saved for ticket "+ticketID+". Messages captured: "+String(history.count)+"."
   _=try? await rest.call("POST","channels/\(destination)/messages",body:["content":summary,"allowed_mentions":["parse":[]]])
  }
  await logger.log("INFO","Support ticket closed: "+ticketID)
  return ticket
 }
}
