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
        plugin("Kimi Lock", "Coordinated security and moderation.",
               "Anti-spam|Raid protection|Anti-nuke|Verification|Sanctions|Recovery",
               "Threat monitoring|Security audit"),
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
