import {
  ButtonStyle, RoleSelectMenuBuilder, StringSelectMenuBuilder,
  ChannelType, TextInputStyle
} from "discord.js";
import { requireOwner, respond, deny, modal, textInput, row, button, greyEmbed } from "../ui.js";
import { isSnowflake, renderTemplate } from "../utils.js";
import { applyGuildTheme, applyButtonTheme } from "../styles.js";

export class RolePicker {
  constructor(client,store,logger,verification){this.client=client;this.store=store;this.logger=logger;this.verification=verification;}
  async command(i){
    if(!await requireOwner(i))return;
    return respond(i,"**Role picker setup**\n\nCreate a self-service role menu. Configure its appearance, choose the allowed roles, then publish. Text supports {user}, {username}, {user_tag}, {user_id}, {server}, {server_id}, {member_count}, {channel}, {channel_name}, {owner}, {owner_id}, {bot}, {bot_name}, {date}, {time}, and {timestamp}.",
      [row(button("rolepicker:start","Configure role picker",ButtonStyle.Primary))]);
  }
  async button(i){
    if(i.customId.startsWith("rolepicker:footer-link:")){
      const id=i.customId.slice("rolepicker:footer-link:".length),menu=this.store.data.role_picker_menus[id];
      if(!menu||menu.guild_id!==i.guildId||!menu.footer_channel_id||i.message?.author?.id!==this.client.user.id||i.message.id!==menu.message_id||i.channelId!==menu.channel_id)return deny(i,"This link is no longer available.");
      return respond(i,"Open the channel: https://discord.com/channels/"+menu.guild_id+"/"+menu.footer_channel_id);
    }
    if(i.customId==="rolepicker:start"){
      if(!await requireOwner(i))return;
      return i.showModal(modal("rolepicker:details","Role picker settings",[
        textInput("rp-title","Menu title","Choose your roles",TextInputStyle.Short,true,100),
        textInput("rp-description","Description","Select the roles you want.",TextInputStyle.Paragraph,true,500),
        textInput("rp-placeholder","Dropdown placeholder","Select roles...",TextInputStyle.Short,true,150),
        textInput("rp-footer","Optional bottom button text","",TextInputStyle.Short,false,80),
        textInput("rp-footer-channel","Optional bottom button channel ID","",TextInputStyle.Short,false,22)
      ]));
    }
    if(i.customId.startsWith("rolepicker:publish:")){
      if(!await requireOwner(i))return;
      const id=i.customId.slice("rolepicker:publish:".length),draft=this.store.data.role_picker_drafts[id];
      if(!draft||draft.guild_id!==i.guildId||!draft.roles?.length)return deny(i,"Choose at least one role before publishing.");
      const roles=[];
      for(const roleId of draft.roles){
        const role=await i.guild.roles.fetch(roleId).catch(()=>null);
        if(!role)return deny(i,"One of the selected roles no longer exists. Reopen setup and select roles again.");
        const [ok,message]=await this.verification.validateRole(i.guild,role,true);
        if(!ok)return deny(i,message);
        roles.push({id:role.id,name:role.name});
      }
      const guildMenus=Object.values(this.store.data.role_picker_menus||{}).filter(item=>item?.guild_id===i.guildId).length;
      if(guildMenus>=100)return deny(i,"This server has reached the 100 published role menu safety limit. Remove an older menu before creating another.");
      const menuId=Date.now()+"-"+i.id;
      const menu={id:menuId,guild_id:i.guildId,channel_id:draft.channel_id,title:draft.title,description:draft.description,
        placeholder:draft.placeholder,footer_text:draft.footer_text,footer_channel_id:draft.footer_channel_id,roles,selections:{}};
      const channel=await i.guild.channels.fetch(menu.channel_id),sent=await channel.send(this.publicPayload(menu,{guild:i.guild,user:i.user,member:i.member,channel,client:this.client}));
      menu.message_id=sent.id;this.store.data.role_picker_menus[menuId]=menu;
      delete this.store.data.role_picker_drafts[id];this.store.save();
      return respond(i,`Role picker menu published in <#${channel.id}>. You can create another menu with /roles.`);
    }
  }
  publicPayload(menu,context={}){
    const select=new StringSelectMenuBuilder().setCustomId("rolepicker:menu:"+menu.id)
      .setPlaceholder(renderTemplate(menu.placeholder||"Choose roles",context).slice(0,150)).setMinValues(0)
      .setMaxValues(Math.max(1,Math.min(25,menu.roles.length)))
      .addOptions(menu.roles.map(role=>({label:role.name.slice(0,100),value:role.id})));
    const components=[row(select)];
    if(menu.footer_text&&menu.footer_channel_id){
      components.push(row(applyButtonTheme(button("rolepicker:footer-link:"+menu.id,renderTemplate(menu.footer_text,context).slice(0,80)),this.store,menu.guild_id)));
    }
    const base={embeds:[applyGuildTheme(greyEmbed(renderTemplate(menu.title,context),renderTemplate(menu.description,context)),this.store,menu.guild_id)],components,allowedMentions:{parse:[]}};
    return base;
  }
  async refresh(guild){
    const owner=await guild.members.fetch(guild.ownerId).catch(()=>null);
    for(const menu of Object.values(this.store.data.role_picker_menus||{})){
      if(menu.guild_id!==guild.id||!menu.channel_id||!menu.message_id)continue;
      const channel=await guild.channels.fetch(menu.channel_id).catch(()=>null);
      const message=await channel?.messages.fetch(menu.message_id).catch(()=>null);
      if(message)await message.edit(this.publicPayload(menu,{guild,channel,user:owner?.user||null,member:owner||null,client:this.client})).catch(error=>this.logger.warn("Role picker refresh failed:",error.message));
    }
  }
  async modalSubmit(i){
    if(i.customId!=="rolepicker:details")return;
    if(!await requireOwner(i))return;
    const f=Object.fromEntries(i.fields.fields.map(v=>[v.customId,v.value.trim()]));
    if(!f["rp-title"]||!f["rp-description"]||!f["rp-placeholder"])return deny(i,"Menu title, description, and placeholder are required.");
    if(f["rp-footer-channel"]&&!isSnowflake(f["rp-footer-channel"]))return deny(i,"The bottom button channel must be a valid channel ID.");
    if(f["rp-footer-channel"]){
      const channel=await i.guild.channels.fetch(f["rp-footer-channel"]).catch(()=>null);
      if(!channel||channel.type!==ChannelType.GuildText)return deny(i,"The bottom button channel must be a text channel in this server.");
    }
    const now=Date.now(),drafts=this.store.data.role_picker_drafts||(this.store.data.role_picker_drafts={});
    for(const [draftId,draft] of Object.entries(drafts))if(!draft||now-(draft.created_at||0)>60*60*1000)delete drafts[draftId];
    if(Object.keys(drafts).length>=2000)return deny(i,"Too many role menu setups are currently open. Finish or retry later.");
    const id=i.guildId+":"+i.id;
    const draft={guild_id:i.guildId,channel_id:i.channelId,created_at:now,title:f["rp-title"],description:f["rp-description"],
      placeholder:f["rp-placeholder"],footer_text:f["rp-footer"],footer_channel_id:f["rp-footer-channel"],roles:[]};
    this.store.data.role_picker_drafts[id]=draft;this.store.save();
    const count=i.guild.roles.cache.filter(role=>role.id!==i.guildId&&!role.managed).size;
    const menu=new RoleSelectMenuBuilder().setCustomId("rolepicker:setup-roles:"+id)
      .setPlaceholder("Choose the roles members can pick").setMinValues(1).setMaxValues(25);
    return respond(i,`**${draft.title}**\n${draft.description}\n\nChoose which roles members can select. ${count} assignable roles were found. Select up to 25.`,[row(menu)]);
  }
  async setupRoles(i){
    if(!await requireOwner(i))return;
    const id=i.customId.slice("rolepicker:setup-roles:".length),draft=this.store.data.role_picker_drafts[id];
    if(!draft||draft.guild_id!==i.guildId)return deny(i,"This setup has expired. Run /roles again.");
    draft.roles=[...i.values];this.store.save();
    return respond(i,`**${draft.title}**\n${draft.description}\n\n**Roles included:** ${draft.roles.length}\n\nChange the selection or publish this menu.`,
      [row(button("rolepicker:publish:"+id,"Publish role menu",ButtonStyle.Primary))]);
  }
  async menu(i){
    const id=i.customId.slice("rolepicker:menu:".length),menu=this.store.data.role_picker_menus[id];
    if(!menu||menu.guild_id!==i.guildId||i.message?.author?.id!==this.client.user.id||i.message.id!==menu.message_id||i.channelId!==menu.channel_id)return deny(i,"This role picker is no longer available.");
    const allowed=new Set((Array.isArray(menu.roles)?menu.roles:[]).filter(role=>role&&isSnowflake(role.id)).map(role=>role.id));
    if(!allowed.size||!Array.isArray(i.values)||i.values.some(roleId=>!allowed.has(roleId)))return deny(i,"This menu contains an invalid role selection.");
    const guild=i.guild;
    if(!guild||!i.member)return deny(i,"This role menu is not available in a server.");
    const member=await guild.members.fetch(i.user.id).catch(()=>null);
    if(!member||member.user.bot)return deny(i,"This role menu is only available to server members.");
    const selected=new Set(i.values),previous=new Set((Array.isArray(menu.selections?.[i.user.id])?menu.selections[i.user.id]:[]).filter(id=>allowed.has(id)));
    const add=[...selected].filter(role=>!previous.has(role)),remove=[...previous].filter(role=>!selected.has(role));
    const resolved=new Map();
    for(const roleId of selected){
      const role=await guild.roles.fetch(roleId).catch(()=>null);
      if(!role)return deny(i,"A selected role no longer exists. Contact a server manager.");
      const [ok,message]=await this.verification.validateRole(guild,role,true);
      if(!ok)return deny(i,"That role can no longer be self-assigned. "+message);
      resolved.set(roleId,role);
    }
    const removable=[];
    for(const roleId of remove){
      const role=await guild.roles.fetch(roleId).catch(()=>null);
      if(role?.editable){resolved.set(roleId,role);removable.push(roleId);}
    }
    try{
      if(add.length)await member.roles.add(add.map(id=>resolved.get(id)),"Kimi self-service role picker");
      if(removable.length)await member.roles.remove(removable.map(id=>resolved.get(id)),"Kimi self-service role picker");
    }catch(error){
      this.logger.warn("Role picker role update failed:",error.message);
      return deny(i,"Timi could not update your roles. Check Manage Roles and role hierarchy.");
    }
    menu.selections||={};
    if(!Object.hasOwn(menu.selections,i.user.id)&&Object.keys(menu.selections).length>=5000){
      const oldest=Object.keys(menu.selections)[0];
      if(oldest)delete menu.selections[oldest];
    }
    menu.selections[i.user.id]=[...selected];this.store.save();
    return respond(i,selected.size?"Your role selections have been updated.":"Your role selections have been cleared.");
  }
  async handle(i){
    if(i.isChatInputCommand()&&i.commandName==="roles")return this.command(i);
    if(i.isButton()&&i.customId.startsWith("rolepicker:"))return this.button(i);
    if(i.isModalSubmit()&&i.customId==="rolepicker:details")return this.modalSubmit(i);
    if(i.isRoleSelectMenu()&&i.customId.startsWith("rolepicker:setup-roles:"))return this.setupRoles(i);
    if(i.isStringSelectMenu()&&i.customId.startsWith("rolepicker:menu:"))return this.menu(i);
  }
}
