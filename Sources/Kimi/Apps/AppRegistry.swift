import Foundation

struct KimiAppDefinition:Sendable,Identifiable {
 let name:String;let description:String;let systems:[String];let helpers:[String]
 var id:String{name}
}
enum AppRegistry {
 static let apps:[KimiAppDefinition]=[
  .init(name:"Welcome",description:"Member greetings and departure messages.",systems:["Welcome","Goodbye"],helpers:["Template variables","Channel validation"]),
  .init(name:"Auto Role",description:"Assign a configured role to new members.",systems:["Automatic role assignment"],helpers:["Role hierarchy validation"]),
  .init(name:"Role Picker",description:"Self-service role menus for members.",systems:["Role menus","Role selection"],helpers:["Role safety checks"]),
  .init(name:"Embeds",description:"Create, edit and publish reusable embeds.",systems:["Embed builder","Embed placements"],helpers:["Embed validation"]),
  .init(name:"Kimi Lock",description:"Coordinated security and moderation.",systems:["Anti-spam","Raid protection","Anti-nuke","Verification","Sanctions","Recovery"],helpers:["Threat monitoring","Security audit"]),
  .init(name:"Support",description:"Private tickets and staff support.",systems:["Ticket lifecycle","Staff handoff","Priority","Transcripts"],helpers:["Queue management","Access validation"])
 ]
 static func resolve(_ input:String)->KimiAppDefinition?{
  let key=input.lowercased().filter{!$0.isWhitespace && $0 != "-" && $0 != "_"}
  let aliases=["moderation":"kimilock","security":"kimilock","lock":"kimilock","ticket":"support","tickets":"support","foundation":"welcome","roles":"rolepicker","embed":"embeds"]
  let resolved=aliases[key] ?? key
  return apps.first{$0.name.lowercased().filter{!$0.isWhitespace}==resolved}
 }
}
