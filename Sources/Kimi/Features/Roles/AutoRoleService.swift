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
                        let botRoles = roles.filter { botRoleIDs.contains($0["id"] as? String ?? "") }
                        let highest = botRoles.map { $0["position"] as? Int ?? 0 }.max() ?? 0
                        let canManage = botRoles.contains {
                            (UInt64($0["permissions"] as? String ?? "") ?? 0) & ((1 << 28) | (1 << 3)) != 0
                        }
                        guard canManage, let target = roles.first(where: { ($0["id"] as? String) == role }) else {
                            throw KimiError.configuration("Kimi cannot assign the configured automatic role.")
                        }
                        let permissions = UInt64(target["permissions"] as? String ?? "") ?? 0
                        guard SecurityPolicy.isSafeRole(
                            roleID: role, guildID: guildID, managed: target["managed"] as? Bool ?? false,
                            permissions: permissions), (target["position"] as? Int ?? 0) < highest
                        else {
                            throw KimiError.configuration("The automatic role is unsafe or above Kimi's highest role.")
                        }
                        _ = try await rest.call("PUT", "guilds/\(guildID)/members/\(userID)/roles/\(roleID)")
                    } catch {
                        await logger.log("WARN", "Auto Role failed: \(error.localizedDescription)")
                    }
                
    }
}
