import { ChannelType, PermissionFlagsBits } from "discord.js";
import { Embeds } from "./embeds.js";
import { respond, requireManager } from "../ui.js";
import { renderTemplate, TEMPLATE_PLACEHOLDERS } from "../utils.js";
import { isSafeAssignableRole } from "../permissions.js";

export class Foundation {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;this.embeds=new Embeds(client,store,logger);}
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
    if(i.commandName==="setup")return this.setup(i);
    if(i.commandName==="autorole"){
      const role=i.options.getRole("role");
      if(role){
        const me=await i.guild.members.fetchMe();
        if(!isSafeAssignableRole(role,i.guild.id)||role.position>=me.roles.highest.position)
          return respond(i,"Choose a normal role below Timi's highest role.");
        s.auto_role_id=role.id;
      }else s.auto_role_id="";
      this.store.save();
      return respond(i,s.auto_role_id?"Automatic role set to <@&"+s.auto_role_id+">.":"Automatic role assignment disabled.");
    }
    if(i.commandName==="welcome"){
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
  async ensureSetup(guild){
    const bot=await guild.members.fetchMe();
    const adminRoles=guild.roles.cache.filter(role=>!role.managed&&role.permissions.has(PermissionFlagsBits.ManageGuild)).first(80);
    const definitions=[
      {key:"log_channel_id",name:"timi-log",topic:"Private Timi event and security logs."},
      {key:"confirmation_channel_id",name:"timi-confirmations",topic:"Private Timi approval requests, including newly invited bots."},
      {key:"settings_channel_id",name:"timi-settings",topic:"Private Timi setup and configuration reference."}
    ];
    const overwrites=[
      {id:guild.id,deny:[PermissionFlagsBits.ViewChannel]},
      {id:guild.ownerId,allow:[PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages,PermissionFlagsBits.ReadMessageHistory]},
      {id:bot.id,allow:[PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages,PermissionFlagsBits.ReadMessageHistory,PermissionFlagsBits.EmbedLinks,PermissionFlagsBits.ManageMessages]},
      ...adminRoles.map(role=>({id:role.id,allow:[PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages,PermissionFlagsBits.ReadMessageHistory]}))
    ];
    const saved=this.store.data.timi_setup[guild.id]||{},channels=[];
    for(const definition of definitions){
      let channel=saved[definition.key]?await guild.channels.fetch(saved[definition.key]).catch(()=>null):null;
      if(channel?.type!==ChannelType.GuildText)channel=null;
      if(!channel)channel=guild.channels.cache.find(value=>value.type===ChannelType.GuildText&&value.name===definition.name)||null;
      if(channel){
        await channel.permissionOverwrites.set(overwrites,"Apply Timi private channel permissions");
        if(channel.name!==definition.name||channel.topic!==definition.topic)await channel.edit({name:definition.name,topic:definition.topic});
      }else channel=await guild.channels.create({name:definition.name,type:ChannelType.GuildText,topic:definition.topic,permissionOverwrites:overwrites,reason:"Create Timi setup channel"});
      saved[definition.key]=channel.id;channels.push(channel);
    }
    this.store.data.timi_setup[guild.id]=saved;
    this.store.mods(guild.id).log_channel_id=saved.log_channel_id;
    this.store.save();
    const settings=channels[2];
    const existing=await settings.messages.fetch({limit:25}).catch(()=>null);
    const reference=existing?.find(message=>message.author.id===bot.id&&message.content.includes("Timi setup reference"));
    const referencePayload={content:"**Timi setup reference**\n\nUse /welcome for greetings, /autorole for automatic roles, /verify-config for verification, /moderation for Security, and /ticket-config for Support.\n\nBot approval requests appear in <#"+saved.confirmation_channel_id+">. Event and security logs appear in <#"+saved.log_channel_id+">.",allowedMentions:{parse:[]}};
    if(reference)await reference.edit(referencePayload);
    else await settings.send(referencePayload);
    return {saved,channels};
  }
  async setup(i){
    const {saved}=await this.ensureSetup(i.guild);
    return respond(i,"Timi setup is complete. The private channels are ready:\n**Log:** <#"+saved.log_channel_id+">\n**Confirmation:** <#"+saved.confirmation_channel_id+">\n**Settings:** <#"+saved.settings_channel_id+">\n\nNewly invited bots receive an approval request before Timi applies temporary access restrictions.");
  }
  render(template,member,channel=null){
    return renderTemplate(template,{guild:member.guild,member,user:member.user,channel,client:this.client});
  }
  async sendWelcome(member,channel){
    const template=String(this.settings(member.guild.id).welcome_message||"");
    // Saved embeds are inserted with {embed: name}; remove directives from message text.
    const embedPattern=/\{\s*embed\s*:\s*([a-z0-9_-]+)\s*\}/gi;
    const embedNames=[...template.matchAll(embedPattern)].map(match=>match[1].toLowerCase());
    const contentTemplate=template.replace(embedPattern,"").trim();
    const context={guild:member.guild,member,user:member.user,channel,client:this.client};
    const embeds=[];
    for(const name of embedNames){
      const saved=this.store.embed(member.guild.id,name);
      if(!saved){
        this.logger.warn('Welcome message references missing embed "'+name+'" in guild '+member.guild.id+'.');
        continue;
      }
      try{
        embeds.push(this.embeds.payload(saved,context));
      }catch(error){
        this.logger.warn('Could not render welcome embed "'+name+'":',error.message);
      }
    }
    const content=this.render(contentTemplate,member,channel);
    if(!content&&!embeds.length)return null;
    return channel.send({
      ...(content?{content}:{}),
      ...(embeds.length?{embeds:embeds.slice(0,10)}:{}),
      allowedMentions:{users:[member.id]}
    });
  }
  async testGreet(member){
    const s=this.settings(member.guild.id);
    if(!s.welcome_channel_id)return null;
    const channel=await member.guild.channels.fetch(s.welcome_channel_id).catch(()=>null);
    if(channel?.type!==ChannelType.GuildText)return null;
    return this.sendWelcome(member,channel);
  }
  async memberAdd(member){
    if(member.user.bot)return;
    const s=this.settings(member.guild.id);
    if(s.auto_role_id){
      const role=await member.guild.roles.fetch(s.auto_role_id).catch(()=>null);
      const me=await member.guild.members.fetchMe();
      if(role&&isSafeAssignableRole(role,member.guild.id)&&me.permissions.has(PermissionFlagsBits.ManageRoles)&&role.position<me.roles.highest.position)
        await member.roles.add(role,"Timi automatic role").catch(error=>this.logger.warn("Automatic role assignment failed:",error.message));
    }
    if(!s.welcome_channel_id)return;
    const channel=await member.guild.channels.fetch(s.welcome_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)
      await this.sendWelcome(member,channel);
  }
  async memberRemove(member){
    const s=this.settings(member.guild.id);
    if(!s.goodbye_channel_id)return;
    const channel=await member.guild.channels.fetch(s.goodbye_channel_id).catch(()=>null);
    if(channel?.type===ChannelType.GuildText)
      await channel.send({content:this.render(s.goodbye_message,member),allowedMentions:{parse:[]}});
  }
}
