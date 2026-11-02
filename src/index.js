import { Client, Events, GatewayIntentBits, Partials, REST, Routes, PermissionFlagsBits, ActionRowBuilder, ModalBuilder, TextInputBuilder, TextInputStyle } from "discord.js";
import { loadConfig, createLogger } from "./config.js";
import { startDashboardServer } from "./dashboard.js";
import { commandsForPlugins, pluginCommandsForPlugins, coreCommandData, pluginForCommand } from "./commands.js";
import { Store } from "./store.js";
import { AuthStore } from "./auth-store.js";
import { PluginManager } from "./plugin-manager.js";
import { PLUGINS } from "./plugins/index.js";
import { createFoundationCore } from "./plugins/Foundation/index.js";
import { startWorking, respond, finishWorking } from "./ui.js";
import { pluginForComponent } from "./component-routing.js";
import { getStorageReport, formatBytes } from "./subscriptions.js";
import { KimiSettings } from "./settings.js";
import { translatePayload } from "./i18n.js";
import { PerformanceMonitor } from "./performance.js";
import { createRuntimeServices } from "./services/runtime.js";
import { AutomationEngine } from "./automations/engine.js";
import { GuardRateLimiter } from "./systems/guard.js";
const config=loadConfig(),logger=createLogger(config.logLevel),store=new Store(config.dataDir,logger),authStore=new AuthStore(config.dataDir,logger),guard=new GuardRateLimiter(store);
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildModeration,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent],partials:[Partials.Channel,Partials.Message,Partials.GuildMember]});
const services=createRuntimeServices({logger});
const automationEngine=new AutomationEngine({client,store,logger,services});
const manager=new PluginManager(store,logger),context={client,store,logger,services};
const performanceMonitor=new PerformanceMonitor(logger);
performanceMonitor.start();
const moduleEnabled=(guildId,moduleId)=>store.data.modules?.[guildId]?.[moduleId]!==false;
function recordAnalytics(guildId,metric,commandName=""){
 if(!guildId)return;
 const day=new Date().toISOString().slice(0,10);
 const all=store.data.analytics_requests||(store.data.analytics_requests={});
 const days=all[guildId]||(all[guildId]={});
 const row=days[day]||(days[day]={requests:0,commands:0,components:0,messages:0,joins:0,leaves:0,commandCounts:{}});
 if(metric==="request"){row.requests++;if(commandName){row.commands++;row.commandCounts[commandName]=(row.commandCounts[commandName]||0)+1;}else row.components++;}
 else if(Object.hasOwn(row,metric))row[metric]++;
 for(const key of Object.keys(days))if(Date.now()-Date.parse(key+"T00:00:00Z")>90*86400000)delete days[key];
 store.queueSave();
}
const commandModule={
 "verify":"verification","verify-config":"verification","filter":"moderation","security":"protection","moderation":"moderation","kimi-channel":"setup","setup":"setup","welcome":"welcome","autorole":"auto_role","tickets":"tickets","ticket-config":"tickets",
 "roles":"roles","embed-new":"embeds","embed-edit":"embeds","embed-post":"embeds",
 "ticket-panel":"tickets"
};
const componentModule=id=>id.startsWith("modpanel:")?"moderation":id.startsWith("verify:")?"verification":id.startsWith("botguard:")?"protection":id.startsWith("ticket:")?"tickets":id.startsWith("rolepicker:")?"roles":id.startsWith("embed:")?"embeds":null;
const foundation=createFoundationCore(context);context.foundation=foundation;
const plugins=Object.fromEntries(Object.entries(PLUGINS).map(([name,definition])=>[name,definition.create(context)]));
context.plugins=plugins;
const rest=new REST({version:"10"}).setToken(config.token);
async function syncGlobalCommands(){
 const registered=await rest.put(Routes.applicationCommands(config.clientId),{body:coreCommandData});
 logger.info(`Synced ${registered.length} Kimi core slash commands globally.`);
}
async function syncGuildCommands(guildId){
 const installed=store.data.installed_plugins[guildId]||[];
 const body=pluginCommandsForPlugins(installed);
 const route=Routes.applicationGuildCommands(config.clientId,guildId);
 const registered=await rest.put(route,{body});
 logger.info(`Synced ${registered.length} slash commands for guild ${guildId}.`);
 return registered;
}
function opensModal(i){
 if(i.isChatInputCommand()){
  return ["embed-new","web-token"].includes(i.commandName);
 }
 if(i.isStringSelectMenu?.()&&(i.customId==="automation:action"||i.customId==="automation:condition"))return true;
 if(!i.isButton())return false;
 const id=i.customId;
 return id==="settings:config:welcome"||id==="settings:config:verification"||id==="settings:filter-add"||id==="settings:filter-remove"||id==="settings:appearance-color"||id==="rolepicker:start"||id==="ticket:wizard-start"||id==="ticket:wizard-continue"||id.startsWith("ticket:edit-")||id==="modpanel:sanction"||id==="modpanel:duration"||id==="modpanel:max-count"||id.startsWith("embed:");
}
const openConfiguration=async(i,section)=>{
  const names={moderation:"moderation",tickets:"ticket-config","tickets-setup":"tickets",setup:"setup"};
  const commandName=names[section];
  const plugin=section==="moderation"?"Kimi Lock":section==="tickets"||section==="tickets-setup"?"Support":section==="roles"?"Role Picker":section==="auto-role"?"Auto Role":section==="embeds"?"Embeds":"Welcome";
  if(!commandName||!plugins[plugin])return respond(i,"This configuration section is not available.");
  const options={
   getRole:()=>null,getChannel:()=>null,getString:()=>null,getInteger:()=>null,getBoolean:()=>null,
   getAttachment:()=>null
  };
  const proxy=new Proxy(i,{get(target,key,receiver){
   if(key==="commandName")return commandName;
   if(key==="options")return options;
   if(key==="isChatInputCommand")return ()=>true;
   return Reflect.get(target,key,receiver);
  }});
  return plugins[plugin].handleInteraction(proxy);
 };
