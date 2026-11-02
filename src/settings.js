import { ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder, EmbedBuilder, PermissionFlagsBits, ModalBuilder, TextInputBuilder, TextInputStyle } from "discord.js";
import { GREY, respond } from "./ui.js";
import { PLUGINS } from "./plugins/index.js";
import { t, LOCALE_NAMES } from "./i18n.js";
import { isSafeAssignableRole } from "./permissions.js";

const MODULES = Object.freeze([
  { id:"verification", label:"Verification", plugin:"Kimi Lock", description:"Member verification and review decisions." },
  { id:"moderation", label:"Moderation", plugin:"Kimi Lock", description:"Anti-spam, filters, warnings and sanctions." },
  { id:"protection", label:"Server Protection", plugin:"Kimi Lock", description:"Raid detection, anti-nuke and bot approval." },
  { id:"recovery", label:"Recovery", plugin:"Kimi Lock", description:"Channel snapshots and message recovery." },
  { id:"welcome", label:"Welcome", plugin:"Welcome", description:"Welcome and departure messages." },
  { id:"auto_role", label:"Automatic Role", plugin:"Auto Role", description:"Assign one configured role to new members." },
  { id:"roles", label:"Role Picker", plugin:"Role Picker", description:"Self-service role selection panels." },
  { id:"embeds", label:"Embeds", plugin:"Embeds", description:"Reusable server embeds and placements." },
  { id:"tickets", label:"Tickets", plugin:"Support", description:"Private support tickets and transcripts." },
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

// Discord rejects a message when any interactive component ID is repeated.
// Keep every control functional by assigning a reversible suffix to collisions.
function normalizePanelComponents(components,logger){
  const seen=new Set();
  for(const actionRow of components||[]){
    for(const component of actionRow.components||[]){
      const data=component.toJSON?.()||component.data||{};
      const original=data.custom_id;
      if(!original)continue;
      let next=original,index=1;
      while(seen.has(next)){
        const suffix=":dup:"+index++;
        next=original.slice(0,100-suffix.length)+suffix;
      }
      if(next!==original){
        component.setCustomId(next);
        logger?.warn?.("Duplicate component ID corrected in Kimi Settings panel:",original,"→",next);
      }
      seen.add(next);
    }
  }
  return components;
}
const installed = (store,guildId,name) => (store.data.installed_plugins[guildId]||[]).includes(name);
const enabled = (store,guildId,id) => store.data.modules?.[guildId]?.[id] !== false;
const moduleStatus = (store,guildId,module) => !installed(store,guildId,module.plugin) ? t(store,guildId,"missing") : enabled(store,guildId,module.id) ? t(store,guildId,"enabled") : t(store,guildId,"disabled");

export class KimiSettings {
  constructor(store,manager,logger,hooks={}){this.store=store;this.manager=manager;this.logger=logger;this.hooks=hooks;}
  async show(i,page="home",selected=""){
    if(i.isChatInputCommand?.()&&!i.deferred&&!i.replied)await i.deferReply({ephemeral:false});
    if(!hasAccess(i))return edit({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const guild=i.guild, id=guild.id;
    const edit=payload=>{payload.components=normalizePanelComponents(payload.components,this.logger);return i.editReply(payload);};
    const language=this.store.data.languages?.[id]||"en-US";
    const tr=key=>t(this.store,id,key);
    if(page==="home"){
      return edit({embeds:[embed(tr("title"),`Manage Kimi's systems and server preferences.\n\nOnly you, as this server's owner, can change these settings.`)],components:[
        row(button("settings:modules","Systems"),button("settings:install","App Store")),
        row(button("settings:preferences","Preferences"),button("settings:status","Status"))
      ]});
    }
    if(page==="plugin"){
      const plugin=selected;
      if(!["Welcome","Auto Role","Role Picker","Embeds","Kimi Lock","Support"].includes(plugin))return edit({content:"Unknown app.",embeds:[],components:[]});
      if(!installed(this.store,id,plugin))return edit({content:`${plugin} is not added to this server. Add it from the App Store first.`,embeds:[],components:[]});
      const sections=[];
      if(plugin==="Kimi Lock"){
        sections.push(row(button("settings:config:moderation","Moderation"),button("settings:config:verification","Verification")));
        sections.push(row(button("settings:config:filter","Blocked Phrases")));
      }else if(plugin==="Support"){
        sections.push(row(button("settings:config:tickets-setup","Prepare Tickets"),button("settings:config:tickets","Ticket Settings")));
      }else if(plugin==="Welcome"){
        sections.push(row(button("settings:config:setup","Server Setup"),button("settings:config:welcome","Welcome")));
      }else if(plugin==="Auto Role"){
        sections.push(row(button("settings:config:auto-role","Automatic Role")));
      }else if(plugin==="Role Picker"){
        sections.push(row(button("settings:config:roles","Role Menus")));
      }else if(plugin==="Embeds"){
        sections.push(row(button("settings:config:embeds","Embed Tools")));
      }else{
        sections.push(row(button("settings:home","Back to Kimi Settings")));
      }
      return edit({embeds:[embed(plugin+" Configuration",`Configure the ${plugin} app for this server.`)],components:[...sections,row(button("settings:home","Kimi Settings"))]});
    }
    if(page==="configure"){
      const sections=[];
      if(installed(this.store,id,"Kimi Lock")){sections.push(row(button("settings:config:moderation","Moderation"),button("settings:config:verification","Verification")));sections.push(row(button("settings:config:filter","Blocked Phrases")));}
      if(installed(this.store,id,"Support"))sections.push(row(button("settings:config:tickets-setup","Prepare Tickets"),button("settings:config:tickets","Ticket Settings")));
      if(installed(this.store,id,"Welcome"))sections.push(row(button("settings:config:setup","Server Setup"),button("settings:config:welcome","Welcome")));
      if(installed(this.store,id,"Auto Role"))sections.push(row(button("settings:config:auto-role","Automatic Role")));
      if(installed(this.store,id,"Role Picker"))sections.push(row(button("settings:config:roles","Role Menus")));
      if(installed(this.store,id,"Embeds"))sections.push(row(button("settings:config:embeds","Embed Tools")));
      sections.push(row(button("settings:home",tr("back"))));
      return edit({embeds:[embed("Configuration","Choose a system to configure. Only apps added to this server are shown here.")],components:sections});
    }
    if(page==="filter"){
      const words=this.store.data.automod_words[id]||[];
      const description=words.length?words.map((word,index)=>`${index+1}. ${word}`).join("\n"):"No blocked phrases are configured.";
      return edit({embeds:[embed("Blocked Phrases",description)],components:[row(button("settings:filter-add","Add Phrase"),button("settings:filter-remove","Remove Phrase")),row(button("settings:configure","Back"))]});
    }
    if(page==="modules"){
      const lines=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\\n");
      const availableModules=MODULES.filter(m=>installed(this.store,id,m.plugin));
      const options=availableModules.map(m=>({label:m.label,value:m.id,description:m.description.slice(0,100)}));
      const menu=new StringSelectMenuBuilder().setCustomId("settings:module-select").setPlaceholder(tr("choose"));
      if(options.length)menu.addOptions(options);
      const components=options.length?[row(menu)]:[];
      if(selected){
        const m=MODULES.find(x=>x.id===selected);
        if(m&&installed(this.store,id,m.plugin))components.push(row(button("settings:module-on:"+selected,tr("enable")),button("settings:module-off:"+selected,tr("disable")),button("settings:module-info:"+selected,tr("details"))));
      }
      components.push(row(button("settings:home",tr("back"))));
      return edit({embeds:[embed(tr("modules"),lines+"\n\nSelect a system to manage it. Disabling a system preserves its saved configuration.")],components});
    }
    if(page==="install"||page==="uninstall"){
      const choices=Object.values(PLUGINS).filter(lib=>page==="install"?!installed(this.store,id,lib.name):installed(this.store,id,lib.name));
      const menu=new StringSelectMenuBuilder().setCustomId("settings:plugin-select:"+page).setPlaceholder(page==="install"?"Choose an app to add":"Choose an app to remove");
      if(choices.length)menu.addOptions(choices.map(lib=>({label:lib.name,value:lib.name,description:lib.description.slice(0,100)})));
      const components=choices.length?[row(menu)]:[];
      if(selected&&choices.some(lib=>lib.name===selected))components.push(row(button("settings:plugin-confirm:"+page+":"+selected,page==="install"?tr("install"):tr("uninstall"),page==="install"?ButtonStyle.Secondary:ButtonStyle.Danger)));
      components.push(row(button("settings:home",tr("back"))));
      const description=choices.length?choices.map(lib=>`**${lib.name}**\n${lib.description}`).join("\n\n"):(page==="install"?"All available apps are already added.":"There are no apps to remove.");
      return edit({embeds:[embed(page==="install"?"App Store":"Remove Apps",description)],components});
    }
    if(page==="language"){
      const makeLanguageMenu=(items,suffix,customId="settings:language-select")=>new StringSelectMenuBuilder().setCustomId(customId).setPlaceholder(suffix).addOptions(items.map(([value,label])=>({label:LOCALE_NAMES[value]||label,value,default:value===language})));
      const first=makeLanguageMenu(LANGUAGES.slice(0,25),tr("language"));
      const second=makeLanguageMenu(LANGUAGES.slice(25),tr("language"),"settings:language-select:more");
      return edit({embeds:[embed(tr("language"),`Current server language: **${LOCALE_NAMES[language]||language}**

Choose from the supported Discord locale list. The preference is saved per server.`)],components:[row(first),row(second),row(button("settings:home","Back"))]});
    }
    if(page==="status"){
      const libs=Object.values(PLUGINS).map(lib=>`**${lib.name}** — ${installed(this.store,id,lib.name)?"Installed":"Not installed"}`).join("\\n");
      const mods=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\\n");
      return edit({embeds:[embed(tr("status"),`**Apps**
${libs}

**Modules**
${mods}

**Language**
${language}`)],components:[row(button("settings:home","Back"))]});
    }
    if(page==="permissions"){
      return edit({embeds:[embed(tr("permissions"),"Only this server's owner can open or change Kimi Settings. Other administrators cannot modify these settings.")],components:[row(button("settings:home","Back"))]});
    }
    if(page==="preferences"){
      return edit({embeds:[embed("Preferences","Choose how Kimi appears and communicates in this server.")],components:[
        row(button("settings:language",tr("language")),button("settings:appearance","Appearance")),
        row(button("settings:home",tr("back")))
      ]});
    }
    if(page==="appearance"){
      const appearance=this.store.data.customizations?.[id]||{};
      const color=typeof appearance.accent_color==="string"&&/^#[0-9A-F]{6}$/i.test(appearance.accent_color)?appearance.accent_color:"#808080";
      const style=["Primary","Secondary","Success","Danger"].includes(appearance.button_style)?appearance.button_style:"Secondary";
      const styleMenu=new StringSelectMenuBuilder().setCustomId("settings:appearance-style").setPlaceholder("Choose a button style").addOptions(["Primary","Secondary","Success","Danger"].map(value=>({label:value,value,default:value===style})));
      return edit({embeds:[new EmbedBuilder().setColor(Number.parseInt(color.slice(1),16)).setTitle("Appearance").setDescription("**Accent color:** `"+color+"`\n**Button style:** "+style+"\n\nChoose the visual style Kimi should use for its panels and controls. These preferences are saved for this server.")],components:[row(button("settings:appearance-color","Change Accent Color")),row(styleMenu),row(button("settings:home","Back"))]});
    }
    if(page==="advanced"){
      return edit({embeds:[embed(tr("advanced"),"Configuration reset and backup controls are reserved for a later safe implementation. No server data is changed from this page.")],components:[row(button("settings:home","Back"))]});
    }
  }
  async handle(i){
    if(!i.inGuild())return i.editReply({content:"Use Kimi Settings inside a server.",embeds:[],components:[]});
    if(!hasAccess(i))return i.editReply({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const id=(i.customId||"").replace(/:dup:\\d+$/,"");
    if(i.isModalSubmit()&&id==="settings:appearance-color-modal"){
      const color=i.fields.getTextInputValue("accent-color").trim();
      if(!/^#?[0-9A-Fa-f]{6}$/.test(color))return i.editReply({content:"Enter a valid six-digit hexadecimal color, such as #5865F2.",components:[],embeds:[]});
      this.store.data.customizations||={};this.store.data.customizations[i.guildId]||={};
      this.store.data.customizations[i.guildId].accent_color="#"+color.replace(/^#/,"").toUpperCase();
      this.store.save();return this.show(i,"appearance");
    }
    if(i.isModalSubmit()&&(id==="settings:filter:add-modal"||id==="settings:filter:remove-modal")){
      if(!installed(this.store,i.guildId,"Kimi Lock"))return i.editReply({content:"The Kimi Lock app is no longer added.",components:[],embeds:[]});
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
      if(!installed(this.store,i.guildId,"Kimi Lock"))return i.editReply({content:"The Kimi Lock app is no longer added.",components:[],embeds:[]});
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
        if(id===roleId&&role.position>=bot.roles.highest.position)return i.editReply({content:"Kimi must have a higher role than the configured verification roles.",components:[],embeds:[]});
      }
      if(roleId&&!bot.permissions.has(PermissionFlagsBits.ManageRoles))return i.editReply({content:"Kimi needs Manage Roles permission to grant the verified role.",components:[],embeds:[]});
      Object.assign(value,{role_id:roleId,required_role_id:requiredRoleId,review_channel_id:reviewId,min_age_days:age,thresholds:{pass:thresholds[0],review:thresholds[1]}});
      this.store.data.verification[i.guildId]=value;this.store.save();
      await this.hooks.plugins?.["Kimi Lock"]?.refreshVerification?.(i.guild);
      return i.editReply({content:"Verification settings saved. Existing verification panels have been refreshed.",components:[],embeds:[]});
    }
    if(i.isModalSubmit()&&id==="settings:welcome:modal"){
      if(!installed(this.store,i.guildId,"Welcome"))return i.editReply({content:"The Welcome app is no longer added.",components:[],embeds:[]});
      const current=this.store.data.welcome[i.guildId]||{welcome_channel_id:"",welcome_message:"Welcome {user} to {server}! You are member #{member_count}.",goodbye_channel_id:"",goodbye_message:"{username} has left {server}.",auto_role_id:""};
      const read=key=>i.fields.getTextInputValue(key).trim();
      const channelId=key=>read(key).replace(/[<#>]/g,"");
      const welcomeChannel=channelId("welcome-channel"),goodbyeChannel=channelId("goodbye-channel");
      for(const value of [welcomeChannel,goodbyeChannel])if(value&&!/^\d{15,22}$/.test(value))return i.editReply({content:"Enter a valid Discord channel ID or leave it blank.",components:[],embeds:[]});
      for(const value of [welcomeChannel,goodbyeChannel])if(value&&(!i.guild.channels.cache.has(value)||!i.guild.channels.cache.get(value).isTextBased()))return i.editReply({content:"Choose text channels from this server.",components:[],embeds:[]});
      this.store.data.welcome[i.guildId]={...current,welcome_channel_id:welcomeChannel,welcome_message:read("welcome-message")||current.welcome_message,goodbye_channel_id:goodbyeChannel,goodbye_message:read("goodbye-message")||current.goodbye_message,auto_role_id:current.auto_role_id||""};
      this.store.save();
      return i.editReply({content:"Welcome and goodbye settings saved. Configure automatic role assignment in the Auto Role app with /autorole.",components:[],embeds:[]});
    }
    if(i.isStringSelectMenu()){
      if(id==="settings:appearance-style"){
        if(!["Primary","Secondary","Success","Danger"].includes(i.values[0]))return this.show(i,"appearance");
        this.store.data.customizations||={};this.store.data.customizations[i.guildId]||={};
        this.store.data.customizations[i.guildId].button_style=i.values[0];this.store.save();
        return this.show(i,"appearance");
      }
      if(id==="settings:module-select")return this.show(i,"modules",i.values[0]);
      if(id==="settings:language-select"||id==="settings:language-select:more"){
        this.store.data.languages||={};this.store.data.languages[i.guildId]=i.values[0];this.store.save();
        return this.show(i,"language");
      }
      if(id.startsWith("settings:plugin-select:"))return this.show(i,id.split(":")[2],i.values[0]);
    }
    if(!i.isButton())return;
    if(id==="settings:filter-add"||id==="settings:filter-remove"){
      if(!installed(this.store,i.guildId,"Kimi Lock"))return respond(i,"The Kimi Lock app is no longer added.");
      const add=id==="settings:filter-add";
      const modal=new ModalBuilder().setCustomId(add?"settings:filter:add-modal":"settings:filter:remove-modal").setTitle(add?"Block a phrase":"Remove a phrase").addComponents(new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("phrase").setLabel("Word or phrase").setStyle(TextInputStyle.Short).setRequired(true).setMaxLength(100)));
      return i.showModal(modal);
    }
    if(id==="settings:home")return this.show(i,"home");
    if(id==="settings:appearance")return this.show(i,"appearance");
    if(id==="settings:appearance-color"){
      const current=this.store.data.customizations?.[i.guildId]?.accent_color||"#808080";
      const input=new TextInputBuilder().setCustomId("accent-color").setLabel("Accent color (HEX)").setPlaceholder("#5865F2").setStyle(TextInputStyle.Short).setRequired(true).setMinLength(6).setMaxLength(7).setValue(current);
      const modal=new ModalBuilder().setCustomId("settings:appearance-color-modal").setTitle("Change accent color").addComponents(new ActionRowBuilder().addComponents(input));
      return i.showModal(modal);
    }
    if(id==="settings:modules")return this.show(i,"modules");
    if(id==="settings:configure")return this.show(i,"configure");
    if(id.startsWith("settings:config:")){
      const section=id.split(":")[2];
      const plugin=section==="moderation"||section==="verification"||section==="filter"?"Kimi Lock":section==="tickets"||section==="tickets-setup"?"Support":section==="welcome"?"Welcome":section==="roles"?"Role Picker":section==="auto-role"?"Auto Role":section==="embeds"?"Embeds":"Welcome";
      if(!installed(this.store,i.guildId,plugin))return respond(i,"That app is no longer added. Reopen Kimi Settings to refresh the panel.");
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
      if(section==="roles")return respond(i,"**Role Picker**\nUse `/roles` to publish a self-service role menu.");
      if(section==="auto-role")return respond(i,"**Auto Role**\nUse `/autorole` to choose the role assigned automatically when a member joins.");
      if(section==="embeds")return respond(i,"**Embeds**\nUse `/embed-new` to create an embed, `/embed-edit` to update it, and `/embed-post` to publish it.");
      if(section==="welcome"){
        const value=this.store.data.welcome[i.guildId]||{};
        const field=(key,label,placeholder,current,style=TextInputStyle.Short)=>new TextInputBuilder().setCustomId(key).setLabel(label).setPlaceholder(placeholder).setStyle(style).setRequired(false).setMaxLength(style===TextInputStyle.Paragraph?1800:22).setValue(String(current||"").slice(0,style===TextInputStyle.Paragraph?1800:22));
        const modal=new ModalBuilder().setCustomId("settings:welcome:modal").setTitle("Welcome settings").addComponents(
          new ActionRowBuilder().addComponents(field("welcome-channel","Welcome channel ID","Channel ID",value.welcome_channel_id)),
          new ActionRowBuilder().addComponents(field("welcome-message","Welcome message","Supports {user}, {username}, {server}, {member_count}",value.welcome_message,TextInputStyle.Paragraph)),
          new ActionRowBuilder().addComponents(field("goodbye-channel","Goodbye channel ID","Channel ID",value.goodbye_channel_id)),
          new ActionRowBuilder().addComponents(field("goodbye-message","Goodbye message","Goodbye message",value.goodbye_message,TextInputStyle.Paragraph)),
        );
        return i.showModal(modal);
      }
      if(!this.hooks.openConfiguration)return i.editReply({content:"This configuration page is not available yet.",components:[],embeds:[]});
      return this.hooks.openConfiguration(i,section);
    }
    if(id==="settings:install"||id==="settings:uninstall")return this.show(i,id.slice("settings:".length));
    if(id==="settings:preferences")return this.show(i,"preferences");
    if(id==="settings:language")return this.show(i,"language");
    if(id==="settings:status")return this.show(i,"status");
    if(id==="settings:permissions")return this.show(i,"permissions");
    if(id==="settings:advanced")return this.show(i,"advanced");
    if(id.startsWith("settings:module-on:")||id.startsWith("settings:module-off:")){
      const [,action,moduleId]=id.split(":");
      const module=MODULES.find(m=>m.id===moduleId);
      if(!module)return this.show(i,"modules");
      if(!installed(this.store,i.guildId,module.plugin))return i.editReply({content:`Add the **${module.plugin}** app before enabling ${module.label}.`,embeds:[],components:[row(button("settings:modules","Back to Systems"))]});
      this.store.data.modules||={};this.store.data.modules[i.guildId]||={};
      this.store.data.modules[i.guildId][moduleId]=action==="module-on";this.store.save();
      this.logger.info(`Module ${moduleId} ${action==="module-on"?"enabled":"disabled"} for guild ${i.guildId}.`);
      return this.show(i,"modules",moduleId);
    }
    if(id.startsWith("settings:module-info:"))return this.show(i,"modules",id.split(":")[2]);
    if(id.startsWith("settings:plugin-confirm:")){
      const [, ,action,name]=id.split(":");
      if(i.guild.ownerId!==i.user.id)return i.editReply({content:"Only the server owner can add or remove apps.",embeds:[],components:[]});
      if(action==="install"){
        const result=this.manager.install(i.guildId,name);
        if(!result.ok)return i.editReply({content:result.error,embeds:[],components:[]});
        await this.hooks.syncGuildCommands?.(i.guildId);
        const plugin=this.hooks.plugins?.[name];
        if(plugin?.ready)await plugin.ready(i.guild);
        if(plugin?.onInstall)await plugin.onInstall(i.guild);
        return i.editReply({embeds:[embed("App Added",`**${name}** is now added. Its commands will be registered when Kimi next synchronizes this server.`)],components:[row(button("settings:install","Add Another"),button("settings:home","Done"))]});
      }
      const result=this.manager.uninstall(i.guildId,name);
      if(!result.ok)return i.editReply({content:result.error,embeds:[],components:[]});
      const plugin=this.hooks.plugins?.[name];
      if(plugin?.onUninstall)await plugin.onUninstall(i.guild);
      await this.hooks.syncGuildCommands?.(i.guildId);
      return i.editReply({embeds:[embed("App Removed",`**${name}** has been removed. Saved configuration and project data are preserved.`)],components:[row(button("settings:uninstall","Remove Another"),button("settings:home","Done"))]});
    }
  }
}
