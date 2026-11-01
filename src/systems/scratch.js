import {
  ActionRowBuilder, AttachmentBuilder, StringSelectMenuBuilder, TextInputStyle,
  ChannelType, PermissionFlagsBits
} from "discord.js";
import { autoFixTbScript, buildTbScriptModal, compileTbScript, renderTbScript } from "../tbscript.js";
import { getStorageReport, canStoreGuildState, formatBytes } from "../subscriptions.js";
import { textInput, modal, respond, deny, requireOwner } from "../ui.js";
import { isSafeAssignableRole } from "../permissions.js";

const STARTER = [
  "panel:",
  '    title "Welcome"',
  '    description "Hello @author, welcome to @server!"',
  '    color "#808080"',
  ""
].join("\n");

const KIT = {
  panel: 'panel:\n    title "Welcome"\n    description "Hello @author!"\n    color "#808080"',
  button: 'panel:\n    title "Choose an action"\n    button "Get role" : member\n\nonclick member:\n    give role "Member"\n    reply "Role assigned."',
  ticket: 'panel:\n    title "Ticket Support"\n    description "Click below to create a private ticket."\n    color "#808080"\n    button "Open Ticket" : ticket\n\nonclick ticket:\n    create channel "ticket"\n    make private\n    allow @author\n    reply "Your ticket has been created."',
  welcome: 'on member join:\n    send #welcome "Welcome @author to @server!"\nend',
  message: 'on message create:\n    if message.content == "hello":\n        reply "Hello!"\n    end\nend'
};

const TEMPLATES = {
  ...KIT,
  verification: 'panel:\n    title "Verification"\n    description "Verify to access the server."\n    color "#808080"\n    button "Verify" : verify\n\nonclick verify:\n    give role "Verified"\n    reply "You are now verified."',
  ticket: KIT.ticket
};
const DOCUMENTATION = {
  syntax: 'TBScript uses readable statements and four-space indentation. A panel starts with panel:. Events use on member join: or on message create:. Buttons use button "Label" : id, and onclick id: defines their actions. Use end to close onclick, on, and if blocks. A panel closes automatically when the next top-level statement begins.',
  keywords: 'UI: panel, title, description, color, footer, author, image, thumbnail, url, content, field, button, ephemeral. Events: on member join, on message create, onclick. Flow: if, else, end. Actions: reply, send, create channel, make private, allow, give role.',
  actions: 'reply "text" responds to the current interaction or message. send #channel "text" sends to a server text channel. create channel "name" creates a private text channel. make private keeps the created channel hidden from @everyone. allow @author or allow "Role Name" grants access. give role "Role Name" assigns a safe, non-privileged role.',
  placeholders: 'Text placeholders: @author, @authorID, @server, @serverID, @channel, @memberCount. They are resolved from the current Discord event or interaction.',
  safety: 'TBScript is a restricted language, not JavaScript. It never evaluates source code. Channel creation starts private, role assignment checks role permissions and hierarchy, and scripts run only after an owner explicitly starts them. Event scripts remain active until stopped.'
};

export function isTrustedTbScriptAttachmentUrl(value){
  try{
    const url=new URL(value);
    return url.protocol==="https:"&&["cdn.discordapp.com","media.discordapp.net"].includes(url.hostname.toLowerCase())&&!url.username&&!url.password;
  }catch{return false;}
}
async function readTbScriptAttachment(attachment){
  if(!attachment?.name?.toLowerCase().endsWith(".tdl"))throw new Error("Attach a TbScript file with the .tdl extension.");
  if(Number(attachment.size)>64*1024)throw new Error("TbScript imports are limited to 64 KB.");
  if(!isTrustedTbScriptAttachmentUrl(attachment.url))throw new Error("TbScript files must be uploaded as Discord attachments.");
  const url=new URL(attachment.url);
  const response=await fetch(url,{signal:AbortSignal.timeout(10000),redirect:"error"});
  if(!response.ok)throw new Error("Timi could not download that attachment.");
  const declared=Number(response.headers.get("content-length")||0);
  if(declared>64*1024)throw new Error("TbScript imports are limited to 64 KB.");
  if(!response.body)throw new Error("Discord returned an empty attachment.");
  const chunks=[];let total=0;
  for await(const chunk of response.body){
    total+=chunk.length;
    if(total>64*1024)throw new Error("TbScript imports are limited to 64 KB.");
    chunks.push(Buffer.from(chunk));
  }
  try{return new TextDecoder("utf-8",{fatal:true}).decode(Buffer.concat(chunks,total));}
  catch{throw new Error("TbScript files must contain valid UTF-8 text.");}
}
function slugify(value) {
  return String(value || "").toLowerCase().trim().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24);
}
function quote(value) {
  return '"' + String(value ?? "").replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n") + '"';
}
function panelSource(title, description) {
  return "panel:\n    title " + quote(title) + "\n    description " + quote(description) + "\n    color \"#808080\"";
}
function errorsText(errors) {
  return errors.slice(0, 8).map(error => typeof error === "string"
    ? "• " + error
    : "• Line " + error.line + ", column " + error.column + ": " + error.message).join("\n");
}
function storageError(report) {
  return "This change would exceed your Timi storage allocation (" + formatBytes(report.bytes) + " / "
    + formatBytes(report.limit) + "). Remove unused saved content to free storage.";
}
function panelTarget(target) {
  return ["ticket-panel","verification-panel","moderation-panel","role-picker-panel"].includes(target);
}
function insertKitBlock(source, snippet) {
  const base=String(source||"").trim();
  const addition=String(snippet||"").trim();
  if(!base.startsWith("{")||!base.endsWith("}")||!addition.startsWith("{")||!addition.endsWith("}")) {
    throw new Error("A component can only be assembled into a complete TbScript block.");
  }
  const inner=addition.slice(1,-1).trim();
  return base.slice(0,-1).trimEnd()+"\n   "+inner.replace(/\n/g,"\n   ")+"\n}";
}
function stopRuntime(store,guildId,slug) {
  const active=store.data.developer_active[guildId]?.[slug];
  if(active) active.status="stopped";
  const project=store.data.developer_projects[guildId]?.[slug];
  if(project){project.status="saved";project.active=false;}
}

