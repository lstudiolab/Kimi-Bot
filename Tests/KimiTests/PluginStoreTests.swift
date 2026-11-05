import XCTest
@testable import Kimi

final class PluginStoreTests: XCTestCase {
    func testPluginCatalogueHasUniqueDefinitionsAndUsesControlCenterInsteadOfPluginCommands() {
        let names = PluginRegistry.plugins.map(\.name)
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(Set(names).count, names.count)
        for plugin in PluginRegistry.plugins {
            XCTAssertFalse(plugin.systems.isEmpty)
            XCTAssertFalse(plugin.helpers.isEmpty)
            XCTAssertNotNil(CommandCatalog.pluginCommands[plugin.name])
            XCTAssertTrue(CommandCatalog.pluginCommands[plugin.name]?.isEmpty ?? false)
        }
        XCTAssertEqual(CommandCatalog.globalCommands().compactMap { $0["name"] as? String }, ["control-center"])
        XCTAssertTrue(CommandCatalog.guildCommands(installed: names).isEmpty)
    }

    func testKimiGuardIsListedAsItsOwnSixLevelModule() {
        let plugin = PluginRegistry.plugins.first { $0.name == "Kimi Guard" }
        XCTAssertNotNil(plugin)
        XCTAssertNotNil(CommandCatalog.pluginCommands["Kimi Guard"])
        XCTAssertTrue(CommandCatalog.pluginCommands["Kimi Guard"]?.isEmpty ?? false)
        XCTAssertEqual(KimiGuardCatalog.sections.count, 6)
        XCTAssertTrue(KimiGuardCatalog.sections.contains { $0.title == "Micro / Tiny Essentials" })
        XCTAssertTrue(KimiGuardCatalog.sections.contains { $0.title == "Massive / Cutting-Edge Systems" })
        XCTAssertTrue(KimiGuardCatalog.sections.flatMap(\.features).contains { $0.name.contains("phishing") })
        XCTAssertGreaterThan(KimiGuardCatalog.availableCount, 0)
        XCTAssertGreaterThan(KimiGuardCatalog.plannedCount, 0)
    }

    func testPluginStoreMenuAndDetailComponentsRespectDiscordLimits() throws {
        let menu = PluginStoreUI.catalogRows(installed: [])
        XCTAssertNoThrow(try KimiUI.validateMessageComponents(menu))
        XCTAssertEqual(
            (menu.first?["components"] as? [[String: Any]])?.first?["custom_id"] as? String,
            "store:select")
        XCTAssertEqual(
            (menu.last?["components"] as? [[String: Any]])?.first?["custom_id"] as? String,
            "store:home")

        for plugin in PluginRegistry.plugins {
            let detail = PluginStoreUI.detailRows(plugin, installed: false)
            XCTAssertNoThrow(try KimiUI.validateMessageComponents(detail))
            let button = (detail.first?["components"] as? [[String: Any]])?.first
            XCTAssertEqual(button?["label"] as? String, "Install")
            XCTAssertEqual(button?["custom_id"] as? String, "store:install:" + PluginStoreUI.slug(plugin.name))
            XCTAssertEqual(
                (detail.first?["components"] as? [[String: Any]])?.last?["custom_id"] as? String,
                "store:back")
        }
    }

    func testInstallationControlsContainProgressAndCancellationActions() throws {
        for plugin in PluginRegistry.plugins {
            let rows = PluginStoreUI.installingRows(PluginStoreUI.slug(plugin.name))
            XCTAssertNoThrow(try KimiUI.validateMessageComponents(rows))
            let buttons = rows.first?["components"] as? [[String: Any]] ?? []
            XCTAssertEqual(buttons.compactMap { $0["label"] as? String }, ["Installing", "Cancel"])
        }
    }

    func testInstalledModuleScreenHasBackNavigation() throws {
        let rows = PluginStoreUI.installedRows()
        XCTAssertNoThrow(try KimiUI.validateMessageComponents(rows))
        XCTAssertEqual(
            (rows.first?["components"] as? [[String: Any]])?.first?["custom_id"] as? String,
            "store:back")
    }

    func testPluginSlugResolutionIsStable() {
        for plugin in PluginRegistry.plugins {
            let slug = PluginStoreUI.slug(plugin.name)
            XCTAssertEqual(PluginStoreUI.resolve(slug)?.name, plugin.name)
        }
    }
}
