import Foundation

enum CommandCatalog {
    static let core = [
        "kimi", "setup", "plan", "apps", "app-store", "install", "uninstall", "automations", "guard-review",
        "web-token", "analytics", "performance", "configure-foundation", "configure-welcome", "configure-roles",
        "configure-auto-role", "configure-embeds", "configure-kimi-lock", "configure-support",
    ]
    static let groups: [String: [String]] = [
        "Welcome": ["welcome"], "Auto Role": ["autorole"], "Role Picker": ["roles"],
        "Embeds": ["embed-new", "embed-edit", "embed-post"],
        "Kimi Lock": ["moderation", "verify", "verify-config", "filter", "security"],
        "Support": ["tickets", "ticket-panel", "ticket-config"],
    ]
    static let all: [String: [String: Any]] = {
        let admin = "32"
        func command(_ n: String, _ d: String, _ o: [[String: Any]] = []) -> [String: Any] {
            var v: [String: Any] = ["name": n, "description": d, "type": 1, "options": o]
            if !["plan", "apps", "app-store"].contains(n) { v["default_member_permissions"] = admin }
            return v
        }
        func text(_ n: String, _ d: String, _ required: Bool = false, _ choices: [[String: Any]] = []) -> [String: Any]
        {
            var v: [String: Any] = ["type": 3, "name": n, "description": d, "required": required]
            if !choices.isEmpty { v["choices"] = choices }
            return v
        }
        func user(_ n: String, _ d: String) -> [String: Any] {
            ["type": 6, "name": n, "description": d, "required": true]
        }
        func role(_ n: String, _ d: String) -> [String: Any] { ["type": 8, "name": n, "description": d] }
        func channel(_ n: String, _ d: String) -> [String: Any] {
            ["type": 7, "name": n, "description": d, "channel_types": [0]]
        }
        func integer(_ n: String, _ d: String, _ min: Int, _ max: Int) -> [String: Any] {
            ["type": 4, "name": n, "description": d, "min_value": min, "max_value": max]
        }
        func boolean(_ n: String, _ d: String) -> [String: Any] { ["type": 5, "name": n, "description": d] }
        let apps = ["Welcome", "Auto Role", "Role Picker", "Embeds", "Kimi Lock", "Support"].map {
            ["name": $0, "value": $0]
        }
        return [
            "kimi": command("kimi", "Open Kimi server settings"),
            "setup": command("setup", "Prepare private Kimi channels"),
            "plan": command("plan", "View Kimi storage usage"), "apps": command("apps", "Browse Kimi apps"),
            "app-store": command("app-store", "Manage installed apps"),
            "install": command("install", "Install a Kimi app", [text("app", "App to install", true, apps)]),
            "uninstall": command("uninstall", "Uninstall a Kimi app", [text("app", "App to remove", true, apps)]),
            "automations": command(
                "automations", "Manage server automations",
                [
                    ["type": 1, "name": "list", "description": "List saved automation rules"],
                    [
                        "type": 1, "name": "create", "description": "Create an event automation",
                        "options": [
                            text("name", "Rule name", true),
                            text(
                                "trigger", "Trigger: message_create, message_contains, member_join or member_leave",
                                true), text("condition", "Required text when trigger is message_contains"),
                            text(
                                "action",
                                "Action: delete_message, send_message:CHANNEL:TEXT, timeout:MINUTES, add_role:ROLE or remove_role:ROLE",
                                true),
                        ],
                    ],
                    [
                        "type": 1, "name": "remove", "description": "Remove an automation rule",
                        "options": [text("id", "Rule ID", true)],
                    ],
                    [
                        "type": 1, "name": "toggle", "description": "Enable or disable a rule",
                        "options": [
                            text("id", "Rule ID", true),
                            ["type": 5, "name": "enabled", "description": "Enable this rule", "required": true],
                        ],
                    ],
                ]),
            "guard-review": command(
                "guard-review", "Review bot containment",
                [
                    user("bot", "Bot under review"),
                    text(
                        "decision", "Restore or keep restricted", true,
                        [["name": "Restore", "value": "restore"], ["name": "Keep restricted", "value": "keep"]]),
                ]), "web-token": command("web-token", "Open the Kimi dashboard"),
            "analytics": command("analytics", "View server activity and system statistics"),
            "performance": command("performance", "View Kimi command latency and failure metrics"),
            "welcome": command(
                "welcome", "Configure welcome and goodbye messages",
                [
                    channel("welcome-channel", "Welcome channel"), channel("goodbye-channel", "Goodbye channel"),
                    text("welcome-message", "Welcome message"), text("goodbye-message", "Goodbye message"),
                ]),
            "autorole": command(
                "autorole", "Configure automatic member role", [role("role", "Role assigned to new members")]),
            "roles": command(
                "roles", "Create a self-service role menu",
                [text("name", "Menu name"), channel("channel", "Publishing channel")]),
            "embed-new": command(
                "embed-new", "Create a reusable embed",
                [
                    text("name", "Saved embed name", true), text("title", "Embed title", true),
                    text("description", "Embed description", true), text("author", "Author"), text("footer", "Footer"),
                    text("thumbnail", "Thumbnail HTTPS URL"), text("image", "Image HTTPS URL"),
                    text("url", "Title HTTPS URL"), integer("color", "Embed color as decimal RGB", 0, 16_777_215),
                    text("field-name", "Optional field name"), text("field-value", "Optional field value"),
                    boolean("field-inline", "Display the new field inline"),
                    integer("remove-field", "Remove a field by its 1-based number", 1, 25),
                ]),
            "embed-edit": command(
                "embed-edit", "Edit a saved embed",
                [
                    text("name", "Embed name", true), text("title", "New title"),
                    text("description", "New description"), text("author", "Author"), text("footer", "Footer"),
                    text("thumbnail", "Thumbnail HTTPS URL"), text("image", "Image HTTPS URL"),
                    text("url", "Title HTTPS URL"),
                ]), "embed-post": command("embed-post", "Publish a saved embed", [text("name", "Embed name", true)]),
            "moderation": command(
                "moderation", "Configure Kimi Lock",
                [
                    boolean("enabled", "Enable automatic moderation"),
                    text(
                        "sanction", "Automatic sanction", false,
                        [
                            ["name": "Timeout", "value": "timeout"], ["name": "Kick", "value": "kick"],
                            ["name": "Ban", "value": "ban"], ["name": "Delete only", "value": "delete"],
                        ]), integer("timeout-minutes", "Timeout duration in minutes", 1, 40320),
                    integer("messages-per-minute", "Message rate threshold", 2, 100),
                    boolean("block-invites", "Block Discord invite links"),
                    boolean("block-mentions", "Block mass mentions"), boolean("block-caps", "Block excessive capitals"),
                    channel("log-channel", "Private moderation log channel"),
                ]), "verify": command("verify", "Configure member verification"),
            "verify-config": command(
                "verify-config", "Configure verification",
                [
                    role("role", "Verified role"), role("required-role", "Role required before verification"),
                    channel("channel", "Verification channel"), integer("min-age-days", "Minimum account age", 0, 3650),
                    channel("review-channel", "Manual review channel"),
                ]),
            "filter": command(
                "filter", "Manage blocked phrases",
                [
                    [
                        "type": 1, "name": "add", "description": "Add a blocked phrase",
                        "options": [text("phrase", "Phrase", true)],
                    ],
                    [
                        "type": 1, "name": "remove", "description": "Remove a blocked phrase",
                        "options": [text("phrase", "Phrase", true)],
                    ], ["type": 1, "name": "list", "description": "List blocked phrases"],
                ]),
            "configure-foundation": command(
                "configure-foundation", "Configure the Welcome app (legacy alias)",
                [
                    channel("welcome-channel", "Welcome channel"), channel("goodbye-channel", "Goodbye channel"),
                    text("welcome-message", "Welcome message"), text("goodbye-message", "Goodbye message"),
                ]),
            "configure-welcome": command(
                "configure-welcome", "Configure the Welcome app",
                [
                    channel("welcome-channel", "Welcome channel"), channel("goodbye-channel", "Goodbye channel"),
                    text("welcome-message", "Welcome message"), text("goodbye-message", "Goodbye message"),
                ]),
            "configure-roles": command(
                "configure-roles", "Configure the Role Picker app",
                [text("name", "Menu name"), channel("channel", "Publishing channel")]),
            "configure-auto-role": command(
                "configure-auto-role", "Configure automatic member role", [role("role", "Role assigned to new members")]
            ),
            "configure-embeds": command(
                "configure-embeds", "Configure saved embeds",
                [
                    text("name", "Saved embed name", true), text("title", "Embed title"),
                    text("description", "Embed description"), text("author", "Author"), text("footer", "Footer"),
                    text("thumbnail", "Thumbnail HTTPS URL"), text("image", "Image HTTPS URL"),
                    text("url", "Title HTTPS URL"),
                ]),
            "configure-kimi-lock": command(
                "configure-kimi-lock", "Configure Kimi Lock",
                [
                    boolean("enabled", "Enable automatic moderation"),
                    text(
                        "sanction", "Automatic sanction", false,
                        [
                            ["name": "Timeout", "value": "timeout"], ["name": "Kick", "value": "kick"],
                            ["name": "Ban", "value": "ban"], ["name": "Delete only", "value": "delete"],
                        ]), integer("timeout-minutes", "Timeout duration in minutes", 1, 40320),
                    integer("messages-per-minute", "Message rate threshold", 2, 100),
                    boolean("block-invites", "Block Discord invite links"),
                    boolean("block-mentions", "Block mass mentions"), boolean("block-caps", "Block excessive capitals"),
                    channel("log-channel", "Private moderation log channel"),
                ]),
            "configure-support": command(
                "configure-support", "Configure Support",
                [role("support-role", "Support staff role"), channel("transcript-channel", "Transcript channel")]),
            "security": command("security", "Audit server security"),
            "tickets": command("tickets", "Prepare Support tickets"),
            "ticket-panel": command("ticket-panel", "Publish a ticket panel"),
            "ticket-config": command(
                "ticket-config", "View ticket settings",
                [role("support-role", "Support staff role"), channel("transcript-channel", "Transcript channel")]),
        ]
    }()
    static func globalCommands() -> [[String: Any]] { core.compactMap { all[$0] } }
    static func guildCommands(installed: [String]) -> [[String: Any]] {
        installed.flatMap { groups[$0] ?? [] }.compactMap { all[$0] }
    }
    static func appNames() -> [String] { groups.keys.sorted() }
}
