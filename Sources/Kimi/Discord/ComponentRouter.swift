import Foundation

enum ComponentRouter {
    enum App: String, Sendable {
        case support = "Support"
        case kimiLock = "Kimi Lock"
        case rolePicker = "Role Picker"
        case embeds = "Embeds"
        case welcome = "Welcome"
        case autoRole = "Auto Role"
    }
    enum Route: Sendable {
        case ticketOpen, ticketClose(String), ticketConfirmClose(String), ticketCancel, verifyStart, verifyApprove(
            String), verifyReject(String), roleSelect, botApprove(String), botReject(String), settings(String), unknown
    }
    static func app(for id: String) -> App? {
        if id.hasPrefix("ticket:") { return .support }
        if id.hasPrefix("modpanel:") || id.hasPrefix("botguard:") || id.hasPrefix("verify:") { return .kimiLock }
        if id.hasPrefix("rolepicker:") { return .rolePicker }
        if id.hasPrefix("embed:") { return .embeds }
        if id.hasPrefix("welcome:") { return .welcome }
        if id.hasPrefix("autorole:") { return .autoRole }
        return nil
    }
    static func route(_ id: String) -> Route {
        if id == "ticket:open" { return .ticketOpen }
        if id.hasPrefix("ticket:close:") { return .ticketClose(String(id.dropFirst(13))) }
        if id.hasPrefix("ticket:confirm-close:") { return .ticketConfirmClose(String(id.dropFirst(21))) }
        if id == "ticket:cancel-close" { return .ticketCancel }
        if id == "verify:start" { return .verifyStart }
        if id.hasPrefix("verify:approve:") { return .verifyApprove(String(id.dropFirst(15))) }
        if id.hasPrefix("verify:reject:") { return .verifyReject(String(id.dropFirst(14))) }
        if id == "rolepicker:select" { return .roleSelect }
        if id.hasPrefix("botguard:yes:") { return .botApprove(String(id.dropFirst(13))) }
        if id.hasPrefix("botguard:no:") { return .botReject(String(id.dropFirst(12))) }
        if id.hasPrefix("settings:") { return .settings(String(id.dropFirst(9))) }
        return .unknown
    }
}
