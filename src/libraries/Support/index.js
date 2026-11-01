import { Tickets } from "../../systems/tickets.js";
export function createSupportLibrary({client,store,logger,foundation}){
  const tickets=new Tickets(client,store,logger,foundation);
  return {
    async handleInteraction(i){
      if(i.isChatInputCommand()&&["tickets","ticket-panel","ticket-config"].includes(i.commandName))return tickets.handle(i);
      if((i.customId||"").startsWith("ticket:"))return tickets.handle(i);
    },
    async refreshPanels(guild){await tickets.refresh(store.ticket(guild.id));}
  };
}
