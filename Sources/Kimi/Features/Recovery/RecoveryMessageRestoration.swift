import Foundation

extension RecoveryService {
        func restoreMessage(_ guild: String, _ channel: String, _ message: String) async {
            guard let saved = await deletedMessage(guild, channel, message),
                !saved.content.isEmpty || !(saved.attachments ?? []).isEmpty
            else { return }
            let date = ISO8601DateFormatter().string(from: saved.createdAt)
            let author = saved.authorName.map { " (" + $0 + ")" } ?? ""
            let files = (saved.attachments ?? []).map { item in
                "[Attachment: " + item.name + ", " + String(item.size ?? 0) + " bytes] " + item.url
            }.joined(separator: "\n")
            let body =
                "**Recovered message** · <@\(saved.authorID)>\(author) · \(date)\n" + String(saved.content.prefix(1300))
                + (files.isEmpty ? "" : "\n" + String(files.prefix(350)))
            do {
                _ = try await rest.call(
                    "POST", "channels/\(channel)/messages",
                    body: ["content": DiscordText.prefixUTF16(body, limit: 1900), "allowed_mentions": ["parse": []]])
            } catch {
                await logger.log("ERROR", "Message recovery failed for " + message + ": " + error.localizedDescription)
            }
        }
}
