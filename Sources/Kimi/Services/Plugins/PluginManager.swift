import Foundation

actor PluginManager {
    struct Result: Sendable {
        let ok: Bool
        let message: String
        let plugin: String?
    }

    private let store: PersistentStore
    private let storageKey = "plugins.installed"
    private let legacyStorageKey = "apps.installed"

    init(store: PersistentStore) { self.store = store }

    private func loadInstallations() async -> [String: [String]] {
        var current = await store.get(storageKey, as: [String: [String]].self) ?? [:]
        let legacy = await store.get(legacyStorageKey, as: [String: [String]].self) ?? [:]
        for (guildID, plugins) in legacy where current[guildID] == nil {
            current[guildID] = plugins
        }
        return current
    }

    func installed(guildID: String) async -> [String] {
        let installations = await loadInstallations()
        return installations[guildID] ?? []
    }

    func install(_ name: String, guildID: String) async throws -> Result {
        guard CommandCatalog.pluginCommands[name] != nil else {
            return Result(ok: false, message: "Unknown plugin.", plugin: nil)
        }
        let legacy = await store.get(legacyStorageKey, as: [String: [String]].self) ?? [:]
        return try await store.modifyGuild(storageKey, guildID: guildID, as: [String: [String]].self) { stored in
            var all = stored ?? [:]
            for (id, plugins) in legacy where all[id] == nil { all[id] = plugins }
            var values = all[guildID] ?? []
            guard !values.contains(name) else {
                return (all, Result(ok: false, message: "\(name) is already installed.", plugin: name))
            }
            values.append(name)
            all[guildID] = values
            return (all, Result(ok: true, message: "\(name) installed.", plugin: name))
        }
    }

    func uninstall(_ name: String, guildID: String) async throws -> Result {
        let legacy = await store.get(legacyStorageKey, as: [String: [String]].self) ?? [:]
        return try await store.modifyGuild(storageKey, guildID: guildID, as: [String: [String]].self) { stored in
            var all = stored ?? [:]
            for (id, plugins) in legacy where all[id] == nil { all[id] = plugins }
            var values = all[guildID] ?? []
            guard values.contains(name) else {
                return (all, Result(ok: false, message: "\(name) is not installed.", plugin: name))
            }
            values.removeAll { $0 == name }
            all[guildID] = values
            return (all, Result(ok: true, message: "\(name) removed; saved settings were preserved.", plugin: name))
        }
    }
}
