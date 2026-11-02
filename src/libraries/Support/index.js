import { ChannelType } from "discord.js";
import { Tickets } from "../../systems/tickets.js";
export function createSupportLibrary({client,store,logger,foundation,services}){
  const tickets=new Tickets(client,store,logger,foundation);
  return {
    async ready(guild){
      if(foundation?.ensureSetup)await foundation.ensureSetup(guild);
      let category=guild.channels.cache.find(channel=>channel.type===ChannelType.GuildCategory&&channel.name.toLowerCase()==="ticket");
      if(!category)await guild.channels.create({name:"ticket",type:ChannelType.GuildCategory,reason:"Prepare Kimi Support"});
    },
    async handleInteraction(i){
      if(i.isChatInputCommand()&&["tickets","support","ticket-panel","ticket-config"].includes(i.commandName))return tickets.handle(i);
      if((i.customId||"").startsWith("ticket:"))return tickets.handle(i);
    },
    async refreshPanels(guild){await tickets.refresh(store.ticket(guild.id));},
    diagnostics(guild){return services?.diagnoseGuild?.(guild,["ViewChannel","SendMessages","ManageChannels","ManageRoles","ReadMessageHistory"])||{ok:true,missing:[]};}
  };
}
