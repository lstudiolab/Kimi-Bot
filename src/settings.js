import { ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder, EmbedBuilder, PermissionFlagsBits } from "discord.js";
import { GREY } from "./ui.js";
import { LIBRARIES } from "./libraries/index.js";
import { t, LOCALE_NAMES } from "./i18n.js";

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
const hasAccess = i => i.guild?.ownerId===i.user.id || i.memberPermissions?.has(PermissionFlagsBits.ManageGuild);
const installed = (store,guildId,name) => (store.data.installed_libraries[guildId]||[]).includes(name);
const enabled = (store,guildId,id) => store.data.modules?.[guildId]?.[id] !== false;
const moduleStatus = (store,guildId,module) => !installed(store,guildId,module.library) ? t(store,guildId,"missing") : enabled(store,guildId,module.id) ? t(store,guildId,"enabled") : t(store,guildId,"disabled");

export class TimiSettings {
  constructor(store,manager,logger,hooks={}){this.store=store;this.manager=manager;this.logger=logger;this.hooks=hooks;}
  async show(i,page="home",selected=""){
    if(!hasAccess(i))return i.editReply({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const guild=i.guild, id=guild.id;
    const language=this.store.data.languages?.[id]||"en-US";
    const tr=key=>t(this.store,id,key);
    if(page==="home"){
      return i.editReply({embeds:[embed(tr("title"),"Manage Timi's systems, libraries and server preferences.\n\nChoose a section below.")],components:[
        row(button("settings:modules",tr("modules")),button("settings:install",tr("install")),button("settings:uninstall",tr("uninstall"))),
        row(button("settings:language",tr("language")),button("settings:status",tr("status")),button("settings:permissions",tr("permissions"))),
        row(button("settings:advanced",tr("advanced")))
      ]});
    }
    if(page==="modules"){
      const lines=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\n");
      const options=MODULES.map(m=>({label:m.label,value:m.id,description:m.description.slice(0,100)}));
      const menu=new StringSelectMenuBuilder().setCustomId("settings:module-select").setPlaceholder(tr("choose")).addOptions(options);
      const components=[row(menu)];
      if(selected){
        const m=MODULES.find(x=>x.id===selected);
        if(m)components.push(row(button("settings:module-on:"+selected,tr("enable")),button("settings:module-off:"+selected,tr("disable")),button("settings:module-info:"+selected,tr("details"))));
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
      return i.editReply({embeds:[embed(tr("language"),`Current server language: **${LANGUAGES.find(x=>x[0]===language)?.[1]||language}**\n\nChoose from the supported Discord locale list. The preference is saved per server.`)],components:[row(first),row(second),row(button("settings:home","Back"))]});
    }
    if(page==="status"){
      const libs=Object.values(LIBRARIES).map(lib=>`**${lib.name}** — ${installed(this.store,id,lib.name)?"Installed":"Not installed"}`).join("\n");
      const mods=MODULES.map(m=>`**${m.label}** — ${moduleStatus(this.store,id,m)}`).join("\n");
      return i.editReply({embeds:[embed(tr("status"),`**Libraries**\n${libs}\n\n**Modules**\n${mods}\n\n**Language**\n${language}`)],components:[row(button("settings:home","Back"))]});
    }
    if(page==="permissions"){
      return i.editReply({embeds:[embed(tr("permissions"),"Only the server owner and members with Manage Server can use Timi Settings. Library installation and removal remain server-owner-only.")],components:[row(button("settings:home","Back"))]});
    }
    if(page==="advanced"){
      return i.editReply({embeds:[embed(tr("advanced"),"Configuration reset and backup controls are reserved for a later safe implementation. No server data is changed from this page.")],components:[row(button("settings:home","Back"))]});
    }
  }
  async handle(i){
    if(!i.inGuild())return i.editReply({content:"Use Timi Settings inside a server.",embeds:[],components:[]});
    if(!hasAccess(i))return i.editReply({content:t(this.store,i.guildId,"permissionDenied"),embeds:[],components:[]});
    const id=i.customId||"";
    if(i.isStringSelectMenu()){
      if(id==="settings:module-select")return this.show(i,"modules",i.values[0]);
      if(id==="settings:language-select"){
        this.store.data.languages||={};this.store.data.languages[i.guildId]=i.values[0];this.store.save();
        return this.show(i,"language");
      }
      if(id.startsWith("settings:library-select:"))return this.show(i,id.split(":")[2],i.values[0]);
    }
    if(!i.isButton())return;
    if(id==="settings:home")return this.show(i,"home");
    if(id==="settings:modules")return this.show(i,"modules");
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
