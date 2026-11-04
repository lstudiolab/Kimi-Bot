import Foundation

struct ServerAudit {
    struct Finding: Sendable {
        let severity: String
        let title: String
        let detail: String
    }

    private let elevatedPermissions: [(bit: Int, title: String, detail: String)] = [
        (1, "can kick members", "Restrict Kick Members."),
        (2, "can ban members", "Restrict Ban Members."),
        (4, "can manage channels", "Restrict Manage Channels."),
        (7, "can view the audit log", "Restrict View Audit Log."),
        (5, "can manage the server", "Restrict Manage Guild."),
        (28, "can manage roles", "Restrict Manage Roles."),
        (29, "can manage webhooks", "Restrict Manage Webhooks."),
        (40, "can moderate members", "Review who can timeout members."),
        (13, "can manage messages", "Restrict message deletion and pinning."),
        (17, "can mention everyone", "Restrict mass mentions."),
        (22, "can mute members", "Restrict voice moderation."),
        (23, "can deafen members", "Restrict voice moderation."),
        (24, "can move members", "Restrict voice moderation."),
        (27, "can manage nicknames", "Restrict nickname management."),
        (30, "can manage server expressions", "Restrict expression management."),
        (33, "can manage events", "Restrict event management."),
        (34, "can manage threads", "Restrict thread management."),
        (43, "can manage guild expressions", "Restrict expression management."),
        (44, "can create events", "Restrict event creation."),
    ]

    func evaluate(roles: [[String: Any]], everyonePermissions: UInt64) -> [Finding] {
        var results: [Finding] = []
        if everyonePermissions & (1 << 3) != 0 {
            results.append(
                .init(
                    severity: "critical", title: "@everyone has Administrator",
                    detail: "Remove Administrator from @everyone."))
        }
        for permission in elevatedPermissions where everyonePermissions & (UInt64(1) << permission.bit) != 0 {
            results.append(
                .init(severity: "high", title: "@everyone " + permission.title, detail: permission.detail))
        }

        for role in roles {
            let name = role["name"] as? String ?? "Unnamed"
            guard name != "@everyone" else { continue }
            let permissions = UInt64(role["permissions"] as? String ?? "") ?? 0
            if permissions & (1 << 3) != 0 {
                results.append(
                    .init(severity: "critical", title: "Administrator role: " + name, detail: "Review role membership."))
            }
            for permission in elevatedPermissions where permissions & (UInt64(1) << permission.bit) != 0 {
                results.append(
                    .init(
                        severity: "high", title: "Role " + name + " " + permission.title,
                        detail: permission.detail))
            }
        }
        return results
    }
}
