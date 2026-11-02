import { createSecurityLibrary } from "./Security/index.js";
import { createSupportLibrary } from "./Support/index.js";
import { createFoundationLibrary } from "./Foundation/index.js";

export const LIBRARIES = Object.freeze({
  Foundation: Object.freeze({name:"Foundation",description:"Essential member experience and presentation systems.",systems:["Greet system","Embed system","Automatic role assignment","Role selection"],create:createFoundationLibrary}),
  "Kimi Lock": Object.freeze({name:"Kimi Lock",description:"Moderation, verification and server protection.",systems:["Verification system","Anti-spam and AutoMod","Anti-nuke detection","Bot detector and approval","Warnings and sanctions","Raid protection","Audit logs and recovery"],create:createSecurityLibrary}),
  Support: Object.freeze({name:"Support",description:"The complete ticket and support system.",systems:["Ticket setup and panels","Private tickets","Staff threads","Transcripts","Permissions and logs"],create:createSupportLibrary}),
});
export function normalizeLibraryName(value){
  const key=String(value||"").trim().toLowerCase().replace(/[\s_-]/g,"");
  const aliases={moderation:"Kimi Lock",security:"Kimi Lock",lock:"Kimi Lock",core:"Foundation",shield:"Kimi Lock",ticket:"Support"};
  return aliases[key]||Object.keys(LIBRARIES).find(name=>name.toLowerCase().replace(/\s/g,"")===key)||null;
}
