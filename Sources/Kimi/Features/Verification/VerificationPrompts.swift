import Foundation

extension VerificationService {
        func memberJoined(guild: String, userID: String, username: String) async {
            let value = await settings(guild)
            guard let channel = value.channelID else { return }
            let message: [String: Any] = [
                "content": "<@\(userID)> Please verify to access this server.",
                "components": [
                    ["type": 1, "components": [["type": 2, "style": 1, "label": "Verify", "custom_id": "verify:start"]]]
                ], "allowed_mentions": ["users": [userID], "parse": []],
            ]
            do {
                let result = try await rest.call("POST", "channels/\(channel)/messages", body: message)
                if let id = (result as? [String: Any])?["id"] as? String {
                    try await store.set(id, key: "verification.prompt." + guild + "." + userID)
                }
            } catch { await logger.log("WARN", "Verification prompt could not be posted: " + error.localizedDescription) }
        }
}
