import Foundation
struct Protection {
    struct Finding:Sendable {let action:String,severity:Int,reason:String}
    func evaluate(action:String,count:Int,threshold:Int)->Finding? {
        guard count>max(1,threshold) else{return nil}
        let critical=["channel_delete","role_delete","webhook_create","ban","kick"].contains(action)
        return Finding(action:action,severity:critical ? 100:70,reason:"Repeated privileged action exceeded configured threshold.")
    }
}
actor RateGuard {
    private struct Bucket {var tokens=10.0;var updated=Date()}
    private var buckets:[String:Bucket]=[:]
    func consume(key:String,now:Date=Date())->Bool {
        var b=buckets[key] ?? Bucket()
        b.tokens=min(10,b.tokens+max(0,now.timeIntervalSince(b.updated))*10/60);b.updated=now
        guard b.tokens>=1 else{buckets[key]=b;return false}
        b.tokens-=1;buckets[key]=b;return true
    }
}
