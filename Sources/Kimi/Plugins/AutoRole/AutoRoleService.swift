import Foundation

actor AutoRoleService {
    private let rest: DiscordREST
    private let logger: Logger

    init(rest: DiscordREST, logger: Logger) {
        self.rest = rest
        self.logger = logger
    }

    func assign(guildID: String, userID: String, roleID: String) async {
        do {
            let roles = try await rest.call("GET", "guilds/\(guildID)/roles") as? [[String: Any]] ?? []
            let bot = try await rest.call("GET", "guilds/\(guildID)/members/@me") as? [String: Any] ?? [:]
            let botRoleIDs = Set(bot["roles"] as? [String] ?? [])
            try AutoRolePolicy.validate(
                guildID: guildID, roleID: roleID, roles: roles, botRoleIDs: botRoleIDs)
            _ = try await rest.call("PUT", "guilds/\(guildID)/members/\(userID)/roles/\(roleID)")
        } catch {
            await logger.log("WARN", "Auto Role failed: \(error.localizedDescription)")
        }
    }
}
