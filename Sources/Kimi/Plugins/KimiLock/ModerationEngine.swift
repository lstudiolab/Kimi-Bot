import Foundation

actor ModerationEngine {
    struct Policy: Codable, Sendable {
        var enabled: Bool = true
        var messagesPerMinute: Int = 20
        var timeoutMinutes: Int = 10
        var blockedPhrases: [String] = []
        var sanction: String = "timeout"
        var actionDurationSeconds: Int = 10
        var blockInvites, blockMassMentions: Bool = true
        var blockExcessiveCaps, blockSelfAdvertising: Bool = true
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
        let guildID, userID: String
        let messageID, reason: String
        let score: Int
    }
    struct Legacy: Decodable {
        var enabled: Bool?
        var timeout_minutes, max_message_count: Int?
        var sanction: String?
        var action_duration_seconds: Int?
        var block_invites, block_mass_mentions: Bool?
        var block_excessive_caps: Bool?
        var log_channel_id: String?
    }
    struct DuplicateEvent: Codable, Sendable {
        let content: String
        let timestamp: Date
    }
    struct GlobalThreat: Codable, Sendable {
        var guilds: [String]
        var incidents: Int
        var reasons: [String]
        var lastSeen: Date
    }
    let store: PersistentStore
    var policies: [String: Policy] = [:]
    var rateHistory: [String: [Date]] = [:]
    var duplicateHistory: [String: [DuplicateEvent]] = [:]
    var evaluationInProgress = false
    var evaluationWaiters: [CheckedContinuation<Void, Never>] = []
    var evaluationWaiterHead = 0

    func acquireEvaluation() async {
        if !evaluationInProgress {
            evaluationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            evaluationWaiters.append(continuation)
        }
    }

    func releaseEvaluation() {
        guard evaluationWaiterHead < evaluationWaiters.count else {
            evaluationWaiters.removeAll(keepingCapacity: true)
            evaluationWaiterHead = 0
            evaluationInProgress = false
            return
        }
        let continuation = evaluationWaiters[evaluationWaiterHead]
        evaluationWaiterHead += 1
        if evaluationWaiterHead >= 128 && evaluationWaiterHead * 2 >= evaluationWaiters.count {
            evaluationWaiters.removeFirst(evaluationWaiterHead)
            evaluationWaiterHead = 0
        }
        continuation.resume()
    }

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

}