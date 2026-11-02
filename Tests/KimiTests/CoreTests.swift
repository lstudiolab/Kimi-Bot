import XCTest
@testable import Kimi

final class CoreTests:XCTestCase {
 func testSnowflakeFormat(){
  XCTAssertTrue("123456789012345678".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
  XCTAssertFalse("invalid".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
 }
 func testChannelNameNormalization(){
  XCTAssertEqual(SecurityPolicy.channelName("Hello World!"),"hello-world")
 }
 func testCommandCatalogHasUniqueNamesAndRequiredOperations(){
  let commands=CommandCatalog.globalCommands()
  let names=commands.compactMap{$0["name"] as? String}
  XCTAssertEqual(names.count,Set(names).count)
  for required in ["setup","install","uninstall","automations","guard-review","web-token","plan","apps","app-store"]{XCTAssertTrue(names.contains(required))}
  XCTAssertTrue(CommandCatalog.appNames().contains("Kimi Lock"))
  XCTAssertTrue(CommandCatalog.appNames().contains("Support"))
 }
 func testModerationDefaults(){
  let policy=ModerationEngine.Policy()
  XCTAssertTrue(policy.enabled)
  XCTAssertEqual(policy.messagesPerMinute,20)
  XCTAssertEqual(policy.timeoutMinutes,10)
  XCTAssertEqual(policy.sanction,"timeout")
 }
 func testStorageQuota(){
  let value=StorageQuota.usage(of:Data(repeating:0,count:1024))
  XCTAssertEqual(value.used,1024)
  XCTAssertEqual(value.percent,0)
  XCTAssertEqual(StorageQuota.format(1024),"1.0 KB")
 }
 func testVerificationAgeThreshold(){
  let engine=VerificationEngine()
  let now=Date()
  let accepted=engine.evaluate(createdAt:now.addingTimeInterval(-10*86400),defaultAvatar:true,suspiciousBehavior:true,attempts:3,minimumAgeDays:7,now:now)
  let review=engine.evaluate(createdAt:now.addingTimeInterval(-2*86400),defaultAvatar:false,suspiciousBehavior:false,attempts:1,minimumAgeDays:7,now:now)
  XCTAssertEqual(accepted.decision,.approve)
  XCTAssertEqual(review.decision,.review)
 }
}
