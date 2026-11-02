import DiscordBM
import Foundation

@main
struct KimiApp {
    static func main() async throws {
        let config = try AppConfig.load()
        let logger = KimiLogger(level: config.logLevel)
        let store = try JSONStore(directory: config.dataDirectory)
        let apps = AppManager(store: store, logger: logger)

        await logger.info("Starting Kimi Swift runtime.")
        await logger.info("Loaded \(await apps.available().count) app definitions.")
        await logger.info("Persistent data directory: \(config.dataDirectory.path)")

        let bot = await BotGatewayManager(
            token: config.token,
            presence: .init(status: .online),
            intents: [.guilds, .guildMembers, .guildMessages, .messageContent]
        )

        await logger.info("Connecting to the Discord Gateway.")
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await bot.connect()
            }
            group.addTask {
                for await _ in await bot.events {
                    await logger.debug("Discord Gateway event received.")
                }
            }
        }
    }
}
