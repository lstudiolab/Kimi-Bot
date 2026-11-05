import XCTest
@testable import Kimi

final class PluginStoreTests: XCTestCase {
    func testPluginCatalogueHasUniqueDefinitionsAndCommandBindings() {
        let names = PluginRegistry.plugins.map(\.name)
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(Set(names).count, names.count)
        for plugin in PluginRegistry.plugins {
            XCTAssertFalse(plugin.systems.isEmpty)
            XCTAssertFalse(plugin.helpers.isEmpty)
            XCTAssertFalse(CommandCatalog.pluginCommands[plugin.name]?.isEmpty ?? true)
        }
    }

    func testPluginStoreMenuAndDetailComponentsRespectDiscordLimits() throws {
        let menu = PluginStoreUI.catalogRows(installed: [])
        XCTAssertNoThrow(try KimiUI.validateMessageComponents(menu))
        XCTAssertEqual(
            (menu.first?["components"] as? [[String: Any]])?.first?["custom_id"] as? String,
            "store:select")

        for plugin in PluginRegistry.plugins {
            let detail = PluginStoreUI.detailRows(plugin, installed: false)
            XCTAssertNoThrow(try KimiUI.validateMessageComponents(detail))
            let button = (detail.first?["components"] as? [[String: Any]])?.first
            XCTAssertEqual(button?["label"] as? String, "Install")
            XCTAssertEqual(button?["custom_id"] as? String, "store:install:" + PluginStoreUI.slug(plugin.name))
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

    func testPluginSlugResolutionIsStable() {
        for plugin in PluginRegistry.plugins {
            let slug = PluginStoreUI.slug(plugin.name)
            XCTAssertEqual(PluginStoreUI.resolve(slug)?.name, plugin.name)
        }
    }
}
