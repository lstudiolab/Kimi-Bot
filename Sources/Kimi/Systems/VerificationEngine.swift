import Foundation

struct VerificationEngine {
 enum Decision:String,Codable,Sendable {case approve,review,reject}
 struct Result:Sendable {let score:Int;let decision:Decision;let reasons:[String]}
 func evaluate(createdAt:Date,defaultAvatar:Bool,suspiciousBehavior:Bool,attempts:Int,minimumAgeDays:Int=7,now:Date=Date())->Result {
  let age=max(0,Int(now.timeIntervalSince(createdAt)/86400));var score=40;var reasons:[String]=[]
  if age<minimumAgeDays{score-=35;reasons.append("Account is younger than the configured minimum.")}
  if defaultAvatar{score-=10;reasons.append("Default avatar.")}
  if suspiciousBehavior{score-=25;reasons.append("Suspicious message behavior.")}
  if attempts>1{score-=min(20,(attempts-1)*10);reasons.append("Repeated verification attempts.")}
  if age>=90{score+=30}
  score=min(100,max(0,score))
  return Result(score:score,decision:score>=80 ? .approve:(score>=60 ? .review:.reject),reasons:reasons)
 }
}
