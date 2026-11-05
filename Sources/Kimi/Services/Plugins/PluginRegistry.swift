import Foundation

struct KimiPluginDefinition: Sendable, Identifiable {
    let name, description: String
    let systems, helpers, dependencies: [String]
    var id: String { name }

    init(name: String, description: String, systems: [String], helpers: [String], dependencies: [String] = []) {
        self.name = name
        self.description = description
        self.systems = systems
        self.helpers = helpers
        self.dependencies = dependencies
    }
}

enum PluginRegistry {
    private static func plugin(_ name: String, _ description: String, _ systems: String, _ helpers: String) -> KimiPluginDefinition {
        .init(name: name, description: description, systems: systems.components(separatedBy: "|"),
              helpers: helpers.components(separatedBy: "|"))
    }

    static let plugins = [
        plugin("Welcome", "Member greetings and departure messages.", "Welcome|Goodbye", "Template variables|Channel validation"),
        plugin("Auto Role", "Assign a configured role to new members.", "Automatic role assignment", "Role hierarchy validation"),
        plugin("Role Picker", "Self-service role menus for members.", "Role menus|Role selection", "Role safety checks"),
        plugin("Embeds", "Create, edit and publish reusable embeds.", "Embed builder|Embed placements", "Embed validation"),
        plugin("Auto-Moderator", "A dedicated moderation suite, from member actions and case history to automated protection.",
               "Micro / Tiny Essentials: kick, ban, unban, timeout, untimeout, softban, purge, slowmode and lockdown|Small / Core Management: warnings, case IDs, moderator notes, private reports and role controls|Medium Features: audit logs, verification gates, account-age checks and member profiles|Large Features: phrase filters, anti-flood, duplicate detection, mention and emoji limits, phishing checks and escalation rules|Major Protection: anti-raid, join-rate limits, emergency lockdown and anti-nuke safeguards|Massive / Enterprise: content analysis, appeals dashboard, threat intelligence and staff analytics",
               "Existing message filters, spam detection, sanctions, verification and raid protection|Case history, moderation commands and audit coverage are staged for implementation|External threat feeds, AI media scanning and web dashboard require separate services"),
        plugin("Kimi Lock", "Coordinated server security, recovery and anti-nuke protection.",
               "Raid protection|Anti-nuke|Verification|Recovery|Bot containment",
               "Threat monitoring|Security audit|Channel and message recovery"),
        plugin("Support", "Private tickets and staff support.",
               "Ticket lifecycle|Staff handoff|Priority|Transcripts", "Queue management|Access validation")
    ]

    static func resolve(_ input: String) -> KimiPluginDefinition? {
        let key = input.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        let aliases = [
            "moderation": "kimilock", "security": "kimilock", "lock": "kimilock",
            "ticket": "support", "tickets": "support", "foundation": "welcome",
            "roles": "rolepicker", "embed": "embeds"
        ]
        let resolved = aliases[key] ?? key
        return plugins.first { $0.name.lowercased().filter { !$0.isWhitespace } == resolved }
    }
}
