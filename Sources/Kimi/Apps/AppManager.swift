import Foundation

actor AppManager {
    struct Result: Sendable {
        let ok: Bool
        let message: String
        let app: String?
    }
    private let store: PersistentStore
    init(store: PersistentStore) { self.store = store }
    func installed(guildID: String) async -> [String] {
        let all = await store.get("apps.installed", as: [String: [String]].self) ?? [:]
        return all[guildID] ?? []
    }
    func install(_ name: String, guildID: String) async throws -> Result {
        guard CommandCatalog.groups[name] != nil else { return Result(ok: false, message: "Unknown plugin.", app: nil) }
        var all = await store.get("apps.installed", as: [String: [String]].self) ?? [:]
        var values = all[guildID] ?? []
        guard !values.contains(name) else {
            return Result(ok: false, message: "\(name) is already installed.", app: name)
        }
        values.append(name)
        all[guildID] = values
        try await store.setGuild(all, key: "apps.installed", guildID: guildID)
        return Result(ok: true, message: "\(name) installed.", app: name)
    }
    func uninstall(_ name: String, guildID: String) async throws -> Result {
        var all = await store.get("apps.installed", as: [String: [String]].self) ?? [:]
        var values = all[guildID] ?? []
        guard values.contains(name) else { return Result(ok: false, message: "\(name) is not installed.", app: name) }
        values.removeAll { $0 == name }
        all[guildID] = values
        try await store.setGuild(all, key: "apps.installed", guildID: guildID)
        return Result(ok: true, message: "\(name) removed; saved settings were preserved.", app: name)
    }
}
