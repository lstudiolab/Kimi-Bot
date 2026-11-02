import Foundation

struct ServerAudit {
 struct Finding:Sendable {let severity:String;let title:String;let detail:String}
 func evaluate(roles:[[String:Any]],channels:[[String:Any]],everyonePermissions:UInt64)->[Finding]{
  var results:[Finding]=[]
  if everyonePermissions & (1<<3) != 0{results.append(.init(severity:"critical",title:"@everyone has Administrator",detail:"Remove Administrator from the everyone role."))}
  if everyonePermissions & (1<<5) != 0{results.append(.init(severity:"high",title:"@everyone can manage the server",detail:"Restrict Manage Guild to trusted staff."))}
  for role in roles{
   let name=role["name"] as? String ?? "Unnamed role"
   let permissions=UInt64(role["permissions"] as? String ?? "") ?? 0
   if permissions & (1<<3) != 0, name != "@everyone"{results.append(.init(severity:"high",title:"Administrator role: \(name)",detail:"Review membership and role hierarchy."))}
  }
  if channels.isEmpty{results.append(.init(severity:"info",title:"No channels returned",detail:"The bot may lack View Channels permission."))}
  return results
 }
}
