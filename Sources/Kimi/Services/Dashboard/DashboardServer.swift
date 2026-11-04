import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

final class DashboardServer: @unchecked Sendable {
    private struct OAuthGuild: Decodable, Sendable {
        let id: String
        let name: String
        let owner: Bool?
        let permissions: String?
        let permissions_new: String?
    }
    private struct OAuthUser: Decodable, Sendable {
        let id: String
        let username: String
        let global_name: String?
    }
    private struct Session: Sendable {
        let user: OAuthUser
        let accessToken: String
        let expiresAt: Date
        let csrf: String
        let guilds: [OAuthGuild]
    }
    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: String
    }
    private let config: Configuration
    private let rest: DiscordREST
    private let store: PersistentStore
    private let logger: Logger
    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    private var states: [String: Date] = [:]
    private var listener: Int32 = -1
    init(config: Configuration, rest: DiscordREST, store: PersistentStore, logger: Logger) {
        self.config = config
        self.rest = rest
        self.store = store
        self.logger = logger
    }
    func start() {
        guard !config.oauthSecret.isEmpty, !config.oauthRedirectURI.isEmpty else {
            Task {
                await logger.log(
                    "INFO", "Dashboard disabled: configure DISCORD_OAUTH_CLIENT_SECRET and DISCORD_OAUTH_REDIRECT_URI.")
            }
            return
        }
        #if canImport(Glibc)
            listener = Glibc.socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
            listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard listener >= 0 else {
            Task { await logger.log("ERROR", "Dashboard socket could not be created.") }
            return
        }
        var reuse: Int32 = 1
        _ = withUnsafePointer(to: &reuse) {
            setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = htons(UInt16(config.dashboardPort))
        address.sin_addr = in_addr(s_addr: inet_addr(config.dashboardHost == "0.0.0.0" ? "0.0.0.0" : "127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(listener, 64) == 0 else {
            Task {
                await logger.log(
                    "ERROR", "Dashboard could not bind to \(config.dashboardHost):\(config.dashboardPort).")
            }
            return
        }
        Task {
            await logger.log("INFO", "Swift dashboard listening on \(config.dashboardHost):\(config.dashboardPort).")
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.acceptLoop() }
    }
    private func acceptLoop() {
        while listener >= 0 {
            #if canImport(Glibc)
                let fd = Glibc.accept(listener, nil, nil)
            #else
                let fd = Darwin.accept(listener, nil, nil)
            #endif
            if fd < 0 { continue }
            Task.detached { await self.handle(fd) }
        }
    }
    private func handle(_ fd: Int32) async {
        defer { closeSocket(fd) }
        guard let request = readRequest(fd) else {
            write(fd, 400, "Bad Request", "text/plain")
            return
        }
        let host = request.headers["host"] ?? "localhost"
        let components = URLComponents(string: "http://" + host + request.path)
        let path = components?.path ?? "/"
        let query = Dictionary(
            (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let cookie = request.headers["cookie"] ?? ""
        let token = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.first(where: {
            $0.hasPrefix("kimi_session=")
        }).map { String($0.dropFirst("kimi_session=".count)) }
        let session = token.flatMap { getSession($0) }
        if request.method == "GET" && path == "/health" {
            write(fd, 200, "{\"ok\":true,\"service\":\"kimi-swift-dashboard\"}", "application/json")
            return
        }
        if request.method == "GET" && path == "/login" {
            beginOAuth(fd: fd)
            return
        }
        if request.method == "GET" && path == "/oauth/callback" {
            await completeOAuth(fd: fd, query: query)
            return
        }
        if request.method == "POST" && path == "/logout" {
            let form = parseForm(request.body)
            guard let session, sameOrigin(request, host: host), form["csrf"] == session.csrf else {
                write(fd, 403, "Sign-out request could not be verified.", "text/plain")
                return
            }
            if let token { removeSession(token) }
            write(
                fd, 303, "", "text/plain",
                ["Location": "/login", "Set-Cookie": "kimi_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"])
            return
        }
        if request.method == "GET" && path == "/" {
            guard let session else {
                redirect(fd, "/login")
                return
            }
            let page = await renderHome(session)
            write(fd, 200, page, "text/html; charset=utf-8", ["Cache-Control": "no-store"])
            return
        }
        if request.method == "GET" && path == "/guild" {
            guard let session else {
                redirect(fd, "/login")
                return
            }
            let guild = query["id"] ?? ""
            guard let selected = session.guilds.first(where: { $0.id == guild }), await canManage(selected),
                await botIsPresent(guild)
            else {
                write(
                    fd, 403, page("Access denied", "You need Manage Server permission and Kimi must be installed."),
                    "text/html")
                return
            }
            let page = await renderGuild(session, guild: guild, name: selected.name, owner: selected.owner == true)
            write(fd, 200, page, "text/html; charset=utf-8", ["Cache-Control": "no-store"])
            return
        }
        if request.method == "POST" && path == "/settings" {
            guard let session else {
                redirect(fd, "/login")
                return
            }
            guard sameOrigin(request, host: host) else {
                write(fd, 403, "Cross-origin request blocked.", "text/plain")
                return
            }
            let form = parseForm(request.body)
            let guild = form["guild"] ?? ""
            guard form["csrf"] == session.csrf, let selected = session.guilds.first(where: { $0.id == guild }),
                await canManage(selected), await botIsPresent(guild)
            else {
                write(fd, 403, "Server settings access denied.", "text/plain")
                return
            }
            do {
                var languages = await store.get("languages", as: [String: String].self) ?? [:]
                let locale = form["language"] ?? "en-US"
                guard KimiLocalization.names[locale] != nil else {
                    throw KimiError.configuration("Unsupported language.")
                }
                languages[guild] = locale
                try await store.set(languages, key: "languages")
                let foundation = FoundationEngine(store: store, rest: rest, logger: logger)
                var welcome = await foundation.settings(guildID: guild)
                welcome.welcomeChannel = form["welcome-channel"]
                welcome.goodbyeChannel = form["goodbye-channel"]
                welcome.autoRole = form["auto-role"]
                welcome.welcomeMessage = form["welcome-message"] ?? welcome.welcomeMessage
                welcome.goodbyeMessage = form["goodbye-message"] ?? welcome.goodbyeMessage
                try await foundation.configure(guildID: guild, welcome)
                let moderation = ModerationEngine(store: store)
                var policy = await moderation.policy(guildID: guild)
                policy.enabled = form["moderation-enabled"] == "true"
                policy.messagesPerMinute = Int(form["messages-per-minute"] ?? "") ?? policy.messagesPerMinute
                policy.timeoutMinutes = Int(form["timeout-minutes"] ?? "") ?? policy.timeoutMinutes
                policy.sanction = form["sanction"] ?? policy.sanction
                policy.logChannelID = form["log-channel"]
                policy.blockInvites = form["block-invites"] == "true"
                policy.blockMassMentions = form["block-mentions"] == "true"
                policy.blockExcessiveCaps = form["block-caps"] == "true"
                try await moderation.configure(policy, guildID: guild)
                let support = SupportService(store: store, rest: rest, logger: logger)
                var supportSettings = await support.settings(guild)
                supportSettings.supportRoleID = form["support-role"].flatMap { $0.isEmpty ? nil : $0 }
                supportSettings.transcriptChannelID = form["transcript-channel"].flatMap { $0.isEmpty ? nil : $0 }
                supportSettings.panelTitle = form["ticket-title"] ?? supportSettings.panelTitle
                supportSettings.panelDescription = form["ticket-description"] ?? supportSettings.panelDescription
                try await support.configure(supportSettings, guild: guild)
                let verification = VerificationService(store: store, rest: rest, logger: logger)
                var verificationSettings = await verification.settings(guild)
                verificationSettings.channelID = form["verification-channel"].flatMap { $0.isEmpty ? nil : $0 }
                verificationSettings.roleID = form["verified-role"].flatMap { $0.isEmpty ? nil : $0 }
                verificationSettings.requiredRoleID = form["required-role"].flatMap { $0.isEmpty ? nil : $0 }
                verificationSettings.reviewChannelID = form["review-channel"].flatMap { $0.isEmpty ? nil : $0 }
                verificationSettings.minimumAgeDays =
                    Int(form["minimum-account-age"] ?? "") ?? verificationSettings.minimumAgeDays
                try await verification.configure(verificationSettings, guild: guild)
                write(fd, 303, "", "text/plain", ["Location": "/guild?id=" + guild])
            } catch { write(fd, 400, page("Settings could not be saved", error.localizedDescription), "text/html") }
            return
        }
        if request.method == "POST" && (path == "/plugin") {
            guard let session else {
                redirect(fd, "/login")
                return
            }
            guard sameOrigin(request, host: host) else {
                write(fd, 403, "Cross-origin request blocked.", "text/plain")
                return
            }
            let form = parseForm(request.body)
            let guild = form["guild"] ?? ""
            let plugin = form["plugin"] ?? ""
            let action = form["action"] ?? ""
            guard form["csrf"] == session.csrf, let selected = session.guilds.first(where: { $0.id == guild }),
                selected.owner == true, await botIsPresent(guild)
            else {
                write(fd, 403, "Only the server owner can manage installed plugins.", "text/plain")
                return
            }
            do {
                let manager = PluginManager(store: store)
                let result =
                    action == "install"
                    ? try await manager.install(plugin, guildID: guild)
                    : try await manager.uninstall(plugin, guildID: guild)
                guard result.ok else { throw KimiError.configuration(result.message) }
                let installed = await manager.installed(guildID: guild)
                try await rest.registerGuildCommands(config.clientID, guildID: guild, installed: installed)
                write(fd, 303, "", "text/plain", ["Location": "/guild?id=" + guild])
            } catch { write(fd, 400, page("Could not update plugin", error.localizedDescription), "text/html") }
            return
        }
        redirect(fd, "/login")
    }
    private func readRequest(_ fd: Int32) -> Request? {
        let maximumHeaderBytes = 16 * 1024
        let maximumBodyBytes = 64 * 1024
        let delimiter = Data([13, 10, 13, 10])
        var received = Data()
        var boundary: Range<Data.Index>?

        while boundary == nil {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = chunk.withUnsafeMutableBytes { buffer in
                recv(fd, buffer.baseAddress, buffer.count, 0)
            }
            guard count > 0 else { return nil }
            received.append(contentsOf: chunk.prefix(count))
            guard received.count <= maximumHeaderBytes + maximumBodyBytes,
                let range = received.range(of: delimiter) ?? (received.count > maximumHeaderBytes ? nil : nil)
            else { return nil }
            if range.lowerBound <= maximumHeaderBytes {
                boundary = range
            } else {
                return nil
            }
        }

        guard let boundary,
            let header = String(data: received[..<boundary.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, headers[key] == nil else { return nil }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil else { return nil }
        let bodyLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0, parsed <= maximumBodyBytes else { return nil }
            bodyLength = parsed
        } else {
            bodyLength = 0
        }

        var bodyData = Data(received[boundary.upperBound...])
        guard bodyData.count <= bodyLength else { return nil }
        while bodyData.count < bodyLength {
            var chunk = [UInt8](repeating: 0, count: min(4096, bodyLength - bodyData.count))
            let count = chunk.withUnsafeMutableBytes { buffer in
                recv(fd, buffer.baseAddress, buffer.count, 0)
            }
            guard count > 0 else { return nil }
            bodyData.append(contentsOf: chunk.prefix(count))
        }
        guard let body = String(data: bodyData, encoding: .utf8) else { return nil }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: body)
    }
    private func beginOAuth(fd: Int32) {
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        lock.lock()
        states[state] = Date().addingTimeInterval(600)
        lock.unlock()
        var c = URLComponents(string: "https://discord.com/oauth2/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.oauthRedirectURI),
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "scope", value: "identify guilds"),
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "prompt", value: "none"),
        ]
        redirect(fd, c.url?.absoluteString ?? "/login")
    }
    private func completeOAuth(fd: Int32, query: [String: String]) async {
        guard let code = query["code"], let state = query["state"] else {
            redirect(fd, "/login")
            return
        }
        let expiry = consumeState(state)
        guard let expiry, expiry > Date() else {
            write(fd, 400, page("Sign-in expired", "Return to Kimi and try again."), "text/html")
            return
        }
        do {
            var request = URLRequest(url: URL(string: "https://discord.com/api/v10/oauth2/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let form = [
                "client_id": config.clientID, "client_secret": config.oauthSecret, "grant_type": "authorization_code",
                "code": code, "redirect_uri": config.oauthRedirectURI,
            ]
            request.httpBody = form.map { urlEncode($0.key) + "=" + urlEncode($0.value) }.joined(separator: "&").data(
                using: .utf8)
            let (tokenData, tokenResponse) = try await URLSession.shared.data(for: request)
            guard let tokenHTTP = tokenResponse as? HTTPURLResponse,
                (200..<300).contains(tokenHTTP.statusCode)
            else {
                let status = (tokenResponse as? HTTPURLResponse)?.statusCode ?? 0
                throw KimiError.http(status, String(data: tokenData.prefix(500), encoding: .utf8) ?? "")
            }
            guard let tokenObject = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
                let access = tokenObject["access_token"] as? String
            else { throw KimiError.invalidResponse }
            let user = try await oauthGET("/users/@me", access: access, as: OAuthUser.self)
            let guilds = try await oauthGET("/users/@me/guilds", access: access, as: [OAuthGuild].self)
            let sessionToken =
                UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let csrf = UUID().uuidString
            let expires = Date().addingTimeInterval(7 * 86400)
            saveSession(
                sessionToken, Session(user: user, accessToken: access, expiresAt: expires, csrf: csrf, guilds: guilds))
            let secure = config.oauthRedirectURI.hasPrefix("https://") ? "; Secure" : ""
            write(
                fd, 303, "", "text/plain",
                [
                    "Location": "/",
                    "Set-Cookie": "kimi_session=" + sessionToken + "; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800"
                        + secure,
                ])
        } catch { write(fd, 400, page("Discord sign-in failed", error.localizedDescription), "text/html") }
    }
    private func oauthGET<T: Decodable>(_ path: String, access: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: "https://discord.com/api/v10" + path)!)
        request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KimiError.invalidResponse
        }
        return try JSONDecoder().decode(type, from: data)
    }
    private func renderHome(_ session: Session) async -> String {
        var rows = ""
        for guild in session.guilds {
            let canManageGuild = await canManage(guild)
            let hasKimi = await botIsPresent(guild.id)
            if canManageGuild && hasKimi {
                rows +=
                    "<a class='server' href='/guild?id=" + escape(guild.id) + "'><span class='server-icon'>"
                    + escape(String(guild.name.prefix(1)).uppercased()) + "</span><span><b>" + escape(guild.name)
                    + "</b><small>" + (guild.owner == true ? "Server owner" : "Manage Server")
                    + "</small></span><span class='arrow'>›</span></a>"
            }
        }
        if rows.isEmpty {
            rows =
                "<p class='muted'>No servers found where you have Manage Server permission and Kimi is installed.</p>"
        }
        return shell(
            "Your servers", "Signed in as " + (session.user.global_name ?? session.user.username),
            "<section class='panel'><h2>Server workspace</h2><p>Select a server to manage its installed Kimi plugins.</p>"
                + rows
                + "</section><form method='post' action='/logout'><input type='hidden' name='csrf' value='"
                + escape(session.csrf) + "'><button class='secondary'>Sign out</button></form>")
    }
    private func renderGuild(_ session: Session, guild: String, name: String, owner: Bool) async -> String {
        let installed = await PluginManager(store: store).installed(guildID: guild)
        let locale = (await store.get("languages", as: [String: String].self) ?? [:])[guild] ?? "en-US"
        let languageOptions = KimiLocalization.locales.map { code in
            "<option value='" + escape(code) + "'" + (locale == code ? " selected" : "") + ">"
                + escape(KimiLocalization.names[code] ?? code) + "</option>"
        }.joined()
        let cards = CommandCatalog.pluginNames().map { plugin in
            let active = installed.contains(plugin)
            let button =
                owner
                ? "<form method='post' action='/plugin'><input type='hidden' name='csrf' value='" + escape(session.csrf)
                    + "'><input type='hidden' name='guild' value='" + escape(guild)
                    + "'><input type='hidden' name='plugin' value='" + escape(plugin)
                    + "'><input type='hidden' name='action' value='" + (active ? "uninstall" : "install")
                    + "'><button class='" + (active ? "secondary" : "primary") + "'>" + (active ? "Remove" : "Install")
                    + "</button></form>" : ""
            return
                "<article class='plugin'><div><b>" + escape(plugin) + "</b><small>"
                + (active ? "Installed" : "Available") + "</small></div>" + button + "</article>"
        }.joined()
        let analytics = await AnalyticsService(store: store).report(guild: guild)
        let stats =
            "<div class='stats'><div><b>" + String(analytics.messages) + "</b><small>Messages</small></div><div><b>"
            + String(analytics.joins) + "</b><small>Joins</small></div><div><b>" + String(analytics.commands)
            + "</b><small>Commands</small></div><div><b>" + String(analytics.moderation)
            + "</b><small>Moderation</small></div></div>"
        let foundation = FoundationEngine(store: store, rest: rest, logger: logger)
        let welcome = await foundation.settings(guildID: guild)
        let policy = await ModerationEngine(store: store).policy(guildID: guild)
        let supportSettings = await SupportService(store: store, rest: rest, logger: logger).settings(guild)
        let verificationSettings = await VerificationService(store: store, rest: rest, logger: logger).settings(guild)
        let settings =
            "<section class='panel'><h2>Server settings</h2><form method='post' action='/settings'><input type='hidden' name='csrf' value='"
            + escape(session.csrf) + "'><input type='hidden' name='guild' value='" + escape(guild)
            + "'><label>Language<select name='language'>" + languageOptions
            + "</select></label><h3>Welcome</h3><label>Welcome channel ID<input name='welcome-channel' value='"
            + escape(welcome.welcomeChannel ?? "")
            + "'></label><label>Goodbye channel ID<input name='goodbye-channel' value='"
            + escape(welcome.goodbyeChannel ?? "") + "'></label><label>Automatic role ID<input name='auto-role' value='"
            + escape(welcome.autoRole ?? "") + "'></label><label>Welcome message<input name='welcome-message' value='"
            + escape(welcome.welcomeMessage) + "'></label><label>Goodbye message<input name='goodbye-message' value='"
            + escape(welcome.goodbyeMessage)
            + "'></label><h3>Kimi Lock</h3><input type='hidden' name='moderation-enabled' value='false'><label class='check'><input type='checkbox' name='moderation-enabled' value='true'"
            + (policy.enabled ? " checked" : "")
            + "> Enable automatic moderation</label><label>Messages per minute<input type='number' min='2' max='100' name='messages-per-minute' value='"
            + String(policy.messagesPerMinute)
            + "'></label><label>Timeout minutes<input type='number' min='1' max='40320' name='timeout-minutes' value='"
            + String(policy.timeoutMinutes) + "'></label><label>Sanction<select name='sanction'>"
            + ["delete", "timeout", "kick", "ban"].map { v in
                "<option value='" + v + "'" + (policy.sanction == v ? " selected" : "") + ">" + v.capitalized
                    + "</option>"
            }.joined() + "</select></label><label>Moderation log channel ID<input name='log-channel' value='"
            + escape(policy.logChannelID ?? "")
            + "'></label><input type='hidden' name='block-invites' value='false'><label class='check'><input type='checkbox' name='block-invites' value='true'"
            + (policy.blockInvites ? " checked" : "")
            + "> Block Discord invites</label><input type='hidden' name='block-mentions' value='false'><label class='check'><input type='checkbox' name='block-mentions' value='true'"
            + (policy.blockMassMentions ? " checked" : "")
            + "> Block mass mentions</label><input type='hidden' name='block-caps' value='false'><label class='check'><input type='checkbox' name='block-caps' value='true'"
            + (policy.blockExcessiveCaps ? " checked" : "")
            + "> Block excessive capitals</label><h3>Support</h3><label>Support role ID<input name='support-role' value='"
            + escape(supportSettings.supportRoleID ?? "")
            + "'></label><label>Transcript archive channel ID<input name='transcript-channel' value='"
            + escape(supportSettings.transcriptChannelID ?? "")
            + "'></label><label>Ticket panel title<input name='ticket-title' value='"
            + escape(supportSettings.panelTitle)
            + "'></label><label>Ticket panel description<input name='ticket-description' value='"
            + escape(supportSettings.panelDescription)
            + "'></label><h3>Verification</h3><label>Verification channel ID<input name='verification-channel' value='"
            + escape(verificationSettings.channelID ?? "")
            + "'></label><label>Verified role ID<input name='verified-role' value='"
            + escape(verificationSettings.roleID ?? "")
            + "'></label><label>Required role ID<input name='required-role' value='"
            + escape(verificationSettings.requiredRoleID ?? "")
            + "'></label><label>Manual review channel ID<input name='review-channel' value='"
            + escape(verificationSettings.reviewChannelID ?? "")
            + "'></label><label>Minimum account age in days<input type='number' min='0' max='3650' name='minimum-account-age' value='"
            + String(verificationSettings.minimumAgeDays)
            + "'></label><button class='primary'>Save settings</button></form></section>"
        let commandNames = (CommandCatalog.globalCommands() + CommandCatalog.guildCommands(installed: installed))
            .compactMap { $0["name"] as? String }.sorted()
        let commandHTML =
            "<section class='panel'><h2>Commands</h2><p>Commands available in this server.</p><div class='chips'>"
            + commandNames.map { "<code>/" + escape($0) + "</code>" }.joined(separator: " ") + "</div></section>"
        let entries = await logger.recent(limit: 120)
        let logs = entries.filter { $0.message.contains(guild) }.suffix(30).map { entry in
            "<div class='log'><small>" + escape(ISO8601DateFormatter().string(from: entry.date)) + " · "
                + escape(entry.level) + "</small><p>" + escape(entry.message) + "</p></div>"
        }.joined()
        let activity =
            "<section class='panel'><h2>Recent activity</h2>"
            + (logs.isEmpty ? "<p class='muted'>No recent activity for this server.</p>" : logs) + "</section>"
        let overview =
            "<section class='panel'><h2>Overview · Last 30 days</h2>" + stats + "<p>Active days: "
            + String(analytics.activeDays) + " · Leaves: " + String(analytics.leaves) + " · Tickets opened: "
            + String(analytics.ticketsOpened) + " · Tickets closed: " + String(analytics.ticketsClosed)
            + "</p></section>"
        return shell(
            name, "Kimi server workspace",
            "<a class='back' href='/'>← All servers</a>" + overview + "<section class='panel'><h2>Plugin Store</h2><p>"
                + (owner
                    ? "As server owner, you can install or remove plugins."
                    : "Only the server owner can change installed plugins.") + "</p>" + cards + "</section>" + settings
                + commandHTML + activity)
    }
    private func canManage(_ guild: OAuthGuild) async -> Bool {
        if guild.owner == true { return true }
        let raw = guild.permissions_new ?? guild.permissions ?? "0"
        let bits = UInt64(raw) ?? 0
        return bits & (1 << 5) != 0 || bits & (1 << 3) != 0
    }
    private func botIsPresent(_ guild: String) async -> Bool {
        do {
            _ = try await rest.call("GET", "guilds/" + guild)
            return true
        } catch { return false }
    }
    private func consumeState(_ state: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return states.removeValue(forKey: state)
    }
    private func saveSession(_ token: String, _ session: Session) {
        lock.lock()
        sessions[token] = session
        lock.unlock()
    }
    private func getSession(_ token: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = sessions[token], value.expiresAt > Date() else {
            sessions.removeValue(forKey: token)
            return nil
        }
        return value
    }
    private func removeSession(_ token: String) {
        lock.lock()
        sessions.removeValue(forKey: token)
        lock.unlock()
    }
    private func sameOrigin(_ request: Request, host: String) -> Bool {
        guard let origin = request.headers["origin"], let url = URL(string: origin) else { return false }
        return url.host?.lowercased() == host.split(separator: ":").first.map(String.init)?.lowercased()
    }
    private func parseForm(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let p = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { values[urlDecode(p[0])] = urlDecode(p[1]) }
        }
        return values
    }
    private func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
            .replacingOccurrences(of: "%20", with: "+")
    }
    private func urlDecode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    private func page(_ title: String, _ description: String) -> String {
        shell(
            title, description,
            "<section class='panel'><p>" + escape(description)
                + "</p><a class='button' href='/login'>Continue</a></section>")
    }
    private func shell(_ title: String, _ subtitle: String, _ body: String) -> String {
        "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><meta name='theme-color' content='#101112'><title>"
            + escape(title)
            + " · Kimi</title><style>*{box-sizing:border-box}body{margin:0;background:#101112;color:#f3f4f5;font:15px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}main{width:min(760px,calc(100% - 32px));margin:8vh auto}.brand{font-size:22px;font-weight:650;letter-spacing:-1px;margin-bottom:48px}.brand i{display:inline-grid;place-items:center;width:34px;height:34px;background:#eee;color:#111;border-radius:11px;margin-right:9px;font-style:normal}.eyebrow{font-size:11px;letter-spacing:1.5px;color:#8b9095;margin:0 0 10px}h1{font-size:38px;letter-spacing:-1.5px;margin:0 0 8px}h2{font-size:18px;margin:0 0 8px}p{color:#a4a9ae;line-height:1.6}.panel{background:#191b1e;border:1px solid #303337;border-radius:18px;padding:24px;margin-top:28px}.server,.plugin{display:flex;align-items:center;gap:14px;padding:15px 0;border-top:1px solid #303337;color:#f3f4f5;text-decoration:none}.server-icon{width:38px;height:38px;display:grid;place-items:center;background:#303337;border-radius:12px}.server small,.plugin small{display:block;color:#8b9095;margin-top:4px}.arrow{margin-left:auto;color:#aaa}.plugin form{margin-left:auto}.button,button{border:0;border-radius:10px;padding:11px 16px;background:#e6e8ea;color:#151617;text-decoration:none;font-weight:600;cursor:pointer}.secondary{background:#292c30;color:#e6e8ea}.back{color:#c4c8cc;text-decoration:none}.muted{color:#999}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin:20px 0}.stats div{background:#222529;border-radius:12px;padding:14px}.stats b{display:block;font-size:24px}.stats small{color:#999}.panel label{display:block;color:#c6cbd0;margin:14px 0}.panel input:not([type=checkbox]),.panel select{display:block;width:100%;margin-top:6px;padding:11px;background:#111315;color:#eee;border:1px solid #383c40;border-radius:9px}.panel .check{display:flex;align-items:center;gap:9px}.log{border-top:1px solid #303337;padding:8px 0}.log small{color:#888}.log p{margin:4px 0}.chips code{display:inline-block;background:#25282c;border-radius:6px;padding:5px 7px;margin:3px}</style><main><div class='brand'><i>K</i>kimi</div><div class='eyebrow'>KIMI CONTROL CENTER</div><h1>"
            + escape(title) + "</h1><p>" + escape(subtitle) + "</p>" + body
            + "<p class='muted'>Kimi Swift · Discord OAuth · Server-side rendering</p></main></html>"
    }
    private func redirect(_ fd: Int32, _ location: String) { write(fd, 303, "", "text/plain", ["Location": location]) }
    private func write(_ fd: Int32, _ status: Int, _ body: String, _ type: String, _ headers: [String: String] = [:]) {
        let reason =
            status == 200
            ? "OK"
            : (status == 303 ? "See Other" : (status == 400 ? "Bad Request" : (status == 403 ? "Forbidden" : "Error")))
        var head =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
        for (key, value) in headers { head += key + ": " + value + "\r\n" }
        head += "\r\n"
        let data = Data((head + body).utf8)
        data.withUnsafeBytes { buffer in if let base = buffer.baseAddress { _ = send(fd, base, buffer.count, 0) } }
    }
    private func closeSocket(_ fd: Int32) {
        #if canImport(Glibc)
            _ = Glibc.close(fd)
        #else
            _ = Darwin.close(fd)
        #endif
    }
}
