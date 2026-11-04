import Foundation

actor KimiGuardService {
    struct Incident: Codable, Sendable {
        let id: String
        let guildID: String
        let actorID: String
        let action: String
        let reason: String
        let originalRoles: [String]
        let removedRoles: [String]
        let createdAt: Date
        let timeoutUntil: Date?
        var status: String
    }
    struct Result: Sendable {
        let incident: Incident
        let removedCount: Int
        let timeoutApplied: Bool
    }
    private let store: PersistentStore
    private let rest: DiscordREST
    private let logger: Logger
    init(store: PersistentStore, rest: DiscordREST, logger: Logger) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func contain(guild: String, actor: String, action: String) async throws -> Result? {
        let owner = try await rest.ownerID(guild)
        guard actor != owner else {
            await logger.log("WARN", "Kimi Guard ignored owner action in " + guild)
            return nil
        }
        let member = try await rest.call("GET", "guilds/\(guild)/members/\(actor)") as? [String: Any] ?? [:]
        let roleIDs = member["roles"] as? [String] ?? []
        let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
        let botMember = try await rest.call("GET", "guilds/\(guild)/members/@me") as? [String: Any] ?? [:]
        let botRoles = Set(botMember["roles"] as? [String] ?? [])
        let highest =
            roles.filter { role in botRoles.contains(role["id"] as? String ?? "") }.map { $0["position"] as? Int ?? 0 }
            .max() ?? 0
        let manageable = roles.filter { role in
            guard let id = role["id"] as? String, roleIDs.contains(id), id != guild, role["managed"] as? Bool != true
            else { return false }
            return (role["position"] as? Int ?? 0) < highest
        }
        var removed: [String] = []
        for role in manageable {
            guard let id = role["id"] as? String else { continue }
            do {
                _ = try await rest.call("DELETE", "guilds/\(guild)/members/\(actor)/roles/\(id)")
                removed.append(id)
            } catch {
                await logger.log("WARN", "Kimi Guard could not remove role " + id + ": " + error.localizedDescription)
            }
        }
        var timeoutUntil: Date? = nil
        if member["user"] as? [String: Any] != nil {
            let isBot = (member["user"] as? [String: Any])?["bot"] as? Bool ?? false
            if !isBot {
                do {
                    try await rest.timeoutKimiMember(
                        guild, actor, 40320, "Kimi Guard automatic containment after repeated privileged actions")
                    timeoutUntil = Date().addingTimeInterval(40320 * 60)
                } catch { await logger.log("WARN", "Kimi Guard timeout failed: " + error.localizedDescription) }
            }
        }
        let reason = "Repeated privileged action: " + action
        let incident = Incident(
            id: UUID().uuidString, guildID: guild, actorID: actor, action: action, reason: reason,
            originalRoles: roleIDs, removedRoles: removed, createdAt: Date(), timeoutUntil: timeoutUntil,
            status: removed.isEmpty && timeoutUntil == nil ? "review_required" : "restricted")
        var all = await store.get("guard.incidents", as: [String: Incident].self) ?? [:]
        all[guild + ":" + actor] = incident
        try await store.set(all, key: "guard.incidents")
        await logger.log(
            "WARN",
            "Kimi Guard " + incident.status + " actor " + actor + " in " + guild + "; removed " + String(removed.count)
                + " roles.")
        return Result(incident: incident, removedCount: removed.count, timeoutApplied: timeoutUntil != nil)
    }
    func review(guild: String, actor: String, decision: String, reviewer: String) async throws -> String {
        guard try await rest.ownerID(guild) == reviewer else {
            throw KimiError.configuration("Only the server owner can review a Kimi Guard incident.")
        }

        var all = await store.get("guard.incidents", as: [String: Incident].self) ?? [:]
        let key = guild + ":" + actor
        guard var incident = all[key],
            ["restricted", "review_required", "kept", "partial_release"].contains(incident.status)
        else {
            throw KimiError.configuration("No active Kimi Guard incident exists for this account.")
        }

        if decision == "keep" {
            incident.status = "kept"
            all[key] = incident
            try await store.set(all, key: "guard.incidents")
            return "The account remains restricted."
        }
        guard decision == "restore" else {
            throw KimiError.configuration("Choose restore or keep.")
        }

        let roles = try await rest.call("GET", "guilds/\\(guild)/roles") as? [[String: Any]] ?? []
        let botMember = try await rest.call("GET", "guilds/\\(guild)/members/@me") as? [String: Any] ?? [:]
        let botRoles = Set(botMember["roles"] as? [String] ?? [])
        let highest = roles.filter { botRoles.contains($0["id"] as? String ?? "") }
            .map { $0["position"] as? Int ?? 0 }.max() ?? 0
        let safe = incident.removedRoles.filter { id in
            guard let role = roles.first(where: { ($0["id"] as? String) == id }) else { return false }
            let permissions = UInt64(role["permissions"] as? String ?? "") ?? 0
            return (role["position"] as? Int ?? 0) < highest
                && SecurityPolicy.isSafeRole(
                    roleID: id, guildID: guild, managed: role["managed"] as? Bool ?? false,
                    permissions: permissions)
        }

        var failures: [String] = []
        for role in safe {
            do {
                _ = try await rest.call("PUT", "guilds/\\(guild)/members/\\(actor)/roles/\\(role)")
            } catch {
                failures.append("role \\(role): \\(error.localizedDescription)")
            }
        }

        if let expectedTimeout = incident.timeoutUntil {
            do {
                let current = try await rest.call(
                    "GET", "guilds/\\(guild)/members/\\(actor)") as? [String: Any] ?? [:]
                if let raw = current["communication_disabled_until"] as? String,
                    let actualTimeout = ISO8601DateFormatter().date(from: raw),
                    abs(actualTimeout.timeIntervalSince(expectedTimeout)) < 120
                {
                    _ = try await rest.call(
                        "PATCH", "guilds/\\(guild)/members/\\(actor)",
                        body: ["communication_disabled_until": NSNull()],
                        auditReason: "Released after server owner Kimi Guard review")
                }
            } catch {
                failures.append("timeout release: \\(error.localizedDescription)")
            }
        }

        incident.status = failures.isEmpty ? "released" : "partial_release"
        all[key] = incident
        try await store.set(all, key: "guard.incidents")

        if failures.isEmpty {
            return "Incident reviewed. Restored \\(safe.count) safe roles. Elevated roles were not restored."
        }
        return "Some restrictions could not be released. Restored \\(safe.count - failures.filter { $0.hasPrefix("role ") }.count) safe roles. Retry the review after resolving: "
            + failures.joined(separator: "; ")
    }\n}\n