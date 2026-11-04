import Foundation

extension ModerationEngine {
        func normalized(_ input: String) -> String {
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

        func containsSuspiciousURL(_ content: String) -> Bool {
            let pattern = #"(?i)(?:https?://|www\.)[^\s<>]+|(?<![@\w])(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:/[^\s<>]*)?|(?<![0-9])\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?(?:/[^\s<>]*)?"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(content.startIndex..., in: content)
            let urls = regex.matches(in: content, range: range).compactMap { match -> String? in
                guard let r = Range(match.range, in: content) else { return nil }
                return String(content[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?)]}>"))
            }
            let loggerDomains: Set<String> = [
                "grabify.link", "iplogger.org", "iplogger.com", "2no.co", "yip.su",
                "ps3cfw.com", "blasze.com", "leancoding.co", "stopify.co",
            ]
            let shorteners: Set<String> = ["bit.ly", "tinyurl.com", "t.co", "is.gd", "cutt.ly", "rb.gy"]
            return urls.contains { raw in
                let candidate = raw.hasPrefix("http://") || raw.hasPrefix("https://") ? raw : "https://" + raw
                guard let parts = URLComponents(string: candidate),
                    let host = parts.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                else { return true }
                if parts.user != nil || parts.password != nil || host.hasPrefix("xn--") || host.contains(".xn--") {
                    return true
                }
                let matchesKnownDomain = { (domains: Set<String>) in
                    domains.contains { host == $0 || host.hasSuffix("." + $0) }
                }
                if matchesKnownDomain(loggerDomains) || matchesKnownDomain(shorteners) { return true }
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
}
