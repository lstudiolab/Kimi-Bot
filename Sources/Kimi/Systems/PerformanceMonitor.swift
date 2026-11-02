import Foundation
actor PerformanceMonitor {
 struct Sample:Codable,Sendable {let subsystem:String;let milliseconds:Double;let success:Bool;let timestamp:Date}
 struct Summary:Sendable {let count:Int;let averageMilliseconds:Double;let p95Milliseconds:Double;let failures:Int}
 private var samples:[Sample]=[]
 func record(_ subsystem:String,duration:TimeInterval,success:Bool=true){
  samples.append(Sample(subsystem:subsystem,milliseconds:max(0,duration*1000),success:success,timestamp:Date()))
  if samples.count>2000{samples.removeFirst(samples.count-2000)}
 }
 func summary(_ subsystem:String)->Summary{
  let values=samples.filter{$0.subsystem==subsystem}
  guard !values.isEmpty else{return Summary(count:0,averageMilliseconds:0,p95Milliseconds:0,failures:0)}
  let sorted=values.map{$0.milliseconds}.sorted()
  let p95=sorted[min(sorted.count-1,Int(Double(sorted.count-1)*0.95))]
  return Summary(count:values.count,averageMilliseconds:sorted.reduce(0,+)/Double(sorted.count),p95Milliseconds:p95,failures:values.filter{!$0.success}.count)
 }
 func recent(limit:Int=100)->[Sample]{Array(samples.suffix(max(0,limit)))}
}
