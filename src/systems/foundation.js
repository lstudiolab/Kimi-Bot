import { ChannelType, EmbedBuilder } from "discord.js";
import { respond, requireManager } from "../ui.js";
import { renderTemplate, TEMPLATE_PLACEHOLDERS } from "../utils.js";
import { applyGuildTheme } from "../styles.js";

export class Foundation {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;}
  settings(guildId){
    this.store.data.welcome[guildId] ||= {welcome_channel_id:"",welcome_message:"Welcome {user} to {server}! You are member #{member_count}.",goodbye_channel_id:"",goodbye_message:"{username} has left {server}.",auto_role_id:""};
    return this.store.data.welcome[guildId];
  }
  async command(i){
    if(i.commandName==="ping")return respond(i,`Pong. Gateway latency: ${this.client.ws.ping} ms.`);
    if(i.commandName==="server-info"){
      const g=i.guild;
      const embed=applyGuildTheme(new EmbedBuilder().setColor(0x808080).setTitle(g.name).setThumbnail(g.iconURL({size:256})),this.store,g.id)
        .addFields({name:"Owner",value:`<@${g.ownerId}>`,inline:true},
          {name:"Members",value:String(g.memberCount),inline:true},{name:"Channels",value:String(g.channels.cache.size),inline:true},
          {name:"Created",value:`<t:${Math.floor(g.createdTimestamp/1000)}:F>`});
      return respond(i,null,[],[embed]);
    }
    if(i.commandName==="user-info"){
      const user=i.options.getUser("user")||i.user,member=await i.guild.members.fetch(user.id).catch(()=>null);
      const embed=applyGuildTheme(new EmbedBuilder().setColor(0x808080).setTitle(user.tag).setThumbnail(user.displayAvatarURL({size:256})),this.store,i.guildId)
        .addFields({name:"User ID",value:user.id},{name:"Account created",value:`<t:${Math.floor(user.createdTimestamp/1000)}:F>`},
          {name:"Joined server",value:member?`<t:${Math.floor(member.joinedTimestamp/1000)}:F>`:"Not a server member"});
      return respond(i,null,[],[embed]);
    }
    if(i.commandName==="avatar"){
      const user=i.options.getUser("user")||i.user;
      const embed=applyGuildTheme(new EmbedBuilder().setColor(0x808080).setTitle(`${user.username}'s avatar`).setImage(user.displayAvatarURL({size:1024})),this.store,i.guildId);
      return respond(i,null,[],[embed]);
    }
    if(i.commandName==="auto-role"){
      if(!await requireManager(i))return;
      const s=this.settings(i.guildId),role=i.options.getRole("role");
      if(role){
        const me=await i.guild.members.fetchMe();
        if(role.managed||role.id===i.guild.id||role.position>=me.roles.highest.position)return respond(i,"Choose a normal role below Timi's highest role.");
        s.auto_role_id=role.id;
      }else s.auto_role_id="";
      this.store.save();
      return respond(i,s.auto_role_id?"Automatic role set to <@&"+s.auto_role_id+">.":"Automatic role assignment disabled.");
    }
    if(i.commandName==="greet-settings"){
      if(!await requireManager(i))return;
      const s=this.settings(i.guildId);
      const welcomeChannel=i.options.getChannel("welcome-channel"),goodbyeChannel=i.options.getChannel("goodbye-channel");
      const welcomeMessage=i.options.getString("welcome-message"),goodbyeMessage=i.options.getString("goodbye-message");
      if(welcomeChannel)s.welcome_channel_id=welcomeChannel.id;
      if(goodbyeChannel)s.goodbye_channel_id=goodbyeChannel.id;
      if(welcomeMessage!==null)s.welcome_message=welcomeMessage;
      if(goodbyeMessage!==null)s.goodbye_message=goodbyeMessage;
      this.store.save();
      return respond(i,"Welcome and goodbye settings saved. Welcome channel: "+(s.welcome_channel_id?"<#"+s.welcome_channel_id+">":"Disabled")+". Goodbye channel: "+(s.goodbye_channel_id?"<#"+s.goodbye_channel_id+">":"Disabled")+". Available placeholders: "+TEMPLATE_PLACEHOLDERS.join(", ")+".");
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
      if(role&&!role.managed&&role.position<me.roles.highest.position)await member.roles.add(role,"Timi automatic role").catch(error=>this.logger.warn("Automatic role assignment failed:",error.message));
    }
    if(!s.welcome_channel_id)return;
    const channel=await member.guild.channels.fetch(s.welcome_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)await channel.send({content:this.render(s.welcome_message,member),allowedMentions:{users:[member.id]}});
  }
  async memberRemove(member){
    const s=this.settings(member.guild.id);if(!s.goodbye_channel_id)return;
    const channel=await member.guild.channels.fetch(s.goodbye_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)await channel.send({content:this.render(s.goodbye_message,member),allowedMentions:{parse:[]}});
  }
}
