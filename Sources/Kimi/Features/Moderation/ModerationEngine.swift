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
    private var duplicateHistory: [String: [(String, Date)]] = [:]
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
    private func normalized(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let hidden: Set<UInt32> = [0x034F, 0x061C, 0x180E, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        let clean = String(String.UnicodeScalarView(folded.unicodeScalars.filter {
            !hidden.contains($0.value) && !CharacterSet.controlCharacters.contains($0)
        }))
        let map: [Character: Character] = ["а":"a", "е":"e", "і":"i", "о":"o", "р":"p", "с":"c", "х":"x", "у":"y", "ѕ":"s", "ԁ":"d"]
        let mapped = String(clean.map { map[$0] ?? $0 }).lowercased()
        return mapped.filter { $0.isLetter || $0.isNumber }
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "3", with: "e")
            .replacingOccurrences(of: "4", with: "a")
            .replacingOccurrences(of: "5", with: "s")
            .replacingOccurrences(of: "7", with: "t")
    }

    private func containsSuspiciousURL(_ content: String) -> Bool {
        let pattern = #"(?i)(?:https?://|www\.)[^\s<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..., in: content)
        let urls = regex.matches(in: content, range: range).compactMap { match -> String? in
            return String(content[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?)]}>"))
            return String(content[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?)]}>'\\""))
        }
        let loggerDomains: Set<String> = ["grabify.link", "iplogger.org", "iplogger.com", "2no.co", "yip.su", "ps3cfw.com", "blasze.com", "leancoding.co", "stopify.co"]
        let shorteners: Set<String> = ["bit.ly", "tinyurl.com", "t.co", "is.gd", "cutt.ly", "rb.gy"]
        return urls.contains { raw in
            let candidate = raw.hasPrefix("www.") ? "https://" + raw : raw
            guard let parts = URLComponents(string: candidate), let host = parts.host?.lowercased() else { return true }
            if parts.user != nil || parts.password != nil || host.hasPrefix("xn--") || host.contains(".xn--") { return true }
            if loggerDomains.contains(host) || shorteners.contains(host) { return true }
            return host.range(of: #"^\\d{1,3}(?:\.\\d{1,3}){3}$"#, options: .regularExpression) != nil
        }
    }

    func evaluate(
        guildID: String, userID: String, messageID: String, content: String, channelID: String = "",
        now: Date = Date(), attachments: [[String: Any]] = [], stickerCount: Int = 0,
        mentionEveryone: Bool = false, roleMentionCount: Int = 0, userMentionCount: Int = 0
    ) async -> Finding? {
        let value = await policy(guildID: guildID)
        guard value.enabled else { return nil }
        let key = guildID + ":" + channelID + ":" + userID
        var events = (history[key] ?? []).filter { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 60 }
        events.append(now)
        history[key] = events
        if history.count > 20000 {
            history = history.filter { !$0.value.isEmpty && now.timeIntervalSince($0.value.last ?? now) < 120 }
        }

        let normalizedContent = normalized(content)
        let defaultTerms = ["fuck", "fucking", "motherfucker", "shit", "bullshit", "bitch", "bastard", "asshole", "dickhead", "cunt", "slut", "whore", "retard"]
        let customTerm = value.blockedPhrases.first { phrase in
            let needle = normalized(phrase)
            return needle.count >= 2 && normalizedContent.contains(needle)
        }
        let profanity = defaultTerms.contains { normalizedContent.contains(normalized($0)) }
        let spam = events.count > max(1, value.messagesPerMinute)
        let excessive = content.count > 1900
        let letters = content.filter { $0.isLetter }
        let uppercase = letters.filter { $0.isUppercase }.count
        let caps = value.blockExcessiveCaps && letters.count >= 12
            && Double(uppercase) / Double(max(1, letters.count)) >= 0.75
        let formattingLines = content.split(separator: "\n", omittingEmptySubsequences: false).count
        let backticks = String(repeating: String(UnicodeScalar(96)!), count: 3)
        let formattingMarkers = content.components(separatedBy: "**").count - 1
            + content.components(separatedBy: backticks).count - 1
            + content.components(separatedBy: "__").count - 1
        let formattingWall = formattingLines >= 18 || (formattingMarkers >= 12 && content.count > 500)
        let emojiCount = content.unicodeScalars.filter {
            (0x1F000...0x1FAFF).contains($0.value) || (0x2600...0x27BF).contains($0.value)
        }.count
        let customEmojiCount = content.components(separatedBy: "<:").count - 1
            + content.components(separatedBy: "<a:").count - 1
        let emojiSpam = emojiCount + customEmojiCount > 20 || stickerCount > 3
        let massMention = value.blockMassMentions && (mentionEveryone || content.contains("@everyone")
            || content.contains("@here") || userMentionCount >= 5 || roleMentionCount >= 3)
        let invite = value.blockInvites && content.range(
            of: #"(?i)(?:discord\.gg/|discord(?:app)?\.com/invite/)"#, options: .regularExpression) != nil
        let suspiciousLink = containsSuspiciousURL(content)
        let attachmentsBlocked = attachments.contains { item in
            let filename = item["filename"] as? String ?? ""
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            return ["exe", "dll", "com", "scr", "msi", "bat", "cmd", "ps1", "sh", "bash", "vbs", "js", "hta", "jar", "apk", "dmg", "pkg", "py", "pyc", "wasm", "lnk", "reg", "sys"].contains(ext)
        }
        var repeated = (duplicateHistory[key] ?? []).filter {
            now.timeIntervalSince($0.1) >= 0 && now.timeIntervalSince($0.1) <= 10
        }
        repeated.append((normalizedContent, now))
        duplicateHistory[key] = repeated
        if duplicateHistory.count > 20000 {
            duplicateHistory = duplicateHistory.filter { !$0.value.isEmpty && now.timeIntervalSince($0.value.last?.1 ?? now) < 30 }
        }
        let duplicate = repeated.filter { $0.0 == normalizedContent }.count >= 3 && normalizedContent.count > 3
        let triggered = customTerm != nil || profanity || spam || excessive || caps || formattingWall
            || emojiSpam || massMention || invite || suspiciousLink || attachmentsBlocked || duplicate
        guard triggered else { return nil }

        var reasons: [String] = []
        var score = 0
        func add(_ reason: String, _ points: Int) { reasons.append(reason); score += points }
        if customTerm != nil { add("Custom blocked keyword", 85) }
        if profanity { add("Blocked language", 85) }
        if spam { add("High-velocity message flood", 70) }
        if excessive { add("Message length flood", 35) }
        if caps { add("Excessive capitals", 35) }
        if formattingWall { add("Formatting wall-of-text flood", 40) }
        if emojiSpam { add("Emoji, emote or sticker spam", 45) }
        if massMention { add("Mass mention abuse", 80) }
        if invite { add("Unsolicited Discord invite", 65) }
        if suspiciousLink { add("Suspicious or tracking URL", 90) }
        if attachmentsBlocked { add("Executable or script attachment", 95) }
        if duplicate { add("Repeated message burst", 55) }

        let infractionKey = "moderation.infractions." + guildID + "." + userID
        let previous = await store.get(infractionKey, as: Int.self) ?? 0
        let total = min(10000, previous + 1)
        try? await store.setGuild(total, key: infractionKey, guildID: guildID)
        if total >= 3 {
            score += min(30, (total - 2) * 5)
            reasons.append("Cumulative infractions: " + String(total))
        }
        return Finding(guildID: guildID, userID: userID, messageID: messageID, reason: reasons.joined(separator: "; "), score: min(200, score))
    }
}
