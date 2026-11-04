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
        var blockSelfAdvertising: Bool = true
        var logChannelID: String?
        init() {}
        enum CodingKeys: String, CodingKey {
            case enabled, messagesPerMinute, timeoutMinutes, blockedPhrases, sanction, actionDurationSeconds,
                blockInvites, blockMassMentions, blockExcessiveCaps, blockSelfAdvertising, logChannelID
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
            blockSelfAdvertising = try c.decodeIfPresent(Bool.self, forKey: .blockSelfAdvertising) ?? true
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
    private struct DuplicateEvent: Codable, Sendable {
        let content: String
        let timestamp: Date
    }
    private struct GlobalThreat: Codable, Sendable {
        var guilds: [String]
        var incidents: Int
        var reasons: [String]
        var lastSeen: Date
    }
    private let store: PersistentStore
    private var policies: [String: Policy] = [:]
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
        try await store.setGuild(value, key: "moderation." + guildID, guildID: guildID)
        policies[guildID] = value
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
        let pattern = #"(?i)(?:https?://|www\.)[^\s<>]+|(?<![@\w])(?:[a-z0-9-]+\.)+(?:com|net|org|io|gg|co|ru|xyz|top|link|info|biz)(?:/[^\s<>]*)?|(?<![0-9])\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?(?:/[^\s<>]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(content.startIndex..., in: content)
        let urls = regex.matches(in: content, range: range).compactMap { match -> String? in
            guard let r = Range(match.range, in: content) else { return nil }
            return String(content[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?)]}>"))
        }
        let loggerDomains: Set<String> = ["grabify.link", "iplogger.org", "iplogger.com", "2no.co", "yip.su", "ps3cfw.com", "blasze.com", "leancoding.co", "stopify.co"]
        let shorteners: Set<String> = ["bit.ly", "tinyurl.com", "t.co", "is.gd", "cutt.ly", "rb.gy"]
        return urls.contains { raw in
            let candidate = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://" + raw
            guard let parts = URLComponents(string: candidate), let host = parts.host?.lowercased() else { return true }
            if parts.user != nil || parts.password != nil || host.hasPrefix("xn--") || host.contains(".xn--") { return true }
            if loggerDomains.contains(host) || shorteners.contains(host) { return true }
            return host.range(of: #"^\d{1,3}(?:\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        }
    }

    func profileViolation(_ name: String, guildID: String) async -> String? {
        let candidate = normalized(name)
        guard !candidate.isEmpty else { return nil }
        let value = await policy(guildID: guildID)
        let blocked = value.blockedPhrases.contains { phrase in
            let needle = normalized(phrase)
            return needle.count >= 2 && candidate.contains(needle)
        }
        let offensive = ["fuck", "shit", "bitch", "asshole", "cunt"].contains {
            candidate.contains(normalized($0))
        }
        let impersonationNames = [
            "discordsupport", "discordstaff", "discordmoderator", "discordsecurity",
            "discordnitro", "officialdiscord", "discordadmin", "steamadmin",
        ]
        let impersonation = impersonationNames.contains { candidate == $0 || candidate.hasPrefix($0) }
        if blocked || offensive { return "Offensive profile name" }
        if impersonation { return "Staff or official-service impersonation pattern" }
        return nil
    }

    func evaluate(
        guildID: String, userID: String, messageID: String, content: String, channelID: String = "",
        now: Date = Date(), attachments: [[String: Any]] = [], stickerCount: Int = 0,
        mentionEveryone: Bool = false, allowMassMentions: Bool = false, roleMentionCount: Int = 0, userMentionCount: Int = 0
    ) async -> Finding? {
        let value = await policy(guildID: guildID)
        guard value.enabled else { return nil }
        let rateKey = "moderation.rate." + guildID + "." + channelID + "." + userID
        var events = (await store.get(rateKey, as: [Date].self) ?? []).filter {
            now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 60
        }
        events.append(now)
        if events.count > 120 { events = Array(events.suffix(120)) }
        let normalizedContent = normalized(content)
        let defaultTerms = ["fuck", "fucking", "motherfucker", "shit", "bullshit", "bitch", "bastard", "asshole", "dickhead", "cunt", "slut", "whore", "retard"]
        let wordTokens = content.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
        let singleCharacterObfuscation = wordTokens.allSatisfy { $0.count == 1 }
        let customTerm = value.blockedPhrases.first { phrase in
            let needle = phrase.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
            guard !needle.isEmpty, needle.joined().count >= 2 else { return false }
            let tokenMatch = needle.count <= wordTokens.count
                && (0...(wordTokens.count - needle.count)).contains { start in
                    Array(wordTokens[start..<(start + needle.count)]) == needle
                }
            let obfuscatedMatch = singleCharacterObfuscation && wordTokens.joined().contains(needle.joined())
            return tokenMatch || obfuscatedMatch
        }
        let tokens = wordTokens
        var compactRuns: [String] = []
        var singleCharacterRun = ""
        for token in tokens {
            if token.count == 1 {
                singleCharacterRun += token
            } else {
                if !singleCharacterRun.isEmpty { compactRuns.append(singleCharacterRun); singleCharacterRun = "" }
                compactRuns.append(token)
            }
        }
        if !singleCharacterRun.isEmpty { compactRuns.append(singleCharacterRun) }
        let profanity = compactRuns.contains { token in
            defaultTerms.contains { token == normalized($0) }
        }
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
        let massMention = value.blockMassMentions
            && ((mentionEveryone || content.contains("@everyone") || content.contains("@here")) && !allowMassMentions
                || userMentionCount >= 5 || roleMentionCount >= 3)
        let invite = value.blockInvites && content.range(
            of: #"(?i)(?:discord\.gg/|discord(?:app)?\.com/invite/)"#, options: .regularExpression) != nil
        let advertisingPhrases = [
            "join my server", "join our server", "my discord server", "follow my channel",
            "subscribe to my channel", "check out my channel", "support my stream",
            "use my referral", "use my promo code", "follow me on twitch", "follow me on tiktok",
        ]
        let hasExternalLink = content.range(
            of: #"(?i)(?:https?://|www\.|(?<![@\w])(?:[a-z0-9-]+\.)+(?:com|net|org|io|gg|co|ru|xyz|top|link|info|biz))"#, options: .regularExpression) != nil
        let selfAdvertising = value.blockSelfAdvertising && hasExternalLink
            && advertisingPhrases.contains { normalizedContent.contains(normalized($0)) }
        let suspiciousLink = containsSuspiciousURL(content)
        let attachmentsBlocked = attachments.contains { item in
            let filename = item["filename"] as? String ?? ""
            let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
            let contentType = (item["content_type"] as? String ?? "").lowercased()
            let dangerousTypes = [
                "application/x-msdownload", "application/x-dosexec", "application/x-executable",
                "application/x-sh", "application/javascript", "text/javascript",
                "application/vnd.android.package-archive",
            ]
            return ["exe", "dll", "com", "scr", "msi", "bat", "cmd", "ps1", "sh", "bash", "vbs", "js", "hta", "jar", "apk", "dmg", "pkg", "py", "pyc", "wasm", "lnk", "reg", "sys"].contains(ext)
                || dangerousTypes.contains(contentType)
        }
        let duplicateKey = "moderation.duplicates." + guildID + "." + channelID + "." + userID
        var repeated = (await store.get(duplicateKey, as: [DuplicateEvent].self) ?? []).filter {
            now.timeIntervalSince($0.timestamp) >= 0 && now.timeIntervalSince($0.timestamp) <= 10
        }
        repeated.append(DuplicateEvent(content: normalizedContent, timestamp: now))
        if repeated.count > 30 { repeated = Array(repeated.suffix(30)) }
        let duplicate = repeated.filter { $0.content == normalizedContent }.count >= 3 && normalizedContent.count > 3
        if let rateData = try? JSONEncoder().encode(events),
            let duplicateData = try? JSONEncoder().encode(repeated)
        {
            try? await store.setGuildBatch(
                [rateKey: rateData, duplicateKey: duplicateData], guildID: guildID)
        }
        let triggered = customTerm != nil || profanity || spam || excessive || caps || formattingWall
            || emojiSpam || massMention || invite || suspiciousLink || selfAdvertising || attachmentsBlocked || duplicate
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
        if selfAdvertising { add("Unsolicited self-advertising", 50) }
        if suspiciousLink { add("Suspicious or tracking URL", 90) }
        if attachmentsBlocked { add("Executable or script attachment", 95) }
        if duplicate { add("Repeated message burst", 55) }

        let infractionKey = "moderation.infractions." + guildID
        var infractions = await store.get(infractionKey, as: [String: Int].self) ?? [:]
        let total = min(10000, (infractions[userID] ?? 0) + 1)
        infractions[userID] = total
        try? await store.setGuild(infractions, key: infractionKey, guildID: guildID)
        if total >= 3 {
            score += min(30, (total - 2) * 5)
            reasons.append("Cumulative infractions: " + String(total))
        }
        if suspiciousLink || attachmentsBlocked || invite {
            let globalKey = "security.global-threats"
            var profiles = await store.get(globalKey, as: [String: GlobalThreat].self) ?? [:]
            var profile = profiles[userID] ?? GlobalThreat(guilds: [], incidents: 0, reasons: [], lastSeen: now)
            if !profile.guilds.contains(guildID) { profile.guilds.append(guildID) }
            profile.incidents = min(10000, profile.incidents + 1)
            profile.reasons = Array(Set(profile.reasons + reasons).sorted().prefix(8))
            profile.lastSeen = now
            profiles[userID] = profile
            if profiles.count > 10000 {
                let stale = profiles.sorted { $0.value.lastSeen < $1.value.lastSeen }
                for item in stale.prefix(profiles.count - 10000) { profiles.removeValue(forKey: item.key) }
            }
            try? await store.set(profiles, key: globalKey)
            if profile.guilds.count >= 2 {
                score += 20
                reasons.append("High-confidence threat observed across multiple servers")
            }
        }
        return Finding(guildID: guildID, userID: userID, messageID: messageID, reason: reasons.joined(separator: "; "), score: min(200, score))
    }
}
