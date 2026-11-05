import Foundation

extension VerificationService {
        func memberJoined(guild: String, userID: String, username: String) async {
            let value = await settings(guild)
            guard let channel = value.channelID else { return }
            let message = KimiUI.panel(title: "Verify your account", description: "<@\(userID)> Please verify to access this server.", components: [KimiUI.row([KimiUI.button(id: "verify:start", label: "Verify")])]).merging(["allowed_mentions": ["users": [userID], "parse": []]]) { _, new in new }
            do {
                let result = try await rest.call("POST", "channels/\(channel)/messages", body: message)
                if let id = (result as? [String: Any])?["id"] as? String {
                    try await store.set(id, key: "verification.prompt." + guild + "." + userID)
                }
            } catch { await logger.log("WARN", "Verification prompt could not be posted: " + error.localizedDescription) }
        }
}
