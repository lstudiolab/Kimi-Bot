import Foundation

extension VerificationService {
        func review(
            guild: String, userID: String, decision: String, reviewer: String, applicationID: String,
            interactionToken: String
        ) async {
            do {
                let owner = try await rest.ownerID(guild)
                guard owner == reviewer else {
                    throw KimiError.configuration("Only the server owner can decide this review.")
                }
                guard decision == "approve" || decision == "reject" else {
                    throw KimiError.configuration("Choose approve or reject.")
                }
                let value = await settings(guild)
                let records = VerificationRecords(store: store)
                let pending = await records.record(guildID: guild, userID: userID)
                guard pending.verifiedAt == nil, pending.reviewMessageID != nil else {
                    throw KimiError.configuration("This verification review is no longer pending.")
                }
                if decision == "approve" {
                    if let role = value.roleID {
                        let roles = try await rest.call("GET", "guilds/" + guild + "/roles") as? [[String: Any]] ?? []
                        let bot = try await rest.call("GET", "guilds/" + guild + "/members/@me") as? [String: Any] ?? [:]
                        let botIDs = Set(bot["roles"] as? [String] ?? [])
                        let highest =
                            roles.filter { botIDs.contains($0["id"] as? String ?? "") }.map { $0["position"] as? Int ?? 0 }
                            .max() ?? 0
                        let canManage = roles.contains {
                            botIDs.contains($0["id"] as? String ?? "")
                                && ((UInt64($0["permissions"] as? String ?? "") ?? 0) & 268_435_464 != 0)
                        }
                        guard let target = roles.first(where: { ($0["id"] as? String) == role }) else {
                            throw KimiError.configuration("The verified role no longer exists.")
                        }
                        let permissions = UInt64(target["permissions"] as? String ?? "") ?? 0
                        guard canManage,
                            SecurityPolicy.isSafeRole(
                                roleID: role, guildID: guild, managed: target["managed"] as? Bool ?? false,
                                permissions: permissions), (target["position"] as? Int ?? 0) < highest
                        else { throw KimiError.configuration("The verified role is unsafe or above Kimi's highest role.") }
                        _ = try await rest.call("PUT", "guilds/" + guild + "/members/" + userID + "/roles/" + role)
                    }
                    try await records.markVerified(guildID: guild, userID: userID)
                    try await rest.editKimiInteraction(applicationID, interactionToken, "Member approved and verified.")
                } else if decision == "reject" {
                    try await records.markFailed(
                        guildID: guild, userID: userID, reason: "Rejected by server owner during verification review.")
                    _ = try await rest.call("DELETE", "guilds/" + guild + "/members/" + userID)
                    try await rest.editKimiInteraction(
                        applicationID, interactionToken, "Member rejected and removed from the server.")
                } else {
                    throw KimiError.configuration("Choose approve or reject.")
                }
            } catch {
                try? await rest.editKimiInteraction(
                    applicationID, interactionToken, "Verification review failed: " + error.localizedDescription)
            }
        }
}
