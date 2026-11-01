import { Moderation } from "../../systems/moderation.js";
import { Protection } from "../../systems/protection.js";
import { Recovery } from "../../systems/recovery.js";
import { Verification } from "../../systems/verification.js";
import { ImageAnalysis } from "../../systems/image-analysis.js";
import { respond } from "../../ui.js";

export function createSecurityLibrary({client,store,logger,foundation}){
  const moderation=new Moderation(client,store,logger);
  const verification=new Verification(client,store,logger);
  const protection=new Protection(client,store,logger);
  const recovery=new Recovery(client,store,logger);
  const imageAnalysis=new ImageAnalysis(client,logger);
  return {
    async ready(guild){
      await moderation.resumeJobs(guild);
      await protection.ready(guild);
      recovery.prune(guild.id);
      for(const channel of guild.channels.cache.values())recovery.snapshot(channel);
    },
    async handleInteraction(i){
      if(i.isChatInputCommand()&&i.commandName==="security")return respond(i,await protection.scan(i.guild));
      if(i.isChatInputCommand()&&["moderation","filter"].includes(i.commandName))return moderation.handle(i);
      if(i.isChatInputCommand()&&["verify-config","verify"].includes(i.commandName))return verification.handle(i);
      const id=i.customId||"";
      if(id.startsWith("modpanel:"))return moderation.handle(i);
      if(id.startsWith("verify:")||id.startsWith("botguard:"))return verification.handle(i);
    },
    async messageDelete(message){await moderation.onMessageDelete(message);},
    async messageUpdate(oldMessage,newMessage){await moderation.onMessageUpdate(oldMessage,newMessage);},
    async memberUpdate(oldMember,newMember){await moderation.onMemberUpdate(oldMember,newMember);},
    async ban(guild,user,removed=false){await moderation.onBan(guild,user,removed);},
    async messageCreate(message){
      recovery.backupMessage(message);
      const results=await Promise.allSettled([moderation.onMessage(message),imageAnalysis.handleMessage(message)]);
      for(const result of results)if(result.status==="rejected")logger.error("Security message processing failed:",result.reason);
    },
    async guildMemberAdd(member){await protection.memberJoin(member);},
    async auditLog(entry,guild){await protection.auditLog(entry,guild);},
    channelCreate(channel){recovery.snapshot(channel);},
    channelUpdate(oldChannel,channel){recovery.snapshot(channel);},
    async channelDelete(channel){await recovery.onChannelDelete(channel);},
    async refreshPanel(guild){await moderation.refresh(guild,store.mods(guild.id));}
  };
}
