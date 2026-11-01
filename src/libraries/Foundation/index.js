import { Verification } from "../../systems/verification.js";
import { RolePicker } from "../../systems/role-picker.js";
import { Embeds } from "../../systems/embeds.js";
import { Foundation } from "../../systems/foundation.js";

export function createFoundationLibrary({client,store,logger}){
  const verificationHelper=new Verification(client,store,logger);
  const rolePicker=new RolePicker(client,store,logger,verificationHelper);
  const embeds=new Embeds(client,store,logger);
  const greet=new Foundation(client,store,logger);
  return {
    async handleInteraction(i){
      if(i.isChatInputCommand()){
        if(i.commandName==="roles")return rolePicker.handle(i);
        if(["setup","welcome","autorole"].includes(i.commandName))return greet.command(i);
        if(["embed-new","embed-edit","embed-post"].includes(i.commandName))return embeds.handle(i);
      }
      const id=i.customId||"";
      if(id.startsWith("rolepicker:"))return rolePicker.handle(i);
      if(id.startsWith("embed:"))return embeds.handle(i);
    },
    async guildMemberAdd(member){await greet.memberAdd(member);},
    async guildMemberRemove(member){await greet.memberRemove(member);},
    async refreshRolePickers(guild){await rolePicker.refresh(guild);},
    async refreshVerification(guild){await verificationHelper.refresh(guild);}
  };
}
