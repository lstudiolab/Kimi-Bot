import { Verification } from "../../systems/verification.js";
import { RolePicker } from "../../systems/role-picker.js";
import { Embeds } from "../../systems/embeds.js";
import { Foundation } from "../../systems/foundation.js";

export function createFoundationLibrary({client,store,logger,services,app="core"}){
  const verificationHelper=new Verification(client,store,logger);
  const rolePicker=new RolePicker(client,store,logger,verificationHelper);
  const embeds=new Embeds(client,store,logger);
  const greet=new Foundation(client,store,logger);
  verificationHelper.ensureSetup=guild=>greet.ensureSetup(guild);
  const is=(name)=>app===name||app==="core";
  return {
    async ready(guild){if(app==="core"||app==="welcome")await greet.ensureSetup(guild);},
    async handleInteraction(i){
      if(i.isChatInputCommand()){
        if(app==="core"&&["setup","kimi-channel"].includes(i.commandName))return greet.command(i);
        if(is("roles")&&i.commandName==="roles")return rolePicker.handle(i);
        if(is("welcome")&&["setup","welcome"].includes(i.commandName))return greet.command(i);
        if(is("autorole")&&i.commandName==="autorole")return greet.command(i);
        if(is("embeds")&&["embed-new","embed-edit","embed-post"].includes(i.commandName))return embeds.handle(i);
      }
      const id=i.customId||"";
      if(is("roles")&&id.startsWith("rolepicker:"))return rolePicker.handle(i);
      if(is("embeds")&&id.startsWith("embed:"))return embeds.handle(i);
    },
    async guildMemberAdd(member){if(app==="welcome")await greet.memberAdd(member,{welcome:true,autorole:false});if(app==="autorole")await greet.memberAdd(member,{welcome:false,autorole:true});},
    async guildMemberRemove(member){if(app==="welcome")await greet.memberRemove(member);},
    async ensureSetup(guild){return greet.ensureSetup(guild);},
    async refreshRolePickers(guild){if(is("roles"))await rolePicker.refresh(guild);},
    async refreshVerification(guild){await verificationHelper.refresh(guild);},
    diagnostics(guild){return services?.diagnoseGuild?.(guild,["ViewChannel","SendMessages","ManageRoles"])||{ok:true,missing:[]};}
  };
}
export const createFoundationCore=(options)=>createFoundationLibrary({...options,app:"core"});
export const createWelcomeLibrary=(options)=>createFoundationLibrary({...options,app:"welcome"});
export const createRolesLibrary=(options)=>createFoundationLibrary({...options,app:"roles"});
export const createAutoRoleLibrary=(options)=>createFoundationLibrary({...options,app:"autorole"});
export const createEmbedsLibrary=(options)=>createFoundationLibrary({...options,app:"embeds"});
