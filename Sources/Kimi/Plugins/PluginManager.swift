import Foundation

actor PluginManager {
    struct Result: Sendable {
        let ok: Bool
        let message: String
        let plugin: String?
    }

    private let store: PersistentStore
    // Persisted key is retained to preserve existing guild installations.
    private let storageKey = "apps.installed"

    init(store: PersistentStore) { self.store = store }

    private func loadInstallations() async -> [String: [String]] {
        await store.get(storageKey, as: [String: [String]].self) ?? [:]
    }

    func installed(guildID: String) async -> [String] {
        let installations = await loadInstallations()
        return installations[guildID] ?? []
    }

    func install(_ name: String, guildID: String) async throws -> Result {
        guard CommandCatalog.pluginCommands[name] != nil else {
            return Result(ok: false, message: "Unknown plugin.", plugin: nil)
        }

        var all = await loadInstallations()
        var values = all[guildID] ?? []
        guard !values.contains(name) else {
            return Result(ok: false, message: "\(name) is already installed.", plugin: name)
        }

        values.append(name)
        all[guildID] = values
        try await store.setGuild(all, key: storageKey, guildID: guildID)
        return Result(ok: true, message: "\(name) installed.", plugin: name)
    }

    func uninstall(_ name: String, guildID: String) async throws -> Result {
        var all = await loadInstallations()
        var values = all[guildID] ?? []
        guard values.contains(name) else {
            return Result(ok: false, message: "\(name) is not installed.", plugin: name)
        }

        values.removeAll { $0 == name }
        all[guildID] = values
        try await store.setGuild(all, key: storageKey, guildID: guildID)
        return Result(ok: true, message: "\(name) removed; saved settings were preserved.", plugin: name)
    }
}
