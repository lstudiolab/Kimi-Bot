import { Client, Events, GatewayIntentBits, Partials, REST, Routes, PermissionFlagsBits, ActionRowBuilder, ModalBuilder, TextInputBuilder, TextInputStyle } from "discord.js";
import { loadConfig, createLogger } from "./config.js";
import { startDashboardServer } from "./dashboard.js";
import { commandsForPlugins, pluginCommandsForPlugins, coreCommandData, pluginForCommand } from "./commands.js";
import { Store } from "./store.js";
import { AuthStore } from "./auth-store.js";
import { PluginManager } from "./plugin-manager.js";
import { PLUGINS } from "./plugins/index.js";
import { startWorking, respond, finishWorking } from "./ui.js";
import { pluginForComponent } from "./component-routing.js";
import { getStorageReport, formatBytes } from "./subscriptions.js";
import { KimiSettings } from "./settings.js";
import { translatePayload } from "./i18n.js";
import { PerformanceMonitor } from "./performance.js";
import { createRuntimeServices } from "./services/runtime.js";
import { AutomationEngine } from "./automations/engine.js";
const config=loadConfig(),logger=createLogger(config.logLevel),store=new Store(config.dataDir,logger),authStore=new AuthStore(config.dataDir,logger);
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
 "verify":"verification","verify-config":"verification","filter":"moderation","security":"protection","moderation":"moderation","kimi-channel":"setup","setup":"setup","welcome":"welcome","autorole":"welcome","tickets":"tickets","ticket-config":"tickets",
 "roles":"roles","embed-new":"embeds","embed-edit":"embeds","embed-post":"embeds",
 "ticket-panel":"tickets"
};
const componentModule=id=>id.startsWith("modpanel:")?"moderation":id.startsWith("verify:")?"verification":id.startsWith("botguard:")?"protection":id.startsWith("ticket:")?"tickets":id.startsWith("rolepicker:")?"roles":id.startsWith("embed:")?"embeds":null;
const foundation=PLUGINS.Foundation.create(context);context.foundation=foundation;
const plugins=Object.fromEntries(Object.entries(PLUGINS).map(([name,definition])=>[name,name==="Foundation"?foundation:definition.create(context)]));
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
  const plugin=section==="moderation"?"Kimi Lock":section==="tickets"||section==="tickets-setup"?"Support":"Foundation";
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
async function coreCommand(i){
 if(!i.inGuild())return respond(i,"Use this command inside a Discord server.");
 if(i.commandName==="web-token"){
  const modal=new ModalBuilder().setCustomId("web-token:submit").setTitle("Connect server to Kimi");
  const tokenInput=new TextInputBuilder().setCustomId("web-token").setLabel("One-time Kimi token").setPlaceholder("Paste the token from your Kimi dashboard").setStyle(TextInputStyle.Short).setMinLength(20).setMaxLength(64).setRequired(true);
  modal.addComponents(new ActionRowBuilder().addComponents(tokenInput));
  return i.showModal(modal);
 }
 if(i.commandName==="kimi")return settings.show(i,"home");
 const configurePlugin={"configure-foundation":"Foundation","configure-kimi-lock":"Kimi Lock","configure-support":"Support"}[i.commandName];
 if(configurePlugin)return settings.show(i,"plugin",configurePlugin);
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
  return respond(i,`**${result.plugin.name}** is now disabled in this server. Its slash commands have been removed; saved configuration, source code, and projects are preserved.`);
 }
 if(i.commandName==="install"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can add Kimi apps.");
  const name=i.options.getString("app");
  if(!name)return respond(i,"Choose a plugin in the app option. Available apps: Foundation, Kimi Lock, Support. Use /apps for details.");
  const result=manager.install(i.guildId,name);if(!result.ok)return respond(i,result.error);
  await showInstallAnimation(i,result.plugin.name);
  try {
   await syncGuildCommands(i.guildId);
  } catch(error) {
   logger.error(`Could not publish ${result.plugin.name} commands for guild ${i.guildId}:`,error);
   return respond(i,`**${result.plugin.name}** was saved as installed, but Discord did not accept the slash-command update. Check the bot's application permissions and restart Kimi to retry the sync.`);
  }
  const pluginKey=({Core:"Foundation",Shield:"Kimi Lock",Support:"Support"})[result.plugin.name]||result.plugin.name;
  if(plugins[pluginKey]?.ready)await plugins[pluginKey].ready(i.guild);
  if(plugins[pluginKey]?.onInstall)await plugins[pluginKey].onInstall(i.guild);
  return respond(i,`**${result.plugin.name}** is installed and active in this server. Its slash commands have been published.\n${result.plugin.description}`);
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
 if(i.isModalSubmit()&&i.customId==="web-token:submit"){
  if(!i.inGuild())return respond(i,"Use this form inside a Discord server.");
  if(!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to connect this server to a Kimi account.");
  const result=authStore.completeWebToken(i.fields.getTextInputValue("web-token"),i.guild,i.user);
  return respond(i,result.error||"This server is now connected to the Kimi account that generated the token. Return to the dashboard.");
 }
 if(i.isChatInputCommand()&&i.guildId&&store.data.command_settings?.[i.guildId]?.[i.commandName]===false)return respond(i,"This slash command is disabled for this server. Re-enable it in the Kimi dashboard.");
 const opensPublicSettings=i.isChatInputCommand()&&["kimi","configure-foundation","configure-kimi-lock","configure-support"].includes(i.commandName);
 if(i.isRepliable()&&!opensModal(i)&&!opensPublicSettings)await startWorking(i);
 if(i.isChatInputCommand()){
  if(["kimi","configure-foundation","configure-kimi-lock","configure-support","install","uninstall","apps","app-store","automations","plan","web-token"].includes(i.commandName))return coreCommand(i);
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
 if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** plugin is not installed. This control is inactive.`);
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
 if(m.author.bot||!m.guild)return;
 automationEngine.messageCreate(m).catch(error=>logger.error("Automation message trigger failed:",error));
 if(m.content.trim().toLowerCase()==="&testgreet"){
  if(!m.member?.permissions.has(PermissionFlagsBits.ManageGuild))return m.reply("You need Manage Server permission to run the greet test.").catch(()=>{});
  if(!manager.installed(m.guild.id,"Foundation"))return m.reply("The Foundation plugin is not installed in this server.").catch(()=>{});
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
 automationEngine.memberJoin(m).catch(error=>logger.error("Automation join trigger failed:",error));
 const record=store.member(m.guild.id,m.id);
 record.joins++;
 record.last_join=Date.now();
 store.queueSave();
 if(manager.installed(m.guild.id,"Kimi Lock")){
  const modules={protection:moduleEnabled(m.guild.id,"protection"),verification:moduleEnabled(m.guild.id,"verification")};
  if(modules.protection||modules.verification)plugins["Kimi Lock"].guildMemberAdd(m,modules).catch(e=>logger.error("Security member-join processing failed:",e));
 }
 if(manager.installed(m.guild.id,"Foundation")&&moduleEnabled(m.guild.id,"welcome"))plugins.Foundation.guildMemberAdd(m).catch(e=>logger.error("Welcome message failed:",e));
});
client.on(Events.GuildMemberRemove,m=>{
 automationEngine.memberLeave(m).catch(error=>logger.error("Automation leave trigger failed:",error));
 const record=store.member(m.guild.id,m.id);
 record.leaves++;
 store.queueSave();
 if(manager.installed(m.guild.id,"Foundation")&&moduleEnabled(m.guild.id,"welcome"))plugins.Foundation.guildMemberRemove(m).catch(e=>logger.error("Goodbye message failed:",e));
});
client.on(Events.ChannelCreate,c=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelCreate(c);});
client.on(Events.ChannelUpdate,(o,c)=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelUpdate(o,c);});
client.on(Events.ChannelDelete,c=>{if(c.guild&&manager.installed(c.guild.id,"Kimi Lock")&&moduleEnabled(c.guild.id,"recovery"))plugins["Kimi Lock"].channelDelete(c).catch(e=>logger.error("Recovery failed:",e));});
client.on(Events.Error,e=>logger.error("Discord client error:",e));process.on("unhandledRejection",e=>logger.error("Unhandled rejection:",e));
function shutdown(signal){logger.info(`Received ${signal}; shutting down Kimi.`);try{store.save();}catch(e){logger.error("Final save failed:",e);}client.destroy();process.exit(0);}
process.once("SIGINT",()=>shutdown("SIGINT"));process.once("SIGTERM",()=>shutdown("SIGTERM"));
startDashboardServer({config,client,store,manager,plugins,logger,syncGuildCommands,authStore});
try{await client.login(config.token);}catch(e){logger.error("Kimi could not log in. Check DISCORD_TOKEN and application settings:",e);process.exitCode=1;}
