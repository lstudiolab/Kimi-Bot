import Foundation

extension SupportService {
        func updatePanel(guild: String) async throws -> Bool {
            let value = await settings(guild)
            guard let channel = value.panelChannelID, let message = value.panelMessageID else { return false }
            _ = try await rest.call(
                "PATCH", "channels/\(channel)/messages/\(message)", body: panelBody(value))
            return true
        }

        func publishPanel(guild: String, channel: String) async throws {
            var value = await settings(guild)
            if value.panelChannelID == channel, let message = value.panelMessageID {
                do {
                    _ = try await rest.call(
                        "PATCH", "channels/\(channel)/messages/\(message)", body: panelBody(value))
                    return
                } catch KimiError.http(404, _) {
                    await logger.log("WARN", "Existing ticket panel no longer exists; publishing a replacement.")
                    value.panelMessageID = nil
                }
            }
    
            let response = try await rest.call(
                "POST", "channels/\(channel)/messages", body: panelBody(value)) as? [String: Any] ?? [:]
            guard let messageID = response["id"] as? String, !messageID.isEmpty else {
                throw KimiError.invalidResponse
            }
            value.panelChannelID = channel
            value.panelMessageID = messageID
            do {
                try await configure(value, guild: guild)
            } catch {
                _ = try? await rest.call("DELETE", "channels/\(channel)/messages/\(messageID)")
                throw error
            }
        }
}
