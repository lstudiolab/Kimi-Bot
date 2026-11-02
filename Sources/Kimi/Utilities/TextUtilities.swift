import Foundation

enum TextUtilities {
    static let dayMilliseconds: Int64 = 86_400_000

    static func isSnowflake(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(of: #"^\d{15,22}$"#, options: .regularExpression) != nil
    }

    static func snowflakeDate(_ id: String, now: Date = Date()) -> Date {
        guard let raw = UInt64(id) else { return now }
        let milliseconds = (raw >> 22) + 1_420_070_400_000
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    static func normalizeMessage(_ value: String) -> String {
        var result = value.lowercased()
        for pattern in [#"https?://\S+"#, #"<@!?\d+>|<@&\d+>|<#\d+>"#] {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        result = result.replacingOccurrences(of: #"[\p{P}\p{C}]"#, with: " ", options: .regularExpression)
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func matchesBlockedPhrase(_ content: String, phrase: String) -> Bool {
        let haystack = content.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let needle = phrase.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !needle.isEmpty else { return false }
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            let before = range.lowerBound > haystack.startIndex ? haystack[haystack.index(before: range.lowerBound)] : nil
            let after = range.upperBound < haystack.endIndex ? haystack[range.upperBound] : nil
            func isWord(_ character: Character?) -> Bool {
                guard let character else { return false }
                return character.unicodeScalars.contains { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0) }
            }
            let first = needle.first, last = needle.last
            if (first.map { !isWord(before) } ?? true) && (last.map { !isWord(after) } ?? true) { return true }
            searchRange = range.upperBound..<haystack.endIndex
        }
        return false
    }

    static func jaccard(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(normalizeMessage(lhs).split(separator: " "))
        let right = Set(normalizeMessage(rhs).split(separator: " "))
        guard !left.isEmpty || !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    static func cleanChannelName(_ value: String) -> String {
        let lowered = value.lowercased()
        let mapped = lowered.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-") ? character : "-"
        }
        let collapsed = String(mapped).replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((collapsed.isEmpty ? "ticket" : collapsed).prefix(90))
    }

    static func chunkText(_ value: String, maximum: Int = 1900) -> [String] {
        let limit = max(1, maximum)
        var chunks: [String] = []
        var current = ""
        for line in value.components(separatedBy: "\n") {
            if line.isEmpty {
                if current.count < limit { current += current.isEmpty ? "" : "\n" }
                else if !current.isEmpty { chunks.append(current); current = "" }
                continue
            }
            var remaining = line[...]
            while !remaining.isEmpty {
                let separator = current.isEmpty ? "" : "\n"
                let room = limit - current.count - separator.count
                if room <= 0 { chunks.append(current); current = ""; continue }
                let end = remaining.index(remaining.startIndex, offsetBy: min(room, remaining.count))
                current += separator + remaining[..<end]
                remaining = remaining[end...]
                if !remaining.isEmpty { chunks.append(current); current = "" }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
