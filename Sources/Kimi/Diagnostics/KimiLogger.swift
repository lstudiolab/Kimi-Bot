import Foundation

enum LogLevel: Int, Sendable {
    case debug = 10, info = 20, warning = 30, error = 40
    init(_ value: String) {
        switch value.lowercased() {
        case "debug": self = .debug
        case "warn", "warning": self = .warning
        case "error": self = .error
        default: self = .info
        }
    }
}

struct LogEntry: Codable, Sendable {
    let timestamp: Date
    let level: String
    let message: String
}

actor KimiLogger {
    private let threshold: LogLevel
    private var recent: [LogEntry] = []
    init(level: LogLevel) { threshold = level }

    func debug(_ message: String) { write(.debug, message) }
    func info(_ message: String) { write(.info, message) }
    func warning(_ message: String) { write(.warning, message) }
    func error(_ message: String) { write(.error, message) }

    func recentEntries(limit: Int = 200) -> [LogEntry] {
        Array(recent.suffix(max(1, min(500, limit))).reversed())
    }

    private func write(_ level: LogLevel, _ message: String) {
        guard level.rawValue >= threshold.rawValue else { return }
        let entry = LogEntry(timestamp: Date(), level: String(describing: level).uppercased(), message: String(message.prefix(4000)))
        recent.append(entry)
        if recent.count > 500 { recent.removeFirst(recent.count - 500) }
        let formatter = ISO8601DateFormatter()
        let line = "[\(formatter.string(from: entry.timestamp))] [\(entry.level)] \(entry.message)\n"
        if level.rawValue >= LogLevel.warning.rawValue { FileHandle.standardError.write(Data(line.utf8)) }
        else { FileHandle.standardOutput.write(Data(line.utf8)) }
    }
}
