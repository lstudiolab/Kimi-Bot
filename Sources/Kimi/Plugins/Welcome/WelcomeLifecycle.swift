import Foundation

extension FoundationEngine {
        func memberJoined(
            guildID: String, userID: String, username: String, serverName: String, memberCount: Int,
            welcomeEnabled: Bool = true, autoRoleEnabled: Bool = true
        ) async {
            let value = await settings(guildID: guildID)
            if autoRoleEnabled, let role = value.autoRole {
                await AutoRoleService(rest: rest, logger: logger).assign(
                    guildID: guildID, userID: userID, roleID: role)
            }
            if welcomeEnabled, let channel = value.welcomeChannel {
                let body = value.welcomeMessage.replacingOccurrences(of: "{user}", with: "<@\(userID)>")
                    .replacingOccurrences(of: "{username}", with: username).replacingOccurrences(
                        of: "{server}", with: serverName
                    ).replacingOccurrences(of: "{member_count}", with: String(memberCount))
                do {
                    _ = try await rest.call(
                        "POST", "channels/\(channel)/messages",
                        body: KimiUI.panel(title: "Welcome", description: body).merging(["allowed_mentions": ["users": [userID], "parse": []]]) { _, new in new })
                } catch { await logger.log("WARN", "Welcome message failed: \(error.localizedDescription)") }
            }
        }
        func memberLeft(guildID: String, userID: String, username: String, serverName: String) async {
            let value = await settings(guildID: guildID)
            guard let channel = value.goodbyeChannel else { return }
            let body = value.goodbyeMessage.replacingOccurrences(of: "{user}", with: "<@\(userID)>").replacingOccurrences(
                of: "{username}", with: username
            ).replacingOccurrences(of: "{server}", with: serverName)
            do {
                _ = try await rest.call(
                    "POST", "channels/\(channel)/messages",
                    body: KimiUI.panel(title: "Goodbye", description: body))
            } catch { await logger.log("WARN", "Goodbye message failed: \(error.localizedDescription)") }
        }
}
