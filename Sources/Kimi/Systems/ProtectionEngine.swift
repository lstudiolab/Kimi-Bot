import Foundation

struct ProtectionEngine {
    struct Finding: Sendable {
        let severity: Int
        let reason: String
    }
    func evaluate(action: String, count: Int, threshold: Int) -> Finding? {
        guard count > max(1, threshold) else { return nil }
        let critical = ["channel_delete", "role_delete", "webhook_create", "ban", "kick"].contains(action)
        return Finding(
            severity: critical ? 100 : 70, reason: "Repeated privileged action exceeded its configured threshold.")
    }
}
