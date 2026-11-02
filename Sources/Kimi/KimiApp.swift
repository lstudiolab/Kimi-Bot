import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct KimiApp {
    static func main() async throws {
        let config=try AppConfig.load()
        let logger=KimiLogger(level:config.logLevel)
        let store=try JSONStore(directory:config.dataDirectory)
        let apps=AppManager(store:store,logger:logger)
        let rest=DiscordREST(token:config.token)
        let router=InteractionRouter(rest:rest,store:store,apps:apps,logger:logger)
        try await rest.register(clientID:config.clientID)
        await logger.info("Global Kimi slash commands synchronized.")
        await logger.info("Loaded \(await apps.available().count) app definitions.")
        let gateway=DiscordGateway(token:config.token,logger:logger){event,data in
            if event=="INTERACTION_CREATE"{await router.handle(data)}
            if event=="READY"{await logger.info("Kimi connected to Discord Gateway.")}
            if event=="MESSAGE_CREATE",let guild=data["guild_id"] as? String,
               let user=(data["author"] as? [String:Any])?["id"] as? String,
               let bot=(data["author"] as? [String:Any])?["bot"] as? Bool,bot==false {
                await logger.debug("Message event received from \(user) in \(guild).")
            }
        }
        await logger.info("Starting Kimi Swift runtime.")
        await gateway.run()
    }
}
