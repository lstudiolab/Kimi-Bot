import { createSecurityLibrary } from "./Moderation/index.js";
import { createSupportLibrary } from "./Support/index.js";
import { createFoundationLibrary } from "./Foundation/index.js";
import { createScratchLibrary } from "./Developer/index.js";

export const LIBRARIES = Object.freeze({
  Foundation: Object.freeze({name:"Foundation",description:"Essential member experience and presentation systems.",systems:["Greet system","Embed system","Automatic role assignment","Role selection"],create:createFoundationLibrary}),
  Security: Object.freeze({name:"Security",description:"Verification, moderation, automated protection and recovery.",systems:["Verification system","Anti-spam and AutoMod","Anti-nuke detection","Bot detector and approval","Warnings and sanctions","Raid protection","Audit logs and recovery"],create:createSecurityLibrary}),
  Support: Object.freeze({name:"Support",description:"The complete ticket and support system.",systems:["Ticket setup and panels","Private tickets","Staff threads","Transcripts","Permissions and logs"],create:createSupportLibrary}),
  Scratch: Object.freeze({name:"Scratch",description:"The TbScript development environment.",systems:["TbScript projects","Editor and component kit","Panel scripting","Run and stop testing","Validation and documentation","Version history and import/export"],create:createScratchLibrary})
});
export function normalizeLibraryName(value){
  const key=String(value||"").trim().toLowerCase().replace(/[\s_-]/g,"");
  const aliases={moderation:"Security",developer:"Scratch"};
  return aliases[key]||Object.keys(LIBRARIES).find(name=>name.toLowerCase()===key)||null;
}
