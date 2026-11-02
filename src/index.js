import { Client, Events, GatewayIntentBits, Partials, REST, Routes, PermissionFlagsBits, ActionRowBuilder, ModalBuilder, TextInputBuilder, TextInputStyle } from "discord.js";
import { loadConfig, createLogger } from "./config.js";
import { startDashboardServer } from "./dashboard.js";
import { commandsForLibraries, libraryCommandsForLibraries, coreCommandData, libraryForCommand } from "./commands.js";
import { Store } from "./store.js";
import { AuthStore } from "./auth-store.js";
import { LibraryManager } from "./module-manager.js";
import { LIBRARIES } from "./libraries/index.js";
import { startWorking, respond, finishWorking } from "./ui.js";
import { libraryForComponent } from "./component-routing.js";
import { getStorageReport, formatBytes } from "./subscriptions.js";
import { KimiSettings } from "./settings.js";
import { translatePayload } from "./i18n.js";
import { PerformanceMonitor } from "./performance.js";
const config=loadConfig(),logger=createLogger(config.logLevel),store=new Store(config.dataDir,logger),authStore=new AuthStore(config.dataDir,logger);
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildModeration,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent],partials:[Partials.Channel,Partials.Message,Partials.GuildMember]});
const manager=new LibraryManager(store,logger),context={client,store,logger};
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
 "ticket-panel":"tickets",
 "script":"scratch","script-edit":"scratch","scripts":"scratch","script-run":"scratch","script-stop":"scratch","script-delete":"scratch",
 "script-export":"scratch","script-import":"scratch","script-history":"scratch","script-check":"scratch","script-undo":"scratch","script-redo":"scratch","script-kit":"scratch","script-help":"scratch","script-template":"scratch"
};
const componentModule=id=>id.startsWith("modpanel:")?"moderation":id.startsWith("verify:")?"verification":id.startsWith("botguard:")?"protection":id.startsWith("ticket:")?"tickets":id.startsWith("rolepicker:")?"roles":id.startsWith("embed:")?"embeds":(id.startsWith("tbs:")||id.startsWith("tbm:")||id.startsWith("developer:"))?"scratch":null;
const foundation=LIBRARIES.Foundation.create(context);context.foundation=foundation;
const libraries=Object.fromEntries(Object.entries(LIBRARIES).map(([name,definition])=>[name,name==="Foundation"?foundation:definition.create(context)]));
context.libraries=libraries;
const rest=new REST({version:"10"}).setToken(config.token);
async function syncGlobalCommands(){
 const registered=await rest.put(Routes.applicationCommands(config.clientId),{body:coreCommandData});
 logger.info(`Synced ${registered.length} Kimi core slash commands globally.`);
}
async function syncGuildCommands(guildId){
 const installed=store.data.installed_libraries[guildId]||[];
 const body=libraryCommandsForLibraries(installed);
 const route=Routes.applicationGuildCommands(config.clientId,guildId);
 const registered=await rest.put(route,{body});
 logger.info(`Synced ${registered.length} slash commands for guild ${guildId}.`);
 return registered;
}
function opensModal(i){
 if(i.isChatInputCommand()){
  const file=i.commandName==="script"||i.commandName==="script-edit" ? i.options.getAttachment("file") : null;
  if(file)return false;
  return ["embed-new","script","script-edit","web-token"].includes(i.commandName);
 }
 if(!i.isButton())return false;
 const id=i.customId;
 return id==="settings:config:welcome"||id==="settings:config:verification"||id==="settings:filter-add"||id==="settings:filter-remove"||id==="settings:appearance-color"||id==="rolepicker:start"||id==="ticket:wizard-start"||id==="ticket:wizard-continue"||id.startsWith("ticket:edit-")||id==="modpanel:sanction"||id==="modpanel:duration"||id==="modpanel:max-count"||id.startsWith("embed:")||id.startsWith("tbm:");
}
const openConfiguration=async(i,section)=>{
  const names={moderation:"moderation",tickets:"ticket-config","tickets-setup":"tickets",setup:"setup"};
  const commandName=names[section];
  const library=section==="moderation"?"Security":section==="tickets"||section==="tickets-setup"?"Support":"Foundation";
  if(!commandName||!libraries[library])return respond(i,"This configuration section is not available.");
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
  return libraries[library].handleInteraction(proxy);
 };
