import XCTest
@testable import Kimi
final class CoreTests:XCTestCase{
 func testSnowflakeFormat(){XCTAssertTrue("123456789012345678".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil);XCTAssertFalse("invalid".range(of:#"^\d{15,22}$"#,options:.regularExpression) != nil)}
 func testChannelNameNormalization(){let value="Hello World!".lowercased().replacingOccurrences(of:" ",with:"-");XCTAssertEqual(value,"hello-world!")}
}
