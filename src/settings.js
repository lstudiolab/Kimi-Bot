import { ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder, EmbedBuilder, PermissionFlagsBits, ModalBuilder, TextInputBuilder, TextInputStyle } from "discord.js";
import { GREY, respond } from "./ui.js";
import { LIBRARIES } from "./libraries/index.js";
import { t, LOCALE_NAMES } from "./i18n.js";
import { isSafeAssignableRole } from "./permissions.js";

const MODULES = Object.freeze([
  { id:"verification", label:"Verification", library:"Security", description:"Member verification and review decisions." },
  { id:"moderation", label:"Moderation", library:"Security", description:"Anti-spam, filters, warnings and sanctions." },
  { id:"protection", label:"Server Protection", library:"Security", description:"Raid detection, anti-nuke and bot approval." },
  { id:"recovery", label:"Recovery", library:"Security", description:"Channel snapshots and message recovery." },
  { id:"welcome", label:"Welcome", library:"Foundation", description:"Welcome, goodbye and automatic role systems." },
  { id:"roles", label:"Role Picker", library:"Foundation", description:"Self-service role selection panels." },
  { id:"embeds", label:"Embeds", library:"Foundation", description:"Reusable server embeds and placements." },
  { id:"tickets", label:"Tickets", library:"Support", description:"Private support tickets and transcripts." },
  { id:"scratch", label:"TbScript", library:"Scratch", description:"TbScript projects and panel scripting." }
]);

// Discord-supported locale identifiers. These are persisted per server.
const LANGUAGES = [
  ["en-US","English (US)"],["en-GB","English (UK)"],["bg","Bulgarian"],["zh-CN","Chinese (Simplified)"],
  ["zh-TW","Chinese (Traditional)"],["hr","Croatian"],["cs","Czech"],["da","Danish"],["nl","Dutch"],
  ["fi","Finnish"],["fr","French"],["de","German"],["el","Greek"],["hi","Hindi"],["hu","Hungarian"],
  ["id","Indonesian"],["it","Italian"],["ja","Japanese"],["ko","Korean"],["lt","Lithuanian"],
  ["no","Norwegian"],["pl","Polish"],["pt-BR","Portuguese (Brazil)"],["ro","Romanian"],["ru","Russian"],
  ["es-ES","Spanish"],["sv-SE","Swedish"],["th","Thai"],["tr","Turkish"],["uk","Ukrainian"],
  ["vi","Vietnamese"]
];

const button = (id,label,style=ButtonStyle.Secondary) => new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style);
const row = (...items) => new ActionRowBuilder().addComponents(...items);
const embed = (title,description) => new EmbedBuilder().setColor(GREY).setTitle(title).setDescription(description);
const hasAccess = i => Boolean(i.guild && i.guild.ownerId === i.user.id);
const installed = (store,guildId,name) => (store.data.installed_libraries[guildId]||[]).includes(name);
const enabled = (store,guildId,id) => store.data.modules?.[guildId]?.[id] !== false;
const moduleStatus = (store,guildId,module) => !installed(store,guildId,module.library) ? t(store,guildId,"missing") : enabled(store,guildId,module.id) ? t(store,guildId,"enabled") : t(store,guildId,"disabled");

