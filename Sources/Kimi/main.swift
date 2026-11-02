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
 let token:String;let clientID:String;let dataDirectory:URL
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
  return Configuration(token:token,clientID:id,dataDirectory:dir)
 }
}
actor PersistentStore {
 private let url:URL;private var values:[String:Data]=[:]
 init(directory:URL)throws{url=directory.appendingPathComponent("kimi.json");if let d=try? Data(contentsOf:url),let v=try? JSONDecoder().decode([String:Data].self,from:d){values=v}}
 func get<T:Decodable>(_ key:String,as type:T.Type)->T?{guard let d=values[key] else{return nil};return try? JSONDecoder().decode(type,from:d)}
 func set<T:Encodable>(_ value:T,key:String)throws{values[key]=try JSONEncoder().encode(value);try JSONEncoder().encode(values).write(to:url,options:.atomic)}
}
actor DiscordREST {
 let token:String;let session:URLSession;let base=URL(string:"https://discord.com/api/v10")!
 init(token:String){self.token=token;session=URLSession(configuration:.ephemeral)}
 func call(_ method:String,_ path:String,body:Any?=nil)async throws->Any{
  var r=URLRequest(url:base.appendingPathComponent(path));r.httpMethod=method;r.setValue("Bot \(token)",forHTTPHeaderField:"Authorization");r.setValue("application/json",forHTTPHeaderField:"Content-Type")
  if let body{r.httpBody=try JSONSerialization.data(withJSONObject:body,options:[.fragmentsAllowed])}
  let (d,response)=try await session.data(for:r);guard let h=response as? HTTPURLResponse else{throw KimiError.invalidResponse}
  guard (200..<300).contains(h.statusCode) else{throw KimiError.http(h.statusCode,String(data:d.prefix(1000),encoding:.utf8) ?? "")}
  return (try? JSONSerialization.jsonObject(with:d,options:[.fragmentsAllowed])) ?? NSNull()
 }
 func registerCommands(_ client:String)async throws{
  let definitions:[(String,String)]=[("kimi","Open Kimi control centre"),("setup","Set up Kimi in this server"),("apps","Browse Kimi apps"),("install","Install a Kimi app"),("uninstall","Uninstall a Kimi app"),("plan","View server storage usage"),("moderation","Open Kimi Lock"),("ticketpanel","Create Support category"),("verifypanel","Open verification setup"),("automations","View automation status")]
  let body=definitions.map{["name":$0.0,"description":$0.1,"type":1] as [String:Any]}
  _=try await call("PUT","applications/\(client)/commands",body:body)
 }
 func respond(_ id:String,_ token:String,_ text:String)async throws{
  _=try await call("POST","interactions/\(id)/\(token)/callback",body:["type":4,"data":["content":String(text.prefix(1900)),"flags":64,"allowed_mentions":["parse":[]]]])
 }
 func createChannel(guild:String,name:String,type:Int=0)async throws->String{
  let v=try await call("POST","guilds/\(guild)/channels",body:["name":name,"type":type])
  return (v as? [String:Any])?["id"] as? String ?? ""
 }
}
actor DiscordGateway {
 private let token:String;private let logger:Logger;private let onEvent:@Sendable([String:Any])async->Void
 private var socket:URLSessionWebSocketTask?;private var sequence:Int?;private var heartbeat:Task<Void,Never>?
 init(token:String,logger:Logger,onEvent:@escaping @Sendable([String:Any])async->Void){self.token=token;self.logger=logger;self.onEvent=onEvent}
 func run()async{
  while !Task.isCancelled{
   do{try await connect()}catch{await logger.log("ERROR","Gateway: \(error.localizedDescription)")}
   heartbeat?.cancel();socket?.cancel(with:.goingAway,reason:nil);try? await Task.sleep(nanoseconds:3_000_000_000)
  }
 }
 private func connect()async throws{
  let ws=URLSession.shared.webSocketTask(with:URL(string:"wss://gateway.discord.gg/?v=10&encoding=json")!);socket=ws;ws.resume()
  await logger.log("INFO","Discord Gateway connected.")
  while true{
   let m=try await ws.receive();let d:Data
   switch m{case .data(let x):d=x;case .string(let x):d=Data(x.utf8);@unknown default:continue}
   guard let p=try JSONSerialization.jsonObject(with:d) as? [String:Any] else{continue}
   if let s=p["s"] as? Int{sequence=s}
   let op=p["op"] as? Int ?? -1;let payload=p["d"] as? [String:Any] ?? [:]
   switch op{
   case 10:
    let interval=(payload["heartbeat_interval"] as? Double ?? 41250)/1000
    try await send(["op":2,"d":["token":token,"intents":1|2|4|512|1024|32768|65536,"properties":["os":"linux","browser":"Kimi Swift","device":"Termux"]]])
    heartbeat?.cancel();heartbeat=Task{while !Task.isCancelled{try? await Task.sleep(nanoseconds:UInt64(interval*1_000_000_000));try? await self.send(["op":1,"d":self.sequence as Any? ?? NSNull()])}}
   case 1:try await send(["op":1,"d":sequence as Any? ?? NSNull()])
   case 7,9:throw KimiError.http(0,"Gateway reconnect requested")
   default:break
   }
   if let name=p["t"] as? String{await onEvent(["name":name,"data":payload])}
  }
 }
 private func send(_ object:[String:Any])async throws{guard let socket else{return};try await socket.send(.data(JSONSerialization.data(withJSONObject:object,options:[.fragmentsAllowed])))}
}
actor KimiRuntime {
 let rest:DiscordREST;let store:PersistentStore;let logger:Logger
 init(rest:DiscordREST,store:PersistentStore,logger:Logger){self.rest=rest;self.store=store;self.logger=logger}
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
   try await rest.registerCommands(config.clientID);await logger.log("INFO","Kimi Swift started. Global commands synchronized.")
   let runtime=KimiRuntime(rest:rest,store:store,logger:logger)
   let gateway=DiscordGateway(token:config.token,logger:logger){event in
    let name=event["name"] as? String ?? "",data=event["data"] as? [String:Any] ?? [:]
    if name=="INTERACTION_CREATE"{await runtime.handle(data)}
    else{await runtime.dispatchMigratedEvent(name,data);if name=="READY"{await logger.log("INFO","Discord READY.")}}
   }
   await gateway.run()
  }catch{FileHandle.standardError.write(Data("Kimi startup failed: \(error.localizedDescription)\n".utf8));exit(1)}
 }
}
