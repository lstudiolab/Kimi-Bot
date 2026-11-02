import Foundation

enum PermissionPolicy {
    // Discord permission bit positions that must never be granted through self-service role assignment.
    static let blockedBitPositions: Set<Int> = [
        3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43
    ]

    static func isSafeAssignableRole(roleID: String, guildID: String, isManaged: Bool, permissionBits: UInt64) -> Bool {
        guard roleID != guildID, !isManaged else { return false }
        for bit in blockedBitPositions where (permissionBits & (UInt64(1) << UInt64(bit))) != 0 {
            return false
        }
        return true
    }
}
