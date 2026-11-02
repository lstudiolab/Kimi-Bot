import Foundation

struct MessagePolicy {
    struct Result: Sendable {
        let shouldDelete: Bool
        let shouldTimeout: Bool
        let timeoutSeconds: Int
        let reason: String
        let score: Int
    }
    func evaluate(content: String, rateCount: Int, blocked: [String], maxMessages: Int = 20) -> Result? {
        let text = content.lowercased()
        if let phrase = blocked.first(where: { !$0.isEmpty && text.contains($0.lowercased()) }) {
            return Result(
                shouldDelete: true, shouldTimeout: false, timeoutSeconds: 0, reason: "Blocked phrase: \(phrase)",
                score: 90)
        }
        if rateCount > maxMessages {
            return Result(
                shouldDelete: true, shouldTimeout: true, timeoutSeconds: 600, reason: "Message rate exceeded", score: 95
            )
        }
        if content.count > 1900 {
            return Result(
                shouldDelete: true, shouldTimeout: false, timeoutSeconds: 0, reason: "Message exceeds safe length",
                score: 35)
        }
        if content.filter({ $0.isUppercase }).count > max(12, content.count * 7 / 10), content.count > 30 {
            return Result(
                shouldDelete: true, shouldTimeout: false, timeoutSeconds: 0, reason: "Excessive capital letters",
                score: 45)
        }
        let mentions = content.components(separatedBy: "<@").count - 1
        if mentions >= 8 {
            return Result(
                shouldDelete: true, shouldTimeout: false, timeoutSeconds: 0, reason: "Mass mention pattern", score: 80)
        }
        return nil
    }
}
