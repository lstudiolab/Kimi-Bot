import Foundation
actor InteractionRouter {
    private let rest:DiscordREST,store:JSONStore,apps:AppManager,logger:KimiLogger
    init(rest:DiscordREST,store:JSONStore,apps:AppManager,logger:KimiLogger){self.rest=rest;self.store=store;self.apps=apps;self.logger=logger}
    func handle(_ interaction:[String:Any]) async {
        guard let id=interaction["id"] as? String,let token=interaction["token"] as? String else{return}
        let data=interaction["data"] as? [String:Any] ?? [:],name=data["name"] as? String ?? ""
        let guild=interaction["guild_id"] as? String ?? "",channel=interaction["channel_id"] as? String ?? ""
        let options=data["options"] as? [[String:Any]] ?? []
        let app=options.first(where:{$0["name"] as? String=="app"})?["value"] as? String ?? ""
        do {
            switch name {
            case "kimi":
                let installed=await apps.installed(in:guild)
                try await rest.respond(id:id,token:token,content:"**Kimi Control Centre**\nInstalled apps: \(installed.isEmpty ? "None":installed.joined(separator:", "))")
            case "apps":
                let content=await apps.available().map{"**\($0.name)** — \($0.description)\nSystems: \($0.systems.joined(separator:", "))\nHelpers: \($0.helpers.joined(separator:", "))"}.joined(separator:"\n\n")
                try await rest.respond(id:id,token:token,content:content)
            case "install":
                let result=try await apps.install(app,in:guild)
                switch result {case .success(let item):try await rest.respond(id:id,token:token,content:"**\(item.name)** installed.");case .failure(let error):try await rest.respond(id:id,token:token,content:"Install failed: \(error)")}
            case "uninstall":
                let result=try await apps.uninstall(app,from:guild)
                switch result {case .success(let item):try await rest.respond(id:id,token:token,content:"**\(item.name)** removed. Configuration preserved.");case .failure(let error):try await rest.respond(id:id,token:token,content:"Uninstall failed: \(error)")}
            case "setup":
                try await rest.deferReply(id:id,token:token)
                _=try await rest.createChannel(guild:guild,name:"kimi-logs")
                _=try await rest.createChannel(guild:guild,name:"kimi-control")
                _=try await rest.createChannel(guild:guild,name:"ticket",type:4)
                try await rest.send(channel:channel,content:"Kimi created its initial channels. Restrict kimi-logs and kimi-control permissions before storing sensitive audit data.")
            case "moderation":try await rest.respond(id:id,token:token,content:"**Kimi Lock**\nThe Swift moderation engine is available. Review policy settings before enabling automatic sanctions.")
            case "ticketpanel":
                let category=try await rest.createChannel(guild:guild,name:"ticket",type:4)
                try await rest.respond(id:id,token:token,content:"Support category created: \(category["name"] as? String ?? "ticket").")
            case "verifypanel":try await rest.respond(id:id,token:token,content:"Verification scoring is available. Configure account-age and review settings before publishing.")
            case "automations":try await rest.respond(id:id,token:token,content:"Automation rule storage is ready.")
            case "plan":
                let bytes=(try? JSONEncoder().encode(await store.snapshot()).count) ?? 0
                try await rest.respond(id:id,token:token,content:"Kimi Free storage: \(bytes) bytes / 5 MB.")
            default:try await rest.respond(id:id,token:token,content:"This command is not available in the current Swift runtime.")
            }
        } catch {
            await logger.error("Interaction /\(name) failed: \(error.localizedDescription)")
            try? await rest.respond(id:id,token:token,content:"Kimi could not complete that action. The error was recorded.")
        }
    }
}
