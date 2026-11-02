import Foundation
struct VerificationEngine {
 enum Decision:String,Codable,Sendable {case approve,review,reject}
 struct Result:Sendable {let score:Int;let decision:Decision;let reasons:[String]}
 func evaluate(createdAt:Date,defaultAvatar:Bool,suspiciousBehavior:Bool,attempts:Int,minimumAgeDays:Int=7,now:Date=Date())->Result {
  let age=max(0,Int(now.timeIntervalSince(createdAt)/86400))
  let passed=age>=max(0,minimumAgeDays)
  var reasons:[String]=[]
  if !passed{reasons.append("Account is younger than the configured minimum.")}
  if defaultAvatar{reasons.append("Default avatar recorded as context only.")}
  if suspiciousBehavior{reasons.append("Previously observed behavior recorded as context only.")}
  if attempts>1{reasons.append("Repeated attempts recorded as context only.")}
  return Result(score:passed ? 100:0,decision:passed ? .approve:.review,reasons:reasons)
 }
}
