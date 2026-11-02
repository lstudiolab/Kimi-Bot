import Foundation
actor KimiLock {
    struct Policy:Codable,Sendable {var enabled=true;var messagesPerMinute=20;var timeoutMinutes=10}
    struct Finding:Sendable {let guildID:String,userID:String,messageID:String,reason:String}
    private let store:JSONStore,logger:KimiLogger
    private var history:[String:[Date]]=[:]
    init(store:JSONStore,logger:KimiLogger){self.store=store;self.logger=logger}
    func evaluate(guildID:String,userID:String,messageID:String,bot:Bool,now:Date=Date()) async -> Finding? {
        guard !bot else{return nil}
        var policy=Policy()
        if case .object(let v)?=await store.value(for:"lock_policy_\(guildID)") {
            if case .bool(let x)?=v["enabled"]{policy.enabled=x}
            if case .number(let x)?=v["messagesPerMinute"]{policy.messagesPerMinute=Int(x)}
            if case .number(let x)?=v["timeoutMinutes"]{policy.timeoutMinutes=Int(x)}
        }
        guard policy.enabled else{return nil}
        let key=guildID+":"+userID
        var values=(history[key] ?? []).filter{now.timeIntervalSince($0)<60}
        values.append(now);history[key]=values
        guard values.count>max(1,policy.messagesPerMinute) else{return nil}
        let finding=Finding(guildID:guildID,userID:userID,messageID:messageID,reason:"Message rate exceeded \(policy.messagesPerMinute) per minute.")
        await logger.warning("Kimi Lock: \(finding.reason) user=\(userID), guild=\(guildID)")
        return finding
    }
    func setPolicy(_ policy:Policy,guildID:String) async throws {
        let data=try JSONEncoder().encode(policy)
        let value=try JSONDecoder().decode(JSONValue.self,from:data)
        try await store.set(value,for:"lock_policy_\(guildID)")
        await logger.info("Kimi Lock policy updated for \(guildID).")
    }
}
