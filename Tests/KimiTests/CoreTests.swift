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
            "setup", "plugin-install", "plugin-remove", "automations", "guard-review",
            "plan", "plugins", "plugin-store",
            "analytics", "performance",
        ] {
            XCTAssertTrue(names.contains(required), "Missing global command: " + required)
        }
        for removed in ["apps", "app-store", "install", "uninstall", "web-token"] {
            XCTAssertFalse(names.contains(removed), "Legacy app command is still registered: " + removed)
        }
        XCTAssertTrue(CommandCatalog.pluginNames().contains("Kimi Lock"))
        XCTAssertTrue(CommandCatalog.pluginNames().contains("Support"))
    }
    func testPluginStoreNamingAndCommandRegistration() {
        let names = Set(CommandCatalog.globalCommands().compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("plugin-store"))
        XCTAssertTrue(names.contains("plugin-install"))
        XCTAssertTrue(names.contains("plugin-remove"))
        XCTAssertFalse(names.contains("app-store"))
        XCTAssertFalse(names.contains("install"))
        XCTAssertFalse(names.contains("uninstall"))
        XCTAssertEqual(PluginRegistry.resolve("Kimi Lock")?.name, "Kimi Lock")
        XCTAssertEqual(PluginRegistry.resolve("tickets")?.name, "Support")
        let support = Set(CommandCatalog.guildCommands(installed: ["Support"]).compactMap { $0["name"] as? String })
        XCTAssertEqual(support, Set(["ticket-screen"]))
        XCTAssertTrue(CommandCatalog.guildCommands(installed: []).isEmpty)
        XCTAssertEqual(
            Set(CommandCatalog.guildCommands(installed: ["Kimi Lock"]).compactMap { $0["name"] as? String }),
            Set(["kimi-lock-screen"])
        )
    }

    func testPluginManagerPersistsInstallationsAndMigratesLegacyData() async throws {
        let guild = "123456789012345678"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-plugin-store-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = ["installed_plugins": [guild: ["Welcome"]]]
        let data = try JSONSerialization.data(withJSONObject: legacy, options: [.prettyPrinted])
        try data.write(to: directory.appendingPathComponent("timi.json"))

        let store = try PersistentStore(directory: directory)
        let manager = PluginManager(store: store)
        let migrated = await manager.installed(guildID: guild)
        XCTAssertEqual(migrated, ["Welcome"])

        let installed = try await manager.install("Support", guildID: guild)
        XCTAssertTrue(installed.ok)
        let afterInstall = await manager.installed(guildID: guild)
        XCTAssertEqual(Set(afterInstall), Set(["Welcome", "Support"]))

        let duplicate = try await manager.install("Support", guildID: guild)
        XCTAssertFalse(duplicate.ok)

        let removed = try await manager.uninstall("Support", guildID: guild)
        XCTAssertTrue(removed.ok)
        let afterRemoval = await manager.installed(guildID: guild)
        XCTAssertEqual(afterRemoval, ["Welcome"])

        let reopened = try PersistentStore(directory: directory)
        let persisted = await PluginManager(store: reopened).installed(guildID: guild)
        XCTAssertEqual(persisted, ["Welcome"])
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
        let store = try PersistentStore(directory: directory)
        try await store.set("committed", key: "test.existing")
        let file = directory.appendingPathComponent("timi.json")
        let backup = directory.appendingPathComponent("timi.json.backup")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        do {
            try await store.set("not committed", key: "test.value")
            XCTFail("A write over a directory must fail.")
        } catch {}
        let value = await store.get("test.value", as: String.self)
        let existing = await store.get("test.existing", as: String.self)
        XCTAssertNil(value, "Failed disk writes must not publish new values.")
        XCTAssertEqual(existing, "committed", "Failed writes must preserve previously committed memory state.")
    }

    func testModerationDetectsObfuscatedTermsAndExecutableAttachments() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-threat-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        var policy = await engine.policy(guildID: "123456789012345678")
        policy.blockedPhrases = ["badword"]
        try await engine.configure(policy, guildID: "123456789012345678")

        let obfuscated = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345678",
            messageID: "323456789012345678",
            content: "b.a.d.w.o.r.d with a hidden character"
        )
        XCTAssertTrue(obfuscated?.reason.contains("Custom blocked keyword") == true)

        let spacedObfuscation = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345679",
            messageID: "323456789012345679",
            content: "b a d w o r d"
        )
        XCTAssertTrue(spacedObfuscation?.reason.contains("Custom blocked keyword") == true)

        let hidden = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "323456789012345679",
            messageID: "423456789012345678",
            content: "f\u{200B}.u.c.k"
        )
        XCTAssertTrue(hidden?.reason.contains("Blocked language") == true)

        let attachment = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "423456789012345679",
            messageID: "523456789012345678",
            content: "Please run this file",
            attachments: [["filename": "payload.exe"]]
        )
        XCTAssertTrue(attachment?.reason.contains("Executable or script attachment") == true)
    }

    func testModerationDetectsTrackingLinksAndDuplicateBursts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-threat-rate-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        let link = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345678",
            messageID: "323456789012345678",
            content: "Check https://grabify.link/abc"
        )
        XCTAssertTrue(link?.reason.contains("Suspicious or tracking URL") == true)

        let advertising = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345679",
            messageID: "323456789012345679",
            content: "Join my server https://example.com"
        )
        XCTAssertTrue(advertising?.reason.contains("Unsolicited self-advertising") == true)

        let now = Date()
        _ = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "323456789012345679",
            messageID: "423456789012345678",
            content: "same repeated message",
            now: now
        )
        _ = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "323456789012345679",
            messageID: "423456789012345679",
            content: "same repeated message",
            now: now.addingTimeInterval(1)
        )
        let duplicate = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "323456789012345679",
            messageID: "423456789012345680",
            content: "same repeated message",
            now: now.addingTimeInterval(2)
        )
        XCTAssertTrue(duplicate?.reason.contains("Repeated message burst") == true)
    }

    func testModerationRateHistorySurvivesNewEngineInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-rate-persistence-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let guild = "123456789012345678"
        let user = "223456789012345678"
        var policy = await ModerationEngine(store: store).policy(guildID: guild)
        policy.messagesPerMinute = 2
        try await ModerationEngine(store: store).configure(policy, guildID: guild)
        let now = Date()
        _ = await ModerationEngine(store: store).evaluate(
            guildID: guild, userID: user, messageID: "323456789012345678",
            content: "first", channelID: "423456789012345678", now: now)
        _ = await ModerationEngine(store: store).evaluate(
            guildID: guild, userID: user, messageID: "323456789012345679",
            content: "second", channelID: "423456789012345678", now: now.addingTimeInterval(1))
        let finding = await ModerationEngine(store: store).evaluate(
            guildID: guild, userID: user, messageID: "323456789012345680",
            content: "third", channelID: "423456789012345678", now: now.addingTimeInterval(2))
        XCTAssertTrue(finding?.reason.contains("High-velocity message flood") == true)
    }

    func testAuditProtectionHistorySurvivesNewInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-audit-persistence-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let now = Date()
        let first = try await AuditProtection(store: store).record(
            guildID: "123456789012345678", actorID: "223456789012345678",
            action: "12", threshold: 1, now: now)
        XCTAssertNil(first)
        let second = try await AuditProtection(store: store).record(
            guildID: "123456789012345678", actorID: "223456789012345678",
            action: "12", threshold: 1, now: now.addingTimeInterval(1))
        XCTAssertNotNil(second)
    }

    func testTicketCooldownReservationIsAtomicAndPerGuild() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-ticket-cooldown-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let guild = "123456789012345678"
        let now = Date()
        let key = "support.ticket-cooldowns." + guild

        let first = try await store.claimGuildCooldown(
            key, subject: "223456789012345678", guildID: guild, interval: 60, now: now)
        let duplicate = try await store.claimGuildCooldown(
            key, subject: "223456789012345678", guildID: guild, interval: 60,
            now: now.addingTimeInterval(1))
        let afterCooldown = try await store.claimGuildCooldown(
            key, subject: "223456789012345678", guildID: guild, interval: 60,
            now: now.addingTimeInterval(61))

        XCTAssertTrue(first)
        XCTAssertFalse(duplicate)
        XCTAssertTrue(afterCooldown)
    }

    func testModerationDetectsHiddenAndSingleCharacterKeywordObfuscation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-obfuscation-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        var policy = await engine.policy(guildID: "123456789012345678")
        policy.blockedPhrases = ["badword"]
        try await engine.configure(policy, guildID: "123456789012345678")

        let hidden = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345678", content: "b\u{200B}a\u{200D}dword")
        XCTAssertTrue(hidden?.reason.contains("Custom blocked keyword") == true)

        let spaced = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345679", content: "b a d w o r d")
        XCTAssertTrue(spaced?.reason.contains("Custom blocked keyword") == true)
    }

    func testModerationDetectsTrackingAndRawIPAddressLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-url-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        let tracking = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345678", content: "Open https://grabify.link/example")
        XCTAssertTrue(tracking?.reason.contains("Suspicious or tracking URL") == true)
        let rawIP = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345679", content: "Visit 192.168.1.20:8080/path")
        XCTAssertTrue(rawIP?.reason.contains("Suspicious or tracking URL") == true)
    }

    func testModerationDetectsUnsolicitedSelfAdvertising() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-advertising-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        let finding = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345678",
            content: "Join my server at https://example.com")
        XCTAssertTrue(finding?.reason.contains("Unsolicited self-advertising") == true)
    }

    func testModerationDetectsDiscordInviteLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-moderation-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        let finding = await engine.evaluate(
            guildID: "123456789012345678",
            userID: "223456789012345678",
            messageID: "323456789012345678",
            content: "Join our community at discord.gg/example"
        )

        XCTAssertTrue(finding?.reason.contains("Unsolicited Discord invite") == true)
    }

    func testSecurityPolicyRejectsPrivilegedChannelAndEventRoles() {
        XCTAssertFalse(
            SecurityPolicy.isSafeRole(
                roleID: "223456789012345678", guildID: "123456789012345678",
                managed: false, permissions: 1 << 4),
            "Manage Channels must not be assignable through automated role menus."
        )
        XCTAssertFalse(
            SecurityPolicy.isSafeRole(
                roleID: "223456789012345679", guildID: "123456789012345678",
                managed: false, permissions: 1 << 33),
            "Manage Events must not be assignable through automated role menus."
        )
        XCTAssertTrue(
            SecurityPolicy.isSafeRole(
                roleID: "223456789012345680", guildID: "123456789012345678",
                managed: false, permissions: 1 << 11)
        )
    }

    func testModerationCacheChangesOnlyAfterSuccessfulPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-moderation-cache-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("timi.json"), withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        var changed = ModerationEngine.Policy()
        changed.messagesPerMinute = 77
        do {
            try await engine.configure(changed, guildID: "123456789012345678")
            XCTFail("Configuration should fail when the store path is not writable.")
        } catch {}
        let current = await engine.policy(guildID: "123456789012345678")
        XCTAssertEqual(current.messagesPerMinute, 20)
    }

    func testEmbedValidatorEnforcesDiscordCombinedCharacterAndColorLimits() {
        let validator = EmbedValidator()
        let valid = EmbedValidator.Definition(
            title: String(repeating: "t", count: 256),
            description: String(repeating: "d", count: 4096),
            fields: [.init(name: String(repeating: "n", count: 256), value: String(repeating: "v", count: 1024))],
            color: 0x808080,
            author: String(repeating: "a", count: 256),
            footer: String(repeating: "f", count: 112),
            url: nil,
            imageURL: nil
        )
        XCTAssertTrue(validator.validate(valid).isEmpty)
        let invalid = EmbedValidator.Definition(
            title: valid.title, description: valid.description, fields: valid.fields,
            color: 0x1000000, author: valid.author, footer: valid.footer + "x",
            url: "javascript:alert(1)", imageURL: nil
        )
        XCTAssertFalse(validator.validate(invalid).isEmpty)
    }

    func testStringSelectClampsSelectionToAvailableOptions() throws {
        let menu = KimiUI.stringSelect(
            id: "roles", placeholder: "Choose roles",
            options: [["label": "A", "value": "a"], ["label": "B", "value": "b"]],
            minimum: 0, maximum: 10)
        XCTAssertEqual(menu["max_values"] as? Int, 2)
        XCTAssertNoThrow(try KimiUI.validateMessageComponents([KimiUI.row([menu])]))
    }

}