export class Scratch {
  constructor(context) {
    this.client = context.client;
    this.store = context.store;
    this.logger = context.logger;
    this.context = context;
  }

  async allowed(i) {
    return requireOwner(i);
  }

  projects(guildId) {
    this.store.data.developer_projects[guildId] ||= {};
    return this.store.data.developer_projects[guildId];
  }

  project(guildId, name) {
    return this.projects(guildId)[slugify(name)] || null;
  }

  async command(i) {
    if (!await this.allowed(i)) return;
    const name = i.commandName;

    if (name === "script") {
      const slug = slugify(i.options.getString("name"));
      if (!/^[a-z0-9][a-z0-9_-]{0,23}$/.test(slug)) return deny(i, "Project names can contain letters, numbers, underscores, and hyphens (up to 24 characters).");
      if (this.project(i.guildId, slug)) return deny(i, "That project already exists. Use /script-edit.");
      const attachment=i.options.getAttachment("file");
      if(attachment)return this.createProjectFromAttachment(i,slug,attachment);
      return i.showModal(modal("developer:editor:new:" + slug, "Create TbScript project", [
        textInput("source", "TbScript source", STARTER, TextInputStyle.Paragraph, true, 4000)
      ]));
    }
    if(name==="script-template")return this.createTemplate(i,i.options.getString("name"),i.options.getString("template"));
    if(name==="script-help")return this.docs(i,i.options.getString("topic")||"syntax");
    if(name==="script-check")return this.validate(i,i.options.getString("name"));

    if (name === "script-edit") {
      const target = i.options.getString("target");
      const attachment=i.options.getAttachment("file");
      if(attachment)return this.replaceTargetFromAttachment(i,target,attachment);
      if (target === "project") {
        const slug = slugify(i.options.getString("name"));
        const project = this.project(i.guildId, slug);
        if (!project) return deny(i, "That project does not exist. Use /scripts or /script.");
        if(Buffer.byteLength(project.source,"utf8")>3900)return deny(i,"This source is too large for a Discord editor modal. Use /script-export, edit the .tdl file, then run /script-edit with target:Project, name, and the edited file attached.");
        return i.showModal(modal("developer:editor:project:" + slug, "Edit " + project.name, [
          textInput("source", "TbScript source", project.source, TextInputStyle.Paragraph, true, 4000)
        ]));
      }
      if (panelTarget(target)) {
        const current = this.store.data.panel_scripts[i.guildId]?.[target];
        if(current&&Buffer.byteLength(current,"utf8")>3900)return deny(i,"This source is too large for a Discord editor modal. Edit a .tdl file and attach it to /script-edit with the same target.");
        const settings = target === "ticket-panel" ? this.store.ticket(i.guildId)
          : target === "verification-panel" ? this.store.verify(i.guildId) : null;
        const fallback=panelSource(settings?.panel_title||target.replace("-panel",""),settings?.panel_description||"Customize this Timi panel with TbScript.");
        return i.showModal(modal("developer:editor:panel:" + target, "Edit " + target.replace("-panel", " panel") + " code", [
          textInput("source", "TbScript source", current || fallback, TextInputStyle.Paragraph, true, 4000)
        ]));
      }
      return deny(i, "Choose project, ticket-panel, or verification-panel.");
    }

    if (name === "scripts") {
      const entries = Object.entries(this.projects(i.guildId));
      const storage = getStorageReport(this.store, i.guildId);
      const body = entries.length
        ? entries.slice(0, 20).map(([slug, p]) => "**" + p.name + "** (" + slug + ") · v" + p.version + " · " + (p.status || "saved")).join("\n")
        : "No projects saved yet. Use /script to create one.";
      return respond(i, "**Scratch projects**\n" + body + "\n\nStorage: " + formatBytes(storage.bytes) + " / " + formatBytes(storage.limit));
    }
    if (name === "script-run") return this.run(i, i.options.getString("name"));
    if (name === "script-stop") return this.stop(i, i.options.getString("name"));
    if (name === "script-delete") return this.remove(i, i.options.getString("name"));
    if (name === "script-export") return this.export(i, i.options.getString("name"));
    if (name === "script-import") return this.import(i, i.options.getAttachment("file"), i.options.getBoolean("replace") === true);
    if (name === "script-history") return this.history(i, i.options.getString("name"));
    if (name === "script-undo") return this.undo(i, i.options.getString("name"));
    if (name === "script-redo") return this.redo(i, i.options.getString("name"));
    if (name === "script-kit") return this.kit(i);
  }

  async createProjectFromAttachment(i,slug,attachment){
    let original;
    try{original=await readTbScriptAttachment(attachment);}catch(error){return deny(i,error.message);}
    const source=autoFixTbScript(original),compiled=compileTbScript(source);
    if(!compiled.ok)return deny(i,"The file contains invalid TbScript:\n"+errorsText(compiled.errors));
    return this.createProjectFromSource(i,slug,source,"attached .tdl file");
  }

