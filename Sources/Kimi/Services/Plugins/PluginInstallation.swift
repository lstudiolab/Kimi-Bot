import Foundation

/// Tracks one installation task per server, user and plugin.
/// Actor isolation makes the duplicate-install guard and cancellation lookup atomic.
actor PluginInstallJobs {
    private var jobs: [String: Task<Void, Never>] = [:]
    private var watchdogs: [String: Task<Void, Never>] = [:]
    private var expired: Set<String> = []

    func start(key: String, operation: @escaping @Sendable () async -> Void) -> Bool {
        guard jobs[key] == nil else { return false }
        let task = Task { await operation() }
        jobs[key] = task
        watchdogs[key] = Task {
            do {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                self.expire(key: key)
            } catch {
                // The installation completed or was cancelled before its deadline.
            }
        }
        return true
    }

    func cancel(key: String) {
        jobs[key]?.cancel()
    }

    func wasTimedOut(key: String) -> Bool {
        let value = expired.contains(key)
        expired.remove(key)
        return value
    }

    private func expire(key: String) {
        guard jobs[key] != nil else { return }
        expired.insert(key)
        jobs[key]?.cancel()
    }

    func finish(key: String) {
        watchdogs[key]?.cancel()
        watchdogs[key] = nil
        jobs[key] = nil
    }
}

enum PluginStoreUI {
    static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func resolve(_ slug: String) -> KimiPluginDefinition? {
        PluginRegistry.plugins.first { self.slug($0.name) == slug }
    }

    static func catalogRows(installed: [String]) -> [[String: Any]] {
        let options = PluginRegistry.plugins.map { plugin -> [String: Any] in
            [
                "label": plugin.name,
                "value": slug(plugin.name),
                "description": installed.contains(plugin.name) ? "Installed · View details" : plugin.description,
            ]
        }
        return [
            KimiUI.row([
                KimiUI.stringSelect(
                    id: "store:select", placeholder: "Choose a module",
                    options: options, minimum: 1, maximum: 1)
            ]),
            KimiUI.row([KimiUI.button(id: "store:home", label: "Back to Control Center")]),
        ]
    }

    static func detailRows(_ plugin: KimiPluginDefinition, installed: Bool) -> [[String: Any]] {
        [KimiUI.row([
            KimiUI.button(
                id: "store:install:" + slug(plugin.name),
                label: installed ? "Installed" : "Install",
                disabled: installed),
            KimiUI.button(id: "store:back", label: "Back"),
        ])]
    }

    static func installedRows() -> [[String: Any]] {
        [KimiUI.row([KimiUI.button(id: "store:back", label: "Back to modules")])]
    }

    static func installingRows(_ slug: String) -> [[String: Any]] {
        [KimiUI.row([
            KimiUI.button(id: "store:installing:" + slug, label: "Installing", disabled: true),
            KimiUI.button(id: "store:cancel:" + slug, label: "Cancel"),
        ])]
    }
}

