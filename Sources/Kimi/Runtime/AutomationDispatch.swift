import Foundation

extension KimiRuntime {
    func runAutomations(
        guild: String, trigger: String, userID: String, channelID: String?, messageID: String?, content: String,
        username: String = "member"
    ) async {
        await AutomationEngine(store: store, rest: rest, logger: logger).run(
            trigger: trigger, guild: guild, user: userID, channel: channelID ?? "", message: content,
            username: username, messageID: messageID)
    }
}
