import Foundation

struct VerificationEngine {
    enum Decision: String, Codable, Sendable { case approve, review, reject }
    struct Result: Sendable {
        let score: Int
        let decision: Decision
        let reasons: [String]
    }
    func evaluate(
        createdAt: Date, defaultAvatar: Bool, suspiciousBehavior: Bool, attempts: Int, minimumAgeDays: Int = 7,
        now: Date = Date()
    ) -> Result {
        let age = max(0, Int(now.timeIntervalSince(createdAt) / 86400))
        let agePass = age >= max(0, minimumAgeDays)
        var score = agePass ? 40 : 0
        score += suspiciousBehavior ? 0 : 30
        score += attempts <= 1 ? 20 : max(0, 20 - (attempts - 1) * 10)
        score += defaultAvatar ? 0 : 10
        var reasons: [String] = []
        if !agePass { reasons.append("Account age is below the configured minimum.") }
        if attempts > 1 { reasons.append("Repeated verification attempts were recorded.") }
        if suspiciousBehavior { reasons.append("Previous suspicious behavior was recorded.") }
        if defaultAvatar { reasons.append("Default avatar is a low-weight risk signal.") }
        let decision = score >= 80 ? Decision.approve : (score >= 60 ? Decision.review : Decision.reject)
        return Result(score: min(100, max(0, score)), decision: decision, reasons: reasons)
    }
}
