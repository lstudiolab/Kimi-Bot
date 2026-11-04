import Foundation

enum AutoRolePolicy {
    static func validate(
        guildID: String,
        roleID: String,
        roles: [[String: Any]],
        botRoleIDs: Set<String>
    ) throws {
        let botRoles = roles.filter { botRoleIDs.contains($0["id"] as? String ?? "") }
        let highestPosition = botRoles.map { $0["position"] as? Int ?? 0 }.max() ?? 0
        let canManageRoles = botRoles.contains {
            (UInt64($0["permissions"] as? String ?? "") ?? 0) & ((1 << 28) | (1 << 3)) != 0
        }
        guard canManageRoles,
            let target = roles.first(where: { ($0["id"] as? String) == roleID })
        else {
            throw KimiError.configuration("Kimi cannot assign the configured automatic role.")
        }

        let permissions = UInt64(target["permissions"] as? String ?? "") ?? 0
        let safe = SecurityPolicy.isSafeRole(
            roleID: roleID,
            guildID: guildID,
            managed: target["managed"] as? Bool ?? false,
            permissions: permissions
        )
        let targetPosition = target["position"] as? Int ?? 0
        guard safe, targetPosition < highestPosition else {
            throw KimiError.configuration("The automatic role is unsafe or above Kimi's highest role.")
        }
    }
}