extension KimiRuntime {
    func handlePluginStoreComponent(
        _ customID: String,
        data: [String: Any],
        guildID: String,
        actorID: String,
        applicationID: String,
        interactionToken: String
    ) async {
        do {
            if customID == "store:home" {
                let installed = await PluginManager(store: store).installed(guildID: guildID)
                let enabled = await store.get("control.enabled." + guildID, as: Bool.self) ?? true
                let rows = [KimiUI.row([
                    KimiUI.button(id: "settings:plugins", label: "Module Store"),
                    KimiUI.button(id: "control:memory", label: "Memory"),
                    KimiUI.button(id: "control:customize", label: "Customize"),
                    KimiUI.button(id: "control:toggle", label: enabled ? "Turn Off" : "Turn On"),
                ])]
                let message = "Kimi Control Center\nStatus: " + (enabled ? "On" : "Off")
                    + "\nInstalled modules: " + String(installed.count)
                    + "\nManage your server modules, memory and Kimi availability below."
                try await self.editThemedInteraction(
                    applicationID, interactionToken, message, rows, guildID: guildID)
                return
            }

            if customID == "settings:plugins" || customID == "settings:apps" || customID == "store:back" {
                let installed = await PluginManager(store: store).installed(guildID: guildID)
                try await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Module Store\nChoose a module to review its features and install it in this server.",
                    PluginStoreUI.catalogRows(installed: installed))
                return
            }

            if customID == "store:select" {
                guard let selected = (data["values"] as? [String])?.first,
                    let plugin = PluginStoreUI.resolve(selected)
                else { throw KimiError.configuration("Choose a valid plugin from the catalogue.") }
                let installed = await PluginManager(store: store).installed(guildID: guildID)
                let isInstalled = installed.contains(plugin.name)
                let systems = plugin.systems.map { "• " + $0 }.joined(separator: "\n")
                let helpers = plugin.helpers.map { "• " + $0 }.joined(separator: "\n")
                let status = isInstalled ? "Installed" : "Available"
                let description: String
                if plugin.name == "Kimi Guard" {
                    let tiers = KimiGuardCatalog.sections.map { section in
                        let features = section.features.map {
                            ($0.available ? "Ready" : "Planned") + " · " + $0.name
                        }.joined(separator: "\n")
                        return section.level + " · " + section.title + "\n" + features
                    }.joined(separator: "\n\n")
                    description = "Kimi Guard · \(status)\n\n"
                        + "A six-level moderation suite. Ready features use Kimi's existing moderation engine; planned features are not active yet.\n\n"
                        + tiers + "\n\nReady: " + String(KimiGuardCatalog.availableCount)
                        + " · Planned: " + String(KimiGuardCatalog.plannedCount)
                } else {
                    description = "\(plugin.name) · \(status)\n\n\(plugin.description)\n\nIncluded systems\n\(systems)\n\nCompatibility and safeguards\n\(helpers)"
                }
                try await rest.editKimiInteraction(
                    applicationID, interactionToken, description,
                    PluginStoreUI.detailRows(plugin, installed: isInstalled))
                return
            }

            if customID.hasPrefix("store:cancel:") {
                let slug = String(customID.dropFirst("store:cancel:".count))
                guard PluginStoreUI.resolve(slug) != nil else {
                    throw KimiError.configuration("This installation request is no longer valid.")
                }
                let key = installKey(guildID: guildID, actorID: actorID, slug: slug)
                await pluginInstallJobs.cancel(key: key)
                try await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Cancellation requested. The installation result will appear in its original status message.",
                    PluginStoreUI.installedRows())
                return
            }

