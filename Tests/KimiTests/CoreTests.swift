import XCTest
@testable import Kimi

final class CoreTests:XCTestCase {
 func testSnowflakeFormat(){
  XCTAssertTrue("123456789012345678".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
  XCTAssertFalse("invalid".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)
 }
 func testChannelNameNormalization(){
  let value="Hello World!".lowercased().replacingOccurrences(of:" ",with:"-")
  XCTAssertEqual(value,"hello-world!")
 }
 func testCommandCatalogHasUniqueNamesAndRequiredOperations(){
  let commands=CommandCatalog.globalCommands()
  let names=commands.compactMap{$0["name"] as? String}
  XCTAssertEqual(names.count,Set(names).count,"Global slash-command names must be unique.")
  for required in ["setup","install","uninstall","automations","guard-review","web-token","plan","apps","app-store","analytics","performance"]{
   XCTAssertTrue(names.contains(required),"Missing global command: "+required)
  }
  XCTAssertTrue(CommandCatalog.appNames().contains("Kimi Lock"))
  XCTAssertTrue(CommandCatalog.appNames().contains("Support"))
 }
 func testModerationPolicyDefaultsAreConservative(){
  let policy=ModerationEngine.Policy()
  XCTAssertTrue(policy.enabled)
  XCTAssertEqual(policy.messagesPerMinute,20)
  XCTAssertEqual(policy.timeoutMinutes,10)
  XCTAssertEqual(policy.sanction,"timeout")
  XCTAssertTrue(policy.blockInvites)
  XCTAssertTrue(policy.blockMassMentions)
  XCTAssertTrue(policy.blockExcessiveCaps)
 }
 func testEmbedValidatorEnforcesDiscordLimits(){
  let validator=EmbedValidator()
  let valid=EmbedValidator.Definition(title:"Kimi",description:"Status",fields:[],color:8421504,imageURL:nil)
  XCTAssertTrue(validator.validate(valid).isEmpty)
  let invalid=EmbedValidator.Definition(title:String(repeating:"x",count:257),description:"",fields:[],color:8421504,imageURL:nil)
  XCTAssertFalse(validator.validate(invalid).isEmpty)
 }
 func testVerificationPassReviewAndRejectThresholds(){
  let engine=VerificationEngine(),now=Date(timeIntervalSince1970:2_000_000_000)
  let pass=engine.evaluate(createdAt:now.addingTimeInterval(-10*86400),defaultAvatar:false,suspiciousBehavior:false,attempts:1,minimumAgeDays:7,now:now)
  XCTAssertEqual(pass.score,100);XCTAssertEqual(pass.decision,.approve)
  let review=engine.evaluate(createdAt:now.addingTimeInterval(-10*86400),defaultAvatar:true,suspiciousBehavior:false,attempts:3,minimumAgeDays:7,now:now)
  XCTAssertEqual(review.score,70);XCTAssertEqual(review.decision,.review)
  let reject=engine.evaluate(createdAt:now.addingTimeInterval(-1*86400),defaultAvatar:true,suspiciousBehavior:true,attempts:3,minimumAgeDays:7,now:now)
  XCTAssertEqual(reject.score,0);XCTAssertEqual(reject.decision,.reject)
 }
 func testProtectionThreshold(){
  let engine=ProtectionEngine()
  XCTAssertNil(engine.evaluate(action:"channel_delete",count:3,threshold:3))
  XCTAssertNotNil(engine.evaluate(action:"channel_delete",count:4,threshold:3))
 }
 func testVerificationScoringSeparatesPassReviewAndReject(){
  let engine=VerificationEngine()
  let now=Date()
  let trusted=engine.evaluate(createdAt:now.addingTimeInterval(-30*86400),defaultAvatar:false,suspiciousBehavior:false,attempts:1,minimumAgeDays:7,now:now)
  XCTAssertEqual(trusted.score,100)
  XCTAssertEqual(trusted.decision,.approve)
  let young=engine.evaluate(createdAt:now.addingTimeInterval(-1*86400),defaultAvatar:false,suspiciousBehavior:false,attempts:1,minimumAgeDays:7,now:now)
  XCTAssertEqual(young.score,60)
  XCTAssertEqual(young.decision,.review)
  let risky=engine.evaluate(createdAt:now.addingTimeInterval(-30*86400),defaultAvatar:true,suspiciousBehavior:true,attempts:3,minimumAgeDays:7,now:now)
  XCTAssertLessThan(risky.score,60)
  XCTAssertEqual(risky.decision,.reject)
 }

}
