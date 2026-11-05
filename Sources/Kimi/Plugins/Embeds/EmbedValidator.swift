import Foundation

struct EmbedValidator {
    struct Field: Sendable {
        let name, value: String
    }
    struct Definition: Sendable {
        let title, description: String
        let fields: [Field]
        let color: Int
        let author, footer: String?
        let url, imageURL: String?

        init(
            title: String, description: String, fields: [Field], color: Int,
            author: String? = nil, footer: String? = nil, url: String? = nil, imageURL: String? = nil
        ) {
            self.title = title
            self.description = description
            self.fields = fields
            self.color = color
            self.author = author
            self.footer = footer
            self.url = url
            self.imageURL = imageURL
        }
    }
    func validate(_ embed: Definition) -> [String] {
        var errors: [String] = []
        if embed.title.utf16.count > 256 { errors.append("Title exceeds Discord's 256 character limit.") }
        if embed.description.utf16.count > 4096 { errors.append("Description exceeds Discord's 4096 character limit.") }
        if embed.fields.count > 25 { errors.append("An embed can contain at most 25 fields.") }
        for field in embed.fields
        where field.name.isEmpty || field.name.utf16.count > 256 || field.value.isEmpty || field.value.utf16.count > 1024 {
            errors.append("An embed field has invalid content.")
        }
        if let author = embed.author, author.isEmpty || author.utf16.count > 256 {
            errors.append("Embed author must contain 1–256 characters.")
        }
        if let footer = embed.footer, footer.isEmpty || footer.utf16.count > 2048 {
            errors.append("Embed footer must contain 1–2048 characters.")
        }
        if embed.color < 0 || embed.color > 0xFFFFFF {
            errors.append("Embed color must be a 24-bit RGB value.")
        }
        if embed.title.isEmpty && embed.description.isEmpty && embed.fields.isEmpty {
            errors.append("An embed must contain a title, description, or field.")
        }
        let total = embed.title.utf16.count + embed.description.utf16.count
            + embed.fields.reduce(0) { $0 + $1.name.utf16.count + $1.value.utf16.count }
            + (embed.author?.utf16.count ?? 0) + (embed.footer?.utf16.count ?? 0)
        if total > 6000 { errors.append("Combined embed content exceeds Discord's 6000 character limit.") }

        for candidate in [embed.url, embed.imageURL].compactMap({ $0 }) {
            guard let url = URLComponents(string: candidate), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
                errors.append("Embed URLs must be valid HTTPS URLs.")
                continue
            }
        }
        return errors
    }
}
