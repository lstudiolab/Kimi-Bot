import Foundation

enum CommandCatalog {
 static let core:[String]=["kimi","setup","plan","apps","app-store","install","uninstall","automations","guard-review","web-token"]
 static let groups:[String:[String]]=[
  "Welcome":["welcome"],"Auto Role":["autorole"],"Role Picker":["roles"],
  "Embeds":["embed-new","embed-edit","embed-post"],
  "Kimi Lock":["moderation","verify","verify-config","filter","security"],
  "Support":["tickets","ticket-panel","ticket-config"]
 ]
 static let all:[String:[String:Any]] = {
  let admin="32"
  func command(_ name:String,_ description:String,_ options:[[String:Any]]=[])->[String:Any]{
   var value:[String:Any]=["name":name,"description":description,"type":1,"options":options]
   if name != "plan" && name != "apps" && name != "app-store" {value["default_member_permissions"]=admin}
   return value
  }
  func string(_ name:String,_ description:String,_ required:Bool=false,_ choices:[[String:Any]]=[])->[String:Any]{
   var v:[String:Any]=["type":3,"name":name,"description":description,"required":required]
   if !choices.isEmpty{v["choices"]=choices};return v
  }
  func user(_ name:String,_ description:String)->[String:Any]{["type":6,"name":name,"description":description,"required":true]}
  func role(_ name:String,_ description:String)->[String:Any]{["type":8,"name":name,"description":description]}
  func channel(_ name:String,_ description:String)->[String:Any]{["type":7,"name":name,"description":description,"channel_types":[0]]}
  func integer(_ name:String,_ description:String,_ min:Int,_ max:Int)->[String:Any]{["type":4,"name":name,"description":description,"min_value":min,"max_value":max]}
  let appChoices=["Welcome","Auto Role","Role Picker","Embeds","Kimi Lock","Support"].map{["name":$0,"value":$0]}
  return [
   "kimi":command("kimi","Open Kimi server settings"),
   "setup":command("setup","Prepare private Kimi channels and server infrastructure"),
   "plan":command("plan","View Kimi storage and plan"),
   "apps":command("apps","Browse available Kimi apps"),
   "app-store":command("app-store","Browse and manage installed apps"),
   "install":command("install","Install a Kimi app",[string("app","App to install",true,appChoices)]),
   "uninstall":command("uninstall","Uninstall a Kimi app",[string("app","App to remove",true,appChoices)]),
   "automations":command("automations","Manage server automations"),
   "guard-review":command("guard-review","Review an automated bot containment incident",[user("bot","Bot under review"),string("decision","Restore or keep restricted",true,[["name":"Restore","value":"restore"],["name":"Keep restricted","value":"keep"]])]),
   "web-token":command("web-token","Create a one-time dashboard link token"),
   "welcome":command("welcome","Configure welcome and departure messages",[channel("welcome-channel","Welcome destination"),channel("goodbye-channel","Departure destination"),string("welcome-message","Welcome message template"),string("goodbye-message","Departure message template")]),
   "autorole":command("autorole","Configure automatic member role",[role("role","Role assigned to new members")]),
   "roles":command("roles","Create a self-service role picker"),
   "embed-new":command("embed-new","Create a reusable embed"),
   "embed-edit":command("embed-edit","Edit a saved embed",[string("name","Embed name",true)]),
   "embed-post":command("embed-post","Publish a saved embed",[string("name","Embed name",true)]),
   "moderation":command("moderation","Configure Kimi Lock moderation"),
   "verify":command("verify","Configure member verification"),
   "verify-config":command("verify-config","Configure member verification",[role("role","Verified member role"),channel("channel","Verification channel"),integer("min-age-days","Minimum account age",0,3650),channel("review-channel","Manual review channel")]),
   "filter":command("filter","Manage blocked phrases",[["type":1,"name":"add","description":"Add a blocked phrase","options":[string("phrase","Phrase",true)]],["type":1,"name":"remove","description":"Remove a blocked phrase","options":[string("phrase","Phrase",true)]],["type":1,"name":"list","description":"List blocked phrases"]]),
   "security":command("security","Run a server security audit"),
   "tickets":command("tickets","Prepare private ticket support"),
   "ticket-panel":command("ticket-panel","Publish or refresh the ticket panel"),
   "ticket-config":command("ticket-config","View ticket settings",[role("support-role","Support staff role"),channel("transcript-channel","Transcript destination")])
  ]
 }()
 static func globalCommands()->[[String:Any]]{core.compactMap{all[$0]}}
 static func guildCommands(installed:[String])->[[String:Any]]{
  var names:[String]=[]
  for app in installed{names += groups[app] ?? []}
  return names.compactMap{all[$0]}
 }
 static func appNames()->[String]{groups.keys.sorted()}
}
