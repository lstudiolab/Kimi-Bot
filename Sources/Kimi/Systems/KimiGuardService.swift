import Foundation
actor KimiGuardService {
 struct Incident:Codable,Sendable {
  let id:String;let guildID:String;let actorID:String;let action:String;let reason:String
  let originalRoles:[String];let removedRoles:[String];let createdAt:Date;let timeoutUntil:Date?
  var status:String
 }
 struct Result:Sendable {let incident:Incident;let removedCount:Int;let timeoutApplied:Bool}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func contain(guild:String,actor:String,action:String)async throws->Result?{
  let owner=try await rest.ownerID(guild)
  guard actor != owner else{await logger.log("WARN","Kimi Guard ignored owner action in "+guild);return nil}
  let member=try await rest.call("GET","guilds/\(guild)/members/\(actor)") as? [String:Any] ?? [:]
  let roleIDs=member["roles"] as? [String] ?? []
  let roles=try await rest.call("GET","guilds/\(guild)/roles") as? [[String:Any]] ?? []
  let botMember=try await rest.call("GET","guilds/\(guild)/members/@me") as? [String:Any] ?? [:]
  let botRoles=Set(botMember["roles"] as? [String] ?? [])
  let highest=roles.filter{role in botRoles.contains(role["id"] as? String ?? "")}.map{$0["position"] as? Int ?? 0}.max() ?? 0
  let manageable=roles.filter{role in
   guard let id=role["id"] as? String,roleIDs.contains(id),id != guild,role["managed"] as? Bool != true else{return false}
   return (role["position"] as? Int ?? 0)<highest
  }
  var removed:[String]=[]
  for role in manageable{
   guard let id=role["id"] as? String else{continue}
   do{_ = try await rest.call("DELETE","guilds/\(guild)/members/\(actor)/roles/\(id)");removed.append(id)}catch{await logger.log("WARN","Kimi Guard could not remove role "+id+": "+error.localizedDescription)}
  }
  var timeoutUntil:Date?=nil
  if member["user"] as? [String:Any] != nil {
   let isBot=(member["user"] as? [String:Any])?["bot"] as? Bool ?? false
   if !isBot{
    do{try await rest.timeoutKimiMember(guild,actor,40320,"Kimi Guard automatic containment after repeated privileged actions");timeoutUntil=Date().addingTimeInterval(40320*60)}
    catch{await logger.log("WARN","Kimi Guard timeout failed: "+error.localizedDescription)}
   }
  }
  let reason="Repeated privileged action: "+action
  let incident=Incident(id:UUID().uuidString,guildID:guild,actorID:actor,action:action,reason:reason,originalRoles:roleIDs,removedRoles:removed,createdAt:Date(),timeoutUntil:timeoutUntil,status:removed.isEmpty && timeoutUntil==nil ? "review_required":"restricted")
  var all=await store.get("guard.incidents",as:[String:Incident].self) ?? [:]
  all[guild+":"+actor]=incident;try await store.set(all,key:"guard.incidents")
  await logger.log("WARN","Kimi Guard "+incident.status+" actor "+actor+" in "+guild+"; removed "+String(removed.count)+" roles.")
  return Result(incident:incident,removedCount:removed.count,timeoutApplied:timeoutUntil != nil)
 }
 func review(guild:String,actor:String,decision:String,reviewer:String)async throws->String{
  guard try await rest.ownerID(guild)==reviewer else{throw KimiError.configuration("Only the server owner can review a Kimi Guard incident.")}
  var all=await store.get("guard.incidents",as:[String:Incident].self) ?? [:]
  let key=guild+":"+actor
  guard var incident=all[key],["restricted","review_required","kept"].contains(incident.status) else{throw KimiError.configuration("No active Kimi Guard incident exists for this account.")}
  if decision=="keep"{incident.status="kept";all[key]=incident;try await store.set(all,key:"guard.incidents");return "The account remains restricted."}
  guard decision=="restore" else{throw KimiError.configuration("Choose restore or keep.")}
  let roles=try await rest.call("GET","guilds/\(guild)/roles") as? [[String:Any]] ?? []
  let botMember=try await rest.call("GET","guilds/\(guild)/members/@me") as? [String:Any] ?? [:]
  let botRoles=Set(botMember["roles"] as? [String] ?? [])
  let highest=roles.filter{botRoles.contains($0["id"] as? String ?? "")}.map{$0["position"] as? Int ?? 0}.max() ?? 0
  let safe=incident.removedRoles.filter{id in
   guard let role=roles.first(where:{($0["id"] as? String)==id}) else{return false}
   let permissions=UInt64(role["permissions"] as? String ?? "") ?? 0
   let dangerous=(1<<3)|(1<<5)|(1<<28)|(1<<29)|(1<<30)|(1<<31)|(1<<32)
   return (role["position"] as? Int ?? 0)<highest && permissions & UInt64(dangerous)==0 && role["managed"] as? Bool != true
  }
  for role in safe{_ = try? await rest.call("PUT","guilds/\(guild)/members/\(actor)/roles/\(role)")}
  if incident.timeoutUntil != nil{
   let current=try? await rest.call("GET","guilds/\(guild)/members/\(actor)") as? [String:Any]
   if let current,let raw=current["communication_disabled_until"] as? String,let date=ISO8601DateFormatter().date(from:raw),abs(date.timeIntervalSince(incident.timeoutUntil!))<120{
    _ = try? await rest.call("PATCH","guilds/\(guild)/members/\(actor)",body:["communication_disabled_until":NSNull(),"reason":"Released after server owner Kimi Guard review"])
   }
  }
  incident.status="released";all[key]=incident;try await store.set(all,key:"guard.incidents")
  return "Incident reviewed. Restored "+String(safe.count)+" safe roles. Elevated roles were not restored."
 }
}
