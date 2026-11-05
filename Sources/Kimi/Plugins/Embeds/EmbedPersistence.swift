import Foundation

extension EmbedService {
        func save(
            guild: String, name: String, title: String, description: String, color _: Int = KimiUI.grey, footer: String? = nil,
            author: String? = nil, thumbnailURL: String? = nil, imageURL: String? = nil, url: String? = nil,
            fields: [Field]? = nil
        ) async throws -> Saved {
            guard !name.isEmpty, name.count <= 24 else {
                throw KimiError.configuration("Embed names must be 1–24 characters.")
            }
            var data = await store.get("embeds.saved", as: [String: [Saved]].self) ?? [:]
            var list = data[guild] ?? []
            let existing = list.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            let nextFields = fields ?? existing?.fields ?? []
            let validationFields = nextFields.map { EmbedValidator.Field(name: $0.name, value: $0.value) }
            let validator = EmbedValidator()
            let errors = validator.validate(
                .init(
                    title: title, description: description, fields: validationFields, color: KimiUI.grey,
                    author: author ?? existing?.author, footer: footer ?? existing?.footer,
                    url: url ?? existing?.url, imageURL: imageURL ?? existing?.imageURL))
            guard errors.isEmpty else { throw KimiError.configuration(errors.joined(separator: " ")) }
            if let author = author ?? existing?.author, author.count > 256 {
                throw KimiError.configuration("Embed author exceeds 256 characters.")
            }
            if let footer = footer ?? existing?.footer, footer.count > 2048 {
                throw KimiError.configuration("Embed footer exceeds 2048 characters.")
            }
            for candidate in [thumbnailURL ?? existing?.thumbnailURL, imageURL ?? existing?.imageURL, url ?? existing?.url]
                .compactMap({ $0 })
            {
                guard let parsed = URL(string: candidate), parsed.scheme == "https", parsed.host != nil else {
                    throw KimiError.configuration("Embed image and title URLs must be valid HTTPS URLs.")
                }
            }
            let id = existing?.id ?? UUID().uuidString
            let value = Saved(
                id: id, name: name, title: title, description: description, color: KimiUI.grey,
                footer: footer ?? existing?.footer, author: author ?? existing?.author,
                thumbnailURL: thumbnailURL ?? existing?.thumbnailURL, imageURL: imageURL ?? existing?.imageURL,
                url: url ?? existing?.url, fields: nextFields)
            if let index = list.firstIndex(where: { $0.id == id }) { list[index] = value } else { list.append(value) }
            data[guild] = list
            try await store.setGuild(data, key: "embeds.saved", guildID: guild)
            return value
        }
}