const settings=new KimiSettings(store,manager,logger,{syncGuildCommands,libraries,openConfiguration});
async function showInstallAnimation(interaction,moduleName){
 const frames=[
  {bar:"░░░░░░░░░░",percent:0,status:"Preparing https://kimimodules.com"},
  {bar:"█░░░░░░░░░",percent:10,status:"Loading module's"},
  {bar:"██░░░░░░░░",percent:20,status:"Finding module's name"},
  {bar:"███░░░░░░░",percent:30,status:"Checking module structure"},
  {bar:"████░░░░░░",percent:40,status:"Decompressing module"},
  {bar:"█████░░░░░",percent:50,status:"Listing slash commands"},
  {bar:"██████░░░░",percent:60,status:"Checking slash commands"},
  {bar:"███████░░░",percent:70,status:"Registering slash command"},
  {bar:"████████░░",percent:80,status:"Activating module"},
  {bar:"█████████░",percent:90,status:"Checking module status"},
  {bar:"██████████",percent:100,status:"Installation completed"}
 ];
 for(const frame of frames){
  await interaction.editReply({
   content:"**Installing "+moduleName+"**\\n\`"+frame.bar+"\` "+frame.percent+"%\\n"+frame.status,
   components:[],embeds:[],allowedMentions:{parse:[]}
  });
  if(frame.percent!==100)await new Promise(resolve=>setTimeout(resolve,500));
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
 const configureLibrary={"configure-core":"Foundation","configure-shield":"Security","configure-support":"Support","configure-studio":"Scratch"}[i.commandName];
 if(configureLibrary)return settings.show(i,"library",configureLibrary);
 if(i.commandName==="plan"){
  const report=getStorageReport(store,i.guildId);
  return respond(i,"**Kimi Free**\nKimi is free to use. All built-in libraries, including Studio, can be installed without a subscription.\n\n**Storage:** "+formatBytes(report.bytes)+" / "+formatBytes(report.limit)+" (5 MB per server)\n\nManage libraries and systems in /kimi.");
 }
 if(i.commandName==="libraries"){
  const lines=manager.list().map(l=>{
   const state=manager.installed(i.guildId,l.name)?"Installed":"Available";
   return "**"+l.name+"** — "+state+"\n"+l.description+"\nSystems: "+l.systems.join(", ");
  });
  return respond(i,"**Kimi Library**\n\n"+lines.join("\n\n")+"\n\nInstall or remove libraries in /kimi.");
 }
 if(i.commandName==="uninstall"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can uninstall Kimi libraries.");
  const result=manager.uninstall(i.guildId,i.options.getString("library"));
  if(!result.ok)return respond(i,result.error);
  const libraryKey=({Core:"Foundation",Shield:"Security",Support:"Support",Studio:"Scratch"})[result.library.name]||result.library.name;
  if(libraries[libraryKey]?.onUninstall)await libraries[libraryKey].onUninstall(i.guild);
  await syncGuildCommands(i.guildId);
  return respond(i,`**${result.library.name}** is now disabled in this server. Its slash commands have been removed; saved configuration, source code, and projects are preserved.`);
 }
 if(i.commandName==="install"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can install Kimi libraries.");
  const name=i.options.getString("library");
  if(!name)return respond(i,"Choose a library in the library option. Available: Foundation, Moderation, Support. Use /libraries for details.");
  const result=manager.install(i.guildId,name);if(!result.ok)return respond(i,result.error);
  await showInstallAnimation(i,result.library.name);
  try {
   await syncGuildCommands(i.guildId);
  } catch(error) {
   logger.error(`Could not publish ${result.library.name} commands for guild ${i.guildId}:`,error);
   return respond(i,`**${result.library.name}** was saved as installed, but Discord did not accept the slash-command update. Check the bot's application permissions and restart Kimi to retry the sync.`);
  }
  const libraryKey=({Core:"Foundation",Shield:"Security",Support:"Support",Studio:"Scratch"})[result.library.name]||result.library.name;
  if(libraries[libraryKey]?.ready)await libraries[libraryKey].ready(i.guild);
  if(libraries[libraryKey]?.onInstall)await libraries[libraryKey].onInstall(i.guild);
  return respond(i,`**${result.library.name}** is installed and active in this server. Its slash commands have been published.\n${result.library.description}`);
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
 const opensPublicSettings=i.isChatInputCommand()&&["kimi","configure-core","configure-shield","configure-support","configure-studio"].includes(i.commandName);
 if(i.isRepliable()&&!opensModal(i)&&!opensPublicSettings)await startWorking(i);
 if(i.isChatInputCommand()){
  if(["kimi","configure-core","configure-shield","configure-support","configure-studio","install","uninstall","libraries","plan","web-token"].includes(i.commandName))return coreCommand(i);
  const moduleId=commandModule[i.commandName];
  if(moduleId&&!moduleEnabled(i.guildId,moduleId))return respond(i,`The **${moduleId}** system is disabled. Enable it in /kimi.`);
  const required=libraryForCommand(i.commandName);if(!required)return;
  if(!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to use Kimi library commands.");
  if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** library is not installed in this server. Ask the owner to use /install.`);
  return libraries[required].handleInteraction(i);
 }
 const id=i.customId||"";
 if(id.startsWith("settings:"))return settings.handle(i);
 const moduleId=componentModule(id);
 if(moduleId&&!moduleEnabled(i.guildId,moduleId))return respond(i,`This system is disabled. Enable it in /kimi.`);
 const required=libraryForComponent(id);if(!required)return;
 const ticketAdminControl=id.startsWith("ticket:edit-")||id.startsWith("ticket:settings:")||id==="ticket:publish";
 const administratorControl=id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("embed:")||id.startsWith("developer:")||ticketAdminControl;
 if(administratorControl&&!i.memberPermissions?.has(PermissionFlagsBits.ManageGuild)&&i.guild?.ownerId!==i.user.id)return respond(i,"You need Manage Server permission to use this control.");
 if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** library is not installed. This control is inactive.`);
 return libraries[required].handleInteraction(i);
}
client.on(Events.GuildCreate,guild=>{
 if(!client.isReady())return;
 syncGuildCommands(guild.id).catch(error=>logger.error(`Command sync failed for new guild ${guild.id}:`,error));
});
client.once(Events.ClientReady,async ready=>{
 logger.info(`Logged in as ${ready.user.tag}`);
 const startupTasks=[
  rest.put(Routes.applicationCommands(config.clientId),{body:commandsForLibraries([])})
   .then(()=>logger.info("Registered core global slash commands."))
   .catch(error=>logger.error("Global command sync failed:",error))
 ];
 for(const guild of ready.guilds.cache.values()){
  startupTasks.push((async()=>{
   try{await syncGuildCommands(guild.id);}catch(error){logger.error(`Command sync failed for guild ${guild.id}:`,error);}
   const readyTasks=[];
   for(const [name,library] of Object.entries(libraries)){
    if(manager.installed(guild.id,name)&&library.ready)readyTasks.push(Promise.resolve().then(()=>library.ready(guild)));
   }
   const results=await Promise.allSettled(readyTasks);
   for(let index=0;index<results.length;index++)if(results[index].status==="rejected")logger.error(`Library startup failed in guild ${guild.id}:`,results[index].reason);
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
 if(m.content.trim().toLowerCase()==="&testgreet"){
  if(!m.member?.permissions.has(PermissionFlagsBits.ManageGuild))return m.reply("You need Manage Server permission to run the greet test.").catch(()=>{});
  if(!manager.installed(m.guild.id,"Foundation"))return m.reply("The Foundation library is not installed in this server.").catch(()=>{});
  try{
   const sent=await foundation.testGreet(m.member);
   if(!sent)return m.reply("Greet test could not be sent. Check that a welcome channel is configured and Kimi can view and send messages there.").catch(()=>{});
   return m.reply("Test greeting sent to <#"+sent.channelId+">.").catch(()=>{});
  }catch(error){
   logger.error("Greet test failed:",error);
   return m.reply("Kimi could not send the test greeting. Check the welcome channel permissions.").catch(()=>{});
  }
 }
 if(manager.installed(m.guildId,"Scratch")&&moduleEnabled(m.guildId,"scratch"))libraries.Scratch.onMessageCreate(m).catch(e=>logger.error("TBScript message event failed:",e));
 if(manager.installed(m.guildId,"Security"))libraries.Security.messageCreate(m,{moderation:moduleEnabled(m.guildId,"moderation"),recovery:moduleEnabled(m.guildId,"recovery")}).catch(e=>logger.error("Moderation message processing failed:",e));
});
client.on(Events.MessageDelete,m=>{if(m.guild&&manager.installed(m.guild.id,"Security")&&moduleEnabled(m.guild.id,"moderation"))libraries.Security.messageDelete(m).catch(e=>logger.error("Message delete log failed:",e));});
client.on(Events.MessageUpdate,(oldMessage,newMessage)=>{if(newMessage.guild&&manager.installed(newMessage.guild.id,"Security")&&(moduleEnabled(newMessage.guild.id,"moderation")||moduleEnabled(newMessage.guild.id,"recovery")))libraries.Security.messageUpdate(oldMessage,newMessage,{moderation:moduleEnabled(newMessage.guild.id,"moderation"),recovery:moduleEnabled(newMessage.guild.id,"recovery")}).catch(e=>logger.error("Message edit log failed:",e));});
client.on(Events.GuildMemberUpdate,(oldMember,newMember)=>{if(manager.installed(newMember.guild.id,"Security")&&moduleEnabled(newMember.guild.id,"moderation"))libraries.Security.memberUpdate(oldMember,newMember).catch(e=>logger.error("Member update log failed:",e));});
client.on(Events.GuildBanAdd,ban=>{if(manager.installed(ban.guild.id,"Security")&&moduleEnabled(ban.guild.id,"moderation"))libraries.Security.ban(ban.guild,ban.user).catch(e=>logger.error("Ban log failed:",e));});
client.on(Events.GuildBanRemove,ban=>{if(manager.installed(ban.guild.id,"Security")&&moduleEnabled(ban.guild.id,"moderation"))libraries.Security.ban(ban.guild,ban.user,true).catch(e=>logger.error("Unban log failed:",e));});
client.on(Events.GuildAuditLogEntryCreate,(entry,guild)=>{if(manager.installed(guild.id,"Security")&&moduleEnabled(guild.id,"protection"))libraries.Security.auditLog(entry,guild).catch(e=>logger.error("Anti-nuke audit processing failed:",e));});
client.on(Events.GuildMemberAdd,m=>{
 const record=store.member(m.guild.id,m.id);
 record.joins++;
 record.last_join=Date.now();
 store.queueSave();
 if(manager.installed(m.guild.id,"Scratch")&&moduleEnabled(m.guild.id,"scratch"))libraries.Scratch.onMemberJoin(m).catch(e=>logger.error("TBScript member-join event failed:",e));
 if(manager.installed(m.guild.id,"Security")){
  const modules={protection:moduleEnabled(m.guild.id,"protection"),verification:moduleEnabled(m.guild.id,"verification")};
  if(modules.protection||modules.verification)libraries.Security.guildMemberAdd(m,modules).catch(e=>logger.error("Security member-join processing failed:",e));
 }
 if(manager.installed(m.guild.id,"Foundation")&&moduleEnabled(m.guild.id,"welcome"))libraries.Foundation.guildMemberAdd(m).catch(e=>logger.error("Welcome message failed:",e));
});
client.on(Events.GuildMemberRemove,m=>{
 const record=store.member(m.guild.id,m.id);
 record.leaves++;
 store.queueSave();
 if(manager.installed(m.guild.id,"Foundation")&&moduleEnabled(m.guild.id,"welcome"))libraries.Foundation.guildMemberRemove(m).catch(e=>logger.error("Goodbye message failed:",e));
});
client.on(Events.ChannelCreate,c=>{if(c.guild&&manager.installed(c.guild.id,"Security")&&moduleEnabled(c.guild.id,"recovery"))libraries.Security.channelCreate(c);});
client.on(Events.ChannelUpdate,(o,c)=>{if(c.guild&&manager.installed(c.guild.id,"Security")&&moduleEnabled(c.guild.id,"recovery"))libraries.Security.channelUpdate(o,c);});
client.on(Events.ChannelDelete,c=>{if(c.guild&&manager.installed(c.guild.id,"Security")&&moduleEnabled(c.guild.id,"recovery"))libraries.Security.channelDelete(c).catch(e=>logger.error("Recovery failed:",e));});
client.on(Events.Error,e=>logger.error("Discord client error:",e));process.on("unhandledRejection",e=>logger.error("Unhandled rejection:",e));
function shutdown(signal){logger.info(`Received ${signal}; shutting down Kimi.`);try{store.save();}catch(e){logger.error("Final save failed:",e);}client.destroy();process.exit(0);}
process.once("SIGINT",()=>shutdown("SIGINT"));process.once("SIGTERM",()=>shutdown("SIGTERM"));
startDashboardServer({config,client,store,manager,libraries,logger,syncGuildCommands,authStore});
try{await client.login(config.token);}catch(e){logger.error("Kimi could not log in. Check DISCORD_TOKEN and application settings:",e);process.exitCode=1;}
