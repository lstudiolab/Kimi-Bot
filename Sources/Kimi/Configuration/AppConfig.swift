import Foundation

struct AppConfig: Sendable {
    let token: String
    let clientID: String
    let dataDirectory: URL
    let logLevel: LogLevel
    let dashboardHost: String
    let dashboardPort: UInt16
    let dashboardOwnerID: String
    let dashboardCookieSecure: Bool

    static func load(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> AppConfig {
        let fileValues = try EnvironmentFile.read(at: root.appendingPathComponent(".env"))
        func value(_ key: String) -> String {
            ProcessInfo.processInfo.environment[key] ?? fileValues[key] ?? ""
        }

        let token = value("DISCORD_TOKEN").trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = value("CLIENT_ID").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token != "your_discord_bot_token" else {
            throw ConfigError.invalid("DISCORD_TOKEN is missing. Set it in .env.")
        }
        guard clientID.range(of: #"^\d{15,22}$"#, options: .regularExpression) != nil else {
            throw ConfigError.invalid("CLIENT_ID must be a valid Discord application ID.")
        }

        let rawPort = value("DASHBOARD_PORT").isEmpty ? "8787" : value("DASHBOARD_PORT")
        guard let port = UInt16(rawPort), port >= 1024 else {
            throw ConfigError.invalid("DASHBOARD_PORT must be between 1024 and 65535.")
        }

        let directoryName = value("DATA_DIR").isEmpty ? "data" : value("DATA_DIR")
        let dataDirectory = root.appendingPathComponent(directoryName, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        return AppConfig(
            token: token,
            clientID: clientID,
            dataDirectory: dataDirectory,
            logLevel: LogLevel(value("LOG_LEVEL")),
            dashboardHost: value("DASHBOARD_HOST").isEmpty ? "127.0.0.1" : value("DASHBOARD_HOST"),
            dashboardPort: port,
            dashboardOwnerID: value("DASHBOARD_OWNER_ID"),
            dashboardCookieSecure: value("DASHBOARD_COOKIE_SECURE").isEmpty || value("DASHBOARD_COOKIE_SECURE").lowercased() == "true"
        )
    }
}

enum ConfigError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

private enum EnvironmentFile {
    static func read(at url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let source = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\u{FEFF}", with: "")
        var values: [String: String] = [:]
        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let normalized = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line
            guard let separator = normalized.firstIndex(of: "=") else { continue }
            let key = String(normalized[..<separator]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            var value = String(normalized[normalized.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: #"\s+#"#, options: .regularExpression) {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            values[key] = value
        }
        return values
    }
}
