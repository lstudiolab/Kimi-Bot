import Foundation
actor RecoveryService {
 struct Message:Codable,Sendable {let id:String;let channelID:String;let authorID:String;let content:String;let createdAt:Date}
 private let store:PersistentStore;private let logger:Logger;private let rest:DiscordREST
 init(store:PersistentStore,logger:Logger,rest:DiscordREST){self.store=store;self.logger=logger;self.rest=rest}
 func captureChannel(_ guild:String,_ channel:[String:Any])async{
  guard let id=channel["id"] as? String,let data=try? JSONSerialization.data(withJSONObject:channel,options:[.fragmentsAllowed]) else{return}
  var all=await store.get("recovery.channels",as:[String:[String:Data]].self) ?? [:]
  all[guild,default:[:]][id]=data
  if all[guild,default:[:]].count>500{all[guild]=Dictionary(uniqueKeysWithValues:all[guild,default:[:]].sorted{$0.key<$1.key}.suffix(500))}
  try? await store.set(all,key:"recovery.channels")
 }
 func captureMessage(_ guild:String,_ channel:String,_ message:String,_ author:String,_ content:String,attachments:[String]=[])async{
  var all=await store.get("recovery.messages",as:[String:[Message]].self) ?? [:]
  var rows=(all[guild] ?? []).filter{Date().timeIntervalSince($0.createdAt)<7*86400}
  rows.removeAll{$0.id==message}
  let attachmentText=attachments.prefix(10).map{"[attachment] "+$0}.joined(separator:"\n")
  let archived=String(content.prefix(3000))+(attachmentText.isEmpty ? "":"\n"+attachmentText)
  rows.append(Message(id:message,channelID:channel,authorID:author,content:String(archived.prefix(4000)),createdAt:Date()))
  while rows.count>2000 || rows.reduce(0,{$0+$1.content.utf8.count})>4*1024*1024{rows.removeFirst()}
  all[guild]=rows;try? await store.set(all,key:"recovery.messages")
 }
 func savedMessage(_ guild:String,_ channel:String,_ message:String)async->Message?{
  let rows=await store.get("recovery.messages",as:[String:[Message]].self) ?? [:]
  return rows[guild]?.first(where:{$0.id==message && $0.channelID==channel})
 }
 func deletedMessage(_ guild:String,_ channel:String,_ message:String)async->Message?{
  let rows=await store.get("recovery.messages",as:[String:[Message]].self) ?? [:]
  guard let found=rows[guild]?.first(where:{$0.id==message && $0.channelID==channel}) else{return nil}
  await logger.log("INFO","Recovery retained deleted message "+message+" from guild "+guild)
  return found
 }
 func queueDeletedChannel(_ guild:String,_ channel:String)async{
  var all=await store.get("recovery.pending-channels",as:[String:[String]].self) ?? [:]
  var values=all[guild] ?? [];if !values.contains(channel){values.append(channel)}
  all[guild]=Array(values.suffix(100));try? await store.set(all,key:"recovery.pending-channels")
 }
 func restorePendingChannels(_ guild:String)async{
  let all=await store.get("recovery.pending-channels",as:[String:[String]].self) ?? [:]
  let pending=all[guild] ?? []
  var remaining:[String]=[]
  for channel in pending{if !(await restoreChannel(guild,channel)){remaining.append(channel)}}
  var updated=all;updated[guild]=remaining;try? await store.set(updated,key:"recovery.pending-channels")
 }
 func restoreChannel(_ guild:String,_ channelID:String)async->Bool{
  let all=await store.get("recovery.channels",as:[String:[String:Data]].self) ?? [:]
  guard let data=all[guild]?[channelID],let source=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return false}
  let allowed=["name","type","topic","nsfw","rate_limit_per_user","parent_id","permission_overwrites","bitrate","user_limit"]
  var body:[String:Any]=[:]
  for key in allowed{if let value=source[key]{body[key]=value}}
  body["name"]=SecurityPolicy.channelName(source["name"] as? String ?? "restored-channel")
  do{
   let created=try await rest.call("POST","guilds/\(guild)/channels",body:body)
   let restored=(created as? [String:Any])?["id"] as? String ?? "unknown"
   await logger.log("WARN","Kimi Lock restored deleted channel "+channelID+" as "+restored+" in guild "+guild)
   return true
  }catch{await logger.log("ERROR","Channel recovery failed for "+channelID+": "+error.localizedDescription);return false}
 }
 func restoreMessage(_ guild:String,_ channel:String,_ message:String)async{
  guard let saved=await deletedMessage(guild,channel,message),!saved.content.isEmpty else{return}
  let date=ISO8601DateFormatter().string(from:saved.createdAt)
  let content="**Recovered message** · <@\(saved.authorID)> · \(date)\n"+String(saved.content.prefix(1750))
  do{_ = try await rest.call("POST","channels/\(channel)/messages",body:["content":content,"allowed_mentions":["parse":[]]])}
  catch{await logger.log("ERROR","Message recovery failed for "+message+": "+error.localizedDescription)}
 }
}
