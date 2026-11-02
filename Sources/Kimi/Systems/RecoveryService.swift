import Foundation

actor RecoveryService {
 struct Message:Codable,Sendable {let id:String;let channelID:String;let authorID:String;let content:String;let createdAt:Date}
 private let store:PersistentStore;private let logger:Logger
 init(store:PersistentStore,logger:Logger){self.store=store;self.logger=logger}
 func captureChannel(_ guild:String,_ channel:[String:Any])async{
  guard let id=channel["id"] as? String,let data=try? JSONSerialization.data(withJSONObject:channel,options:[.fragmentsAllowed]) else{return}
  var all=await store.get("recovery.channels",as:[String:[String:Data]].self) ?? [:]
  all[guild,default:[:]][id]=data
  if all[guild,default:[:]].count>500{all[guild]=Dictionary(uniqueKeysWithValues:all[guild,default:[:]].sorted{$0.key<$1.key}.suffix(500))}
  try? await store.set(all,key:"recovery.channels")
 }
 func captureMessage(_ guild:String,_ channel:String,_ message:String,_ author:String,_ content:String)async{
  var all=await store.get("recovery.messages",as:[String:[Message]].self) ?? [:]
  var rows=(all[guild] ?? []).filter{Date().timeIntervalSince($0.createdAt)<7*86400}
  rows.append(Message(id:message,channelID:channel,authorID:author,content:String(content.prefix(4000)),createdAt:Date()))
  while rows.count>2000 || rows.reduce(0,{$0+$1.content.utf8.count})>4*1024*1024{rows.removeFirst()}
  all[guild]=rows;try? await store.set(all,key:"recovery.messages")
 }
 func deletedMessage(_ guild:String,_ channel:String,_ message:String)async->Message?{
  let rows=await store.get("recovery.messages",as:[String:[Message]].self) ?? [:]
  guard let found=rows[guild]?.first(where:{$0.id==message && $0.channelID==channel}) else{return nil}
  await logger.log("INFO","Recovery retained deleted message "+message+" from guild "+guild)
  return found
 }
 func deletedChannel(_ guild:String,_ channel:String)async->Data?{
  let all=await store.get("recovery.channels",as:[String:[String:Data]].self) ?? [:]
  return all[guild]?[channel]
 }
}
