import Foundation

enum SecurityPolicy {
    // Permissions that can grant moderation, administration, or destructive server control.
    static let privilegedPermissionBits: [UInt64] = [
        1, 2, 3, 4, 5, 7, 13, 17, 22, 23, 24, 27, 28, 29, 30, 33, 34, 40, 43, 44,
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
