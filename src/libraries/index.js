import { createKimiLockLibrary } from "./KimiLock/index.js";
import { createSupportLibrary } from "./Support/index.js";
import { createFoundationLibrary } from "./Foundation/index.js";

export const LIBRARIES = Object.freeze({
  Foundation: Object.freeze({name:"Foundation",description:"The essential tools for shaping and maintaining a server.",systems:["Guided server setup","Welcome and departure messages","Automatic role assignment","Self-service role menus","Reusable embeds","Member experience settings"],helpers:["Setup assistant","Permission checker","Role safety validator","Welcome preview","Embed builder","Configuration health check"],create:createFoundationLibrary}),
  "Kimi Lock": Object.freeze({name:"Kimi Lock",description:"Proactive protection that detects risk, contains damage and helps restore a server.",systems:["Anti-spam and AutoMod","Raid and join protection","Anti-nuke containment","Member verification and review","Warnings and timed sanctions","Suspicious link and image checks","Audit trail and recovery"],helpers:["Threat monitor","Permission and hierarchy checker","Raid response planner","Sanction scheduler","Recovery snapshots","Security health report"],create:createKimiLockLibrary}),
  Support: Object.freeze({name:"Support",description:"A complete support desk for members and staff.",systems:["Guided ticket setup","Private ticket channels","Staff assignment and handoff","Priority and status tracking","Transcript and archive","Support activity logs"],helpers:["Ticket setup assistant","Staff access validator","Transcript exporter","Queue and priority manager","Close confirmation","Support activity report"],create:createSupportLibrary}),
});
export function normalizeLibraryName(value){
  const key=String(value||"").trim().toLowerCase().replace(/[\s_-]/g,"");
  const aliases={moderation:"Kimi Lock",security:"Kimi Lock",lock:"Kimi Lock",core:"Foundation",shield:"Kimi Lock",ticket:"Support"};
  return aliases[key]||Object.keys(LIBRARIES).find(name=>name.toLowerCase().replace(/\s/g,"")===key)||null;
}
