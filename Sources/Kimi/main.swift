import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum KimiError: Error, LocalizedError {
 case configuration(String), invalidResponse, http(Int,String)
 var errorDescription:String? { switch self {case .configuration(let s):return s;case .invalidResponse:return "Invalid Discord response";case .http(let c,let s):return "Discord HTTP \(c): \(s)"} }
}
actor Logger {
 func log(_ level:String,_ message:String) { let line="[\(ISO8601DateFormatter().string(from:Date()))] [\(level)] \(message)\n"; FileHandle.standardOutput.write(Data(line.utf8)) }
}
struct Configuration {
 let token:String;let clientID:String;let dataDirectory:URL;let dashboardPort:Int;let dashboardHost:String;let oauthSecret:String;let oauthRedirectURI:String
 static func load() throws -> Configuration {
  let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
  var env:[String:String]=[:]
  if let text=try? String(contentsOf:root.appendingPathComponent(".env"),encoding:.utf8) {
   for raw in text.components(separatedBy:.newlines) { let line=raw.trimmingCharacters(in:.whitespaces); if line.isEmpty || line.hasPrefix("#"){continue};let p=line.split(separator:"=",maxSplits:1).map(String.init);if p.count==2{env[p[0].trimmingCharacters(in:.whitespaces)]=p[1].trimmingCharacters(in:.whitespaces).trimmingCharacters(in:CharacterSet(charactersIn:"\"'"))} }
  }
  func get(_ key:String)->String {ProcessInfo.processInfo.environment[key] ?? env[key] ?? ""}
  let token=get("DISCORD_TOKEN"),id=get("CLIENT_ID")
  guard !token.isEmpty else{throw KimiError.configuration("DISCORD_TOKEN is missing from .env")}
  guard id.range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil else{throw KimiError.configuration("CLIENT_ID is invalid")}
  let dir=root.appendingPathComponent(get("DATA_DIR").isEmpty ? "data":get("DATA_DIR"),isDirectory:true)
  try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  let port=Int(get("DASHBOARD_PORT")) ?? 8787
  return Configuration(token:token,clientID:id,dataDirectory:dir,dashboardPort:max(1024,min(65535,port)),dashboardHost:get("DASHBOARD_HOST").isEmpty ? "127.0.0.1":get("DASHBOARD_HOST"),oauthSecret:get("DISCORD_OAUTH_CLIENT_SECRET"),oauthRedirectURI:get("DISCORD_OAUTH_REDIRECT_URI"))
 }
}
actor PersistentStore {
 private let url:URL
 private var values:[String:Data]=[:]
 private var legacy:[String:Any]=[:]
 init(directory:URL)throws{
  url=directory.appendingPathComponent("timi.json")
  if let data=try? Data(contentsOf:url),let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
   legacy=root.filter{$0.key != "_swift_runtime"}
   if let runtime=root["_swift_runtime"],let runtimeData=try? JSONSerialization.data(withJSONObject:runtime),let decoded=try? JSONDecoder().decode([String:Data].self,from:runtimeData){values=decoded}
   if let installed=legacy["installed_plugins"],let bytes=try? JSONSerialization.data(withJSONObject:installed){values["apps.installed"]=bytes}
  }
 }
 func get<T:Decodable>(_ key:String,as type:T.Type)->T?{
  guard let data=values[key] else{return nil}
  return try? JSONDecoder().decode(type,from:data)
 }
 func getLegacy<T:Decodable>(_ key:String,as type:T.Type)->T?{
  guard let value=legacy[key],let data=try? JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]) else{return nil}
  return try? JSONDecoder().decode(type,from:data)
 }
 func set<T:Encodable>(_ value:T,key:String)throws{
  values[key]=try JSONEncoder().encode(value)
  var root=legacy
  let runtime=try JSONEncoder().encode(values)
  root["_swift_runtime"]=try JSONSerialization.jsonObject(with:runtime)
  let data=try JSONSerialization.data(withJSONObject:root,options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed])
  try data.write(to:url,options:.atomic)
 }
}
actor DiscordREST {
 let token:String;let session:URLSession;let base=URL(string:"https://discord.com/api/v10/")!
 init(token:String){self.token=token;session=URLSession(configuration:.ephemeral)}
 func call(_ method:String,_ path:String,body:Any?=nil,auditReason:String?=nil)async throws->Any{
  guard let url=URL(string:path,relativeTo:base)?.absoluteURL else{throw KimiError.invalidResponse}
  var request=URLRequest(url:url);request.httpMethod=method
  request.setValue("Bot "+token,forHTTPHeaderField:"Authorization")
  request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  if let auditReason{request.setValue(auditReason.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? auditReason,forHTTPHeaderField:"X-Audit-Log-Reason")}
  if let body{request.httpBody=try JSONSerialization.data(withJSONObject:body,options:[.fragmentsAllowed])}
  var attempt=0
  while true{
   let (data,response)=try await session.data(for:request)
   guard let http=response as? HTTPURLResponse else{throw KimiError.invalidResponse}
   if http.statusCode==429 && attempt<4{
    attempt+=1
    let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
    let delay=object?["retry_after"] as? Double ?? Double(http.value(forHTTPHeaderField:"Retry-After") ?? "1") ?? 1
    try await Task.sleep(nanoseconds:UInt64(max(0.25,min(30,delay))*1_000_000_000));continue
   }
   if (500...599).contains(http.statusCode) && attempt<3{
    attempt+=1;try await Task.sleep(nanoseconds:UInt64(pow(2.0,Double(attempt))*500_000_000));continue
   }
   guard (200..<300).contains(http.statusCode) else{throw KimiError.http(http.statusCode,String(data:data.prefix(1000),encoding:.utf8) ?? "")}
   return (try? JSONSerialization.jsonObject(with:data,options:[.fragmentsAllowed])) ?? NSNull()
  }
 }
 func registerCommands(_ client:String)async throws{_ = try await call("PUT","applications/\(client)/commands",body:CommandCatalog.globalCommands())}
 func respond(_ id:String,_ token:String,_ text:String)async throws{_ = try await call("POST","interactions/\(id)/\(token)/callback",body:["type":4,"data":["content":String(text.prefix(1900)),"flags":64,"allowed_mentions":["parse":[]]]])}
 func createChannel(guild:String,name:String,type:Int=0)async throws->String{
  let value=try await call("POST","guilds/\(guild)/channels",body:["name":name,"type":type])
  return (value as? [String:Any])?["id"] as? String ?? ""
 }
}
actor DiscordGateway {
 private let token:String;private let logger:Logger;private let onEvent:@Sendable([String:Any])async->Void
 private var socket:URLSessionWebSocketTask?;private var sequence:Int?;private var sessionID:String?;private var resumeURL:String?
 private var heartbeat:Task<Void,Never>?;private var heartbeatInterval:Double=41.25;private var awaitingHeartbeatAck=false
 private var reconnectDelay:UInt64=2_000_000_000
 init(token:String,logger:Logger,onEvent:@escaping @Sendable([String:Any])async->Void){self.token=token;self.logger=logger;self.onEvent=onEvent}
 func run()async{
  while !Task.isCancelled{
   do{try await connect();reconnectDelay=2_000_000_000}
   catch{await logger.log("ERROR","Discord Gateway: "+error.localizedDescription)}
   heartbeat?.cancel();heartbeat=nil;awaitingHeartbeatAck=false;socket?.cancel(with:.goingAway,reason:nil);socket=nil
   try? await Task.sleep(nanoseconds:reconnectDelay);reconnectDelay=min(reconnectDelay*2,30_000_000_000)
  }
 }
 private func connect()async throws{
  let endpoint=resumeURL.map{$0.contains("?") ? $0 : $0+"?v=10&encoding=json"} ?? "wss://gateway.discord.gg/?v=10&encoding=json"
  guard let url=URL(string:endpoint) else{throw KimiError.invalidResponse}
  let ws=URLSession.shared.webSocketTask(with:url);socket=ws;ws.resume()
  await logger.log("INFO","Discord Gateway socket connected.")
  while true{
   let message=try await ws.receive();let data:Data
   switch message{case .data(let value):data=value;case .string(let value):data=Data(value.utf8);@unknown default:continue}
   guard let packet=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{continue}
   if let value=packet["s"] as? Int{sequence=value}
   let opcode=packet["op"] as? Int ?? -1
   let payload=packet["d"] as? [String:Any] ?? [:]
   switch opcode{
   case 10:
    heartbeatInterval=(payload["heartbeat_interval"] as? Double ?? 41250)/1000
    if let sessionID,let sequence{
     try await send(["op":6,"d":["token":token,"session_id":sessionID,"seq":sequence]])
     await logger.log("INFO","Resuming Discord Gateway session.")
    }else{
     let intents=1|2|4|512|1024|32768|65536
     try await send(["op":2,"d":["token":token,"intents":intents,"properties":["os":"linux","browser":"Kimi Swift","device":"Termux"]]])
    }
    heartbeat?.cancel()
    heartbeat=Task{while !Task.isCancelled{
     try? await Task.sleep(nanoseconds:UInt64(max(1,self.heartbeatInterval)*1_000_000_000))
     if Task.isCancelled{return}
     await self.heartbeatTick()
    }}
   case 1:
    await heartbeatTick()
   case 7:
    throw KimiError.http(0,"Gateway requested reconnect.")
   case 9:
    let resumable=payload["d"] as? Bool ?? false
    if !resumable{sessionID=nil;sequence=nil;resumeURL=nil}
    try? await Task.sleep(nanoseconds:UInt64.random(in:1_000_000_000...5_000_000_000))
    throw KimiError.http(0,"Gateway invalidated the session.")
   case 11:
    awaitingHeartbeatAck=false
   default:break
   }
   if let name=packet["t"] as? String{
    if name=="READY"{
     sessionID=payload["session_id"] as? String
     resumeURL=payload["resume_gateway_url"] as? String
    }
    if name=="RESUMED"{await logger.log("INFO","Discord Gateway session resumed.")}
    await onEvent(["name":name,"data":payload])
   }
  }
 }
 private func heartbeatTick()async{
  if awaitingHeartbeatAck{socket?.cancel(with:.goingAway,reason:Data("Heartbeat acknowledgement timed out".utf8));return}
  awaitingHeartbeatAck=true
  do{try await send(["op":1,"d":sequence as Any? ?? NSNull()])}
  catch{socket?.cancel(with:.goingAway,reason:nil)}
 }
 private func send(_ object:[String:Any])async throws{
  guard let socket else{throw KimiError.invalidResponse}
  try await socket.send(.data(JSONSerialization.data(withJSONObject:object,options:[.fragmentsAllowed])))
 }
}
actor KimiRuntime {
 let rest:DiscordREST;let store:PersistentStore;let logger:Logger;let clientID:String
 init(rest:DiscordREST,store:PersistentStore,logger:Logger,clientID:String){self.rest=rest;self.store=store;self.logger=logger;self.clientID=clientID}
 func handle(_ event:[String:Any])async{
  if await handleMigratedCommand(event){return}
  guard let id=event["id"] as? String,let token=event["token"] as? String else{return}
  let data=event["data"] as? [String:Any] ?? [:];let name=data["name"] as? String ?? "";let guild=event["guild_id"] as? String ?? ""
  do{
   let message:String
   switch name{
   case "kimi":message="**Kimi**\nSwift runtime is online. Use /apps to view the available apps."
   case "apps":message="**Kimi Apps**\nFoundation — server setup and configuration\nKimi Lock — security and moderation\nSupport — tickets and staff workflows"
   case "setup":let channel=try await rest.createChannel(guild:guild,name:"kimi-logs");message="Created Kimi log channel (\(channel)). Restrict access to administrators and Kimi staff."
   case "moderation":message="**Kimi Lock**\nThe security module is online. Configure policies before enabling automated sanctions."
   case "ticketpanel":let channel=try await rest.createChannel(guild:guild,name:"ticket",type:4);message="Created Support category (\(channel))."
   case "plan":message="**Kimi Free**\nPersistent server data is stored locally in the Kimi data directory."
   case "verifypanel":message="Verification engine is available. Configure account-age and review policies before publishing a panel."
   case "automations":message="Automation engine is online. Rule execution adapters are not yet enabled."
   default:message="This command is not available in this Swift build."
   }
   try await rest.respond(id,token,message);await logger.log("INFO","Handled /\(name)")
  }catch{await logger.log("ERROR","/\(name): \(error.localizedDescription)");try? await rest.respond(id,token,"Kimi could not complete that action. The error was recorded.")}
 }
}
@main struct KimiApp {
 static func main()async{
  do{
   let config=try Configuration.load(),logger=Logger(),store=try PersistentStore(directory:config.dataDirectory),rest=DiscordREST(token:config.token)
   DashboardServer(config:config,rest:rest,store:store,logger:logger).start()
   try await rest.registerCommands(config.clientID);await logger.log("INFO","Kimi Swift started. Global commands synchronized.")
   let runtime=KimiRuntime(rest:rest,store:store,logger:logger,clientID:config.clientID)
   let gateway=DiscordGateway(token:config.token,logger:logger){event in
    let name=event["name"] as? String ?? "",data=event["data"] as? [String:Any] ?? [:]
    if name=="INTERACTION_CREATE"{await runtime.handle(data)}
    else{await runtime.dispatchMigratedEvent(name,data);if name=="READY"{await logger.log("INFO","Discord READY.")}}
   }
   await gateway.run()
  }catch{FileHandle.standardError.write(Data("Kimi startup failed: \(error.localizedDescription)\n".utf8));exit(1)}
 }
}
