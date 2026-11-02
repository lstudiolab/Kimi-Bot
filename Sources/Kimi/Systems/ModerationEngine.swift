import Foundation

actor ModerationEngine {
    struct Policy: Codable, Sendable {
        var enabled: Bool = true
        var messagesPerMinute: Int = 20
        var timeoutMinutes: Int = 10
        var blockedPhrases: [String] = []
        var sanction: String = "timeout"
        var actionDurationSeconds: Int = 10
        var blockInvites: Bool = true
        var blockMassMentions: Bool = true
        var blockExcessiveCaps: Bool = true
        var logChannelID: String?
        init() {}
        enum CodingKeys: String, CodingKey {
            case enabled, messagesPerMinute, timeoutMinutes, blockedPhrases, sanction, actionDurationSeconds,
                blockInvites, blockMassMentions, blockExcessiveCaps, logChannelID
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            messagesPerMinute = try c.decodeIfPresent(Int.self, forKey: .messagesPerMinute) ?? 20
            timeoutMinutes = try c.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? 10
            blockedPhrases = try c.decodeIfPresent([String].self, forKey: .blockedPhrases) ?? []
            sanction = try c.decodeIfPresent(String.self, forKey: .sanction) ?? "timeout"
            actionDurationSeconds = try c.decodeIfPresent(Int.self, forKey: .actionDurationSeconds) ?? 10
            blockInvites = try c.decodeIfPresent(Bool.self, forKey: .blockInvites) ?? true
            blockMassMentions = try c.decodeIfPresent(Bool.self, forKey: .blockMassMentions) ?? true
            blockExcessiveCaps = try c.decodeIfPresent(Bool.self, forKey: .blockExcessiveCaps) ?? true
            logChannelID = try c.decodeIfPresent(String.self, forKey: .logChannelID)
        }
    }
    struct Finding: Sendable {
        let guildID: String
        let userID: String
        let messageID: String
        let reason: String
        let score: Int
    }
    private struct Legacy: Decodable {
        var enabled: Bool?
        var timeout_minutes: Int?
        var max_message_count: Int?
        var sanction: String?
        var action_duration_seconds: Int?
        var block_invites: Bool?
        var block_mass_mentions: Bool?
        var block_excessive_caps: Bool?
        var log_channel_id: String?
    }
    private let store: PersistentStore
    private var policies: [String: Policy] = [:]
    private var history: [String: [Date]] = [:]
    init(store: PersistentStore) { self.store = store }
    func policy(guildID: String) async -> Policy {
        if let cached = policies[guildID] { return cached }
        var value = await store.get("moderation." + guildID, as: Policy.self) ?? Policy()
        if let legacy = await store.getLegacy("moderation", as: [String: Legacy].self)?[guildID] {
            value.enabled = legacy.enabled ?? value.enabled
            value.timeoutMinutes = max(1, min(40320, legacy.timeout_minutes ?? value.timeoutMinutes))
            value.messagesPerMinute = max(2, min(100, legacy.max_message_count ?? value.messagesPerMinute))
            if let sanction = legacy.sanction, ["timeout", "kick", "ban", "delete"].contains(sanction) {
                value.sanction = sanction
            }
            value.actionDurationSeconds = max(1, min(60, legacy.action_duration_seconds ?? value.actionDurationSeconds))
            value.blockInvites = legacy.block_invites ?? value.blockInvites
            value.blockMassMentions = legacy.block_mass_mentions ?? value.blockMassMentions
            value.blockExcessiveCaps = legacy.block_excessive_caps ?? value.blockExcessiveCaps
            value.logChannelID = legacy.log_channel_id
        }
        if let words = await store.getLegacy("automod_words", as: [String: [String]].self)?[guildID] {
            value.blockedPhrases = Array(words.prefix(100))
        }
        policies[guildID] = value
        return value
    }
    func configure(_ policy: Policy, guildID: String) async throws {
        var value = policy
        value.messagesPerMinute = max(2, min(100, value.messagesPerMinute))
        value.timeoutMinutes = max(1, min(40320, value.timeoutMinutes))
        value.actionDurationSeconds = max(1, min(60, value.actionDurationSeconds))
        value.blockedPhrases = Array(value.blockedPhrases.prefix(100))
        guard ["timeout", "kick", "ban", "delete"].contains(value.sanction) else {
            throw KimiError.configuration("Sanction must be timeout, kick, ban or delete.")
        }
        policies[guildID] = value
        try await store.setGuild(value, key: "moderation." + guildID, guildID: guildID)
    }
    func evaluate(
        guildID: String, userID: String, messageID: String, content: String, channelID: String = "", now: Date = Date()
    ) async -> Finding? {
        let value = await policy(guildID: guildID)
        guard value.enabled else { return nil }
        let key = guildID + ":" + channelID + ":" + userID
        var events = (history[key] ?? []).filter { now.timeIntervalSince($0) < 60 }
        events.append(now)
        history[key] = events
        if history.count > 20000 {
            history = history.filter { !$0.value.isEmpty && now.timeIntervalSince($0.value.last ?? now) < 120 }
        }
        let normalized = content.lowercased()
        let blocked = value.blockedPhrases.first { phrase in
            let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !p.isEmpty && normalized.range(of: p, options: .literal) != nil
        }
        let spam = events.count > max(1, value.messagesPerMinute)
        let excessive = content.count > 1900
        let letters = content.filter { $0.isLetter }
        let uppercase = letters.filter { $0.isUppercase }.count
        let caps =
            value.blockExcessiveCaps && letters.count >= 12 && Double(uppercase) / Double(max(1, letters.count)) >= 0.75
        let mentions = content.components(separatedBy: "<@").count - 1
        let massMention =
            value.blockMassMentions && (content.contains("@everyone") || content.contains("@here") || mentions >= 5)
        let invitePattern = #"discord\.gg/|discord(?:app)?\.com/invite/"#
        let inviteMatch = content.range(of: invitePattern, options: .regularExpression)
        let invite = value.blockInvites && inviteMatch != nil
        let links =
            content.components(separatedBy: "https://").count + content.components(separatedBy: "http://").count - 2
        let linkSpam = links >= 4
        guard blocked != nil || spam || excessive || caps || massMention || invite || linkSpam else { return nil }
        let reason: String
        if let blocked {
            reason = "Blocked phrase: " + blocked
        } else if spam {
            reason = "Message rate exceeded"
        } else if massMention {
            reason = "Mass mention pattern"
        } else if invite {
            reason = "Unapproved Discord invite link"
        } else if linkSpam {
            reason = "Link spam"
        } else if caps {
            reason = "Excessive capitals"
        } else {
            reason = "Message too long"
        }
        var score = 0
        if blocked != nil { score += 90 }
        if spam { score += 60 }
        if massMention { score += 40 }
        if caps { score += 20 }
        if excessive { score += 30 }
        if invite { score += 50 }
        if linkSpam { score += 40 }
        return Finding(guildID: guildID, userID: userID, messageID: messageID, reason: reason, score: score)
    }
}
