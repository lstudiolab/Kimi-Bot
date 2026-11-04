import Foundation

struct EmbedValidator {
    struct Field: Sendable {
        let name: String
        let value: String
    }
    struct Definition: Sendable {
        let title: String
        let description: String
        let fields: [Field]
        let color: Int
        let author: String?
        let footer: String?
        let url: String?
        let imageURL: String?
    }
    func validate(_ embed: Definition) -> [String] {
        var errors: [String] = []
        if embed.title.count > 256 { errors.append("Title exceeds Discord's 256 character limit.") }
        if embed.description.count > 4096 { errors.append("Description exceeds Discord's 4096 character limit.") }
        if embed.fields.count > 25 { errors.append("An embed can contain at most 25 fields.") }
        for field in embed.fields
        where field.name.isEmpty || field.name.count > 256 || field.value.isEmpty || field.value.count > 1024 {
            errors.append("An embed field has invalid content.")
        }
        if let author = embed.author, author.isEmpty || author.count > 256 {
            errors.append("Embed author must contain 1–256 characters.")
        }
        if let footer = embed.footer, footer.isEmpty || footer.count > 2048 {
            errors.append("Embed footer must contain 1–2048 characters.")
        }
        if embed.color < 0 || embed.color > 0xFFFFFF {
            errors.append("Embed color must be a 24-bit RGB value.")
        }
        if embed.title.isEmpty && embed.description.isEmpty && embed.fields.isEmpty {
            errors.append("An embed must contain a title, description, or field.")
        }
        let total = embed.title.count + embed.description.count
            + embed.fields.reduce(0) { $0 + $1.name.count + $1.value.count }
            + (embed.author?.count ?? 0) + (embed.footer?.count ?? 0)
        if total > 6000 { errors.append("Combined embed content exceeds Discord's 6000 character limit.") }

        for candidate in [embed.url, embed.imageURL].compactMap({ $0 }) {
            guard let url = URLComponents(string: candidate), url.scheme == "https", url.host != nil else {
                errors.append("Embed URLs must be valid HTTPS URLs.")
                continue
            }
        }
        return errors
    }
}
