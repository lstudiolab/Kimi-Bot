import Foundation

enum StorageQuota {
    static let freeLimitBytes = 5 * 1024 * 1024
    static let collections = [
        "installed_plugins", "modules", "command_settings", "languages", "automations",
        "welcome", "tickets", "moderation", "verification", "verification_logs",
        "analytics_requests", "customizations", "library_data", "timi_setup",
        "automod_words", "moderation_cases", "moderation_jobs", "guard_state", "messages"
    ]

    static func bytes(for guildID: String, in data: [String: JSONValue]) throws -> Int {
        var snapshot: [String: JSONValue] = [:]
        for collection in collections {
            if case .object(let values)? = data[collection], let guild = values[guildID] {
                snapshot[collection] = .object([guildID: guild])
            }
        }
        for collection in ["role_picker_menus", "role_picker_drafts"] {
            if case .object(let values)? = data[collection] {
                let selected = values.filter { key, value in
                    if case .object(let object) = value, case .string(let id)? = object["guild_id"] { return id == guildID }
                    return key.hasPrefix(guildID + ":")
                }
                if !selected.isEmpty { snapshot[collection] = .object(selected) }
            }
        }
        for collection in ["embeds", "members", "pending_bots", "channels"] {
            if case .object(let values)? = data[collection] {
                let selected = values.filter { $0.key.hasPrefix(guildID + ":") }
                if !selected.isEmpty { snapshot[collection] = .object(selected) }
            }
        }
        return try JSONEncoder().encode(snapshot).count
    }

    static func report(guildID: String, data: [String: JSONValue]) throws -> StorageReport {
        let used = try bytes(for: guildID, in: data)
        return StorageReport(used: used, limit: freeLimitBytes)
    }

    static func format(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(max(0, bytes)) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}

struct StorageReport: Sendable {
    let used: Int
    let limit: Int
    var remaining: Int { max(0, limit - used) }
    var percent: Int { min(100, Int((Double(used) / Double(limit) * 100).rounded())) }
    var exceeded: Bool { used > limit }
}
