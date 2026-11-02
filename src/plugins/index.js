import { createWelcomeLibrary, createRolesLibrary, createEmbedsLibrary } from "./Foundation/index.js";
import { createKimiLockLibrary } from "./KimiLock/index.js";
import { createSupportLibrary } from "./Support/index.js";

export const APPS = Object.freeze({
  Welcome: Object.freeze({name:"Welcome",description:"A focused system for member greetings and departures.",systems:["Welcome and departure messages"],helpers:["Message preview","Template variables","Channel validation"],create:createWelcomeLibrary}),
  Roles: Object.freeze({name:"Roles",description:"A focused system for automatic roles and self-service role menus.",systems:["Automatic role assignment","Self-service role menus"],helpers:["Role hierarchy checker","Role menu editor"],create:createRolesLibrary}),
  Embeds: Object.freeze({name:"Embeds",description:"A focused system for reusable server embeds.",systems:["Create, edit and publish embeds"],helpers:["Embed builder","Placement manager"],create:createEmbedsLibrary}),
  "Kimi Lock": Object.freeze({name:"Kimi Lock",description:"Proactive security and moderation in one coordinated system.",systems:["Anti-spam and AutoMod","Raid and join protection","Anti-nuke containment","Member verification and review","Warnings and timed sanctions","Suspicious link and image checks","Audit trail and recovery"],helpers:["Threat monitor","Permission and hierarchy checker","Raid response planner","Sanction scheduler","Recovery snapshots","Security health report"],create:createKimiLockLibrary}),
  Support: Object.freeze({name:"Support",description:"A focused support desk for members and staff.",systems:["Private tickets, staff handoff, priority, transcripts and support activity"],helpers:["Ticket setup assistant","Staff access validator","Transcript exporter","Queue and priority manager"],create:createSupportLibrary}),
});
export function normalizeAppName(value){
  const key=String(value||"").trim().toLowerCase().replace(/[\s_-]/g,"");
  const aliases={moderation:"Kimi Lock",security:"Kimi Lock",lock:"Kimi Lock",core:"Welcome",foundation:"Welcome",ticket:"Support",role:"Roles",embed:"Embeds"};
  return aliases[key]||Object.keys(APPS).find(name=>name.toLowerCase().replace(/\s/g,"")===key)||null;
}
export const PLUGINS=APPS;
export const normalizePluginName=normalizeAppName;
