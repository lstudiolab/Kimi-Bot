import Foundation

extension DiscordREST {
    func registerGuildCommands(_ clientID: String, guildID: String, installed: [String]) async throws {
        _ = try await call(
            "PUT", "applications/\(clientID)/guilds/\(guildID)/commands",
            body: CommandCatalog.guildCommands(installed: installed))
    }
    func ownerID(_ guildID: String) async throws -> String {
        let data = try await call("GET", "guilds/\(guildID)")
        guard let id = (data as? [String: Any])?["owner_id"] as? String else { throw KimiError.invalidResponse }
        return id
    }
    func createPrivateTextChannel(
        _ guildID: String, _ name: String, _ ownerID: String, _ botID: String, _ parentID: String? = nil
    ) async throws -> String {
        var body: [String: Any] = [
            "name": SecurityPolicy.channelName(name), "type": 0,
            "permission_overwrites": [
                ["id": guildID, "type": 0, "deny": "1024"],
                ["id": ownerID, "type": 1, "allow": "68608"],
                ["id": botID, "type": 1, "allow": "68608"],
            ],
        ]
        if let parentID { body["parent_id"] = parentID }
        let data = try await call("POST", "guilds/\(guildID)/channels", body: body)
        guard let id = (data as? [String: Any])?["id"] as? String else { throw KimiError.invalidResponse }
        return id
    }
    func respondKimiModal(
        _ id: String, _ token: String, customID: String, title: String, inputs: [[String: Any]]
    ) async throws {
        _ = try await call(
            "POST",
            "interactions/\(id)/\(token)/callback",
            body: ["type": 9, "data": KimiUI.modal(id: customID, title: title, inputs: inputs)]
        )
    }
    func deferKimiInteraction(_ id: String, _ token: String) async throws {
        _ = try await call("POST", "interactions/\(id)/\(token)/callback", body: ["type": 5, "data": ["flags": 64]])
    }
    func editKimiInteraction(_ app: String, _ token: String, _ content: String) async throws {
        _ = try await call(
            "PATCH", "webhooks/\(app)/\(token)/messages/@original",
            body: ["content": DiscordText.prefixUTF16(content, limit: 1900), "allowed_mentions": ["parse": []]])
    }
    func editKimiInteraction(_ app: String, _ token: String, _ content: String, _ components: [[String: Any]])
        async throws
    {
        _ = try await call(
            "PATCH", "webhooks/\(app)/\(token)/messages/@original",
            body: [
                "content": String(content.prefix(1900)), "components": components, "allowed_mentions": ["parse": []],
            ])
    }
    func deleteKimiMessage(_ channel: String, _ message: String) async throws {
        _ = try await call("DELETE", "channels/\(channel)/messages/\(message)")
    }
    func timeoutKimiMember(_ guild: String, _ user: String, _ minutes: Int, _ reason: String) async throws {
        let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(max(1, minutes)) * 60))
        _ = try await call(
            "PATCH", "guilds/\(guild)/members/\(user)", body: ["communication_disabled_until": until],
            auditReason: DiscordText.prefixUTF16(reason, limit: 400))
    }
}