  async createProjectFromSource(i,slug,source,origin="template"){
    if(this.project(i.guildId,slug))return deny(i,"That project already exists.");
    const project={id:slug,name:slug,source,version:1,status:"saved",active:false,created_at:Date.now(),updated_at:Date.now(),last_run:null};
    const projects={...this.projects(i.guildId),[slug]:project};
    const report=canStoreGuildState(this.store,i.guildId,{developer_projects:{...(this.store.data.developer_projects||{}),[i.guildId]:projects}});
    if(!report.ok)return deny(i,storageError(report));
    this.store.data.developer_projects[i.guildId]=projects;
    this.store.save();
    return respond(i,"Created **"+slug+"** from a "+origin+". It is saved but not running. Use /script-run to test it.");
  }

  async createTemplate(i,rawName,templateName){
    const slug=slugify(rawName),source=TEMPLATES[templateName];
    if(!/^[a-z0-9][a-z0-9_-]{0,23}$/.test(slug))return deny(i,"Project names can contain letters, numbers, underscores, and hyphens (up to 24 characters).");
    if(!source)return deny(i,"Unknown TbScript template.");
    const compiled=compileTbScript(source);
    if(!compiled.ok)return deny(i,"The built-in template failed validation: "+errorsText(compiled.errors));
    return this.createProjectFromSource(i,slug,source,"the "+templateName+" template");
  }

  async docs(i,topic){
    const selected=DOCUMENTATION[topic]||DOCUMENTATION.syntax;
    const title=topic.charAt(0).toUpperCase()+topic.slice(1);
    return respond(i,"**TbScript documentation — "+title+"**\n"+selected+"\n\nUse /script-kit to assemble components into a project, /script-template to start from a template, and /script-check to inspect a saved project's syntax.");
  }

  async validate(i,rawName){
    const slug=slugify(rawName),project=this.project(i.guildId,slug);
    if(!project)return deny(i,"That project does not exist.");
    const compiled=compileTbScript(project.source);
    if(!compiled.ok)return deny(i,"TbScript validation failed:\n"+errorsText(compiled.errors));
    return respond(i,"TbScript is valid. "+compiled.instructions.length+" instruction block(s) were transpiled. Project remains saved and was not run.");
  }

  async editorSubmit(i) {
    if (!await this.allowed(i)) return;
    const parts = i.customId.split(":");
    const mode = parts[2];
    const target = parts.slice(3).join(":");
    const original = i.fields.getTextInputValue("source");
    const source = autoFixTbScript(original);
    const compiled = compileTbScript(source);
    if (!compiled.ok) return deny(i, "TbScript could not be saved:\n" + errorsText(compiled.errors));
    const autoFixNote = source !== original ? " Source formatting was normalized." : "";

    if (mode === "panel") {
      if (!panelTarget(target)) return deny(i, "Unsupported panel target.");
      const scripts = { ...(this.store.data.panel_scripts[i.guildId] || {}), [target]: source };
      const report = canStoreGuildState(this.store, i.guildId, {
        panel_scripts: { ...(this.store.data.panel_scripts || {}), [i.guildId]: scripts }
      });
      if (!report.ok) return deny(i, storageError(report));
      this.store.data.panel_scripts[i.guildId] = scripts;
      this.store.save();
      await this.refreshPanel(i.guild, target);
      return respond(i, "TbScript saved and existing " + target.replace("-", " ") + " panels refreshed." + autoFixNote + " Use /script-edit to change it again.");
    }

    const slug = target;
    if (!/^[a-z0-9][a-z0-9_-]{0,23}$/.test(slug)) return deny(i, "Invalid project name.");
    const projects = { ...this.projects(i.guildId) };
    const old = projects[slug];
    if (mode === "new" && old) return deny(i, "That project already exists.");
    if (mode !== "new" && !old) return deny(i, "That project no longer exists.");

    const history = { ...(this.store.data.developer_history[i.guildId] || {}) };
    const versions = [...(history[slug] || [])];
    if (old) {
      versions.push({ version: old.version, source: old.source, saved_at: old.updated_at || Date.now() });
      history[slug] = versions.slice(-10);
    }
    projects[slug] = {
      id: old?.id || slug, name: old?.name || slug, source,
      version: (old?.version || 0) + 1, status: "saved", active: false,
      created_at: old?.created_at || Date.now(), updated_at: Date.now(), last_run: old?.last_run || null
    };
    const report = canStoreGuildState(this.store, i.guildId, {
      developer_projects: { ...(this.store.data.developer_projects || {}), [i.guildId]: projects },
      developer_history: { ...(this.store.data.developer_history || {}), [i.guildId]: history }
    });
    if (!report.ok) return deny(i, storageError(report));
    this.store.data.developer_projects[i.guildId] = projects;
    this.store.data.developer_history[i.guildId] = history;
    this.store.data.developer_redo[i.guildId] ||= {};
    delete this.store.data.developer_redo[i.guildId][slug];
    stopRuntime(this.store,i.guildId,slug);
    this.store.save();
    return respond(i, (mode === "new" ? "Project created." : "Project saved.") + autoFixNote + " It is saved but not running. Use /script-run to test it.");
  }

  async replaceTargetFromAttachment(i,target,attachment){
    let original;
    try{original=await readTbScriptAttachment(attachment);}catch(error){return deny(i,error.message);}
    const source=autoFixTbScript(original),compiled=compileTbScript(source);
    if(!compiled.ok)return deny(i,"The file contains invalid TbScript:\n"+errorsText(compiled.errors));
    if(panelTarget(target)){
      const scripts={...(this.store.data.panel_scripts[i.guildId]||{}),[target]:source};
      const report=canStoreGuildState(this.store,i.guildId,{panel_scripts:{...(this.store.data.panel_scripts||{}),[i.guildId]:scripts}});
      if(!report.ok)return deny(i,storageError(report));
      this.store.data.panel_scripts[i.guildId]=scripts;
      this.store.save();
      await this.refreshPanel(i.guild,target);
      return respond(i,"Updated the "+target.replace("-"," ")+" from the attached .tdl file. "+(source!==original?"Missing closing braces were added.":""));
    }
    if(target!=="project")return deny(i,"Choose project, ticket-panel, or verification-panel.");
    const slug=slugify(i.options.getString("name")),project=this.project(i.guildId,slug);
    if(!project)return deny(i,"That project does not exist.");
    return this.replaceProjectSource(i,slug,source,project);
  }

