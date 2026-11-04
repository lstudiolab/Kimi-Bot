import XCTest

@testable import Kimi

final class CoreTests: XCTestCase {
    func testSnowflakeFormat() {
        XCTAssertTrue("123456789012345678".range(of: #"^\d{15,22}$"#, options: .regularExpression) != nil)
        XCTAssertFalse("invalid".range(of: #"^\d{15,22}$"#, options: .regularExpression) != nil)
    }
    func testChannelNameNormalization() {
        let value = "Hello World!".lowercased().replacingOccurrences(of: " ", with: "-")
        XCTAssertEqual(value, "hello-world!")
    }
    func testCommandCatalogHasUniqueNamesAndRequiredOperations() {
        let commands = CommandCatalog.globalCommands()
        let names = commands.compactMap { $0["name"] as? String }
        XCTAssertEqual(names.count, Set(names).count, "Global slash-command names must be unique.")
        for required in [
            "setup", "plugin-install", "plugin-remove", "automations", "guard-review", "web-token", "plan", "plugins", "plugin-store",
            "analytics", "performance",
        ] {
            XCTAssertTrue(names.contains(required), "Missing global command: " + required)
        }
        XCTAssertTrue(CommandCatalog.pluginNames().contains("Kimi Lock"))
        XCTAssertTrue(CommandCatalog.appNames().contains("Support"))
    }
    func testModerationPolicyDefaultsAreConservative() {
        let policy = ModerationEngine.Policy()
        XCTAssertTrue(policy.enabled)
        XCTAssertEqual(policy.messagesPerMinute, 20)
        XCTAssertEqual(policy.timeoutMinutes, 10)
        XCTAssertEqual(policy.sanction, "timeout")
        XCTAssertTrue(policy.blockInvites)
        XCTAssertTrue(policy.blockMassMentions)
        XCTAssertTrue(policy.blockExcessiveCaps)
    }

    func testGatewayJSONFramerHandlesMultiplePacketsAndEscapedBraces() throws {
        var buffer = Data(#"{"op":10,"d":{"text":"brace } and quote \" safely"}}{"op":11,"d":null}"#.utf8)
        let first = GatewayJSONFramer.takeFrame(from: &buffer)
        XCTAssertNotNil(first)
        let firstObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(first)) as? [String: Any])
        XCTAssertEqual(firstObject["op"] as? Int, 10)
        let second = GatewayJSONFramer.takeFrame(from: &buffer)
        XCTAssertNotNil(second)
        let secondObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(second)) as? [String: Any])
        XCTAssertEqual(secondObject["op"] as? Int, 11)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testGatewayJSONFramerWaitsForIncompleteObject() {
        var buffer = Data(#"{"op":10,"d":{"#.utf8)
        XCTAssertNil(GatewayJSONFramer.takeFrame(from: &buffer))
        buffer.append(Data(#""heartbeat_interval":41250}}"#.utf8))
        let frame = GatewayJSONFramer.takeFrame(from: &buffer)
        XCTAssertNotNil(frame)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDiscordComponentRowsRespectFiveRowAndFiveButtonLimits() throws {
        let buttons = (0..<6).map { index in
            KimiUI.button(id: "test:\(index)", label: "Button \(index)")
        }
        let rows = KimiUI.buttonRows(buttons)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual((rows[0]["components"] as? [[String: Any]])?.count, 5)
        XCTAssertEqual((rows[1]["components"] as? [[String: Any]])?.count, 1)
        try KimiUI.validateMessageComponents(rows)

        let oversized = Array(repeating: KimiUI.row([KimiUI.button(id: "x", label: "X")]), count: 6)
        XCTAssertThrowsError(try KimiUI.validateMessageComponents(oversized))
    }

    func testEmbedValidatorEnforcesDiscordLimits() {
        let validator = EmbedValidator()
        let valid = EmbedValidator.Definition(
            title: "Kimi", description: "Status", fields: [], color: 8_421_504, imageURL: nil)
        XCTAssertTrue(validator.validate(valid).isEmpty)
        let invalid = EmbedValidator.Definition(
            title: String(repeating: "x", count: 257), description: "", fields: [], color: 8_421_504, imageURL: nil)
        XCTAssertFalse(validator.validate(invalid).isEmpty)
    }
    func testVerificationPassReviewAndRejectThresholds() {
        let engine = VerificationEngine()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let pass = engine.evaluate(
            createdAt: now.addingTimeInterval(-10 * 86400), defaultAvatar: false, suspiciousBehavior: false,
            attempts: 1, minimumAgeDays: 7, now: now)
        XCTAssertEqual(pass.score, 100)
        XCTAssertEqual(pass.decision, .approve)
        let review = engine.evaluate(
            createdAt: now.addingTimeInterval(-10 * 86400), defaultAvatar: true, suspiciousBehavior: false, attempts: 3,
            minimumAgeDays: 7, now: now)
        XCTAssertEqual(review.score, 70)
        XCTAssertEqual(review.decision, .review)
        let reject = engine.evaluate(
            createdAt: now.addingTimeInterval(-1 * 86400), defaultAvatar: true, suspiciousBehavior: true, attempts: 3,
            minimumAgeDays: 7, now: now)
        XCTAssertEqual(reject.score, 0)
        XCTAssertEqual(reject.decision, .reject)
    }
    func testProtectionThreshold() {
        let engine = ProtectionEngine()
        XCTAssertNil(engine.evaluate(action: "channel_delete", count: 3, threshold: 3))
        XCTAssertNotNil(engine.evaluate(action: "channel_delete", count: 4, threshold: 3))
    }
    func testVerificationScoringSeparatesPassReviewAndReject() {
        let engine = VerificationEngine()
        let now = Date()
        let trusted = engine.evaluate(
            createdAt: now.addingTimeInterval(-30 * 86400), defaultAvatar: false, suspiciousBehavior: false,
            attempts: 1, minimumAgeDays: 7, now: now)
        XCTAssertEqual(trusted.score, 100)
        XCTAssertEqual(trusted.decision, .approve)
        let young = engine.evaluate(
            createdAt: now.addingTimeInterval(-1 * 86400), defaultAvatar: false, suspiciousBehavior: false, attempts: 1,
            minimumAgeDays: 7, now: now)
        XCTAssertEqual(young.score, 60)
        XCTAssertEqual(young.decision, .review)
        let risky = engine.evaluate(
            createdAt: now.addingTimeInterval(-30 * 86400), defaultAvatar: true, suspiciousBehavior: true, attempts: 3,
            minimumAgeDays: 7, now: now)
        XCTAssertLessThan(risky.score, 60)
        XCTAssertEqual(risky.decision, .reject)
    }

    func testAutomationMessageConditionAndPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-tests-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = AutomationEngine(store: store)
        do {
            _ = try await engine.add(
                guildID: "123456789012345678", name: "Missing condition", trigger: "message_contains",
                action: "delete_message")
            XCTFail("message_contains must require a condition")
        } catch {}
        let rule = try await engine.add(
            guildID: "123456789012345678", name: "Invite alert", trigger: "message_contains", action: "delete_message",
            condition: "discord.gg")
        let matched = await engine.matching(
            guildID: rule.guildID, trigger: "message_create", content: "Join discord.gg/example")
        XCTAssertEqual(matched.map { $0.id }, [rule.id])
        let unmatched = await engine.matching(
            guildID: rule.guildID, trigger: "message_create", content: "ordinary conversation")
        XCTAssertTrue(unmatched.isEmpty)
        let removed = try await engine.remove(id: rule.id, guildID: rule.guildID)
        XCTAssertTrue(removed)
    }

    func testPersistentStoreRoundTripsCommittedValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-store-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = try PersistentStore(directory: directory)
        try await store.set("committed", key: "test.value")

        let reopened = try PersistentStore(directory: directory)
        let saved = await reopened.get("test.value", as: String.self)
        XCTAssertEqual(saved, "committed")
    }

    func testPersistentStoreDoesNotPublishUncommittedValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-store-failure-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("timi.json"), withIntermediateDirectories: true)

        let store = try PersistentStore(directory: directory)
        do {
            try await store.set("not committed", key: "test.value")
            XCTFail("A write over a directory must fail.")
        } catch {}
        let value = await store.get("test.value", as: String.self)
        XCTAssertNil(value, "Failed disk writes must not mutate in-memory state.")
    }

    func testModerationDetectsDiscordInviteLinks() async {
        let engine = ModerationEngine()
        let finding = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345678",
            messageID: "323456789012345678",
            content: "Join our community at discord.gg/example"
        )

        XCTAssertEqual(finding?.reason, "Unapproved Discord invite link")
    }

}
