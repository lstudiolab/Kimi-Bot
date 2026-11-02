import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor DiscordREST {
    private let token:String
    private let session:URLSession
    init(token:String){self.token=token;session=URLSession(configuration:.ephemeral)}
    func request(_ method:String,_ path:String,body:Any?=nil) async throws -> Any {
        var r=URLRequest(url:URL(string:"https://discord.com/api/v10/")!.appendingPathComponent(path))
        r.httpMethod=method;r.setValue("Bot \(token)",forHTTPHeaderField:"Authorization");r.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let body {r.httpBody=try JSONSerialization.data(withJSONObject:body,options:[.fragmentsAllowed])}
        let (data,response)=try await session.data(for:r)
        guard let http=response as? HTTPURLResponse else{throw URLError(.badServerResponse)}
        guard (200..<300).contains(http.statusCode) else{throw DiscordRuntimeError.http(http.statusCode,String(data:data.prefix(1000),encoding:.utf8) ?? "")}
        return data.isEmpty ? NSNull():((try? JSONSerialization.jsonObject(with:data,options:[.fragmentsAllowed])) ?? NSNull())
    }
    func register(clientID:String) async throws {
        let apps=["Welcome","Auto Role","Role Picker","Embeds","Kimi Lock","Support"]
        let option:[String:Any]=["type":3,"name":"app","description":"Choose a Kimi app","required":true,"choices":apps.map{["name":$0,"value":$0]}]
        let commands:[[String:Any]]=[
            ["name":"kimi","description":"Open Kimi control centre.","type":1],
            ["name":"apps","description":"Browse Kimi apps.","type":1],
            ["name":"setup","description":"Set up Kimi server channels.","type":1],
            ["name":"install","description":"Install a Kimi app.","type":1,"options":[option]],
            ["name":"uninstall","description":"Uninstall a Kimi app.","type":1,"options":[option]],
            ["name":"moderation","description":"Open Kimi Lock controls.","type":1],
            ["name":"ticketpanel","description":"Create the Support category.","type":1],
            ["name":"verifypanel","description":"Configure member verification.","type":1],
            ["name":"automations","description":"View automation rules.","type":1],
            ["name":"plan","description":"View server storage usage.","type":1]
        ]
        _ = try await request("PUT","applications/\(clientID)/commands",body:commands)
    }
    func respond(id:String,token:String,content:String,ephemeral:Bool=true) async throws {
        _ = try await request("POST","interactions/\(id)/\(token)/callback",body:["type":4,"data":["content":String(content.prefix(1900)),"flags":ephemeral ? 64:0,"allowed_mentions":["parse":[]]]])
    }
    func deferReply(id:String,token:String) async throws {
        _ = try await request("POST","interactions/\(id)/\(token)/callback",body:["type":5,"data":["flags":64]])
    }
    func send(channel:String,content:String) async throws {
        _ = try await request("POST","channels/\(channel)/messages",body:["content":String(content.prefix(1900)),"allowed_mentions":["parse":[]]])
    }
    func createChannel(guild:String,name:String,type:Int=0) async throws -> [String:Any] {
        try await request("POST","guilds/\(guild)/channels",body:["name":name,"type":type]) as? [String:Any] ?? [:]
    }
    func timeout(guild:String,user:String,minutes:Int) async throws {
        let until=ISO8601DateFormatter().string(from:Date().addingTimeInterval(Double(max(1,minutes))*60))
        _ = try await request("PATCH","guilds/\(guild)/members/\(user)",body:["communication_disabled_until":until])
    }
    func deleteMessage(channel:String,message:String) async throws { _ = try await request("DELETE","channels/\(channel)/messages/\(message)") }
    func kick(guild:String,user:String) async throws { _ = try await request("DELETE","guilds/\(guild)/members/\(user)") }
    func ban(guild:String,user:String) async throws { _ = try await request("PUT","guilds/\(guild)/bans/\(user)",body:["delete_message_seconds":0]) }
}
enum DiscordRuntimeError:Error,LocalizedError {case http(Int,String);var errorDescription:String?{if case .http(let c,let s)=self{return "Discord API \(c): \(s)"};return nil}}

actor DiscordGateway {
    typealias Handler=@Sendable(String,[String:Any]) async->Void
    private let token:String,logger:KimiLogger,handler:Handler
    private var socket:URLSessionWebSocketTask?,sequence:Int?,interval:Double=41,stopped=false
    init(token:String,logger:KimiLogger,handler:@escaping Handler){self.token=token;self.logger=logger;self.handler=handler}
    func run() async {
        while !stopped {
            do { try await connect() } catch { await logger.error("Gateway disconnected: \(error.localizedDescription)") }
            socket?.cancel(with:.goingAway,reason:nil)
            if !stopped { try? await Task.sleep(nanoseconds:3_000_000_000) }
        }
    }
    func stop(){stopped=true;socket?.cancel(with:.goingAway,reason:nil)}
    private func connect() async throws {
        let ws=URLSession.shared.webSocketTask(with:URL(string:"wss://gateway.discord.gg/?v=10&encoding=json")!)
        socket=ws;ws.resume()
        while !stopped {
            let message=try await ws.receive()
            let data:Data
            switch message {case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:continue}
            guard let packet=try JSONSerialization.jsonObject(with:data) as? [String:Any] else{continue}
            if let seq=packet["s"] as? Int{sequence=seq}
            let op=packet["op"] as? Int ?? -1,payload=packet["d"] as? [String:Any] ?? [:],event=packet["t"] as? String
            switch op {
            case 10:
                interval=(payload["heartbeat_interval"] as? Double ?? 41250)/1000
                try await send(["op":2,"d":["token":token,"intents":1|2|4|512|1024|32768|65536,"properties":["os":"linux","browser":"Kimi Swift","device":"Termux"]]])
                Task { await heartbeatLoop() }
            case 1:try await send(["op":1,"d":sequence as Any? ?? NSNull()])
            case 7,9:throw URLError(.networkConnectionLost)
            default:break
            }
            if let event {await handler(event,payload)}
        }
    }
    private func heartbeatLoop() async {
        while !stopped {
            try? await Task.sleep(nanoseconds:UInt64(max(1,interval)*1_000_000_000))
            if stopped{return}
            try? await send(["op":1,"d":sequence as Any? ?? NSNull()])
        }
    }
    private func send(_ object:[String:Any]) async throws {
        guard let socket else{return}
        try await socket.send(.data(JSONSerialization.data(withJSONObject:object,options:[.fragmentsAllowed])))
    }
}
