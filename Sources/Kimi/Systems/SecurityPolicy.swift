import Foundation

enum SecurityPolicy {
    static let privilegedPermissionBits: [UInt64] = [
        3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        34, 35, 36, 37, 38, 39, 40, 41, 42, 43,
    ].map { UInt64(1) << $0 }
    static func isSafeRole(roleID: String, guildID: String, managed: Bool, permissions: UInt64) -> Bool {
        guard roleID != guildID && !managed else { return false }
        return !privilegedPermissionBits.contains(where: { permissions & $0 != 0 })
    }
    static func channelName(_ input: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let lower = input.lowercased().unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let clean = lower.replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(
            in: CharacterSet(charactersIn: "-"))
        return String((clean.isEmpty ? "ticket" : clean).prefix(90))
    }
}
