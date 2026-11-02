import Foundation

struct AppDefinition: Sendable, Identifiable {
    let name: String
    let description: String
    let systems: [String]
    let helpers: [String]
    var id: String { name }
}

enum AppRegistry {
    static let all: [AppDefinition] = [
        .init(name: "Welcome", description: "Member greetings and departures.", systems: ["Welcome and departure messages"], helpers: ["Message preview", "Template variables", "Channel validation"]),
        .init(name: "Auto Role", description: "Assign a configured role when a member joins.", systems: ["Automatic role assignment"], helpers: ["Role hierarchy checker", "Assignment validation"]),
        .init(name: "Role Picker", description: "Self-service role menus.", systems: ["Self-service role menus"], helpers: ["Role menu editor", "Role safety validator"]),
        .init(name: "Embeds", description: "Reusable server embeds.", systems: ["Create, edit and publish embeds"], helpers: ["Embed builder", "Placement manager"]),
        .init(name: "Kimi Lock", description: "Coordinated security and moderation.", systems: ["Anti-spam and AutoMod", "Raid and join protection", "Anti-nuke containment", "Member verification and review", "Warnings and timed sanctions", "Suspicious link and image checks", "Audit trail and recovery"], helpers: ["Threat monitor", "Permission and hierarchy checker", "Raid response planner", "Sanction scheduler", "Recovery snapshots", "Security health report"]),
        .init(name: "Support", description: "Private tickets and staff support workflows.", systems: ["Private tickets, staff handoff, priority, transcripts and support activity"], helpers: ["Ticket setup assistant", "Staff access validator", "Transcript exporter", "Queue and priority manager"])
    ]

    static func normalize(_ input: String) -> String? {
        let key = input.lowercased().filter { !$0.isWhitespace && $0 != "_" && $0 != "-" }
        let aliases = ["moderation": "Kimi Lock", "security": "Kimi Lock", "lock": "Kimi Lock", "core": "Welcome", "foundation": "Welcome", "ticket": "Support", "roles": "Role Picker", "role": "Role Picker", "autorole": "Auto Role", "embed": "Embeds"]
        if let alias = aliases[key] { return alias }
        return all.first { $0.name.lowercased().filter { !$0.isWhitespace } == key }?.name
    }
}