  async replaceProjectSource(i,slug,source,project){
    const projects={...this.projects(i.guildId)};
    const history={...(this.store.data.developer_history[i.guildId]||{})};
    history[slug]=[...(history[slug]||[]),{version:project.version,source:project.source,saved_at:project.updated_at||Date.now()}].slice(-10);
    const next={...project,source,version:project.version+1,status:"saved",active:false,updated_at:Date.now()};
    const redo={...(this.store.data.developer_redo[i.guildId]||{}),[slug]:[]};
    const report=canStoreGuildState(this.store,i.guildId,{
      developer_projects:{...(this.store.data.developer_projects||{}),[i.guildId]:{...projects,[slug]:next}},
      developer_history:{...(this.store.data.developer_history||{}),[i.guildId]:history},
      developer_redo:{...(this.store.data.developer_redo||{}),[i.guildId]:redo}
    });
    if(!report.ok)return deny(i,storageError(report));
    this.store.data.developer_projects[i.guildId]={...projects,[slug]:next};
    this.store.data.developer_history[i.guildId]=history;
    this.store.data.developer_redo[i.guildId]=redo;
    stopRuntime(this.store,i.guildId,slug);
    this.store.save();
    return respond(i,"Updated **"+project.name+"** from the attached .tdl file. It is saved but not running.");
  }

  async refreshPanel(guild, target) {
    try {
      if (target === "ticket-panel") await this.context.libraries?.Support?.refreshPanels?.(guild);
      if (target === "verification-panel") await this.context.libraries?.Foundation?.refreshVerification?.(guild);
      if (target === "moderation-panel") await this.context.libraries?.Security?.refreshPanel?.(guild);
      if (target === "role-picker-panel") await this.context.libraries?.Foundation?.refreshRolePickers?.(guild);
    } catch (error) {
      this.logger.warn("TbScript panel refresh failed:", error.message);
    }
  }


  scriptText(value, context = {}) {
    const user=context.user||context.member?.user||context.member||context.message?.author;
    const guild=context.guild||context.message?.guild||context.member?.guild;
    const channel=context.channel||context.message?.channel;
    const values={
      "@authorID":user?.id||"",
      "@author":user?.id?"<@"+user.id+">":user?.username||user?.displayName||"member",
      "@serverID":guild?.id||"",
      "@server":guild?.name||"",
      "@channel":channel?.id?"<#"+channel.id+">":channel?.name||"",
      "@memberCount":String(guild?.memberCount??"")
    };
    return String(value??"").replace(/@authorID|@author|@serverID|@server|@channel|@memberCount/g,key=>values[key]??key);
  }

  scriptCondition(condition, context = {}) {
    const source=String(condition||"").trim();
    const user=context.user||context.member?.user||context.member||context.message?.author;
    const member=context.member||context.message?.member;
    const message=context.message;
    const guild=context.guild||message?.guild||member?.guild;
    const properties={
      "true":true,"false":false,
      "author.is_admin":Boolean(member?.permissions?.has?.(PermissionFlagsBits.ManageGuild)),
      "author.is_owner":Boolean(guild?.ownerId&&user?.id===guild.ownerId),
      "author.bot":Boolean(user?.bot),
      "member.is_admin":Boolean(member?.permissions?.has?.(PermissionFlagsBits.ManageGuild)),
      "message.content":String(message?.content||"")
    };
    const comparison=source.match(/^(message\.content|author\.id|author\.is_admin|author\.is_owner|author\.bot|member\.is_admin)\s*(==|!=)\s*("(?:\\.|[^"\\])*"|true|false|[a-zA-Z0-9_-]+)$/);
    if(comparison){
      let expected=comparison[3];
      if(expected.startsWith('"')){try{expected=JSON.parse(expected);}catch{return false;}}
      else if(expected==="true")expected=true;
      else if(expected==="false")expected=false;
      const actual=comparison[1]==="author.id"?String(user?.id||""):properties[comparison[1]];
      return comparison[2]==="=="?actual===expected:actual!==expected;
    }
    return Boolean(properties[source]);
  }

