import Foundation

enum KimiGuardCatalog {
    struct Feature: Sendable {
        let name: String
        let available: Bool
    }

    struct Section: Sendable {
        let level, title: String
        let features: [Feature]
    }

    private static func feature(_ name: String, _ available: Bool = false) -> Feature {
        Feature(name: name, available: available)
    }

    static let sections: [Section] = [
        Section(level: "01", title: "Micro / Tiny Essentials", features: [
            feature("/kick, /ban, /unban"),
            feature("/timeout, /untimeout"),
            feature("/softban"),
            feature("/purge with user and content filters"),
            feature("/slowmode"),
            feature("/lockdown and /unlock"),
        ]),
        Section(level: "02", title: "Small / Core Management", features: [
            feature("/warn, /warnings and /delwarn"),
            feature("Unique infraction case IDs"),
            feature("Moderator-only user notes"),
            feature("Private mod mail and /report"),
            feature("Role add/remove moderation controls"),
        ]),
        Section(level: "03", title: "Medium Features", features: [
            feature("Deleted and edited message audit logs"),
            feature("Voice join, leave and switch logs"),
            feature("Nickname, role and moderator action logs"),
            feature("Button, rules and CAPTCHA verification"),
            feature("Account-age entry filters"),
            feature("/userinfo member profiles"),
        ]),
        Section(level: "04", title: "Large Features", features: [
            feature("Phrase and invite-link filters", true),
            feature("Message rate limiting and auto-timeout", true),
            feature("Duplicate message detection", true),
            feature("Mention, emoji and caps flood detection", true),
            feature("Suspicious URL and phishing heuristics", true),
            feature("Warning and timeout escalation rules"),
        ]),
        Section(level: "05", title: "Major / Advanced Protection", features: [
            feature("Join-rate anti-raid detection"),
            feature("Automatic emergency lockdown"),
            feature("Mass-ban and mass-purge review tools"),
            feature("Self-bot and spambot behavior signals"),
            feature("Rogue staff and anti-nuke safeguards"),
        ]),
        Section(level: "06", title: "Massive / Cutting-Edge Systems", features: [
            feature("Context-aware text toxicity analysis"),
            feature("NSFW and prohibited-media scanning"),
            feature("Web dashboard and ban appeals portal"),
            feature("Cross-server threat intelligence"),
            feature("Staff performance and case analytics"),
        ]),
    ]

    static var availableCount: Int {
        sections.reduce(0) { total, section in total + section.features.filter { $0.available }.count }
    }

    static var plannedCount: Int {
        sections.reduce(0) { total, section in total + section.features.filter { !$0.available }.count }
    }
}
