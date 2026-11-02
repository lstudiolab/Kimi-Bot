import Foundation
struct Verification {
    enum Decision:String,Sendable {case approve,review,reject}
    struct Result:Sendable {let score:Int;let decision:Decision;let reasons:[String]}
    func evaluate(createdAt:Date,minimumAgeDays:Int,defaultAvatar:Bool,suspiciousBehavior:Bool,attempts:Int,now:Date=Date())->Result {
        let age=max(0,Int(now.timeIntervalSince(createdAt)/86400));var score=40;var reasons:[String]=[]
        if age<minimumAgeDays{score-=35;reasons.append("Account age is below the configured minimum.")}
        if age>=90{score+=30}
        if defaultAvatar{score-=10;reasons.append("Default avatar.")}
        if suspiciousBehavior{score-=25;reasons.append("Suspicious message behavior.")}
        if attempts>1{score-=min(20,(attempts-1)*10);reasons.append("Repeated verification attempts.")}
        score=min(100,max(0,score))
        return Result(score:score,decision:score>=80 ? .approve:(score>=60 ? .review:.reject),reasons:reasons)
    }
}
