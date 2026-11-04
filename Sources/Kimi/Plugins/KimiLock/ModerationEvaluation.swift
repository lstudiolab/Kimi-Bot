import Foundation

extension ModerationEngine {
        func evaluate(
            guildID: String, userID: String, messageID: String, content: String, channelID: String = "",
            now: Date = Date(), attachments: [[String: Any]] = [], stickerCount: Int = 0,
            mentionEveryone: Bool = false, allowMassMentions: Bool = false, roleMentionCount: Int = 0,
            userMentionCount: Int = 0, isEdit: Bool = false
        ) async -> Finding? {
            await acquireEvaluation()
            defer { releaseEvaluation() }
            let value = await policy(guildID: guildID)
            guard value.enabled else { return nil }
            let rateKey = "moderation.rate." + guildID + "." + channelID + "." + userID
            let previousRateEvents: [Date]
            if let cached = rateHistory[rateKey] {
                previousRateEvents = cached
            } else {
                previousRateEvents = await store.get(rateKey, as: [Date].self) ?? []
            }
            var events = previousRateEvents.filter {
                now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 60
            }
            if !isEdit { events.append(now) }
            if events.count > 120 { events = Array(events.suffix(120)) }
            rateHistory[rateKey] = events
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
            let spam = !isEdit && events.count > max(1, value.messagesPerMinute)
            let excessive = content.utf16.count > 1900
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
            let storedDuplicates: [DuplicateEvent]
            if let cached = duplicateHistory[duplicateKey] { storedDuplicates = cached }
            else { storedDuplicates = await store.get(duplicateKey, as: [DuplicateEvent].self) ?? [] }
            var repeated = storedDuplicates.filter {
                now.timeIntervalSince($0.timestamp) >= 0 && now.timeIntervalSince($0.timestamp) <= 10
            }
            if !isEdit { repeated.append(DuplicateEvent(content: normalizedContent, timestamp: now)) }
            if repeated.count > 30 { repeated = Array(repeated.suffix(30)) }
            duplicateHistory[duplicateKey] = repeated
            if rateHistory.count > 5000 {
                rateHistory = rateHistory.filter {
                    $0.value.last.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 60 } ?? false
                }
            }
            if duplicateHistory.count > 5000 {
                duplicateHistory = duplicateHistory.filter {
                    $0.value.last.map { now.timeIntervalSince($0.timestamp) >= 0 && now.timeIntervalSince($0.timestamp) < 30 } ?? false
                }
            }
            let duplicate = !isEdit && repeated.filter { $0.content == normalizedContent }.count >= 3
                && normalizedContent.count > 3
            if events.count == 1 || events.count.isMultiple(of: 5) || spam || duplicate {
                if let rateData = try? JSONEncoder().encode(events),
                    let duplicateData = try? JSONEncoder().encode(repeated)
                {
                    do {
                        try await store.setGuildBatch(
                            [rateKey: rateData, duplicateKey: duplicateData], guildID: guildID)
                    } catch {
                        // The in-memory rolling windows remain authoritative until the next successful checkpoint.
                    }
                }
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
