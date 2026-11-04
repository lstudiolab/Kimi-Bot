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
        let key = guildID + ":" + userID
        let all = try await store.updateGuild("verification.records", guildID: guildID, as: [String: Record].self) { stored in
            var values = stored ?? [:]
            var value = values[key] ?? Record(guildID: guildID, userID: userID)
            value.attempts += 1
            values[key] = value
            return values
        }
        guard let value = all[key] else { throw KimiError.invalidResponse }
        return value
    }

    func markFailed(guildID: String, userID: String, reason: String) async throws {
        let key = guildID + ":" + userID
        _ = try await store.updateGuild("verification.records", guildID: guildID, as: [String: Record].self) { stored in
            var values = stored ?? [:]
            var value = values[key] ?? Record(guildID: guildID, userID: userID)
            value.failures += 1
            value.lastReason = String(reason.prefix(300))
            values[key] = value
            return values
        }
    }

    func setReviewMessage(guildID: String, userID: String, messageID: String) async throws {
        let key = guildID + ":" + userID
        _ = try await store.updateGuild("verification.records", guildID: guildID, as: [String: Record].self) { stored in
            var values = stored ?? [:]
            var value = values[key] ?? Record(guildID: guildID, userID: userID)
            value.reviewMessageID = messageID
            values[key] = value
            return values
        }
    }

    func markVerified(guildID: String, userID: String) async throws {
        let key = guildID + ":" + userID
        _ = try await store.updateGuild("verification.records", guildID: guildID, as: [String: Record].self) { stored in
            var values = stored ?? [:]
            var value = values[key] ?? Record(guildID: guildID, userID: userID)
            value.verifiedAt = Date()
            value.reviewMessageID = nil
            values[key] = value
            return values
        }
    }
}
