import Foundation

enum ComponentRouting {
    static func app(for customID: String) -> String? {
        if customID.hasPrefix("ticket:") { return "Support" }
        if customID.hasPrefix("modpanel:") || customID.hasPrefix("botguard:") || customID.hasPrefix("verify:") { return "Kimi Lock" }
        if customID.hasPrefix("rolepicker:") { return "Role Picker" }
        if customID.hasPrefix("embed:") { return "Embeds" }
        return nil
    }
}
