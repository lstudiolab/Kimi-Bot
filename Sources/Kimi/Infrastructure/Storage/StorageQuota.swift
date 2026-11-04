import Foundation

enum StorageQuota {
    static let freeLimit = 5 * 1024 * 1024
    static func usage(of data: Data) -> (used: Int, limit: Int, percent: Int) {
        usage(bytes: data.count)
    }
    static func usage(bytes: Int) -> (used: Int, limit: Int, percent: Int) {
        let used = max(0, bytes)
        return (used, freeLimit, min(100, Int(Double(used) / Double(freeLimit) * 100)))
    }
    static func format(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.2f MB", Double(bytes) / 1_048_576)
    }
}
