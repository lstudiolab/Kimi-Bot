import XCTest
final class CoreTests:XCTestCase {
 func testSnowflakeFormat() {
  XCTAssertTrue("123456789012345678".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
  XCTAssertFalse("invalid".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
 }
 func testChannelNameNormalization() {
  let value="Hello World!".lowercased().replacingOccurrences(of:" ",with:"-")
  XCTAssertEqual(value,"hello-world!")
 }
}

 func testCommandCatalogHasUniqueNamesAndRequiredOperations() {
  let commands=CommandCatalog.globalCommands()
  let names=commands.compactMap{$0["name"] as? String}
  XCTAssertEqual(names.count,Set(names).count,"Global slash-command names must be unique.")
  for required in ["setup","install","uninstall","automations","guard-review","web-token","plan","apps","app-store"] {
   XCTAssertTrue(names.contains(required),"Missing global command: "+required)
  }
  XCTAssertTrue(CommandCatalog.appNames().contains("Kimi Lock"))
  XCTAssertTrue(CommandCatalog.appNames().contains("Support"))
 }
 func testModerationPolicyDefaultsAreConservative() {
  let policy=ModerationEngine.Policy()
  XCTAssertTrue(policy.enabled)
  XCTAssertEqual(policy.messagesPerMinute,20)
  XCTAssertEqual(policy.timeoutMinutes,10)
  XCTAssertEqual(policy.sanction,"timeout")
  XCTAssertTrue(policy.blockInvites)
  XCTAssertTrue(policy.blockMassMentions)
  XCTAssertTrue(policy.blockExcessiveCaps)
 }
