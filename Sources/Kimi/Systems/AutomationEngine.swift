import Foundation

actor AutomationEngine {
    struct Rule: Codable, Sendable, Identifiable {
        let id: String
        let guildID: String
        var name: String
        var trigger: String
        var condition: String?
        var action: String
        var enabled: Bool
        let createdAt: Date
    }
    struct Execution: Codable, Sendable {
        let ruleID: String
        let guildID: String
        let trigger: String
        let success: Bool
        let detail: String
        let createdAt: Date
    }
    private let store: PersistentStore
    private let rest: DiscordREST?
    private let logger: Logger?
    private let triggers: Set<String> = ["message_create", "message_contains", "member_join", "member_leave"]
    private let actions: Set<String> = ["delete_message", "send_message", "timeout", "add_role", "remove_role"]
    init(store: PersistentStore, rest: DiscordREST? = nil, logger: Logger? = nil) {
        self.store = store
        self.rest = rest
        self.logger = logger
    }
    func rules(guildID: String) async -> [Rule] {
        (await store.get("automation.rules", as: [Rule].self) ?? []).filter { $0.guildID == guildID }
    }
    func add(guildID: String, name: String, trigger: String, action: String, condition: String? = nil) async throws
        -> Rule
    {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KimiError.configuration("Enter a name for this automation.")
        }
        guard triggers.contains(trigger) else {
            throw KimiError.configuration(
                "Unsupported trigger. Choose message_create, message_contains, member_join or member_leave.")
        }
        if trigger == "message_contains" && (condition?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        {
            throw KimiError.configuration("message_contains requires a text condition.")
        }
        let parts = action.split(separator: ":", maxSplits: 2).map(String.init)
        guard let kind = parts.first, actions.contains(kind) else {
            throw KimiError.configuration(
                "Unsupported action. Choose delete_message, send_message, timeout, add_role or remove_role.")
        }
        if kind == "send_message"
            && (parts.count < 3 || parts[1].range(of: #"^\d{15,22}$"#, options: .regularExpression) == nil
                || parts[2].isEmpty)
        {
            throw KimiError.configuration("send_message action format: send_message:CHANNEL_ID:message")
        }
        if kind == "timeout" && (parts.count < 2 || !(1...40320).contains(Int(parts[1]) ?? 0)) {
            throw KimiError.configuration("timeout action format: timeout:MINUTES")
        }
        if (kind == "add_role" || kind == "remove_role")
            && (parts.count < 2 || parts[1].range(of: #"^\d{15,22}$"#, options: .regularExpression) == nil)
        {
            throw KimiError.configuration(kind + " action format: " + kind + ":ROLE_ID")
        }
        var values = await store.get("automation.rules", as: [Rule].self) ?? []
        guard values.filter({ $0.guildID == guildID }).count < 100 else {
            throw KimiError.configuration("This server has reached the 100-rule limit.")
        }
        let rule = Rule(
            id: UUID().uuidString, guildID: guildID, name: String(name.prefix(80)), trigger: trigger,
            condition: condition.map { String($0.prefix(200)) }, action: action, enabled: true, createdAt: Date())
        values.append(rule)
        try await store.setGuild(values, key: "automation.rules", guildID: guildID)
        return rule
    }
    func setEnabled(_ enabled: Bool, id: String, guildID: String) async throws -> Bool {
        var values = await store.get("automation.rules", as: [Rule].self) ?? []
        guard let i = values.firstIndex(where: { $0.id == id && $0.guildID == guildID }) else { return false }
        values[i].enabled = enabled
        try await store.setGuild(values, key: "automation.rules", guildID: guildID)
        return true
    }
    func remove(id: String, guildID: String) async throws -> Bool {
        var values = await store.get("automation.rules", as: [Rule].self) ?? []
        let before = values.count
        values.removeAll { $0.id == id && $0.guildID == guildID }
        guard values.count != before else { return false }
        try await store.setGuild(values, key: "automation.rules", guildID: guildID)
        return true
    }
    func matching(guildID: String, trigger: String, content: String = "") async -> [Rule] {
        await rules(guildID: guildID).filter { rule in
            if !rule.enabled { return false }
            if rule.trigger == trigger { return true }
            guard rule.trigger == "message_contains", !content.isEmpty, let condition = rule.condition,
                !condition.isEmpty
            else { return false }
            return content.localizedCaseInsensitiveContains(condition)
        }
    }
    func record(_ execution: Execution) async {
        var values = await store.get("automation.executions", as: [Execution].self) ?? []
        values.append(execution)
        values = Array(values.suffix(1000))
        try? await store.setGuild(values, key: "automation.executions", guildID: execution.guildID)
    }
    func executions(guildID: String) async -> [Execution] {
        (await store.get("automation.executions", as: [Execution].self) ?? []).filter { $0.guildID == guildID }
    }
    func run(
        trigger: String, guild: String, user: String = "", channel: String = "", message: String = "",
        username: String = "member", server: String = "server", messageID: String? = nil
    ) async {
        guard let rest else { return }
        let candidates = await matching(guildID: guild, trigger: trigger, content: message)
        for rule in candidates {
            do {
                let parts = rule.action.split(separator: ":", maxSplits: 2).map(String.init)
                guard let kind = parts.first else { continue }
                switch kind {
                case "send_message":
                    guard parts.count == 3 else { throw KimiError.configuration("Invalid send_message rule.") }
                    let text = parts[2].replacingOccurrences(of: "{user}", with: user.isEmpty ? "" : "<@" + user + ">")
                        .replacingOccurrences(of: "{username}", with: username).replacingOccurrences(
                            of: "{server}", with: server)
                    _ = try await rest.call(
                        "POST", "channels/\(parts[1])/messages",
                        body: ["content": String(text.prefix(1900)), "allowed_mentions": ["parse": []]])
                case "delete_message":
                    guard let messageID, !channel.isEmpty else {
                        throw KimiError.configuration("No triggering message is available to delete.")
                    }
                    try await rest.deleteKimiMessage(channel, messageID)
                case "timeout":
                    guard !user.isEmpty else { throw KimiError.configuration("No member is available to timeout.") }
                    let owner = try await rest.ownerID(guild)
                    guard user != owner else {
                        throw KimiError.configuration("Automation cannot timeout the server owner.")
                    }
                    let member = try await rest.call("GET", "guilds/\(guild)/members/\(user)") as? [String: Any] ?? [:]
                    let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
                    let ids = Set(member["roles"] as? [String] ?? [])
                    let elevated = roles.contains { role in
                        ids.contains(role["id"] as? String ?? "")
                            && ((UInt64(role["permissions"] as? String ?? "") ?? 0)
                                & ((1 << 3) | (1 << 5) | (1 << 28) | (1 << 29) | (1 << 30) | (1 << 31) | (1 << 32)))
                                != 0
                    }
                    guard member["user"] != nil, !elevated else {
                        throw KimiError.configuration("Automation cannot timeout bots or privileged members.")
                    }
                    try await rest.timeoutKimiMember(guild, user, Int(parts[1]) ?? 10, "Kimi automation: " + rule.name)
                case "add_role", "remove_role":
                    guard parts.count == 2, !user.isEmpty else {
                        throw KimiError.configuration("Invalid role automation.")
                    }
                    let roles = try await rest.call("GET", "guilds/\(guild)/roles") as? [[String: Any]] ?? []
                    guard let role = roles.first(where: { ($0["id"] as? String) == parts[1] }) else {
                        throw KimiError.configuration("Configured role no longer exists.")
                    }
                    let permissions = UInt64(role["permissions"] as? String ?? "") ?? 0
                    guard
                        SecurityPolicy.isSafeRole(
                            roleID: parts[1], guildID: guild, managed: role["managed"] as? Bool ?? false,
                            permissions: permissions)
                    else { throw KimiError.configuration("Automation role has elevated permissions or is managed.") }
                    let method = kind == "add_role" ? "PUT" : "DELETE"
                    _ = try await rest.call(method, "guilds/\(guild)/members/\(user)/roles/\(parts[1])")
                default: throw KimiError.configuration("Unsupported automation action.")
                }
                await record(
                    Execution(
                        ruleID: rule.id, guildID: guild, trigger: trigger, success: true, detail: "Completed " + kind,
                        createdAt: Date()))
            } catch {
                await logger?.log("ERROR", "Automation " + rule.id + " failed: " + error.localizedDescription)
                await record(
                    Execution(
                        ruleID: rule.id, guildID: guild, trigger: trigger, success: false,
                        detail: error.localizedDescription, createdAt: Date()))
            }
        }
    }
}
