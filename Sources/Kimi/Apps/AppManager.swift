import Foundation

actor AppManager {
    private let store: JSONStore
    private let logger: KimiLogger
    init(store: JSONStore, logger: KimiLogger) { self.store = store; self.logger = logger }

    func available() -> [AppDefinition] { AppRegistry.all }

    func installed(in guildID: String) async -> [String] {
        guard let value = await store.value(for: "installed_plugins"),
              case .object(let guilds) = value,
              case .array(let names)? = guilds[guildID] else { return [] }
        return names.compactMap { if case .string(let name) = $0 { return name }; return nil }
    }

    func install(_ input: String, in guildID: String) async throws -> Result<AppDefinition, AppManagerError> {
        guard let name = AppRegistry.normalize(input), let app = AppRegistry.all.first(where: { $0.name == name }) else {
            return .failure(.notFound)
        }
        var guilds: [String: JSONValue] = [:]
        if case .object(let existing)? = await store.value(for: "installed_plugins") { guilds = existing }
        var names: [String] = []
        if case .array(let current)? = guilds[guildID] {
            names = current.compactMap { if case .string(let value) = $0 { return value }; return nil }
        }
        guard !names.contains(name) else { return .failure(.alreadyInstalled(name)) }
        names.append(name)
        guilds[guildID] = .array(names.map(JSONValue.string))
        try await store.set(.object(guilds), for: "installed_plugins")
        await logger.info("Added \(name) app for guild \(guildID).")
        return .success(app)
    }

    func uninstall(_ input: String, from guildID: String) async throws -> Result<AppDefinition, AppManagerError> {
        guard let name = AppRegistry.normalize(input), let app = AppRegistry.all.first(where: { $0.name == name }) else {
            return .failure(.notFound)
        }
        var guilds: [String: JSONValue] = [:]
        if case .object(let existing)? = await store.value(for: "installed_plugins") { guilds = existing }
        guard case .array(let current)? = guilds[guildID] else { return .failure(.notInstalled(name)) }
        let names = current.compactMap { if case .string(let value) = $0 { return value }; return nil }
        guard names.contains(name) else { return .failure(.notInstalled(name)) }
        guilds[guildID] = .array(names.filter { $0 != name }.map(JSONValue.string))
        try await store.set(.object(guilds), for: "installed_plugins")
        await logger.info("Removed \(name) app for guild \(guildID); saved data was preserved.")
        return .success(app)
    }
}

enum AppManagerError: Error, Equatable {
    case notFound
    case alreadyInstalled(String)
    case notInstalled(String)
}
