import Foundation

actor RaidProtectionService {
    struct Incident: Codable, Sendable {
        let guildID: String
        let joinedAt: Date
        let joinCount: Int
        let quarantinedUserID: String?
        let accountAgeDays: Int?
        let action: String
    }
    private struct Join: Codable, Sendable {
        let user: String
        let date: Date
        let createdAt: Date?
    }
    private let store: PersistentStore
    private let rest: DiscordREST
    private let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func memberJoined(guild: String, userID: String, createdAt: Date, isBot: Bool, now: Date = Date()) async {
        guard !isBot else { return }
        let key = "security.raid-joins." + guild
        let recent: [Join]
        do {
            recent = try await store.updateGuild(key, guildID: guild, as: [Join].self) { stored in
                var events = (stored ?? []).filter {
                    now.timeIntervalSince($0.date) <= 10 && now >= $0.date
                }
                events.append(Join(user: userID, date: now, createdAt: createdAt))
                return Array(events.suffix(1000))
            }
        } catch {
            await logger.log("ERROR", "Raid join history could not be persisted: " + error.localizedDescription)
            return
        }
        guard recent.count >= 8 else { return }
        let cooldownKey = "security.raid-cooldown." + guild
        guard let owner = try? await rest.ownerID(guild) else {
            await logger.log("WARN", "Raid protection could not resolve the guild owner; retrying on the next join.")
            return
        }
        do {
            guard try await store.claimGuildCooldown(
                cooldownKey, subject: "raid", guildID: guild, interval: 300, now: now)
            else { return }
        } catch {
            await logger.log("ERROR", "Raid protection could not reserve its cooldown: " + error.localizedDescription)
            return
        }
        let age = max(0, Int(now.timeIntervalSince(createdAt) / 86400))
        var action = "Raid burst detected; alert only."
        var quarantined: String? = nil
        let recentNewAccounts = Set(recent.compactMap { join -> String? in
            guard let createdAt = join.createdAt else { return nil }
            return max(0, Int(now.timeIntervalSince(createdAt) / 86400)) < 7 ? join.user : nil
        })
        var quarantinedUsers: [String] = []
        for candidate in recentNewAccounts where candidate != owner {
            do {
                try await rest.timeoutKimiMember(
                    guild, candidate, 10,
                    "Kimi Lock raid protection: newly created account joined during a coordinated join burst"
                )
                quarantinedUsers.append(candidate)
            } catch {
                await logger.log("WARN", "Raid protection could not timeout " + candidate + ": " + error.localizedDescription)
            }
        }
        if !quarantinedUsers.isEmpty {
            action = String(quarantinedUsers.count) + " newly created accounts temporarily timed out for 10 minutes."
            quarantined = quarantinedUsers.first
        }
        let incident = Incident(
            guildID: guild, joinedAt: now, joinCount: recent.count, quarantinedUserID: quarantined, accountAgeDays: age,
            action: action)
        var records = await store.get("security.raid-incidents", as: [Incident].self) ?? []
        records.append(incident)
        records = Array(records.suffix(500))
        do {
            try await store.set(records, key: "security.raid-incidents")
        } catch {
            await logger.log("ERROR", "Raid incident could not be persisted: " + error.localizedDescription)
        }
        await logger.log(
            "WARN",
            "Kimi Lock raid protection: " + String(recent.count) + " members joined within 10 seconds in guild " + guild
                + ". " + action)
        let legacy = await store.getLegacy("timi_setup", as: [String: [String: String]].self)
        let channel = await store.get("foundation.logs." + guild, as: String.self) ?? legacy?[guild]?["log_channel_id"]
        if let channel {
            let report =
                "**Kimi Lock · Join burst detected**\nMembers joined in 10 seconds: " + String(recent.count)
                + "\nNewest account age: " + String(age) + " days\nAutomatic action: " + action
            _ = try? await rest.call(
                "POST", "channels/" + channel + "/messages",
                body: ["content": report, "allowed_mentions": ["parse": []]])
        }
    }
}
