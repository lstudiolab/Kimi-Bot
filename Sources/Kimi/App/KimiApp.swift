import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum KimiError: Error, LocalizedError {
    case configuration(String), invalidResponse, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .configuration(let s): return s
        case .invalidResponse: return "Invalid Discord response"
        case .http(let c, let s): return "Discord HTTP \(c): \(s)"
        }
    }
}
struct LogEntry: Sendable {
    let date: Date
    let level: String
    let message: String
}
enum DiscordText {
    static func prefixUTF16(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        var result = ""
        result.reserveCapacity(min(value.count, limit))
        var used = 0
        for scalar in value.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            guard used + width <= limit else { break }
            result.unicodeScalars.append(scalar)
            used += width
        }
        return result
    }
}

actor Logger {
    private var entries: [LogEntry] = []
    private var entryHead = 0
    private let dateFormatter = ISO8601DateFormatter()

    func log(_ level: String, _ message: String) {
        let now = Date()
        entries.append(LogEntry(date: now, level: level, message: message))
        if entries.count - entryHead > 1000 { entryHead += entries.count - entryHead - 1000 }
        if entryHead >= 256 && entryHead * 2 >= entries.count {
            entries.removeFirst(entryHead)
            entryHead = 0
        }
        let line = "[\(dateFormatter.string(from: now))] [\(level)] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    func recent(limit: Int = 100) -> [LogEntry] {
        guard limit > 0, entryHead < entries.count else { return [] }
        return Array(entries[entryHead...].suffix(limit))
    }
}
struct Configuration {
    let token: String
    let clientID: String
    let dataDirectory: URL
    static func load() throws -> Configuration {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var env: [String: String] = [:]
        if let text = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) {
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let p = line.split(separator: "=", maxSplits: 1).map(String.init)
                if p.count == 2 {
                    env[p[0].trimmingCharacters(in: .whitespaces)] = p[1].trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        func get(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? env[key] ?? "" }
        let token = get("DISCORD_TOKEN")
        let id = get("CLIENT_ID")
        guard !token.isEmpty else { throw KimiError.configuration("DISCORD_TOKEN is missing from .env") }
        guard id.range(of: #"^\d{15,22}$"#, options: .regularExpression) != nil else {
            throw KimiError.configuration("CLIENT_ID is invalid")
        }
        let dir = root.appendingPathComponent(get("DATA_DIR").isEmpty ? "data" : get("DATA_DIR"), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Configuration(token: token, clientID: id, dataDirectory: dir)
    }
}
actor PersistentStore {
    private let url: URL
    private var values: [String: Data] = [:]
    private var legacy: [String: Any] = [:]
    init(directory: URL) throws {
        url = directory.appendingPathComponent("timi.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw KimiError.configuration("The Kimi data file exists but could not be read: " + error.localizedDescription)
            }

            let root: [String: Any]
            do {
                guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw KimiError.invalidResponse
                }
                root = decoded
            } catch {
                throw KimiError.configuration("The Kimi data file is invalid JSON. The existing data was left untouched.")
            }

            legacy = root.filter { $0.key != "_swift_runtime" }
            if let runtime = root["_swift_runtime"] {
                do {
                    let runtimeData = try JSONSerialization.data(withJSONObject: runtime)
                    values = try JSONDecoder().decode([String: Data].self, from: runtimeData)
                } catch {
                    throw KimiError.configuration(
                        "The Swift runtime data is corrupted. The existing data was left untouched.")
                }
            }
            if values["plugins.installed"] == nil,
                let installed = legacy["installed_plugins"],
                let bytes = try? JSONSerialization.data(withJSONObject: installed)
            {
                values["plugins.installed"] = bytes
            }
        }
    }
    func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = values[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func getLegacy<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let value = legacy[key],
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func set<T: Encodable>(_ value: T, key: String) throws {
        var candidate = values
        candidate[key] = try JSONEncoder().encode(value)
        try persist(candidate)
    }
    func setGuild<T: Encodable>(_ value: T, key: String, guildID: String) throws {
        var candidate = values
        candidate[key] = try JSONEncoder().encode(value)
        let usage = guildUsage(guildID, source: candidate)
        guard usage <= StorageQuota.freeLimit else {
            throw KimiError.configuration(
                "This server has reached its 5 MB storage allowance. Remove old records or snapshots before saving more data."
            )
        }
        try persist(candidate)
    }
    func modify<T: Codable & Sendable, Result: Sendable>(
        _ key: String, as type: T.Type, transform: @Sendable (T?) throws -> (T, Result)
    ) throws -> Result {
        let current: T?
        if let data = values[key] {
            current = try JSONDecoder().decode(T.self, from: data)
        } else {
            current = nil
        }
        let (updated, result) = try transform(current)
        var candidate = values
        candidate[key] = try JSONEncoder().encode(updated)
        try persist(candidate)
        return result
    }

    func modifyGuild<T: Codable & Sendable, Result: Sendable>(
        _ key: String, guildID: String, as type: T.Type,
        transform: @Sendable (T?) throws -> (T, Result)
    ) throws -> Result {
        let current: T?
        if let data = values[key] {
            current = try JSONDecoder().decode(T.self, from: data)
        } else {
            current = nil
        }
        let (updated, result) = try transform(current)
        var candidate = values
        candidate[key] = try JSONEncoder().encode(updated)
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
        return result
    }

    func update<T: Codable & Sendable>(
        _ key: String, as type: T.Type, transform: @Sendable (T?) throws -> T
    ) throws -> T {
        let current: T?
        if let data = values[key] {
            current = try JSONDecoder().decode(T.self, from: data)
        } else {
            current = nil
        }
        let updated = try transform(current)
        var candidate = values
        candidate[key] = try JSONEncoder().encode(updated)
        try persist(candidate)
        return updated
    }

    func updateGuild<T: Codable & Sendable>(
        _ key: String, guildID: String, as type: T.Type, transform: @Sendable (T?) throws -> T
    ) throws -> T {
        let current: T?
        if let data = values[key] {
            current = try JSONDecoder().decode(T.self, from: data)
        } else {
            current = nil
        }
        let updated = try transform(current)
        var candidate = values
        candidate[key] = try JSONEncoder().encode(updated)
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
        return updated
    }

    func setGuildBatch(_ updates: [String: Data], guildID: String) throws {
        guard !updates.isEmpty else { return }
        var candidate = values
        for (key, data) in updates {
            candidate[key] = data
        }
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
    }
    func claimGuildCooldown(
        _ key: String, subject: String, guildID: String, interval: TimeInterval, now: Date = Date()
    ) throws -> Bool {
        var entries = get(key, as: [String: Date].self) ?? [:]
        if let previous = entries[subject],
            now.timeIntervalSince(previous) >= 0,
            now.timeIntervalSince(previous) < interval
        {
            return false
        }
        entries = entries.filter { now.timeIntervalSince($0.value) < 7 * 86400 }
        entries[subject] = now
        if entries.count > 10000 {
            entries = entries.sorted { $0.value > $1.value }.prefix(10000).reduce(into: [:]) { result, entry in result[entry.key] = entry.value }
        }
        var candidate = values
        candidate[key] = try JSONEncoder().encode(entries)
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
        return true
    }
    func reserveGuildCounter(_ key: String, guildID: String, limit: Int, initialValue: Int = 0) throws -> Int? {
        let current = max(initialValue, get(key, as: Int.self) ?? initialValue)
        guard current < limit else { return nil }
        var candidate = values
        let next = current + 1
        candidate[key] = try JSONEncoder().encode(next)
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
        return next
    }
    func releaseGuildCounter(_ key: String, guildID: String, minimumValue: Int = 0) throws -> Int {
        let current = max(minimumValue, get(key, as: Int.self) ?? minimumValue)
        let next = max(minimumValue, current - 1)
        var candidate = values
        candidate[key] = try JSONEncoder().encode(next)
        guard guildUsage(guildID, source: candidate) <= StorageQuota.freeLimit else {
            throw KimiError.configuration("This server has reached its storage allowance.")
        }
        try persist(candidate)
        return next
    }
    func storageUsage(guildID: String) -> Int { guildUsage(guildID, source: values) }
    func storageReport(guildID: String) -> (used: Int, limit: Int, percent: Int) {
        let used = storageUsage(guildID: guildID)
        let limit = StorageQuota.freeLimit
        return (used, limit, min(100, Int(Double(used) / Double(limit) * 100)))
    }
    /// Writes a complete candidate snapshot before publishing it to the actor's in-memory state.
    ///
    /// Keeping the in-memory value unchanged until the atomic file replacement succeeds prevents
    /// callers from observing data that was never durably committed.
    private func persist(_ candidate: [String: Data]) throws {
        var root = legacy
        let runtime = try JSONEncoder().encode(candidate)
        root["_swift_runtime"] = try JSONSerialization.jsonObject(with: runtime)
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        try data.write(to: url, options: .atomic)
        values = candidate
    }
    func guildStorageUsage(guildID: String) -> Int {
        guildUsage(guildID, source: values)
    }

    private func guildUsage(_ guild: String, source: [String: Data]) -> Int {
        var snapshot: [String: Any] = [:]
        func select(_ object: Any) -> Any? {
            if let dictionary = object as? [String: Any] {
                if let value = dictionary[guild] { return [guild: value] }
                let prefixed = dictionary.filter { $0.key.hasPrefix(guild + ":") || $0.key.hasPrefix(guild + ".") }
                if !prefixed.isEmpty { return prefixed }
                return nil
            }
            if let array = object as? [[String: Any]] {
                let selected = array.filter {
                    ($0["guildID"] as? String) == guild || ($0["guild_id"] as? String) == guild
                }
                return selected.isEmpty ? nil : selected
            }
            return nil
        }
        for (key, data) in source {
            if key.hasSuffix("." + guild) || key.contains("." + guild + ".") || key.contains("." + guild + ":") {
                if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    snapshot[key] = object
                }
                continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                let selected = select(object)
            else { continue }
            snapshot[key] = selected
        }
        for (key, value) in legacy {
            if let selected = select(value) { snapshot["legacy." + key] = selected }
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: snapshot, options: [.fragmentsAllowed]) else {
            return 0
        }
        return encoded.count
    }
}
actor DiscordREST {
    let token: String
    let session: URLSession
    private var globalRateLimitUntil = Date.distantPast
    let base = URL(string: "https://discord.com/api/v10/")!
    init(token: String) {
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }
    func call(_ method: String, _ path: String, body: Any? = nil, auditReason: String? = nil) async throws -> Any {
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL,
            url.scheme == "https", url.host?.lowercased() == "discord.com",
            url.user == nil, url.password == nil
        else {
            throw KimiError.configuration("Discord REST requests must target the official Discord API host.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auditReason {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
            let encoded = auditReason.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            request.setValue(encoded, forHTTPHeaderField: "X-Audit-Log-Reason")
        }
        if let body {
            if let object = body as? [String: Any],
                let components = object["components"] as? [[String: Any]]
            {
                try KimiUI.validateMessageComponents(components)
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        }
        var attempt = 0
        while true {
            let globalWait = globalRateLimitUntil.timeIntervalSinceNow
            if globalWait > 0 {
                try await Task.sleep(nanoseconds: UInt64(min(30, globalWait) * 1_000_000_000))
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw KimiError.invalidResponse }
            if http.statusCode == 429 && attempt < 4 {
                attempt += 1
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let delay =
                    object?["retry_after"] as? Double ?? Double(http.value(forHTTPHeaderField: "Retry-After") ?? "1")
                    ?? 1
                let isGlobal = object?["global"] as? Bool == true
                    || http.value(forHTTPHeaderField: "X-RateLimit-Global")?.lowercased() == "true"
                if isGlobal {
                    globalRateLimitUntil = max(
                        globalRateLimitUntil, Date().addingTimeInterval(max(0.25, min(30, delay))))
                } else {
                    try await Task.sleep(nanoseconds: UInt64(max(0.25, min(30, delay)) * 1_000_000_000))
                }
                continue
            }
            // A 5xx response to a non-idempotent request may have happened after Discord
            // applied the mutation. Retrying POST could create duplicate channels or messages.
            let retryableMethod = ["GET", "PUT", "DELETE"].contains(method.uppercased())
            if (500...599).contains(http.statusCode) && retryableMethod && attempt < 3 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 500_000_000))
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                throw KimiError.http(http.statusCode, String(data: data.prefix(1000), encoding: .utf8) ?? "")
            }
            return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
        }
    }
    func registerCommands(_ client: String) async throws {
        _ = try await call("PUT", "applications/\(client)/commands", body: CommandCatalog.globalCommands())
    }
    func respond(_ id: String, _ token: String, _ text: String) async throws {
        _ = try await call(
            "POST", "interactions/\(id)/\(token)/callback",
            body: [
                "type": 4,
                "data": ["content": DiscordText.prefixUTF16(text, limit: 1900), "flags": 64, "allowed_mentions": ["parse": []]],
            ])
    }
    func createChannel(guild: String, name: String, type: Int = 0) async throws -> String {
        let value = try await call("POST", "guilds/\(guild)/channels", body: ["name": name, "type": type])
        guard let id = (value as? [String: Any])?["id"] as? String, !id.isEmpty else {
            throw KimiError.invalidResponse
        }
        return id
    }
}
actor GatewayEventDispatcher {
    private let handler: @Sendable ([String: Any]) async -> Void
    private let logger: Logger
    private let maximumConcurrentInteractions = 8
    private let maximumConcurrentEvents = 16
    private let maximumQueued = 2048
    private var activeInteractions = 0
    private var activeEvents = 0
    private var interactions: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var interactionHead = 0
    private var eventHead = 0
    private var lastOverflowLog = Date.distantPast

    private var queuedCount: Int {
        interactions.count - interactionHead + events.count - eventHead
    }

    private func popInteraction() -> [String: Any]? {
        guard interactionHead < interactions.count else {
            interactions.removeAll(keepingCapacity: true)
            interactionHead = 0
            return nil
        }
        let value = interactions[interactionHead]
        interactionHead += 1
        if interactionHead >= 128 && interactionHead * 2 >= interactions.count {
            interactions.removeFirst(interactionHead)
            interactionHead = 0
        }
        return value
    }

    private func popEvent() -> [String: Any]? {
        guard eventHead < events.count else {
            events.removeAll(keepingCapacity: true)
            eventHead = 0
            return nil
        }
        let value = events[eventHead]
        eventHead += 1
        if eventHead >= 128 && eventHead * 2 >= events.count {
            events.removeFirst(eventHead)
            eventHead = 0
        }
        return value
    }

    init(logger: Logger, handler: @escaping @Sendable ([String: Any]) async -> Void) {
        self.logger = logger
        self.handler = handler
    }

    func enqueue(_ event: [String: Any], isInteraction: Bool) async {
        if queuedCount >= maximumQueued {
            if isInteraction, eventHead < events.count {
                // Interactions are latency-sensitive; evict a lower-priority dispatch event first.
                _ = popEvent()
            } else if isInteraction, interactionHead < interactions.count {
                // Keep the queue strictly bounded during interaction-only bursts.
                // Oldest queued interactions are closest to token expiry, so retain newer work.
                _ = popInteraction()
            } else {
                if Date().timeIntervalSince(lastOverflowLog) >= 10 {
                    lastOverflowLog = Date()
                    await logger.log(
                        "ERROR",
                        "Gateway event queue reached its hard limit; the incoming event was dropped.")
                }
                return
            }
            if Date().timeIntervalSince(lastOverflowLog) >= 10 {
                lastOverflowLog = Date()
                await logger.log(
                    "WARN",
                    "Gateway event queue reached capacity; lower-priority or oldest queued work was evicted.")
            }
        }
        if isInteraction {
            interactions.append(event)
        } else {
            events.append(event)
        }
        schedule()
    }

    private func schedule() {
        while activeInteractions < maximumConcurrentInteractions, let event = popInteraction() {
            activeInteractions += 1
            let handler = self.handler
            Task {
                await handler(event)
                self.completed(isInteraction: true)
            }
        }
        while activeEvents < maximumConcurrentEvents, let event = popEvent() {
            activeEvents += 1
            let handler = self.handler
            Task {
                await handler(event)
                self.completed(isInteraction: false)
            }
        }
    }

    private func completed(isInteraction: Bool) {
        if isInteraction {
            activeInteractions = max(0, activeInteractions - 1)
        } else {
            activeEvents = max(0, activeEvents - 1)
        }
        schedule()
    }
}

