import Foundation

struct KimiAppDefinition:Sendable,Identifiable {
 let name:String;let description:String;let systems:[String];let helpers:[String]
 var id:String{name}
}
enum AppRegistry {
 static let apps:[KimiAppDefinition]=[
  .init(name:"Foundation",description:"Server setup, configuration and core utilities.",systems:["Setup","Welcome","Audit routing"],helpers:["Configuration","Permission checks"]),
  .init(name:"Kimi Lock",description:"Automatic server security and moderation.",systems:["Anti-spam","Raid protection","Verification","Sanctions","Recovery"],helpers:["Threat analysis","Security reports"]),
  .init(name:"Support",description:"Private tickets and staff support.",systems:["Ticket lifecycle","Priority","Staff handoff"],helpers:["Queue management","Transcript preparation"]),
  .init(name:"Automations",description:"Event-driven server workflows.",systems:["Rule storage","Trigger definitions"],helpers:["Rule validation"])
 ]
 static func resolve(_ input:String)->KimiAppDefinition?{
  let key=input.lowercased().filter{!$0.isWhitespace && $0 != "-" && $0 != "_"}
  let aliases=["moderation":"kimilock","security":"kimilock","ticket":"support","tickets":"support"]
  let resolved=aliases[key] ?? key
  return apps.first{$0.name.lowercased().filter{!$0.isWhitespace}==resolved}
 }
}
