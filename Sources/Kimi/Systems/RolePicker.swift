import Foundation
struct RolePicker {
    static func validateSelection(_ selected:[String],allowed:[String])->Bool {
        selected.count<=25 && Set(selected).count==selected.count && selected.allSatisfy{allowed.contains($0)}
    }
    static func isSafe(roleID:String,guildID:String,managed:Bool,permissionBits:UInt64)->Bool {
        guard roleID != guildID && !managed else{return false}
        let dangerous:Set<Int>=[3,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,34,35,36,37,38,39,40,41,42,43]
        return !dangerous.contains{permissionBits & (UInt64(1)<<UInt64($0)) != 0}
    }
}