  async executeActions(interaction, actions, context = {}) {
    const state={...context,guild:context.guild||interaction?.guild||context.message?.guild,
      user:context.user||interaction?.user||context.member?.user||context.message?.author,
      member:context.member||interaction?.member||context.message?.member,
      channel:context.channel||interaction?.channel||context.message?.channel,
      interaction,lastChannel:null,replied:false};
    for(const action of actions||[]){
      if(action.type==="if"){
        const branch=this.scriptCondition(action.condition,state)?action.then:action.else;
        await this.executeActions(interaction,branch,{...state,lastChannel:state.lastChannel});
        continue;
      }
      if(action.type==="create_channel"){
        const raw=this.scriptText(action.args[0],state).replace(/^#/, "");
        const name=slugify(raw)||"ticket";
        const guild=state.guild;
        if(!guild)throw new Error("A server is required to create a channel.");
        const bot=await guild.members.fetchMe();
        if(!bot.permissions.has(PermissionFlagsBits.ManageChannels))throw new Error("Timi needs Manage Channels to create a private channel.");
        const overwrites=[
          {id:guild.roles.everyone.id,deny:[PermissionFlagsBits.ViewChannel]},
          {id:bot.id,allow:[PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages,PermissionFlagsBits.ReadMessageHistory,PermissionFlagsBits.ManageChannels]}
        ];
        if(state.user?.id)overwrites.push({id:state.user.id,allow:[PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages,PermissionFlagsBits.ReadMessageHistory]});
        state.lastChannel=await guild.channels.create({name,type:ChannelType.GuildText,permissionOverwrites:overwrites,reason:"Created by a Timi TBScript"});
        continue;
      }
      if(action.type==="make_private"){
        if(!state.lastChannel)throw new Error("make private must follow create channel.");
        await state.lastChannel.permissionOverwrites.edit(state.guild.roles.everyone.id,{ViewChannel:false});
        continue;
      }
      if(action.type==="allow"){
        if(!state.lastChannel)throw new Error("allow must follow create channel.");
        const target=String(action.args[0]||"");
        if(target==="@author"||target==="author"){
          if(!state.user?.id)throw new Error("There is no author to grant access to.");
          await state.lastChannel.permissionOverwrites.edit(state.user.id,{ViewChannel:true,SendMessages:true,ReadMessageHistory:true});
        }else{
          const roleId=target.match(/^<@&(\d+)>$/)?.[1]||target;
          const role=state.guild.roles.cache.find(item=>item.id===roleId||item.name.toLowerCase()===target.replace(/^@/,"").toLowerCase());
          if(!role)throw new Error("The requested access role could not be found.");
          await state.lastChannel.permissionOverwrites.edit(role.id,{ViewChannel:true,SendMessages:true,ReadMessageHistory:true});
        }
        continue;
      }
      if(action.type==="give_role"||action.type==="remove_role"){
        const target=String(action.args[0]||"");
        const roleId=target.match(/^<@&(\d+)>$/)?.[1]||target;
        const role=state.guild?.roles.cache.find(item=>item.id===roleId||item.name.toLowerCase()===target.toLowerCase());
        if(!isSafeAssignableRole(role,state.guild?.id))throw new Error("The configured role is missing or has privileged permissions.");
        const bot=await state.guild.members.fetchMe();
        if(!bot.permissions.has(PermissionFlagsBits.ManageRoles)||role.position>=bot.roles.highest.position)throw new Error("Timi cannot manage that role. Check Manage Roles and role hierarchy.");
        const member=state.member?.roles?state.member:await state.guild.members.fetch(state.user.id);
        if(action.type==="give_role")await member.roles.add(role,"TBScript role action");
        else await member.roles.remove(role,"TBScript role action");
        continue;
      }
      if(action.type==="send"){
        const destination=String(action.args[0]||"");
        const channelId=destination.match(/^<#(\d+)>$/)?.[1]||destination.replace(/^#/,"");
        let target=state.guild?.channels.cache.get(channelId)||null;
        if(!target)target=state.guild?.channels.cache.find(item=>item.name?.toLowerCase()===channelId.toLowerCase())||null;
        if(!target&&/^\d{17,20}$/.test(channelId))target=await state.guild.channels.fetch(channelId).catch(()=>null);
        if(!target?.isTextBased?.())throw new Error("The send destination is not a text channel.");
        await target.send({content:this.scriptText(action.args[1],state).slice(0,2000),allowedMentions:{parse:[]}});
        continue;
      }
      if(action.type==="reply"){
        const text=this.scriptText(action.args[0],state).slice(0,2000);
        if(interaction&&!state.replied){await respond(interaction,text);state.replied=true;}
        else if(state.message)await state.message.reply({content:text,allowedMentions:{parse:[]}});
        else if(state.channel?.isTextBased?.())await state.channel.send({content:text,allowedMentions:{parse:[]}});
      }
    }
    return state;
  }

  async runEvent(guildId, eventName, context) {
    const active=this.store.data.developer_active?.[guildId]||{};
    for(const [slug,record] of Object.entries(active)){
      if(record.status!=="running")continue;
      const project=this.project(guildId,slug);
      if(!project)continue;
      const compiled=compileTbScript(project.source);
      if(!compiled.ok)continue;
      for(const event of compiled.output.handlers?.events||[]){
        if(event.event!==eventName)continue;
        try{await this.executeActions(null,event.actions,{...context,guild:context.guild});}
        catch(error){this.logger.warn("TBScript event failed ("+slug+"):",error.message);}
      }
    }
  }

  async onMessageCreate(message) {
    if(!message?.guild||message.author?.bot)return;
    return this.runEvent(message.guild.id,"message create",{guild:message.guild,message,user:message.author,member:message.member,channel:message.channel});
  }

  async onMemberJoin(member) {
    if(!member?.guild)return;
    return this.runEvent(member.guild.id,"member join",{guild:member.guild,member,user:member.user,channel:null});
  }

  async run(i, rawName) {
    const slug = slugify(rawName);
    const project = this.project(i.guildId, slug);
    if (!project) return deny(i, "That project does not exist.");
    const compiled = compileTbScript(project.source);
    if (!compiled.ok) return deny(i, "This saved project has errors:\n" + errorsText(compiled.errors));
    const rendered = renderTbScript(compiled, { scope: "p-" + slug, context: { guild: i.guild, user: i.user, member: i.member, channel: i.channel, client: this.client } });
    let message=null;
    const hasPanel=Boolean(rendered.content||rendered.embeds.length||rendered.components.length);
    if(hasPanel&&rendered.ephemeral){
      message=await i.editReply({content:rendered.content||null,embeds:rendered.embeds,components:rendered.components,allowedMentions:{parse:[]}});
    }else if(hasPanel){
      message=await i.channel.send({content:rendered.content,embeds:rendered.embeds,components:rendered.components,allowedMentions:{parse:[]}});
      await respond(i,"Project "+project.name+" is running. Use /script-stop to disable its controls and event handlers.");
    }else{
      await respond(i,"Project "+project.name+" is running. Its event handlers are active. Use /script-stop to disable them.");
    }
    this.store.data.developer_active[i.guildId] ||= {};
    this.store.data.developer_active[i.guildId][slug] = {
      status:"running",channel_id:i.channelId,message_id:message?.id||null,
      ephemeral:rendered.ephemeral,started_at:Date.now()
    };
    project.status = "running";
    project.active = true;
    project.last_run = Date.now();
    this.store.save();
  }

  async stop(i, rawName) {
    const slug = slugify(rawName);
    const active = this.store.data.developer_active[i.guildId]?.[slug];
    if (!active || active.status !== "running") return deny(i, "That project is not currently running.");
    active.status = "stopped";
    const project = this.project(i.guildId, slug);
    if (project) { project.status = "saved"; project.active = false; }
    if (!active.ephemeral && active.message_id) {
      const channel = await i.guild.channels.fetch(active.channel_id).catch(() => null);
      const message = await channel?.messages.fetch(active.message_id).catch(() => null);
      await message?.edit({ components: [] }).catch(() => {});
    }
    this.store.save();
    return respond(i, "Project stopped. Its controls are now inactive.");
  }

  async remove(i, rawName) {
    const slug = slugify(rawName);
    const projects = { ...this.projects(i.guildId) };
    if (!projects[slug]) return deny(i, "That project does not exist.");
    delete projects[slug];
    const history = { ...(this.store.data.developer_history[i.guildId] || {}) };
    delete history[slug];
    const redo={...(this.store.data.developer_redo[i.guildId]||{})};delete redo[slug];
    this.store.data.developer_projects[i.guildId] = projects;
    this.store.data.developer_history[i.guildId] = history;
    this.store.data.developer_redo[i.guildId] = redo;
    if (this.store.data.developer_active[i.guildId]) delete this.store.data.developer_active[i.guildId][slug];
    this.store.save();
    return respond(i, "Project and its saved version history were deleted.");
  }

  async export(i, rawName) {
    const slug = slugify(rawName);
    const project = this.project(i.guildId, slug);
    if (!project) return deny(i, "That project does not exist.");
    const file = new AttachmentBuilder(Buffer.from(project.source, "utf8"), { name: slug + ".tdl" });
    return i.editReply({ content: "Exported " + project.name + " as a TbScript file.", files: [file], allowedMentions: { parse: [] } });
  }

  async import(i, attachment, replaceExisting = false) {
    if (!attachment) return deny(i, "Attach a .tdl file to import.");
    let source;
    try{source=await readTbScriptAttachment(attachment);}catch(error){return deny(i,error.message);}
    const fixed = autoFixTbScript(source);
    const compiled = compileTbScript(fixed);
    if (!compiled.ok) return deny(i, "Import failed:\n" + errorsText(compiled.errors));
    const slug = slugify(attachment.name.replace(/\.tdl$/i, "")) || "imported-project";
    const existing=this.project(i.guildId,slug);
    if(existing&&!replaceExisting)return deny(i,"A project named "+slug+" already exists. Set replace:true to update it and preserve version history.");
    if(existing)return this.replaceProjectSource(i,slug,fixed,existing);
    const projects = { ...this.projects(i.guildId), [slug]: {
      id: slug, name: slug, source: fixed, version: 1, status: "saved", active: false,
      created_at: Date.now(), updated_at: Date.now(), last_run: null
    } };
    const report = canStoreGuildState(this.store, i.guildId, {
      developer_projects: { ...(this.store.data.developer_projects || {}), [i.guildId]: projects }
    });
    if (!report.ok) return deny(i, storageError(report));
    this.store.data.developer_projects[i.guildId] = projects;
    this.store.save();
    return respond(i, "Imported " + slug + ". It is saved but not running.");
  }

  async history(i, rawName) {
    const slug = slugify(rawName);
    const project=this.project(i.guildId,slug);
    if(!project)return deny(i,"That project does not exist.");
    const entries=this.store.data.developer_history[i.guildId]?.[slug]||[];
    const lines=["**Current version "+project.version+"** · "+new Date(project.updated_at).toISOString(),
      ...entries.slice(-10).reverse().map(entry=>"Version "+entry.version+" · "+new Date(entry.saved_at).toISOString())];
    return respond(i,"**Version history: "+slug+"**\n"+lines.join("\n"));
  }

  async undo(i,rawName){
    const slug=slugify(rawName),project=this.project(i.guildId,slug);
    if(!project)return deny(i,"That project does not exist.");
    const history={...(this.store.data.developer_history[i.guildId]||{})};
    const entries=[...(history[slug]||[])];
    if(!entries.length)return deny(i,"There is no saved change to undo.");
    const previous=entries.pop();
    const redo={...(this.store.data.developer_redo[i.guildId]||{})};
    const redoEntries=[...(redo[slug]||[]),{version:project.version,source:project.source,saved_at:Date.now()}].slice(-10);
    const next={...project,source:previous.source,version:project.version+1,status:"saved",active:false,updated_at:Date.now()};
    const report=canStoreGuildState(this.store,i.guildId,{
      developer_projects:{...(this.store.data.developer_projects||{}),[i.guildId]:{...this.projects(i.guildId),[slug]:next}},
      developer_history:{...(this.store.data.developer_history||{}),[i.guildId]:{...history,[slug]:entries}},
      developer_redo:{...(this.store.data.developer_redo||{}),[i.guildId]:{...redo,[slug]:redoEntries}}
    });
    if(!report.ok)return deny(i,storageError(report));
    history[slug]=entries;redo[slug]=redoEntries;
    this.store.data.developer_history[i.guildId]=history;
    this.store.data.developer_redo[i.guildId]=redo;
    this.projects(i.guildId)[slug]=next;stopRuntime(this.store,i.guildId,slug);
    this.store.save();
    return respond(i,"Undid the last saved change. Project is saved and not running.");
  }

  async redo(i,rawName){
    const slug=slugify(rawName),project=this.project(i.guildId,slug);
    if(!project)return deny(i,"That project does not exist.");
    const redo={...(this.store.data.developer_redo[i.guildId]||{})};
    const entries=[...(redo[slug]||[])];
    if(!entries.length)return deny(i,"There is no undone change to redo.");
    const nextVersion=entries.pop();
    const history={...(this.store.data.developer_history[i.guildId]||{})};
    const previous=[...(history[slug]||[]),{version:project.version,source:project.source,saved_at:Date.now()}].slice(-10);
    const next={...project,source:nextVersion.source,version:project.version+1,status:"saved",active:false,updated_at:Date.now()};
    const report=canStoreGuildState(this.store,i.guildId,{
      developer_projects:{...(this.store.data.developer_projects||{}),[i.guildId]:{...this.projects(i.guildId),[slug]:next}},
      developer_history:{...(this.store.data.developer_history||{}),[i.guildId]:{...history,[slug]:previous}},
      developer_redo:{...(this.store.data.developer_redo||{}),[i.guildId]:{...redo,[slug]:entries}}
    });
    if(!report.ok)return deny(i,storageError(report));
    history[slug]=previous;redo[slug]=entries;
    this.store.data.developer_history[i.guildId]=history;
    this.store.data.developer_redo[i.guildId]=redo;
    this.projects(i.guildId)[slug]=next;stopRuntime(this.store,i.guildId,slug);
    this.store.save();
    return respond(i,"Redid the saved change. Project is saved and not running.");
  }

  async kit(i) {
    const menu = new StringSelectMenuBuilder().setCustomId("developer:kit")
      .setPlaceholder("Choose a component to assemble").setMinValues(1).setMaxValues(1)
      .addOptions(
        { label: "Embed", value: "embed", description: "Title, description, footer, author and color" },
        { label: "Button and role action", value: "button", description: "Add a button and assign a role" },
        { label: "Modal", value: "modal", description: "Build an input form using nested blocks" },
        { label: "Private response", value: "visibility", description: "Make output visible only to the runner" },
        { label: "Image", value: "image", description: "Add an image to an embed" }
      );
    return respond(i, "**TbScript component kit**\nChoose a component, then choose the project where it should be assembled. The generated code stays editable.", [new ActionRowBuilder().addComponents(menu)]);
  }

  async assembleKit(i,key,slug){
    if(!await this.allowed(i))return;
    const snippet=KIT[key];
    const project=this.project(i.guildId,slug);
    if(!snippet||!project)return deny(i,"The selected component or project is no longer available.");
    const source=insertKitBlock(project.source,snippet);
    const compiled=compileTbScript(source);
    if(!compiled.ok)return deny(i,"This component cannot be assembled into the current file:\n"+errorsText(compiled.errors));
    const projects={...this.projects(i.guildId)};
    const history={...(this.store.data.developer_history[i.guildId]||{})};
    const entries=[...(history[slug]||[]),{version:project.version,source:project.source,saved_at:Date.now()}].slice(-10);
    const next={...project,source,version:project.version+1,status:"saved",active:false,updated_at:Date.now()};
    const redo={...(this.store.data.developer_redo[i.guildId]||{}),[slug]:[]};
    const report=canStoreGuildState(this.store,i.guildId,{
      developer_projects:{...(this.store.data.developer_projects||{}),[i.guildId]:{...projects,[slug]:next}},
      developer_history:{...(this.store.data.developer_history||{}),[i.guildId]:{...history,[slug]:entries}},
      developer_redo:{...(this.store.data.developer_redo||{}),[i.guildId]:redo}
    });
    if(!report.ok)return deny(i,storageError(report));
    this.store.data.developer_projects[i.guildId]={...projects,[slug]:next};
    this.store.data.developer_history[i.guildId]={...history,[slug]:entries};
    this.store.data.developer_redo[i.guildId]=redo;
    stopRuntime(this.store,i.guildId,slug);
    this.store.save();
    return respond(i,"The "+key+" component was assembled into **"+project.name+"**. Version "+next.version+" is saved but not running.");
  }

  async handleScriptButton(i) {
    const match = i.customId.match(/^tbs:(ticket|verification|moderation|role-picker|p-[a-z0-9_-]{1,24}):(\d+)$/i);
    if (!match) return deny(i, "This TbScript control is invalid.");
    const scope = match[1], index = Number(match[2]);
    let source = "";
    if (scope.startsWith("p-")) {
      const slug = scope.slice(2);
      const active = this.store.data.developer_active[i.guildId]?.[slug];
      const project = this.project(i.guildId, slug);
      if (!project || active?.status !== "running" || active.message_id !== i.message.id) return deny(i, "This project control is no longer active.");
      source = project.source;
    } else {
      if (!(this.store.data.installed_libraries[i.guildId] || []).includes("Scratch")) return deny(i, "The Scratch library is not active.");
      const panels = scope === "ticket" ? this.store.ticket(i.guildId).published_panels
        : scope === "verification" ? this.store.verify(i.guildId).published_panels
        : scope === "moderation" ? [{message_id:this.store.mods(i.guildId).panel_message_id}]
        : Object.values(this.store.data.role_picker_menus||{}).filter(menu=>menu.guild_id===i.guildId);
      if (!panels.some(panel => panel.message_id === i.message.id)) return deny(i, "This panel control is no longer active.");
      source = this.store.data.panel_scripts[i.guildId]?.[scope + "-panel"] || "";
    }
    const compiled = compileTbScript(source);
    if (!compiled.ok) return deny(i, "This saved TbScript is no longer valid.");
    const action = compiled.output.buttons[index]?.action;
    if (!action) return deny(i, "No action is configured for this button.");
    if(Array.isArray(action)){
      await this.executeActions(i,action,{guild:i.guild,user:i.user,member:i.member,channel:i.channel});
      return;
    }
    const role = i.guild.roles.cache.find(candidate => candidate.id === action.role || candidate.name.toLowerCase() === action.role.toLowerCase());
    if (!isSafeAssignableRole(role,i.guild.id)) return deny(i, "The configured role is missing or has administrator, moderation, or channel-management permissions.");
    const member = await i.guild.members.fetch(i.user.id);
    if (member.roles.cache.has(role.id)) return deny(i, "You already have that role.");
    const bot = await i.guild.members.fetchMe();
    if (!bot.permissions.has("ManageRoles") || role.position >= bot.roles.highest.position) return deny(i, "Timi cannot assign that role. Check Manage Roles and role hierarchy.");
    await member.roles.add(role, "TbScript button action");
    return respond(i, "Role " + role.name + " assigned.");
  }

  async modalButton(i) {
    const scope = i.customId.slice(4);
    let source = "";
    if (scope.startsWith("p-")) {
      const slug = scope.slice(2);
      const project = this.project(i.guildId, slug);
      const active = this.store.data.developer_active[i.guildId]?.[slug];
      if (!project || active?.status !== "running" || active.message_id !== i.message.id) return deny(i, "This project form is no longer active.");
      source = project.source;
    } else {
      const target = ["ticket","verification","moderation","role-picker"].includes(scope) ? scope + "-panel" : "";
      if (!target || !(this.store.data.installed_libraries[i.guildId] || []).includes("Scratch")) return deny(i, "This panel form is no longer active.");
      const panels = scope === "ticket" ? this.store.ticket(i.guildId).published_panels
        : scope === "verification" ? this.store.verify(i.guildId).published_panels
        : scope === "moderation" ? [{message_id:this.store.mods(i.guildId).panel_message_id}]
        : Object.values(this.store.data.role_picker_menus||{}).filter(menu=>menu.guild_id===i.guildId);
      if (!panels.some(panel => panel.message_id === i.message.id)) return deny(i, "This panel form is no longer active.");
      source = this.store.data.panel_scripts[i.guildId]?.[target] || "";
    }
    const compiled = compileTbScript(source);
    if (!compiled.ok || !compiled.output.modal) return deny(i, "This TbScript form is invalid.");
    return i.showModal(buildTbScriptModal(compiled, "tbm-submit:" + scope));
  }

  async handleInteraction(i) {
    if (i.isChatInputCommand()) return this.command(i);
    if (i.isButton() && i.customId.startsWith("tbs:")) return this.handleScriptButton(i);
    if (i.isButton() && i.customId.startsWith("tbm:")) return this.modalButton(i);
    if (i.isModalSubmit() && i.customId.startsWith("tbm-submit:")) {
      const values = i.fields.fields.map((field, index) => "• Input " + (index + 1) + ": " + (field.value || "—"));
      return respond(i, "Form submitted.\n" + values.join("\n"));
    }
    if (i.isModalSubmit() && i.customId.startsWith("developer:editor:")) return this.editorSubmit(i);
    if (i.isStringSelectMenu() && i.customId === "developer:kit") {
      const key=i.values[0];
      const projects=Object.entries(this.projects(i.guildId));
      if(!KIT[key])return deny(i,"Unknown component.");
      if(!projects.length){
        const fence=String.fromCharCode(96).repeat(3);
        return respond(i,"Create a project with /script first. Component source:\n"+fence+"text\n"+KIT[key]+"\n"+fence);
      }
      const menu=new StringSelectMenuBuilder().setCustomId("developer:kit-project:"+key)
        .setPlaceholder("Choose a project").setMinValues(1).setMaxValues(1)
        .addOptions(projects.slice(0,25).map(([slug,p])=>({label:p.name.slice(0,100),value:slug,description:"Version "+p.version+" · "+(p.status||"saved")})));
      return respond(i,"Select the project that should receive this component.",[new ActionRowBuilder().addComponents(menu)]);
    }
    if(i.isStringSelectMenu()&&i.customId.startsWith("developer:kit-project:")){
      const key=i.customId.slice("developer:kit-project:".length);
      return this.assembleKit(i,key,i.values[0]);
    }
  }

  async onInstall(guild) {
    for(const target of ["ticket-panel","verification-panel","moderation-panel","role-picker-panel"]) {
      await this.refreshPanel(guild,target);
    }
  }

  async onUninstall(guild) {
    for(const target of ["ticket-panel","verification-panel","moderation-panel","role-picker-panel"]) {
      await this.refreshPanel(guild,target);
    }
  }
}

export function createScratchLibrary(context) {
  const scratch = new Scratch(context);
  return {
    async handleInteraction(i) { return scratch.handleInteraction(i); },
    async onInstall(guild) { return scratch.onInstall(guild); },
    async onUninstall(guild) { return scratch.onUninstall(guild); }
  };
}