actor DiscordGateway {
    private let token: String
    private let logger: Logger
    private let dispatcher: GatewayEventDispatcher
    private var socket: URLSessionWebSocketTask?
    private var sequence: Int?
    private var sessionID: String?
    private var resumeURL: String?
    private var heartbeat: Task<Void, Never>?
    private var heartbeatInterval: Double = 41.25
    private var awaitingHeartbeatAck = false
    private var reconnectDelay: UInt64 = 2_000_000_000
    init(token: String, logger: Logger, onEvent: @escaping @Sendable ([String: Any]) async -> Void) {
        self.token = token
        self.logger = logger
        dispatcher = GatewayEventDispatcher(logger: logger, handler: onEvent)
    }

    func run() async {
        while !Task.isCancelled {
            do {
                try await connect()
            } catch { await logger.log("ERROR", "Discord Gateway: " + error.localizedDescription) }
            heartbeat?.cancel()
            heartbeat = nil
            awaitingHeartbeatAck = false
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            try? await Task.sleep(nanoseconds: reconnectDelay)
            reconnectDelay = min(reconnectDelay * 2, 30_000_000_000)
        }
    }
    private func connect() async throws {
        let endpoint =
            resumeURL.map { $0.contains("?") ? $0 : $0 + "?v=10&encoding=json" }
            ?? "wss://gateway.discord.gg/?v=10&encoding=json"
        guard let url = URL(string: endpoint), url.scheme == "wss",
            let host = url.host?.lowercased(),
            (host == "discord.gg" || host == "gateway.discord.gg" || host.hasSuffix(".discord.gg")),
            url.user == nil, url.password == nil
        else {
            throw KimiError.configuration("Discord supplied an invalid Gateway resume URL.")
        }
        let ws = URLSession.shared.webSocketTask(with: url)
        socket = ws
        ws.resume()
        await logger.log("INFO", "Discord Gateway socket connected.")
        var incomingBuffer = Data()
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await ws.receive()
            } catch {
                if [4006, 4007, 4009].contains(ws.closeCode.rawValue) {
                    sessionID = nil
                    sequence = nil
                    resumeURL = nil
                    await logger.log("WARN", "Discord Gateway session expired; the next connection will identify again.")
                }
                throw error
            }
            let chunk: Data
            switch message {
            case .data(let value): chunk = value
            case .string(let value): chunk = Data(value.utf8)
            @unknown default: continue
            }

            // FoundationNetworking on Android can expose a fragmented WebSocket
            // message as multiple receive results. Buffer bytes until one complete
            // JSON object is available; never parse an individual fragment.
            incomingBuffer.append(chunk)
            if incomingBuffer.count > 8 * 1024 * 1024 {
                await logger.log("WARN", "Discord Gateway discarded an oversized incomplete message.")
                incomingBuffer.removeAll(keepingCapacity: true)
                continue
            }

            while let frame = GatewayJSONFramer.takeFrame(from: &incomingBuffer) {
                let packet: [String: Any]
                do {
                    guard
                        let decoded = try JSONSerialization.jsonObject(
                            with: frame,
                            options: [.fragmentsAllowed]
                        ) as? [String: Any]
                    else {
                        await logger.log("WARN", "Discord Gateway ignored a non-object JSON message.")
                        continue
                    }
                    packet = decoded
                } catch {
                    await logger.log(
                        "WARN",
                        "Discord Gateway ignored an invalid JSON message (\(frame.count) bytes; prefix hex "
                            + frame.prefix(24).map { String(format: "%02x", $0) }.joined() + ")"
                    )
                    continue
                }
                if let value = packet["s"] as? Int { sequence = value }
                let opcode = packet["op"] as? Int ?? -1
                let rawPayload = packet["d"]
                let payload = rawPayload as? [String: Any] ?? [:]
                switch opcode {
                case 10:
                    heartbeatInterval = (payload["heartbeat_interval"] as? Double ?? 41250) / 1000
                    if let sessionID, let sequence {
                        try await send(["op": 6, "d": ["token": token, "session_id": sessionID, "seq": sequence]])
                        await logger.log("INFO", "Resuming Discord Gateway session.")
                    } else {
                        let intents = 1 | 2 | 4 | 32 | 128 | 512 | 1024 | 32768 | 65536
                        try await send([
                            "op": 2,
                            "d": [
                                "token": token, "intents": intents,
                                "properties": ["os": "linux", "browser": "Kimi Swift", "device": "Termux"],
                            ],
                        ])
                    }
                    heartbeat?.cancel()
                    heartbeat = Task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: UInt64(max(1, self.heartbeatInterval) * 1_000_000_000))
                            if Task.isCancelled { return }
                            await self.heartbeatTick()
                        }
                    }
                case 1:
                    await heartbeatTick()
                case 7:
                    throw KimiError.http(0, "Gateway requested reconnect.")
                case 9:
                    let resumable = rawPayload as? Bool ?? false
                    if !resumable {
                        sessionID = nil
                        sequence = nil
                        resumeURL = nil
                    }
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000_000...5_000_000_000))
                    throw KimiError.http(0, "Gateway invalidated the session.")
                case 11:
                    awaitingHeartbeatAck = false
                default: break
                }
                if let name = packet["t"] as? String {
                    if name == "READY" {
                        sessionID = payload["session_id"] as? String
                        resumeURL = payload["resume_gateway_url"] as? String
                        reconnectDelay = 2_000_000_000
                    }
                    if name == "RESUMED" {
                        reconnectDelay = 2_000_000_000
                        await logger.log("INFO", "Discord Gateway session resumed.")
                    }
                    // Keep application work off the receive loop while bounding queued and active work.
                    await dispatcher.enqueue(
                        ["name": name, "data": payload], isInteraction: name == "INTERACTION_CREATE")
                }
            }
        }
    }
    private func heartbeatTick() async {
        if awaitingHeartbeatAck {
            socket?.cancel(with: .goingAway, reason: Data("Heartbeat acknowledgement timed out".utf8))
            return
        }
        awaitingHeartbeatAck = true
        do { try await send(["op": 1, "d": sequence as Any? ?? NSNull()]) } catch {
            socket?.cancel(with: .goingAway, reason: nil)
        }
    }
    private func send(_ object: [String: Any]) async throws {
        guard let socket else { throw KimiError.invalidResponse }
        try await socket.send(.data(JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])))
    }
}
actor KimiRuntime {
    let rest: DiscordREST
    let store: PersistentStore
    let logger: Logger
    let clientID: String
    let performance: PerformanceMonitor
    let moderation: ModerationEngine
    let imageAnalysis: ImageAnalysisService
    var moderationDeletedMessageIDs: [String: Date] = [:]
    init(
        rest: DiscordREST, store: PersistentStore, logger: Logger, clientID: String,
        performance: PerformanceMonitor = PerformanceMonitor()
    ) {
        self.rest = rest
        self.store = store
        self.logger = logger
        self.clientID = clientID
        self.performance = performance
        self.moderation = ModerationEngine(store: store)
        self.imageAnalysis = ImageAnalysisService(store: store, rest: rest, logger: logger)
    }
    func handle(_ event: [String: Any]) async { _ = await handleMigratedCommand(event) }

}
@main struct KimiApp {
    static func main() async {
        do {
            let config = try Configuration.load()
            let logger = Logger()
            let store = try PersistentStore(directory: config.dataDirectory)
            let rest = DiscordREST(token: config.token)
            try await rest.registerCommands(config.clientID)
            await logger.log("INFO", "Kimi Swift started. Global commands synchronized.")
            let runtime = KimiRuntime(
                rest: rest, store: store, logger: logger, clientID: config.clientID)
            let gateway = DiscordGateway(token: config.token, logger: logger) { event in
                let name = event["name"] as? String ?? ""
                let data = event["data"] as? [String: Any] ?? [:]
                if name == "INTERACTION_CREATE" {
                    await runtime.handle(data)
                } else {
                    await runtime.dispatchMigratedEvent(name, data)
                    if name == "READY" { await logger.log("INFO", "Discord READY.") }
                }
            }
            await gateway.run()
        } catch {
            FileHandle.standardError.write(Data("Kimi startup failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