export class KimiSettings {
  constructor(store,manager,logger,hooks={}){this.store=store;this.manager=manager;this.logger=logger;this.hooks=hooks;}
  async show(i,page="home",selected=""){
    if(!hasAccess(i))return i.editReply({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const guild=i.guild, id=guild.id;
    const language=this.store.data.languages?.[id]||"en-US";
    const tr=key=>t(this.store,id,key);
    if(page==="home"){
      return i.editReply({embeds:[embed(tr("title"),`Manage Kimi's systems and server preferences.\n\nOnly you, as this server's owner, can change these settings.`)],components:[
        row(button("settings:modules",tr("modules")),button("settings:install",tr("install")),button("settings:uninstall",tr("uninstall"))),
        row(button("settings:language",tr("language")),button("settings:status",tr("status")),button("settings:permissions",tr("permissions"))),
        row(button("settings:advanced",tr("advanced")))
      ]});
    }
    if(page==="library"){
      const library=selected;
      if(!["Foundation","Security","Support","Scratch"].includes(library))return i.editReply({content:"Unknown library.",embeds:[],components:[]});
      if(!installed(this.store,id,library))return i.editReply({content:`${library} is not installed in this server. Install it first using /install.`,embeds:[],components:[]});
      const sections=[];
      if(library==="Security"){
        sections.push(row(button("settings:config:moderation","Moderation"),button("settings:config:verification","Verification")));
        sections.push(row(button("settings:config:filter","Blocked Phrases")));
      }else if(library==="Support"){
        sections.push(row(button("settings:config:tickets-setup","Prepare Tickets"),button("settings:config:tickets","Ticket Settings")));
      }else if(library==="Foundation"){
        sections.push(row(button("settings:config:setup","Server Setup"),button("settings:config:welcome","Welcome")));
      }else{
        sections.push(row(button("settings:home","Back to Kimi Settings")));
      }
      return i.editReply({embeds:[embed(library+" Configuration",`Configure the ${library} library for this server.`)],components:[...sections,row(button("settings:home","Kimi Settings"))]});
    }
    if(page==="configure"){
      const sections=[];
      if(installed(this.store,id,"Security")){sections.push(row(button("settings:config:moderation","Moderation"),button("settings:config:verification","Verification")));sections.push(row(button("settings:config:filter","Blocked Phrases")));}
      if(installed(this.store,id,"Support"))sections.push(row(button("settings:config:tickets-setup","Prepare Tickets"),button("settings:config:tickets","Ticket Settings")));
      if(installed(this.store,id,"Foundation"))sections.push(row(button("settings:config:setup","Server Setup"),button("settings:config:welcome","Welcome")));
      sections.push(row(button("settings:home",tr("back"))));
      return i.editReply({embeds:[embed("Configuration","Choose a system to configure. Only installed libraries are shown here.")],components:sections});
    }
    if(page==="filter"){
      const words=this.store.data.automod_words[id]||[];
      const description=words.length?words.map((word,index)=>`${index+1}. ${word}`).join("\n"):"No blocked phrases are configured.";
      return i.editReply({embeds:[embed("Blocked Phrases",description)],components:[row(button("settings:filter-add","Add Phrase"),button("settings:filter-remove","Remove Phrase")),row(button("settings:configure","Back"))]});
    }
    if(page==="modules"){
      const lines=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\\n");
      const availableModules=MODULES.filter(m=>installed(this.store,id,m.library));
      const options=availableModules.map(m=>({label:m.label,value:m.id,description:m.description.slice(0,100)}));
      const menu=new StringSelectMenuBuilder().setCustomId("settings:module-select").setPlaceholder(tr("choose"));
      if(options.length)menu.addOptions(options);
      const components=options.length?[row(menu)]:[];
      if(selected){
        const m=MODULES.find(x=>x.id===selected);
        if(m&&installed(this.store,id,m.library))components.push(row(button("settings:module-on:"+selected,tr("enable")),button("settings:module-off:"+selected,tr("disable")),button("settings:module-info:"+selected,tr("details"))));
      }
      components.push(row(button("settings:home",tr("back"))));
      return i.editReply({embeds:[embed(tr("modules"),lines+"\n\nSelect a system to manage it. Disabling a system preserves its saved configuration.")],components});
    }
    if(page==="install"||page==="uninstall"){
      const choices=Object.values(LIBRARIES).filter(lib=>page==="install"?!installed(this.store,id,lib.name):installed(this.store,id,lib.name));
      const menu=new StringSelectMenuBuilder().setCustomId("settings:library-select:"+page).setPlaceholder(page==="install"?"Choose a library to install":"Choose an installed library");
      if(choices.length)menu.addOptions(choices.map(lib=>({label:lib.name,value:lib.name,description:lib.description.slice(0,100)})));
      const components=choices.length?[row(menu)]:[];
      if(selected&&choices.some(lib=>lib.name===selected))components.push(row(button("settings:library-confirm:"+page+":"+selected,page==="install"?tr("install"):tr("uninstall"),page==="install"?ButtonStyle.Secondary:ButtonStyle.Danger)));
      components.push(row(button("settings:home",tr("back"))));
      const description=choices.length?choices.map(lib=>`**${lib.name}**\n${lib.description}`).join("\n\n"):(page==="install"?"All available libraries are installed.":"There are no installed libraries to remove.");
      return i.editReply({embeds:[embed(page==="install"?"Install Libraries":"Uninstall Libraries",description)],components});
    }
    if(page==="language"){
      const makeLanguageMenu=(items,suffix)=>new StringSelectMenuBuilder().setCustomId("settings:language-select").setPlaceholder(suffix).addOptions(items.map(([value,label])=>({label:LOCALE_NAMES[value]||label,value,default:value===language})));
      const first=makeLanguageMenu(LANGUAGES.slice(0,25),tr("language"));
      const second=makeLanguageMenu(LANGUAGES.slice(25),tr("language"));
      return i.editReply({embeds:[embed(tr("language"),`Current server language: **${LOCALE_NAMES[language]||language}**

Choose from the supported Discord locale list. The preference is saved per server.`)],components:[row(first),row(second),row(button("settings:home","Back"))]});
    }
    if(page==="status"){
      const libs=Object.values(LIBRARIES).map(lib=>`**${lib.name}** — ${installed(this.store,id,lib.name)?"Installed":"Not installed"}`).join("\\n");
      const mods=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\\n");
      return i.editReply({embeds:[embed(tr("status"),`**Libraries**
${libs}

**Modules**
${mods}

**Language**
${language}`)],components:[row(button("settings:home","Back"))]});
    }
    if(page==="permissions"){
      return i.editReply({embeds:[embed(tr("permissions"),"Only this server's owner can open or change Kimi Settings. Other administrators cannot modify these settings.")],components:[row(button("settings:home","Back"))]});
    }
    if(page==="advanced"){
      return i.editReply({embeds:[embed(tr("advanced"),"Configuration reset and backup controls are reserved for a later safe implementation. No server data is changed from this page.")],components:[row(button("settings:home","Back"))]});
    }
  }
  async handle(i){
    if(!i.inGuild())return i.editReply({content:"Use Timi Settings inside a server.",embeds:[],components:[]});
    if(!hasAccess(i))return i.editReply({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const id=i.customId||"";
    if(i.isModalSubmit()&&(id==="settings:filter:add-modal"||id==="settings:filter:remove-modal")){
      if(!installed(this.store,i.guildId,"Security"))return i.editReply({content:"The Security library is no longer installed.",components:[],embeds:[]});
      const phrase=i.fields.getTextInputValue("phrase").trim();
      if(!phrase||phrase.length>100)return i.editReply({content:"Enter a phrase between 1 and 100 characters.",components:[],embeds:[]});
      const words=this.store.data.automod_words[i.guildId]||[];
      const index=words.findIndex(word=>word.toLowerCase()===phrase.toLowerCase());
      if(id==="settings:filter:add-modal"){
        if(index!==-1)return i.editReply({content:"That phrase is already blocked.",components:[],embeds:[]});
        if(words.length>=100)return i.editReply({content:"The blocked phrase list is full (100 entries).",components:[],embeds:[]});
        words.push(phrase);
      }else{
        if(index===-1)return i.editReply({content:"That phrase is not in the blocked list.",components:[],embeds:[]});
        words.splice(index,1);
      }
      this.store.data.automod_words[i.guildId]=words;this.store.save();
      return i.editReply({content:id.endsWith("add-modal")?"Blocked phrase added.":"Blocked phrase removed.",components:[],embeds:[]});
    }
    if(i.isModalSubmit()&&id==="settings:verification:modal"){
      if(i.guild.ownerId!==i.user.id)return i.editReply({content:"Only the server owner can change verification policy.",components:[],embeds:[]});
      if(!installed(this.store,i.guildId,"Security"))return i.editReply({content:"The Security library is no longer installed.",components:[],embeds:[]});
      const value=this.store.verify(i.guildId),read=key=>i.fields.getTextInputValue(key).trim();
      const roleId=read("verify-role").replace(/[<@&>]/g,""),requiredRoleId=read("required-role").replace(/[<@&>]/g,""),reviewId=read("review-channel").replace(/[<#>]/g,"");
      const age=read("min-age")===""?value.min_age_days:Number(read("min-age"));
      const thresholds=read("thresholds").split(",").map(part=>Number(part.trim()));
      if(!Number.isInteger(age)||age<0||age>3650)return i.editReply({content:"Minimum account age must be between 0 and 3650 days.",components:[],embeds:[]});
      if(thresholds.length!==2||thresholds.some(n=>!Number.isInteger(n)||n<0||n>100)||thresholds[1]>thresholds[0])return i.editReply({content:"Enter valid thresholds as pass,review (for example: 80,60).",components:[],embeds:[]});
      for(const id of [roleId,requiredRoleId])if(id&&!/^\d{15,22}$/.test(id))return i.editReply({content:"Enter valid role IDs or leave them blank.",components:[],embeds:[]});
      if(reviewId&&!/^\d{15,22}$/.test(reviewId))return i.editReply({content:"Enter a valid review channel ID or leave it blank.",components:[],embeds:[]});
      if(roleId&&!i.guild.roles.cache.has(roleId)||requiredRoleId&&!i.guild.roles.cache.has(requiredRoleId))return i.editReply({content:"One of the role IDs does not belong to this server.",components:[],embeds:[]});
      if(reviewId&&(!i.guild.channels.cache.has(reviewId)||!i.guild.channels.cache.get(reviewId).isTextBased()))return i.editReply({content:"Choose a text channel in this server for manual reviews.",components:[],embeds:[]});
      const bot=await i.guild.members.fetchMe();
      for(const id of [roleId,requiredRoleId]){
        const role=id?i.guild.roles.cache.get(id):null;
        if(role&&!isSafeAssignableRole(role,i.guildId))return i.editReply({content:"Choose normal verification roles without elevated permissions.",components:[],embeds:[]});
        if(id===roleId&&role.position>=bot.roles.highest.position)return i.editReply({content:"Timi must have a higher role than the configured verification roles.",components:[],embeds:[]});
      }
      if(roleId&&!bot.permissions.has(PermissionFlagsBits.ManageRoles))return i.editReply({content:"Timi needs Manage Roles permission to grant the verified role.",components:[],embeds:[]});
      Object.assign(value,{role_id:roleId,required_role_id:requiredRoleId,review_channel_id:reviewId,min_age_days:age,thresholds:{pass:thresholds[0],review:thresholds[1]}});
      this.store.data.verification[i.guildId]=value;this.store.save();
      await this.hooks.libraries?.Foundation?.refreshVerification?.(i.guild);
      return i.editReply({content:"Verification settings saved. Existing verification panels have been refreshed.",components:[],embeds:[]});
    }
    if(i.isModalSubmit()&&id==="settings:welcome:modal"){
      if(!installed(this.store,i.guildId,"Foundation"))return i.editReply({content:"The Foundation library is no longer installed.",components:[],embeds:[]});
      const current=this.store.data.welcome[i.guildId]||{welcome_channel_id:"",welcome_message:"Welcome {user} to {server}! You are member #{member_count}.",goodbye_channel_id:"",goodbye_message:"{username} has left {server}.",auto_role_id:""};
      const read=key=>i.fields.getTextInputValue(key).trim();
      const channelId=key=>read(key).replace(/[<#>]/g,"");
      const welcomeChannel=channelId("welcome-channel"),goodbyeChannel=channelId("goodbye-channel"),roleId=channelId("auto-role");
      for(const value of [welcomeChannel,goodbyeChannel])if(value&&!/^\d{15,22}$/.test(value))return i.editReply({content:"Enter a valid Discord channel ID or leave it blank.",components:[],embeds:[]});
      if(roleId&&!/^\d{15,22}$/.test(roleId))return i.editReply({content:"Enter a valid Discord role ID or leave it blank.",components:[],embeds:[]});
      for(const value of [welcomeChannel,goodbyeChannel])if(value&&(!i.guild.channels.cache.has(value)||!i.guild.channels.cache.get(value).isTextBased()))return i.editReply({content:"Choose text channels from this server.",components:[],embeds:[]});
      if(roleId&&!i.guild.roles.cache.has(roleId))return i.editReply({content:"That role does not belong to this server or is unavailable.",components:[],embeds:[]});
      if(roleId){
        const role=i.guild.roles.cache.get(roleId),bot=await i.guild.members.fetchMe();
        if(!isSafeAssignableRole(role,i.guildId)||role.position>=bot.roles.highest.position||!bot.permissions.has(PermissionFlagsBits.ManageRoles))return i.editReply({content:"Choose a normal role below Timi's highest role. Timi also needs Manage Roles permission.",components:[],embeds:[]});
      }
      this.store.data.welcome[i.guildId]={...current,welcome_channel_id:welcomeChannel,welcome_message:read("welcome-message")||current.welcome_message,goodbye_channel_id:goodbyeChannel,goodbye_message:read("goodbye-message")||current.goodbye_message,auto_role_id:roleId};
      this.store.save();
      return i.editReply({content:"Welcome, goodbye and automatic-role settings saved.",components:[],embeds:[]});
    }
    if(i.isStringSelectMenu()){
      if(id==="settings:module-select")return this.show(i,"modules",i.values[0]);
      if(id==="settings:language-select"){
        this.store.data.languages||={};this.store.data.languages[i.guildId]=i.values[0];this.store.save();
        return this.show(i,"language");
      }
      if(id.startsWith("settings:library-select:"))return this.show(i,id.split(":")[2],i.values[0]);
    }
    if(!i.isButton())return;
    if(id==="settings:filter-add"||id==="settings:filter-remove"){
      if(!installed(this.store,i.guildId,"Security"))return respond(i,"The Security library is no longer installed.");
      const add=id==="settings:filter-add";
      const modal=new ModalBuilder().setCustomId(add?"settings:filter:add-modal":"settings:filter:remove-modal").setTitle(add?"Block a phrase":"Remove a phrase").addComponents(new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("phrase").setLabel("Word or phrase").setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(100)));
      return i.showModal(modal);
    }
    if(id==="settings:home")return this.show(i,"home");
    if(id==="settings:modules")return this.show(i,"modules");
    if(id==="settings:configure")return this.show(i,"configure");
    if(id.startsWith("settings:config:")){
      const section=id.split(":")[2];
      const library=section==="moderation"||section==="verification"||section==="filter"?"Security":section==="tickets"||section==="tickets-setup"?"Support":section==="welcome"||section==="setup"||section==="roles"?"Foundation":"Scratch";
      if(!installed(this.store,i.guildId,library))return respond(i,"That library is no longer installed. Reopen Timi Settings to refresh the panel.");
      if(section==="filter")return this.show(i,"filter");
      if(section==="verification"){
        if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can change verification policy.");
        const value=this.store.verify(i.guildId);
        const field=(key,label,placeholder,current)=>new TextInputBuilder().setCustomId(key).setLabel(label).setPlaceholder(placeholder).setStyle(TextInputStyle.Short).setRequired(false).setMaxLength(100).setValue(String(current??"").slice(0,100));
        const modal=new ModalBuilder().setCustomId("settings:verification:modal").setTitle("Verification settings").addComponents(
          new ActionRowBuilder().addComponents(field("verify-role","Verified role ID","Role ID granted after passing",value.role_id)),
          new ActionRowBuilder().addComponents(field("required-role","Required role ID","Role ID required before verifying",value.required_role_id)),
          new ActionRowBuilder().addComponents(field("review-channel","Review channel ID","Text channel ID for manual reviews",value.review_channel_id)),
          new ActionRowBuilder().addComponents(field("min-age","Minimum account age in days","0 to 3650",value.min_age_days)),
          new ActionRowBuilder().addComponents(field("thresholds","Pass and review thresholds","Example: 80,60",`${value.thresholds.pass},${value.thresholds.review}`))
        );
        return i.showModal(modal);
      }
      if(section==="welcome"){
        const value=this.store.data.welcome[i.guildId]||{};
        const field=(key,label,placeholder,current,style=TextInputStyle.Short)=>new TextInputBuilder().setCustomId(key).setLabel(label).setPlaceholder(placeholder).setStyle(style).setRequired(false).setMaxLength(style===TextInputStyle.Paragraph?1800:22).setValue(String(current||"").slice(0,style===TextInputStyle.Paragraph?1800:22));
        const modal=new ModalBuilder().setCustomId("settings:welcome:modal").setTitle("Welcome settings").addComponents(
          new ActionRowBuilder().addComponents(field("welcome-channel","Welcome channel ID","Channel ID",value.welcome_channel_id)),
          new ActionRowBuilder().addComponents(field("welcome-message","Welcome message","Supports {user}, {username}, {server}, {member_count}",value.welcome_message,TextInputStyle.Paragraph)),
          new ActionRowBuilder().addComponents(field("goodbye-channel","Goodbye channel ID","Channel ID",value.goodbye_channel_id)),
          new ActionRowBuilder().addComponents(field("goodbye-message","Goodbye message","Goodbye message",value.goodbye_message,TextInputStyle.Paragraph)),
          new ActionRowBuilder().addComponents(field("auto-role","Automatic role ID","Role ID; blank disables",value.auto_role_id))
        );
        return i.showModal(modal);
      }
      if(!this.hooks.openConfiguration)return i.editReply({content:"This configuration page is not available yet.",components:[],embeds:[]});
      return this.hooks.openConfiguration(i,section);
    }
    if(id==="settings:install"||id==="settings:uninstall")return this.show(i,id.slice("settings:".length));
    if(id==="settings:language")return this.show(i,"language");
    if(id==="settings:status")return this.show(i,"status");
    if(id==="settings:permissions")return this.show(i,"permissions");
    if(id==="settings:advanced")return this.show(i,"advanced");
    if(id.startsWith("settings:module-on:")||id.startsWith("settings:module-off:")){
      const [,action,moduleId]=id.split(":");
      const module=MODULES.find(m=>m.id===moduleId);
      if(!module)return this.show(i,"modules");
      if(!installed(this.store,i.guildId,module.library))return i.editReply({content:`Install the **${module.library}** library before enabling ${module.label}.`,embeds:[],components:[row(button("settings:modules","Back to Modules"))]});
      this.store.data.modules||={};this.store.data.modules[i.guildId]||={};
      this.store.data.modules[i.guildId][moduleId]=action==="module-on";this.store.save();
      this.logger.info(`Module ${moduleId} ${action==="module-on"?"enabled":"disabled"} for guild ${i.guildId}.`);
      return this.show(i,"modules",moduleId);
    }
    if(id.startsWith("settings:module-info:"))return this.show(i,"modules",id.split(":")[2]);
    if(id.startsWith("settings:library-confirm:")){
      const [, ,action,name]=id.split(":");
      if(i.guild.ownerId!==i.user.id)return i.editReply({content:"Only the server owner can install or uninstall libraries.",embeds:[],components:[]});
      if(action==="install"){
        const result=this.manager.install(i.guildId,name);
        if(!result.ok)return i.editReply({content:result.error,embeds:[],components:[]});
        await this.hooks.syncGuildCommands?.(i.guildId);
        const library=this.hooks.libraries?.[name];
        if(library?.ready)await library.ready(i.guild);
        if(library?.onInstall)await library.onInstall(i.guild);
        return i.editReply({embeds:[embed("Library Installed",`**${name}** is now installed. Its commands will be registered when Timi next synchronizes this server.`)],components:[row(button("settings:install","Install Another"),button("settings:home","Done"))]});
      }
      const result=this.manager.uninstall(i.guildId,name);
      if(!result.ok)return i.editReply({content:result.error,embeds:[],components:[]});
      const library=this.hooks.libraries?.[name];
      if(library?.onUninstall)await library.onUninstall(i.guild);
      await this.hooks.syncGuildCommands?.(i.guildId);
      return i.editReply({embeds:[embed("Library Uninstalled",`**${name}** has been uninstalled. Saved configuration and project data are preserved.`)],components:[row(button("settings:uninstall","Uninstall Another"),button("settings:home","Done"))]});
    }
  }
}