const settings=new KimiSettings(store,manager,logger,{syncGuildCommands,plugins,openConfiguration});
async function showInstallAnimation(interaction,moduleName){
 const frames=[
  {bar:"░░░░░░░░░░",percent:0,status:"Preparing app"},
  {bar:"█░░░░░░░░░",percent:10,status:"Loading app"},
  {bar:"██░░░░░░░░",percent:20,status:"Checking app identity"},
  {bar:"███░░░░░░░",percent:30,status:"Checking module structure"},
  {bar:"████░░░░░░",percent:40,status:"Preparing app systems"},
  {bar:"█████░░░░░",percent:50,status:"Listing slash commands"},
  {bar:"██████░░░░",percent:60,status:"Checking slash commands"},
  {bar:"███████░░░",percent:70,status:"Publishing commands"},
  {bar:"████████░░",percent:80,status:"Activating module"},
  {bar:"█████████░",percent:90,status:"Checking module status"},
  {bar:"██████████",percent:100,status:"Installation completed"}
 ];
 for(const frame of frames){
  await interaction.editReply({
   content:"**Adding "+moduleName+"**\\n\`"+frame.bar+"\` "+frame.percent+"%\\n"+frame.status,
   components:[],embeds:[],allowedMentions:{parse:[]}
  });
  if(frame.percent!==100)await new Promise(resolve=>setTimeout(resolve,120));
 }
}
function allowSystemTrigger(guildId){
 const result=guard.consume(guildId,client.user.id,"bot");
 if(!result.allowed)logger.debug("Kimi Guard paused a system trigger while its activity tokens regenerate in server "+guildId+".");
 return result.allowed;
}
async function restrictBot(member,reason="Kimi Guard bot activity limit exceeded"){
 const guild=member.guild;
 member=await guild.members.fetch({user:member.id,force:true}).catch(()=>null);
 if(!member||!member.user.bot)return null;
 const guardState=store.data.guard_state[guild.id];
 if(!guardState.incidents||typeof guardState.incidents!=="object"||Array.isArray(guardState.incidents))guardState.incidents={};
 const incidents=guardState.incidents;
 for(const [id,value] of Object.entries(incidents))if(!value||typeof value!=="object"||!/^\d{15,22}$/.test(String(value.bot_id||id)))delete incidents[id];
 if(["restricted","kept","review_required"].includes(incidents[member.id]?.status))return incidents[member.id];
 const terminal=Object.entries(incidents).filter(([,value])=>!["restricted","kept","review_required"].includes(value.status)).sort((a,b)=>(a[1].reviewed_at||a[1].created_at||0)-(b[1].reviewed_at||b[1].created_at||0));
 while(Object.keys(incidents).length>=100&&terminal.length){const [oldestId]=terminal.shift();delete incidents[oldestId];}
 if(Object.keys(incidents).length>=100){logger.error("Kimi Guard incident history is full in server "+guild.id+"; review existing incidents before new bot containment.");return null;}
 const originalRoles=member.roles.cache.filter(role=>role.id!==guild.id&&!role.managed).map(role=>role.id);
 const editable=member.roles.cache.filter(role=>role.id!==guild.id&&!role.managed&&role.editable).map(role=>role.id);
 const incident=incidents[member.id]={bot_id:member.id,bot_name:member.user.username,owner_id:guild.ownerId,
  status:"review_required",reason,created_at:Date.now(),original_roles:originalRoles,removed_roles:[],timeout_applied:false,original_timeout_until:member.communicationDisabledUntilTimestamp||null};
 try{if(editable.length){await member.roles.remove(editable,reason);incident.removed_roles=editable;}}catch(error){logger.warn("Kimi Guard could not remove every role from bot "+member.id+":",error.message);}
 try{await member.timeout(28*24*60*60*1000,reason);incident.timeout_applied=true;incident.timeout_until=Date.now()+28*24*60*60*1000;}catch(error){logger.info("Discord did not allow a timeout for bot "+member.id+"; role restriction remains the fallback:",error.message);}
 incident.status=incident.removed_roles.length||incident.timeout_applied?"restricted":"review_required";
 store.queueSave();
 logger.warn("Kimi Guard "+incident.status+" for bot "+member.id+" in server "+guild.id+" after its activity bucket was exhausted.");
 const owner=await client.users.fetch(guild.ownerId).catch(()=>null);
 if(owner)await owner.send("Kimi Guard detected the bot **"+member.user.username+"** exhausting its activity limit in **"+guild.name+"**. "+(incident.status==="restricted"?"Kimi removed "+incident.removed_roles.length+" manageable role(s)"+(incident.timeout_applied?" and applied a timeout.":"."):"Kimi could not apply any automatic containment. Remove the bot or revoke its access manually immediately.")+" Review this incident with `/guard-review` by selecting the bot and choosing Restore or Keep restricted.").catch(error=>logger.info("Could not notify the server owner about bot restriction:",error.message));
 return incident;
}
async function coreCommand(i){
 if(!i.inGuild())return respond(i,"Use this command inside a Discord server.");
 if(i.commandName==="web-token"){
  const modal=new ModalBuilder().setCustomId("web-token:submit").setTitle("Connect server to Kimi");
  const tokenInput=new TextInputBuilder().setCustomId("web-token").setLabel("One-time Kimi token").setPlaceholder("Paste the token from your Kimi dashboard").setStyle(TextInputStyle.Short).setMinLength(20).setMaxLength(64).setRequired(true);
  modal.addComponents(new ActionRowBuilder().addComponents(tokenInput));
  return i.showModal(modal);
 }
 if(i.commandName==="setup")return foundation.handleInteraction(i);
 if(i.commandName==="kimi")return settings.show(i,"home");
 const configurePlugin={"configure-foundation":"Welcome","configure-welcome":"Welcome","configure-roles":"Role Picker","configure-auto-role":"Auto Role","configure-embeds":"Embeds","configure-kimi-lock":"Kimi Lock","configure-support":"Support"}[i.commandName];
 if(configurePlugin)return settings.show(i,"plugin",configurePlugin);
 if(i.commandName==="guard-review"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can review Kimi Guard incidents.");
  const target=i.options.getUser("bot"),decision=i.options.getString("decision");
  if(!target.bot||target.id===client.user.id)return respond(i,"Choose another bot account. Kimi cannot review or restrict itself.");
  const incident=store.data.guard_state?.[i.guildId]?.incidents?.[target.id];
  if(!incident||!["restricted","kept","review_required"].includes(incident.status))return respond(i,"There is no active Kimi Guard incident for that bot.");
  if(decision==="restore"){
   const member=await i.guild.members.fetch(target.id).catch(()=>null);
   if(!member)return respond(i,"That bot is no longer in this server. The incident record was kept.");
   if(!member.user.bot)return respond(i,"That account is no longer a bot. No roles or restrictions were changed.");
   const protectedPermissions=[PermissionFlagsBits.Administrator,PermissionFlagsBits.ManageGuild,PermissionFlagsBits.ManageRoles,PermissionFlagsBits.ManageChannels,PermissionFlagsBits.ManageWebhooks,PermissionFlagsBits.BanMembers,PermissionFlagsBits.KickMembers,PermissionFlagsBits.ModerateMembers,PermissionFlagsBits.ManageMessages,PermissionFlagsBits.ViewAuditLog,PermissionFlagsBits.MentionEveryone];
   const roleIds=Array.isArray(incident.removed_roles)?incident.removed_roles.filter(id=>/^\d{15,22}$/.test(String(id))):[];
   const fetchedRoles=await Promise.all(roleIds.map(id=>i.guild.roles.fetch(id,{force:true}).catch(()=>null)));
   const roles=fetchedRoles.filter(role=>role&&role.id!==i.guild.id&&!role.managed&&role.editable&&!protectedPermissions.some(permission=>role.permissions.has(permission)));
   const skippedRoles=Math.max(0,roleIds.length-roles.length);
   let timeoutCleared=false;
   const currentTimeout=member.communicationDisabledUntilTimestamp||0;
   if(incident.timeout_applied&&Number.isFinite(incident.timeout_until)&&currentTimeout&&Math.abs(currentTimeout-incident.timeout_until)<60000){
    const previousTimeout=Number(incident.original_timeout_until)||0;
    await member.timeout(previousTimeout>Date.now()?previousTimeout-Date.now():null,"Released by the server owner after Kimi Guard review");
    timeoutCleared=true;
   }
   if(roles.length)await member.roles.add(roles,"Released by the server owner after Kimi Guard review");
   const wasContained=Boolean(incident.removed_roles?.length||incident.timeout_applied);
   incident.status="released";incident.reviewed_at=Date.now();incident.reviewed_by=i.user.id;incident.restored_roles=roles.map(role=>role.id);incident.skipped_restore_roles=skippedRoles;incident.timeout_cleared=timeoutCleared;store.queueSave();
   return respond(i,wasContained?"The incident was reviewed. "+roles.length+" safe role(s) were restored"+(skippedRoles?", "+skippedRoles+" unsafe or unavailable role(s) were skipped":"")+(incident.timeout_applied?(timeoutCleared?"; Kimi's timeout was cleared.":"; the current timeout was left unchanged because it could have been set or modified separately."):""):"The incident was closed, but Kimi had not been able to restrict this bot. Its access is unchanged.");
  }
  const wasContained=Boolean(incident.removed_roles?.length||incident.timeout_applied);
  incident.status="kept";incident.reviewed_at=Date.now();incident.reviewed_by=i.user.id;store.queueSave();
  return respond(i,wasContained?"The bot remains restricted. Only you can release it with /guard-review.":"Kimi could not apply an automatic restriction. Remove the bot or revoke its access manually; this incident will remain recorded.");
 }
 if(i.commandName==="setup")return foundation.setup(i);
 if(i.commandName==="automations")return automationEngine.handleInteraction(i);
 if(i.commandName==="plan"){
  const report=getStorageReport(store,i.guildId);
  return respond(i,"**Kimi Free**\nKimi is free to use. All built-in apps can be added without a subscription.\n\n**Storage:** "+formatBytes(report.bytes)+" / "+formatBytes(report.limit)+" (5 MB per server)\n\nManage apps and systems in /kimi.");
 }
 if(i.commandName==="apps"||i.commandName==="app-store"){
  const lines=manager.list().map(l=>{
   const state=manager.installed(i.guildId,l.name)?"Installed":"Available";
   return "**"+l.name+"** — "+state+"\n"+l.description+"\nSystems: "+l.systems.join(", ")+"\nHelpers: "+(l.helpers||[]).join(", ");
  });
  return respond(i,"**Kimi Apps**\n\n"+lines.join("\n\n")+"\n\nAdd or remove apps in the App Store in /kimi.");
 }
 if(i.commandName==="uninstall"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can uninstall Kimi apps.");
  const result=manager.uninstall(i.guildId,i.options.getString("app"));
  if(!result.ok)return respond(i,result.error);
  const pluginKey=result.plugin.name;
  if(plugins[pluginKey]?.onUninstall)await plugins[pluginKey].onUninstall(i.guild);
  await syncGuildCommands(i.guildId);
  return respond(i,`**${result.plugin.name}** has been removed from this server. Its slash commands have been removed; saved configuration, source code, and projects are preserved.`);
 }
 if(i.commandName==="install"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can add Kimi apps.");
  const name=i.options.getString("app");
  if(!name)return respond(i,"Choose an app. Available apps: Welcome, Auto Role, Role Picker, Embeds, Kimi Lock, Support. Use /apps for details.");
  const result=manager.install(i.guildId,name);if(!result.ok)return respond(i,result.error);
  await showInstallAnimation(i,result.plugin.name);
  try {
   await syncGuildCommands(i.guildId);
  } catch(error) {
   logger.error(`Could not publish ${result.plugin.name} commands for guild ${i.guildId}:`,error);
   return respond(i,`**${result.plugin.name}** was saved as installed, but Discord did not accept the slash-command update. Check the bot's application permissions and restart Kimi to retry the sync.`);
  }
  const pluginKey=result.plugin.name;
  if(plugins[pluginKey]?.ready)await plugins[pluginKey].ready(i.guild);
  if(plugins[pluginKey]?.onInstall)await plugins[pluginKey].onInstall(i.guild);
  return respond(i,`**${result.plugin.name}** has been added and is active in this server. Its slash commands have been published.\n${result.plugin.description}`);
 }
}
function localizeInteraction(i){
 const methods=["reply","editReply","followUp","update","showModal"];
 for(const method of methods){
  const original=i[method];
  if(typeof original!=="function")continue;
  i[method]=function(payload,...args){return original.call(this,translatePayload(store,this.guildId,payload),...args);};
 }
}
async function handleInteraction(i){
 localizeInteraction(i);
 if(i.isRepliable()&&i.guildId){
  const actorKind=i.user.bot?"bot":"user";
  const limit=guard.consume(i.guildId,i.user.id,actorKind);
  if(!limit.allowed){
   if(actorKind==="bot"){
    if(i.message?.deletable)await i.message.delete().catch(()=>{});
    const member=await i.guild?.members.fetch(i.user.id).catch(()=>null);
    if(member)await restrictBot(member,"Kimi Guard bot interaction activity limit exhausted").catch(error=>logger.error("Kimi Guard interaction restriction failed:",error));
   }
   return i.reply({content:"Kimi is pausing your actions because your activity limit is exhausted. Wait about "+Math.ceil(limit.retryAfterMs/1000)+" second(s) for all 10 tokens to return.",ephemeral:true,allowedMentions:{parse:[]}});
  }
 }
 if(i.isModalSubmit()&&i.customId==="web-token:submit"){
  if(!i.inGuild())return respond(i,"Use this form inside a Discord server.");
  if(!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to connect this server to a Kimi account.");
  const result=authStore.completeWebToken(i.fields.getTextInputValue("web-token"),i.guild,i.user);
  return respond(i,result.error||"This server is now connected to the Kimi account that generated the token. Return to the dashboard.");
 }
 if(i.isChatInputCommand()&&i.guildId&&store.data.command_settings?.[i.guildId]?.[i.commandName]===false)return respond(i,"This slash command is disabled for this server. Re-enable it in the Kimi dashboard.");
 const opensPublicSettings=i.isChatInputCommand()&&["setup","kimi","configure-foundation","configure-welcome","configure-roles","configure-auto-role","configure-embeds","configure-kimi-lock","configure-support"].includes(i.commandName);
 if(i.isRepliable()&&!opensModal(i)&&!opensPublicSettings)await startWorking(i);
 if(i.isChatInputCommand()){
  if(["setup","kimi","configure-foundation","configure-welcome","configure-roles","configure-auto-role","configure-embeds","configure-kimi-lock","configure-support","install","uninstall","apps","app-store","automations","guard-review","plan","web-token"].includes(i.commandName))return coreCommand(i);
  const moduleId=commandModule[i.commandName];
  if(moduleId&&!moduleEnabled(i.guildId,moduleId))return respond(i,`The **${moduleId}** system is disabled. Enable it in /kimi.`);
  const required=pluginForCommand(i.commandName);if(!required)return;
  if(!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to use Kimi app commands.");
  if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** app is not added in this server. Ask the owner to use /install.`);
  return plugins[required].handleInteraction(i);
 }
 const id=i.customId||"";
 if(id.startsWith("automation:"))return automationEngine.handleInteraction(i);
 if(id.startsWith("settings:"))return settings.handle(i);
 const moduleId=componentModule(id);
 if(moduleId&&!moduleEnabled(i.guildId,moduleId))return respond(i,`This system is disabled. Enable it in /kimi.`);
 const required=pluginForComponent(id);if(!required)return;
 const ticketAdminControl=id.startsWith("ticket:edit-")||id.startsWith("ticket:settings:")||id==="ticket:publish";
 const administratorControl=id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("embed:")||ticketAdminControl;
 if(administratorControl&&!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to use this control.");
 if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** app is not added. This control is inactive.`);
 return plugins[required].handleInteraction(i);
}
client.on(Events.GuildCreate,guild=>{
 if(!client.isReady())return;
 syncGuildCommands(guild.id).catch(error=>logger.error(`Command sync failed for new guild ${guild.id}:`,error));
});
client.once(Events.ClientReady,async ready=>{
 logger.info(`Logged in as ${ready.user.tag}`);
 const startupTasks=[
  rest.put(Routes.applicationCommands(config.clientId),{body:commandsForPlugins([])})
   .then(()=>logger.info("Registered core global slash commands."))
   .catch(error=>logger.error("Global command sync failed:",error))
 ];
 for(const guild of ready.guilds.cache.values()){
  startupTasks.push((async()=>{
   try{await syncGuildCommands(guild.id);}catch(error){logger.error(`Command sync failed for guild ${guild.id}:`,error);}
   const readyTasks=[];
   for(const [name,plugin] of Object.entries(plugins)){
    if(manager.installed(guild.id,name)&&plugin.ready)readyTasks.push(Promise.resolve().then(()=>plugin.ready(guild)));
   }
   const results=await Promise.allSettled(readyTasks);
   for(let index=0;index<results.length;index++)if(results[index].status==="rejected")logger.error(`Plugin startup failed in guild ${guild.id}:`,results[index].reason);
  })());
 }
 await Promise.allSettled(startupTasks);
});
client.on(Events.InteractionCreate,async i=>{
 const endPerformance=performanceMonitor.begin(i);
 logger.debug(`Interaction received: ${i.type} ${i.commandName||i.customId||"unknown"} (${i.id})`);
 try{
  await handleInteraction(i);
  await finishWorking(i);
  logger.debug(`Interaction completed: ${i.id}`);
 }catch(error){
  const details={
   name:error?.name||"Error",
   code:error?.code??error?.rawError?.code??null,
   status:error?.status??error?.httpStatus??null,
   method:error?.method??error?.requestBody?.method??null,
   url:error?.url??null,
   message:error?.message||String(error)
  };
  logger.error(`Interaction ${i.id} (${i.commandName||i.customId||"unknown"}) failed:`,error);
  logger.error(`Interaction failure details ${i.id}:`,JSON.stringify(details));
  if(!i.isRepliable())return;
  const code=details.code!==null?` Error code: ${details.code}.`:"";
  const p={content:"Kimi could not complete that action."+code+" The error was recorded in the Termux log. Send the matching Interaction ID to support: "+i.id,components:[],allowedMentions:{parse:[]}};
  if(i.deferred||i.replied)await i.editReply(p).catch(replyError=>logger.error(`Could not send interaction failure response ${i.id}:`,replyError));
  else await i.reply({...p,ephemeral:true}).catch(replyError=>logger.error(`Could not acknowledge failed interaction ${i.id}:`,replyError));
 }finally{
  const duration=endPerformance();
  logger.debug(`Interaction duration ${i.id}: ${duration.toFixed(1)}ms`);
 }
});
client.on(Events.MessageCreate,async m=>{
 if(!m.guild)return;
 if(m.author.id===client.user.id)return;
 const automatedActor=Boolean(m.author.bot||m.webhookId);
 const actorId=m.webhookId||m.author.id;
 const kind=automatedActor?"bot":"user";
 const limit=guard.consume(m.guild.id,actorId,kind);
 if(!limit.allowed){
  if(automatedActor&&!m.webhookId){
   await m.delete().catch(()=>{});
   const member=m.member||await m.guild.members.fetch(m.author.id).catch(()=>null);
   if(member)await restrictBot(member).catch(error=>logger.error("Kimi Guard bot restriction failed:",error));
  }else if(m.webhookId){
   await m.delete().catch(()=>{});
   const guildState=store.data.guard_state[m.guild.id]||(store.data.guard_state[m.guild.id]={users:{},bots:{},incidents:{}});
   if(!guildState.webhook_incidents||typeof guildState.webhook_incidents!=="object"||Array.isArray(guildState.webhook_incidents))guildState.webhook_incidents={};
   const webhookIncidents=Object.entries(guildState.webhook_incidents);
   if(webhookIncidents.length>=100&&!guildState.webhook_incidents[m.webhookId]){
    webhookIncidents.sort((a,b)=>(a[1]?.created_at||0)-(b[1]?.created_at||0));
    delete guildState.webhook_incidents[webhookIncidents[0][0]];
   }
   if(!guildState.webhook_incidents[m.webhookId]){
    guildState.webhook_incidents[m.webhookId]={source:"webhook",webhook_id:m.webhookId,channel_id:m.channelId,owner_id:m.guild.ownerId,status:"restricted",reason:"Webhook activity bucket exhausted",created_at:Date.now()};
    store.queueSave();
    const owner=await client.users.fetch(m.guild.ownerId).catch(()=>null);
    if(owner)await owner.send("Kimi Guard detected a webhook exceeding its activity limit in "+m.guild.name+". New messages from it are being deleted. Webhook ID: "+m.webhookId+"; channel: "+m.channelId+". Review or remove this webhook in Server Settings → Integrations.").catch(()=>{});
   }
  }else{
   await m.delete().catch(()=>{});
  }
  return;
 }
 if(automatedActor)return;
 if(allowSystemTrigger(m.guild.id))automationEngine.messageCreate(m).catch(error=>logger.error("Automation message trigger failed:",error));
 if(m.content.trim().toLowerCase()==="&testgreet"){
  if(!m.member?.permissions.has(PermissionFlagsBits.ManageGuild))return m.reply("You need Manage Server permission to run the greet test.").catch(()=>{});
  if(!manager.installed(m.guild.id,"Welcome"))return m.reply("The Welcome app is not added to this server.").catch(()=>{});
  try{
   const sent=await foundation.testGreet(m.member);
   if(!sent)return m.reply("Greet test could not be sent. Check that a welcome channel is configured and Kimi can view and send messages there.").catch(()=>{});
   return m.reply("Test greeting sent to <#"+sent.channelId+">.").catch(()=>{});
  }catch(error){
   logger.error("Greet test failed:",error);
   return m.reply("Kimi could not send the test greeting. Check the welcome channel permissions.").catch(()=>{});
  }
 }
  if(manager.installed(m.guildId,"Kimi Lock"))plugins["Kimi Lock"].messageCreate(m,{moderation:moduleEnabled(m.guildId,"moderation"),recovery:moduleEnabled(m.guildId,"recovery")}).catch(e=>logger.error("Moderation message processing failed:",e));
});
client.on(Events.MessageDelete,m=>{if(m.guild&&manager.installed(m.guild.id,"Kimi Lock")&&moduleEnabled(m.guild.id,"moderation"))plugins["Kimi Lock"].messageDelete(m).catch(e=>logger.error("Message delete log failed:",e));});
client.on(Events.MessageUpdate,(oldMessage,newMessage)=>{if(newMessage.guild&&manager.installed(newMessage.guild.id,"Kimi Lock")&&(moduleEnabled(newMessage.guild.id,"moderation")||moduleEnabled(newMessage.guild.id,"recovery")))plugins["Kimi Lock"].messageUpdate(oldMessage,newMessage,{moderation:moduleEnabled(newMessage.guild.id,"moderation"),recovery:moduleEnabled(newMessage.guild.id,"recovery")}).catch(e=>logger.error("Message edit log failed:",e));});
client.on(Events.GuildMemberUpdate,(oldMember,newMember)=>{if(manager.installed(newMember.guild.id,"Kimi Lock")&&moduleEnabled(newMember.guild.id,"moderation"))plugins["Kimi Lock"].memberUpdate(oldMember,newMember).catch(e=>logger.error("Member update log failed:",e));});
client.on(Events.GuildBanAdd,ban=>{if(manager.installed(ban.guild.id,"Kimi Lock")&&moduleEnabled(ban.guild.id,"moderation"))plugins["Kimi Lock"].ban(ban.guild,ban.user).catch(e=>logger.error("Ban log failed:",e));});
client.on(Events.GuildBanRemove,ban=>{if(manager.installed(ban.guild.id,"Kimi Lock")&&moduleEnabled(ban.guild.id,"moderation"))plugins["Kimi Lock"].ban(ban.guild,ban.user,true).catch(e=>logger.error("Unban log failed:",e));});
client.on(Events.GuildAuditLogEntryCreate,(entry,guild)=>{if(manager.installed(guild.id,"Kimi Lock")&&moduleEnabled(guild.id,"protection"))plugins["Kimi Lock"].auditLog(entry,guild).catch(e=>logger.error("Anti-nuke audit processing failed:",e));});
client.on(Events.GuildMemberAdd,m=>{
 const allowAutomation=allowSystemTrigger(m.guild.id);
 if(allowAutomation)automationEngine.memberJoin(m).catch(error=>logger.error("Automation join trigger failed:",error));
 const record=store.member(m.guild.id,m.id);
 record.joins++;
 record.last_join=Date.now();
 store.queueSave();
 if(manager.installed(m.guild.id,"Kimi Lock")){
  const modules={protection:moduleEnabled(m.guild.id,"protection"),verification:moduleEnabled(m.guild.id,"verification")};
  if(modules.protection||modules.verification)plugins["Kimi Lock"].guildMemberAdd(m,modules).catch(e=>logger.error("Security member-join processing failed:",e));
 }
 if(allowAutomation&&manager.installed(m.guild.id,"Welcome")&&moduleEnabled(m.guild.id,"welcome"))plugins.Welcome.guildMemberAdd(m).catch(e=>logger.error("Welcome message failed:",e));
  if(allowAutomation&&manager.installed(m.guild.id,"Auto Role")&&moduleEnabled(m.guild.id,"auto_role"))plugins["Auto Role"].guildMemberAdd(m).catch(e=>logger.error("Automatic role assignment failed:",e));
});
client.on(Events.GuildMemberRemove,m=>{
 const allowAutomation=allowSystemTrigger(m.guild.id);
 if(allowAutomation)automationEngine.memberLeave(m).catch(error=>logger.error("Automation leave trigger failed:",error));
 const record=store.member(m.guild.id,m.id);
 record.leaves++;
 store.queueSave();
 if(allowAutomation&&manager.installed(m.guild.id,"Welcome")&&moduleEnabled(m.guild.id,"welcome"))plugins.Welcome.guildMemberRemove(m).catch(e=>logger.error("Goodbye message failed:",e));
});
client.on(Events.ChannelCreate,c=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelCreate(c);});
client.on(Events.ChannelUpdate,(o,c)=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelUpdate(o,c);});
client.on(Events.ChannelDelete,c=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelDelete(c).catch(e=>logger.error("Recovery failed:",e));});
client.on(Events.Error,e=>logger.error("Discord client error:",e));process.on("unhandledRejection",e=>logger.error("Unhandled rejection:",e));
function shutdown(signal){logger.info(`Received ${signal}; shutting down Kimi.`);try{store.save();}catch(e){logger.error("Final save failed:",e);}client.destroy();process.exit(0);}
process.once("SIGINT",()=>shutdown("SIGINT"));process.once("SIGTERM",()=>shutdown("SIGTERM"));
startDashboardServer({config,client,store,manager,plugins,logger,syncGuildCommands,authStore});
try{await client.login(config.token);}catch(e){logger.error("Kimi could not log in. Check DISCORD_TOKEN and application settings:",e);process.exitCode=1;}
