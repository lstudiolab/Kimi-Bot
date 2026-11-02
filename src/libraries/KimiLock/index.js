import { Moderation } from "../../systems/moderation.js";
import { Protection } from "../../systems/protection.js";
import { Recovery } from "../../systems/recovery.js";
import { Verification } from "../../systems/verification.js";
import { ImageAnalysis } from "../../systems/image-analysis.js";
import { respond } from "../../ui.js";

export function createKimiLockLibrary({client,store,logger,foundation,services}){
  const moderation=new Moderation(client,store,logger);
  const verification=new Verification(client,store,logger);
  verification.ensureSetup=guild=>foundation?.ensureSetup?.(guild);
  const protection=new Protection(client,store,logger);
  const recovery=new Recovery(client,store,logger);
  const imageAnalysis=new ImageAnalysis(client,logger);
  moderation.protection=protection;
  recovery.protection=protection;
  return {
    async ready(guild){
      if(store.data.modules?.[guild.id]?.moderation!==false)await moderation.resumeJobs(guild);
      if(store.data.modules?.[guild.id]?.protection!==false)await protection.ready(guild);
      if(store.data.modules?.[guild.id]?.recovery!==false){
        recovery.prune(guild.id);
        for(const channel of guild.channels.cache.values())recovery.snapshot(channel);
      }
    },
    async handleInteraction(i){
      if(i.isChatInputCommand()&&i.commandName==="security")return respond(i,await protection.scan(i.guild));
      if(i.isChatInputCommand()&&["moderation","filter"].includes(i.commandName))return moderation.handle(i);
      if(i.isChatInputCommand()&&i.commandName==="verify-config")return verification.handle(i);
      const id=i.customId||"";
      if(id.startsWith("modpanel:"))return moderation.handle(i);
      if(id.startsWith("verify:")||id.startsWith("botguard:"))return verification.handle(i);
    },
    async messageDelete(message){await moderation.onMessageDelete(message);},
    async messageUpdate(oldMessage,newMessage,modules={moderation:true,recovery:true}){const tasks=[];if(modules.moderation)tasks.push(moderation.onMessageUpdate(oldMessage,newMessage));if(modules.recovery)tasks.push(recovery.updateMessage(newMessage));await Promise.all(tasks);},
    async memberUpdate(oldMember,newMember){await moderation.onMemberUpdate(oldMember,newMember);},
    async ban(guild,user,removed=false){await moderation.onBan(guild,user,removed);},
    async messageCreate(message,modules={moderation:true,recovery:true}){
      if(modules.recovery)recovery.backupMessage(message);
      if(modules.moderation){await moderation.onMessage(message);if(services?.background)services.background.enqueue("image:"+message.id,()=>imageAnalysis.handleMessage(message)).catch(error=>logger.error("Kimi Lock image analysis failed:",error));else await imageAnalysis.handleMessage(message);}
    },
    async guildMemberAdd(member,modules={protection:true,verification:true}){const tasks=[];if(modules.protection)tasks.push(protection.memberJoin(member));if(modules.verification)tasks.push(verification.memberJoin(member));const results=await Promise.allSettled(tasks);for(const result of results)if(result.status==="rejected")logger.error("Security join check failed:",result.reason);},
    async auditLog(entry,guild){await protection.auditLog(entry,guild);},
    channelCreate(channel){recovery.snapshot(channel);},
    channelUpdate(oldChannel,channel){recovery.snapshot(channel);},
    async channelDelete(channel){await recovery.onChannelDelete(channel);},
    async refreshPanel(guild){await moderation.refresh(guild,store.mods(guild.id));},
    diagnostics(guild){return services?.diagnoseGuild?.(guild,["ViewChannel","SendMessages","ManageMessages","ModerateMembers","ManageChannels","ViewAuditLog"])||{ok:true,missing:[]};}
  };
}
