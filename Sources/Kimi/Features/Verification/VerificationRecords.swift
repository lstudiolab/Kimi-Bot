import Foundation

actor VerificationRecords {
    struct Record: Codable, Sendable {
        let guildID: String
        let userID: String
        var attempts: Int = 0
        var verifiedAt: Date?
        var reviewMessageID: String?
        var failures: Int = 0
        var lastReason: String?
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func record(guildID: String, userID: String) async -> Record {
        let all = await store.get("verification.records", as: [String: Record].self) ?? [:]
        return all[guildID + ":" + userID] ?? Record(guildID: guildID, userID: userID)
    }
    func attempt(guildID: String, userID: String) async throws -> Record {
        var all = await store.get("verification.records", as: [String: Record].self) ?? [:]
        let key = guildID + ":" + userID
        var value = all[key] ?? Record(guildID: guildID, userID: userID)
        value.attempts += 1
        all[key] = value
        try await store.set(all, key: "verification.records")
        return value
    }
    func markFailed(guildID: String, userID: String, reason: String) async throws {
        var all = await store.get("verification.records", as: [String: Record].self) ?? [:]
        let key = guildID + ":" + userID
        var value = all[key] ?? Record(guildID: guildID, userID: userID)
        value.failures += 1
        value.lastReason = String(reason.prefix(300))
        all[key] = value
        try await store.set(all, key: "verification.records")
    }
    func setReviewMessage(guildID: String, userID: String, messageID: String) async throws {
        var all = await store.get("verification.records", as: [String: Record].self) ?? [:]
        let key = guildID + ":" + userID
        var value = all[key] ?? Record(guildID: guildID, userID: userID)
        value.reviewMessageID = messageID
        all[key] = value
        try await store.set(all, key: "verification.records")
    }
    func markVerified(guildID: String, userID: String) async throws {
        var all = await store.get("verification.records", as: [String: Record].self) ?? [:]
        let key = guildID + ":" + userID
        var value = all[key] ?? Record(guildID: guildID, userID: userID)
        value.verifiedAt = Date()
        value.reviewMessageID = nil
        all[key] = value
        try await store.set(all, key: "verification.records")
    }
}
