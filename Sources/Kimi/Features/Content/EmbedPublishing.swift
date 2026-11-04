import Foundation

extension EmbedService {
        func publish(guild: String, name: String, channel: String) async throws {
            guard let item = await all(guild: guild).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            else { throw KimiError.configuration("Saved embed not found.") }
            var embed: [String: Any] = ["title": item.title, "description": item.description, "color": item.color]
            if let footer = item.footer { embed["footer"] = ["text": footer] }
            if let author = item.author { embed["author"] = ["name": author] }
            if let url = item.url { embed["url"] = url }
            if let image = item.imageURL { embed["image"] = ["url": image] }
            if let thumbnail = item.thumbnailURL { embed["thumbnail"] = ["url": thumbnail] }
            if let fields = item.fields, !fields.isEmpty {
                embed["fields"] = fields.map { ["name": $0.name, "value": $0.value, "inline": $0.inline] as [String: Any] }
            }
            _ = try await rest.call(
                "POST", "channels/\(channel)/messages", body: ["embeds": [embed], "allowed_mentions": ["parse": []]])
        }
}