            if customID.hasPrefix("store:install:") {
                let slug = String(customID.dropFirst("store:install:".count))
                guard let plugin = PluginStoreUI.resolve(slug) else {
                    throw KimiError.configuration("This plugin is not in the catalogue.")
                }
                let owner = try await rest.ownerID(guildID)
                guard owner == actorID else {
                    throw KimiError.configuration("Only the server owner can install plugins.")
                }
                let key = installKey(guildID: guildID, actorID: actorID, slug: slug)
                // Update the deferred component response before starting background work,
                // preventing the first progress edit from being overwritten by this view.
                try await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Installing \(plugin.name)…\nPreparing system checks.",
                    PluginStoreUI.installingRows(slug))
                let started = await pluginInstallJobs.start(key: key) {
                    await self.performPluginInstallation(
                        plugin, guildID: guildID, actorID: actorID,
                        applicationID: applicationID, interactionToken: interactionToken,
                        jobKey: key)
                }
                guard started else {
                    try await rest.editKimiInteraction(
                        applicationID, interactionToken,
                        "An installation for this plugin is already running.",
                        PluginStoreUI.installingRows(slug))
                    return
                }
                return
            }

            throw KimiError.configuration("This Plugin Store action is not supported.")
        } catch {
            do {
                try await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Plugin Store could not complete this action.\n" + error.localizedDescription, [])
            } catch {
                await logger.log("WARN", "Plugin Store response could not be edited: " + error.localizedDescription)
            }
        }
    }

    private func installKey(guildID: String, actorID: String, slug: String) -> String {
        guildID + ":" + actorID + ":" + slug
    }

    private func performPluginInstallation(
        _ plugin: KimiPluginDefinition,
        guildID: String,
        actorID: String,
        applicationID: String,
        interactionToken: String,
        jobKey: String
    ) async {
        let manager = PluginManager(store: store)
        let previous = await manager.installed(guildID: guildID)
        let slug = PluginStoreUI.slug(plugin.name)
        do {
            try await showInstallStage(
                "Checking system stability", plugin: plugin.name, slug: slug,
                app: applicationID, token: interactionToken)
            try Task.checkCancellation()
            let botID = try await validateBotEnvironment(guildID: guildID, plugin: plugin)

            try await showInstallStage(
                "Checking compatibility and dependencies", plugin: plugin.name, slug: slug,
                app: applicationID, token: interactionToken)
            try Task.checkCancellation()
            try validatePluginDefinition(plugin, installed: previous)

            try await showInstallStage(
                "Checking permissions and command conflicts", plugin: plugin.name, slug: slug,
                app: applicationID, token: interactionToken)
            try Task.checkCancellation()
            try await validateBotPermissions(guildID: guildID, botID: botID, plugin: plugin)

            try await showInstallStage(
                "Checking package integrity and installation state", plugin: plugin.name, slug: slug,
                app: applicationID, token: interactionToken)
            try Task.checkCancellation()
            guard !previous.contains(plugin.name) else {
                throw KimiError.configuration("\(plugin.name) is already installed.")
            }

            // Three low-frequency edits provide the requested animated progress
            // without flooding Discord's message-edit route.
            for dots in 1...3 {
                try Task.checkCancellation()
                try await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Installing \(plugin.name)" + String(repeating: ".", count: dots)
                        + "\nRegistering plugin commands and activating its systems.",
                    PluginStoreUI.installingRows(slug))
                try await Task.sleep(nanoseconds: 700_000_000)
            }

            try Task.checkCancellation()
            let result = try await manager.install(plugin.name, guildID: guildID)
            guard result.ok else { throw KimiError.configuration(result.message) }

            do {
                try Task.checkCancellation()
                let updated = await manager.installed(guildID: guildID)
                try await rest.registerGuildCommands(applicationID, guildID: guildID, installed: updated)
            } catch {
                // Restore the prior plugin state if command registration or
                // cancellation fails after the local install has been committed.
                _ = try? await manager.uninstall(plugin.name, guildID: guildID)
                try? await rest.registerGuildCommands(applicationID, guildID: guildID, installed: previous)
                throw error
            }

            // This is the commit point: stop the watchdog and make Cancel inert.
            // A failure to refresh the Discord status message must not claim that
            // a successfully activated plugin was rolled back.
            await pluginInstallJobs.finish(key: jobKey)
            if Task.isCancelled {
                _ = try? await manager.uninstall(plugin.name, guildID: guildID)
                try? await rest.registerGuildCommands(applicationID, guildID: guildID, installed: previous)
                throw CancellationError()
            }
            try? await rest.editKimiInteraction(
                applicationID, interactionToken,
                "\(plugin.name) is installed and activated.\nIts available systems can now run in this server.",
                PluginStoreUI.installedRows())
            await logger.log("INFO", "Installed plugin \(plugin.name) in guild \(guildID) by owner \(actorID).")
        } catch is CancellationError {
            let timedOut = await pluginInstallJobs.wasTimedOut(key: jobKey)
            let message = timedOut
                ? "Installation timed out after 90 seconds.\nThe previous plugin state was restored."
                : "Installation cancelled.\nNo partial plugin changes were kept."
            try? await rest.editKimiInteraction(applicationID, interactionToken, message, PluginStoreUI.installedRows())
            await logger.log(
                timedOut ? "WARN" : "INFO",
                (timedOut ? "Plugin installation timed out: " : "Plugin installation cancelled: ")
                    + "\(plugin.name) in guild \(guildID).")
        } catch {
            if Task.isCancelled {
                let timedOut = await pluginInstallJobs.wasTimedOut(key: jobKey)
                let message = timedOut
                    ? "Installation timed out after 90 seconds.\nThe previous plugin state was restored."
                    : "Installation cancelled.\nNo partial plugin changes were kept."
                try? await rest.editKimiInteraction(applicationID, interactionToken, message, [])
                await logger.log(
                    timedOut ? "WARN" : "INFO",
                    (timedOut ? "Plugin installation timed out: " : "Plugin installation cancelled: ")
                        + "\(plugin.name) in guild \(guildID).")
            } else {
                try? await rest.editKimiInteraction(
                    applicationID, interactionToken,
                    "Could not install \(plugin.name).\n\(error.localizedDescription)\n\nThe previous plugin state was preserved.", PluginStoreUI.installedRows())
                await logger.log("WARN", "Plugin installation failed for \(plugin.name): " + error.localizedDescription)
            }
        }
        await pluginInstallJobs.finish(key: jobKey)
    }

    private func showInstallStage(
        _ stage: String, plugin: String, slug: String, app: String, token: String
    ) async throws {
        try await rest.editKimiInteraction(
            app, token, "Installing \(plugin)…\n" + stage + ".",
            PluginStoreUI.installingRows(slug))
    }

    private func validatePluginDefinition(_ plugin: KimiPluginDefinition, installed: [String]) throws {
        guard !plugin.systems.isEmpty, !plugin.helpers.isEmpty,
            let commands = CommandCatalog.pluginCommands[plugin.name]
        else { throw KimiError.configuration("The plugin manifest is incomplete or unavailable.") }
        guard Set(commands).count == commands.count,
            commands.allSatisfy({ $0.range(of: #"^[-a-z0-9]{1,32}$"#, options: .regularExpression) != nil })
        else { throw KimiError.configuration("The plugin command manifest failed integrity checks.") }
        let core = Set(CommandCatalog.core)
        guard commands.allSatisfy({ !core.contains($0) }) else {
            throw KimiError.configuration("The plugin declares a command that conflicts with a core command.")
        }
        for dependency in plugin.dependencies where !installed.contains(dependency) {
            throw KimiError.configuration("Missing dependency: \(dependency). Install it first.")
        }
        let otherCommands = installed
            .filter { $0 != plugin.name }
            .flatMap { CommandCatalog.pluginCommands[$0] ?? [] }
        guard Set(commands).isDisjoint(with: otherCommands) else {
            throw KimiError.configuration("A command name conflicts with another installed plugin.")
        }
    }

    private func validateBotEnvironment(guildID: String, plugin: KimiPluginDefinition) async throws -> String {
        guard let me = try await rest.call("GET", "users/@me") as? [String: Any],
            let botID = me["id"] as? String
        else { throw KimiError.configuration("Kimi could not verify its Discord session.") }
        guard let member = try await rest.call("GET", "guilds/\(guildID)/members/\(botID)") as? [String: Any],
            member["roles"] is [String]
        else { throw KimiError.configuration("Kimi is not an active member of this server.") }
        guard let roles = try await rest.call("GET", "guilds/\(guildID)/roles") as? [[String: Any]],
            !roles.isEmpty
        else { throw KimiError.configuration("The server role configuration could not be read.") }
        return botID
    }

    private func validateBotPermissions(guildID: String, botID: String, plugin: KimiPluginDefinition) async throws {
        guard let member = try await rest.call("GET", "guilds/\(guildID)/members/\(botID)") as? [String: Any],
            let roleIDs = member["roles"] as? [String],
            let roles = try await rest.call("GET", "guilds/\(guildID)/roles") as? [[String: Any]]
        else { throw KimiError.configuration("Kimi could not verify its server permissions.") }

        var permissions: UInt64 = 0
        for role in roles {
            guard let roleID = role["id"] as? String,
                roleID == guildID || roleIDs.contains(roleID)
            else { continue }
            permissions |= UInt64(role["permissions"] as? String ?? "") ?? 0
        }
        if permissions & (1 << 3) != 0 { return } // Administrator

        let required: [(String, UInt64)]
        switch plugin.name {
        case "Welcome":
            required = [("View Channels", 1 << 10), ("Send Messages", 1 << 11)]
        case "Auto Role", "Role Picker":
            required = [("Manage Roles", 1 << 28)]
        case "Embeds":
            required = [("View Channels", 1 << 10), ("Send Messages", 1 << 11), ("Embed Links", 1 << 14)]
        case "Kimi Lock":
            required = [("Manage Messages", 1 << 13), ("Moderate Members", 1 << 40)]
        case "Kimi Guard":
            required = [
                ("Manage Channels", 1 << 4), ("Manage Messages", 1 << 13),
                ("Moderate Members", 1 << 40), ("Kick Members", 1 << 1), ("Ban Members", 1 << 2),
            ]
        case "Support":
            required = [("Manage Channels", 1 << 4), ("View Channels", 1 << 10), ("Send Messages", 1 << 11)]
        default:
            required = [("View Channels", 1 << 10), ("Send Messages", 1 << 11)]
        }
        let missing = required.filter { permissions & $0.1 == 0 }.map { $0.0 }
        guard missing.isEmpty else {
            throw KimiError.configuration("Kimi is missing required server permissions: " + missing.joined(separator: ", ") + ".")
        }
    }
}
