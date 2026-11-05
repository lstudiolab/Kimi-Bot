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

        var prefixed = Data(#"corrupt-prefix{"op":12}"#.utf8)
        let recovered = try XCTUnwrap(GatewayJSONFramer.takeFrame(from: &prefixed))
        let recoveredObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: recovered) as? [String: Any])
        XCTAssertEqual(recoveredObject["op"] as? Int, 12)
    }

    func testGatewayJSONFramerWaitsForIncompleteObject() {
        var buffer = Data(#"{"op":10,"d":{"#.utf8)
        XCTAssertNil(GatewayJSONFramer.takeFrame(from: &buffer))
        buffer.append(Data(#""heartbeat_interval":41250}}"#.utf8))
        let frame = GatewayJSONFramer.takeFrame(from: &buffer)
        XCTAssertNotNil(frame)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testMessageResponsesUseGreyEmbedsAndPrimaryButtons() {
        let response = KimiUI.message("Settings updated.\nAll changes are saved.", components: [
            KimiUI.row([KimiUI.button(id: "settings:home", label: "Home", style: 4)])
        ])
        let embed = (response["embeds"] as? [[String: Any]])?.first
        XCTAssertEqual(embed?["color"] as? Int, KimiUI.grey)
        XCTAssertEqual(embed?["title"] as? String, "Settings updated.")
        XCTAssertEqual(embed?["description"] as? String, "All changes are saved.")
        let rows = response["components"] as? [[String: Any]] ?? []
        let buttons = rows.flatMap { $0["components"] as? [[String: Any]] ?? [] }
        XCTAssertTrue(buttons.allSatisfy { ($0["style"] as? Int) == 1 })
    }

    func testDiscordComponentRowsRespectFiveRowAndFiveButtonLimits() throws {
        let buttons = (0..<6).map { index in
            KimiUI.button(id: "test:\(index)", label: "Button \(index)")
        }
        let rows = KimiUI.buttonRows(buttons)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual((buttons.first?["style"] as? Int), 2, "All Kimi buttons must use Discord secondary styling.")
        XCTAssertEqual((rows[0]["components"] as? [[String: Any]])?.count, 5)
        XCTAssertEqual((rows[1]["components"] as? [[String: Any]])?.count, 1)
        try KimiUI.validateMessageComponents(rows)
        let panel = KimiUI.panel(title: "Settings", description: "Current configuration.")
        let embeds = panel["embeds"] as? [[String: Any]]
        XCTAssertEqual(embeds?.first?["color"] as? Int, 0x808080)
        XCTAssertEqual(embeds?.first?["title"] as? String, "Settings")

        let oversized = Array(repeating: KimiUI.row([KimiUI.button(id: "x", label: "X")]), count: 6)
        XCTAssertThrowsError(try KimiUI.validateMessageComponents(oversized))
    }

    func testDiscordTextUsesUTF16Boundaries() {
        XCTAssertEqual(DiscordText.prefixUTF16("😀😀A", limit: 3), "😀")
        XCTAssertEqual(DiscordText.prefixUTF16("😀A", limit: 1), "")
        XCTAssertEqual(DiscordText.prefixUTF16("abc", limit: 2), "ab")
    }

    func testComponentLabelsAndIdentifiersRespectUTF16Limits() {
        let button = KimiUI.button(
            id: String(repeating: "😀", count: 60),
            label: String(repeating: "😀", count: 50))
        XCTAssertLessThanOrEqual((button["custom_id"] as? String)?.utf16.count ?? 0, 100)
        XCTAssertLessThanOrEqual((button["label"] as? String)?.utf16.count ?? 0, 80)
    }

    func testEmbedValidatorCountsUTF16Units() {
        let validator = EmbedValidator()
        let invalid = EmbedValidator.Definition(
            title: String(repeating: "😀", count: 129), description: "", fields: [], color: 0)
        XCTAssertTrue(validator.validate(invalid).contains { $0.contains("Title exceeds") })
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
        let engine = ModerationEngine(store: store)
        var policy = await engine.policy(guildID: guild)
        policy.messagesPerMinute = 5
        try await engine.configure(policy, guildID: guild)
        let now = Date()
        for index in 0..<5 {
            _ = await engine.evaluate(
                guildID: guild, userID: user,
                messageID: "32345678901234567" + String(index),
                content: "message " + String(index), channelID: "423456789012345678",
                now: now.addingTimeInterval(Double(index)))
        }
        // Rate history is checkpointed every five messages; a new engine must load that checkpoint.
        let restartedEngine = ModerationEngine(store: store)
        let finding = await restartedEngine.evaluate(
            guildID: guild, userID: user, messageID: "323456789012345679",
            content: "sixth message", channelID: "423456789012345678", now: now.addingTimeInterval(5))
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

        let wwwTracking = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345680", content: "Open www.grabify.link/example")
        XCTAssertTrue(wwwTracking?.reason.contains("Suspicious or tracking URL") == true)

        let ordinaryURL = await engine.evaluate(
            guildID: "123456789012345678", userID: "223456789012345678",
            messageID: "323456789012345681", content: "Read https://example.com and continue with the guide")
        XCTAssertFalse(ordinaryURL?.reason.contains("Suspicious or tracking URL") == true)
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
                managed: false, permissions: (1 << 10) | (1 << 11) | (1 << 14) | (1 << 20) | (1 << 21))
        )
        XCTAssertFalse(
            SecurityPolicy.isSafeRole(
                roleID: "223456789012345681", guildID: "123456789012345678",
                managed: false, permissions: 1 << 1),
            "Kick Members must not be assignable through automated role menus."
        )
        XCTAssertFalse(
            SecurityPolicy.isSafeRole(
                roleID: "223456789012345682", guildID: "123456789012345678",
                managed: false, permissions: 1 << 2),
            "Ban Members must not be assignable through automated role menus."
        )
    }

    func testModerationCacheChangesOnlyAfterSuccessfulPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-moderation-cache-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("timi.json"), withIntermediateDirectories: true)
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
            color: 0x1000000, author: valid.author, footer: (valid.footer ?? "") + "x",
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

    func testAnalyticsCountersAreAtomicAcrossServiceInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-analytics-atomic-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await AnalyticsService(store: store).record(guild: "123456789012345678", event: "message")
                }
            }
        }
        let report = await AnalyticsService(store: store).report(guild: "123456789012345678")
        XCTAssertEqual(report.messages, 100)
    }

    func testVerificationAttemptsAreAtomicAcrossServiceInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-verification-atomic-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = try? await VerificationRecords(store: store).attempt(
                        guildID: "123456789012345678", userID: "223456789012345678")
                }
            }
        }
        let record = await VerificationRecords(store: store).record(
            guildID: "123456789012345678", userID: "223456789012345678")
        XCTAssertEqual(record.attempts, 50)
    }

    func testConcurrentModerationEvaluationsPreserveRateHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-moderation-atomic-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        var policy = await engine.policy(guildID: "123456789012345678")
        policy.messagesPerMinute = 2
        try await engine.configure(policy, guildID: "123456789012345678")
        let now = Date()
        let findings = await withTaskGroup(of: ModerationEngine.Finding?.self, returning: [ModerationEngine.Finding?].self) { group in
            for index in 0..<12 {
                group.addTask {
                    await engine.evaluate(
                        guildID: "123456789012345678", userID: "223456789012345678",
                        messageID: "3234567890123456" + String(format: "%02d", index),
                        content: "unique message " + String(index),
                        channelID: "423456789012345678",
                        now: now)
                }
            }
            var values: [ModerationEngine.Finding?] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertTrue(findings.contains { $0?.reason.contains("High-velocity message flood") == true })
    }

    func testModerationDoesNotCountEditsAsNewMessagesAndUsesUTF16Length() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-moderation-edit-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let engine = ModerationEngine(store: store)
        let guild = "123456789012345678"
        let user = "223456789012345678"
        var policy = await engine.policy(guildID: guild)
        policy.messagesPerMinute = 2
        try await engine.configure(policy, guildID: guild)
        let now = Date()
        _ = await engine.evaluate(
            guildID: guild, userID: user, messageID: "323456789012345678",
            content: "first ordinary message", now: now)
        _ = await engine.evaluate(
            guildID: guild, userID: user, messageID: "323456789012345679",
            content: "second ordinary message", now: now.addingTimeInterval(1))
        for offset in 0..<4 {
            let edit = await engine.evaluate(
                guildID: guild, userID: user, messageID: "323456789012345679",
                content: "second ordinary message", now: now.addingTimeInterval(Double(offset + 2)),
                isEdit: true)
            XCTAssertFalse(edit?.reason.contains("High-velocity message flood") == true)
            XCTAssertFalse(edit?.reason.contains("Repeated message burst") == true)
        }
        let oversizedUnicode = await engine.evaluate(
            guildID: guild, userID: "223456789012345680", messageID: "323456789012345680",
            content: String(repeating: "😀", count: 1000), now: now)
        XCTAssertTrue(oversizedUnicode?.reason.contains("Message length flood") == true)
    }

    func testRecoveryEditsPreserveOriginalRetentionTimestamp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-recovery-edit-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let guild = "123456789012345678"
        let messageID = "323456789012345678"
        let originalDate = Date().addingTimeInterval(-2 * 86400)
        let original = RecoveryService.Message(
            id: messageID, channelID: "423456789012345678",
            authorID: "223456789012345678", content: "before edit",
            createdAt: originalDate, authorName: "member", attachments: [])
        try await store.setGuild(
            [guild: [original]], key: "recovery.messages", guildID: guild)

        let service = RecoveryService(
            store: store, logger: Logger(), rest: DiscordREST(token: "test"))
        await service.captureMessage(
            guild, "423456789012345678", messageID, "223456789012345678",
            "after edit", authorName: "member")

        let saved = await store.get(
            "recovery.messages", as: [String: [RecoveryService.Message]].self)
        XCTAssertEqual(saved?[guild]?.first?.content, "after edit")
        XCTAssertEqual(saved?[guild]?.first?.createdAt, originalDate)
    }

    func testVerificationFailureInvalidatesOldReviewMessage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-verification-review-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let records = VerificationRecords(store: try PersistentStore(directory: directory))
        let guild = "123456789012345678"
        let user = "223456789012345678"
        try await records.setReviewMessage(guildID: guild, userID: user, messageID: "323456789012345678")
        try await records.markFailed(guildID: guild, userID: user, reason: "Rejected by owner")
        let record = await records.record(guildID: guild, userID: user)
        XCTAssertNil(record.reviewMessageID)
        XCTAssertEqual(record.failures, 1)
    }

    func testDiscordTextLimitsCountUTF16CodeUnits() {
        let value = "A😀B"
        XCTAssertEqual(DiscordText.prefixUTF16(value, limit: 2), "A")
        XCTAssertEqual(DiscordText.prefixUTF16(value, limit: 3), "A😀")

        let longID = String(repeating: "😀", count: 60)
        let channelMenu = KimiUI.channelSelect(id: longID, placeholder: "Channel")
        let roleMenu = KimiUI.roleSelect(id: longID, placeholder: "Role")
        XCTAssertLessThanOrEqual((channelMenu["custom_id"] as? String ?? "").utf16.count, 100)
        XCTAssertLessThanOrEqual((roleMenu["custom_id"] as? String ?? "").utf16.count, 100)
    }

    func testRecoveryDoesNotReintroduceExpiredMessagesAfterEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kimi-recovery-expired-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PersistentStore(directory: directory)
        let guild = "123456789012345678"
        let service = RecoveryService(
            store: store, logger: Logger(), rest: DiscordREST(token: "test"))
        await service.captureMessage(
            guild, "423456789012345678", "323456789012345678", "223456789012345678",
            "edited after retention", createdAt: Date().addingTimeInterval(-8 * 86400))
        let saved = await store.get(
            "recovery.messages", as: [String: [RecoveryService.Message]].self)
        XCTAssertTrue(saved?[guild]?.isEmpty ?? true)
    }

    func testAutoRolePolicyChecksHierarchyAndPrivilegedPermissions() {
        let guild = "123456789012345678"
        let botRoleID = "223456789012345678"
        let targetRoleID = "323456789012345678"
        let botRole: [String: Any] = [
            "id": botRoleID, "position": 10, "permissions": "268435456", "managed": false,
        ]
        let safeRole: [String: Any] = [
            "id": targetRoleID, "position": 5, "permissions": "0", "managed": false,
        ]
        XCTAssertNoThrow(
            try AutoRolePolicy.validate(
                guildID: guild, roleID: targetRoleID,
                roles: [botRole, safeRole], botRoleIDs: [botRoleID]))

        let elevatedRole: [String: Any] = [
            "id": targetRoleID, "position": 5, "permissions": "8", "managed": false,
        ]
        XCTAssertThrowsError(
            try AutoRolePolicy.validate(
                guildID: guild, roleID: targetRoleID,
                roles: [botRole, elevatedRole], botRoleIDs: [botRoleID]))

        let higherRole: [String: Any] = [
            "id": targetRoleID, "position": 11, "permissions": "0", "managed": false,
        ]
        XCTAssertThrowsError(
            try AutoRolePolicy.validate(
                guildID: guild, roleID: targetRoleID,
                roles: [botRole, higherRole], botRoleIDs: [botRoleID]))
    }

}
