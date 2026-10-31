import { ChannelType } from "discord.js";
import { respond, requireManager } from "../ui.js";
import { renderTemplate, TEMPLATE_PLACEHOLDERS } from "../utils.js";

export class Foundation {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;}
  settings(guildId){
    this.store.data.welcome[guildId] ||= {
      welcome_channel_id:"",
      welcome_message:"Welcome {user} to {server}! You are member #{member_count}.",
      goodbye_channel_id:"",
      goodbye_message:"{username} has left {server}.",
      auto_role_id:""
    };
    return this.store.data.welcome[guildId];
  }
  async command(i){
    if(!await requireManager(i))return;
    const s=this.settings(i.guildId);
    if(i.commandName==="auto-role"){
      const role=i.options.getRole("role");
      if(role){
        const me=await i.guild.members.fetchMe();
        if(role.managed||role.id===i.guild.id||role.position>=me.roles.highest.position)
          return respond(i,"Choose a normal role below Timi's highest role.");
        s.auto_role_id=role.id;
      }else s.auto_role_id="";
      this.store.save();
      return respond(i,s.auto_role_id?"Automatic role set to <@&"+s.auto_role_id+">.":"Automatic role assignment disabled.");
    }
    if(i.commandName==="greet-settings"){
      const welcomeChannel=i.options.getChannel("welcome-channel");
      const goodbyeChannel=i.options.getChannel("goodbye-channel");
      const welcomeMessage=i.options.getString("welcome-message");
      const goodbyeMessage=i.options.getString("goodbye-message");
      if(welcomeChannel)s.welcome_channel_id=welcomeChannel.id;
      if(goodbyeChannel)s.goodbye_channel_id=goodbyeChannel.id;
      if(welcomeMessage!==null)s.welcome_message=welcomeMessage;
      if(goodbyeMessage!==null)s.goodbye_message=goodbyeMessage;
      this.store.save();
      return respond(i,"Greet settings saved. Welcome: "+(s.welcome_channel_id?"<#"+s.welcome_channel_id+">":"Disabled")+
        ". Goodbye: "+(s.goodbye_channel_id?"<#"+s.goodbye_channel_id+">":"Disabled")+
        ". Placeholders: "+TEMPLATE_PLACEHOLDERS.join(", ")+".");
    }
  }
  render(template,member){
    return renderTemplate(template,{guild:member.guild,member,user:member.user,client:this.client});
  }
  async memberAdd(member){
    const s=this.settings(member.guild.id);
    if(s.auto_role_id){
      const role=await member.guild.roles.fetch(s.auto_role_id).catch(()=>null);
      const me=await member.guild.members.fetchMe();
      if(role&&!role.managed&&role.position<me.roles.highest.position)
        await member.roles.add(role,"Timi automatic role").catch(error=>this.logger.warn("Automatic role assignment failed:",error.message));
    }
    if(!s.welcome_channel_id)return;
    const channel=await member.guild.channels.fetch(s.welcome_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)
      await channel.send({content:this.render(s.welcome_message,member),allowedMentions:{users:[member.id]}});
  }
  async memberRemove(member){
    const s=this.settings(member.guild.id);
    if(!s.goodbye_channel_id)return;
    const channel=await member.guild.channels.fetch(s.goodbye_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)
      await channel.send({content:this.render(s.goodbye_message,member),allowedMentions:{parse:[]}});
  }
}
