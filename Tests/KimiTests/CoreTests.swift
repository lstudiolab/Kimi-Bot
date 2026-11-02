import XCTest
@testable import Kimi

final class CoreTests: XCTestCase {
    func testComponentRouting() {
        XCTAssertEqual(ComponentRouting.app(for: "ticket:open"), "Support")
        XCTAssertEqual(ComponentRouting.app(for: "modpanel:settings"), "Kimi Lock")
        XCTAssertEqual(ComponentRouting.app(for: "rolepicker:select"), "Role Picker")
        XCTAssertNil(ComponentRouting.app(for: "unknown:action"))
    }

    func testAppAliases() {
        XCTAssertEqual(AppRegistry.normalize("security"), "Kimi Lock")
        XCTAssertEqual(AppRegistry.normalize("ticket"), "Support")
        XCTAssertEqual(AppRegistry.normalize("role_picker"), "Role Picker")
        XCTAssertNil(AppRegistry.normalize("not-an-app"))
    }

    func testTextUtilities() {
        XCTAssertTrue(TextUtilities.isSnowflake("123456789012345678"))
        XCTAssertFalse(TextUtilities.isSnowflake("not-a-snowflake"))
        XCTAssertTrue(TextUtilities.matchesBlockedPhrase("stop bad words now", phrase: "bad words"))
        XCTAssertFalse(TextUtilities.matchesBlockedPhrase("bad wordsinside", phrase: "bad words"))
        XCTAssertEqual(TextUtilities.jaccard("red green", "red blue"), 1.0 / 3.0, accuracy: 0.0001)
    }
}
