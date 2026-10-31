import { Client, Events, GatewayIntentBits, Partials, REST, Routes, PermissionFlagsBits } from "discord.js";
import { loadConfig, createLogger } from "./config.js";
import { commandsForLibraries, libraryCommandsForLibraries, coreCommandData } from "./commands.js";
import { Store } from "./store.js";
import { LibraryManager } from "./module-manager.js";
import { LIBRARIES } from "./libraries/index.js";
import { startWorking, respond, finishWorking } from "./ui.js";
import { getStorageReport, formatBytes } from "./subscriptions.js";
const config=loadConfig(),logger=createLogger(config.logLevel),store=new Store(config.dataDir,logger);
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMembers,GatewayIntentBits.GuildModeration,GatewayIntentBits.GuildMessages,GatewayIntentBits.MessageContent],partials:[Partials.Channel,Partials.Message,Partials.GuildMember]});
const manager=new LibraryManager(store,logger),context={client,store,logger};
const foundation=LIBRARIES.Foundation.create(context);context.foundation=foundation;
const libraries=Object.fromEntries(Object.entries(LIBRARIES).map(([name,definition])=>[name,name==="Foundation"?foundation:definition.create(context)]));
context.libraries=libraries;
const rest=new REST({version:"10"}).setToken(config.token);
async function syncGlobalCommands(){
 const registered=await rest.put(Routes.applicationCommands(config.clientId),{body:coreCommandData});
 logger.info(`Synced ${registered.length} Timi core slash commands globally.`);
}
async function syncGuildCommands(guildId){
 const installed=store.data.installed_libraries[guildId]||[];
 const body=libraryCommandsForLibraries(installed);
 const route=Routes.applicationGuildCommands(config.clientId,guildId);
 const registered=await rest.put(route,{body});
 logger.info(`Synced ${registered.length} slash commands for guild ${guildId}.`);
 return registered;
}
function commandLibrary(n){
 if(n.startsWith("ticket-"))return "Support";
 if(["moderation-settings","automod-word","verify-settings","verify-panel"].includes(n))return "Security";
 if(["setup-role-picker","create-embed","edit-embed","place-embed","greet-settings","auto-role"].includes(n))return "Foundation";
 if(["code","code-edit","code-list","code-run","code-stop","code-delete","code-export","code-import","code-history","code-validate","code-undo","code-redo","code-kit","code-docs","code-template"].includes(n))return "Scratch";
 return null;
}
function componentLibrary(id){
 if(id.startsWith("ticket:"))return "Support";
 if(id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("verify:"))return "Security";
 if(id.startsWith("rolepicker:")||id.startsWith("embed:"))return "Foundation";
 if(id.startsWith("tbs:")||id.startsWith("tbm:")||id.startsWith("developer:"))return "Scratch";
 return null;
}
function opensModal(i){
 if(i.isChatInputCommand()){
  const file=i.commandName==="code"||i.commandName==="code-edit" ? i.options.getAttachment("file") : null;
  if(file)return false;
  return ["create-embed","code","code-edit"].includes(i.commandName);
 }
 if(!i.isButton())return false;
 const id=i.customId;
 return id==="rolepicker:start"||id==="ticket:wizard-start"||id==="ticket:wizard-continue"||id.startsWith("ticket:edit-")||id==="modpanel:sanction"||id==="modpanel:duration"||id==="modpanel:max-count"||id.startsWith("embed:")||id.startsWith("tbm:");
}
async function coreCommand(i){
 if(i.commandName==="timi-plan"){
  const report=getStorageReport(store,i.guildId);
  return respond(i,"**Timi Free**\nTimi is free to use. All built-in libraries, including Developer, can be installed without a subscription.\n\n**Storage:** "+formatBytes(report.bytes)+" / "+formatBytes(report.limit)+" (5 MB per server)\n\nUse /library-list to browse libraries and /install-library to enable them.");
 }
 if(i.commandName==="library-list"){
  const lines=manager.list().map(l=>{
   const state=manager.installed(i.guildId,l.name)?"Installed":"Available";
   return "**"+l.name+"** — "+state+"\n"+l.description+"\nSystems: "+l.systems.join(", ");
  });
  return respond(i,"**Timi Library**\n\n"+lines.join("\n\n")+"\n\nUse /install-library and enter a libraryname.");
 }
 if(i.commandName==="uninstall-library"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can uninstall Timi libraries.");
  const result=manager.uninstall(i.guildId,i.options.getString("libraryname"));
  if(!result.ok)return respond(i,result.error);
  if(libraries[result.library.name]?.onUninstall)await libraries[result.library.name].onUninstall(i.guild);
  await syncGuildCommands(i.guildId);
  return respond(i,`**${result.library.name}** is now disabled in this server. Its slash commands have been removed; saved configuration, source code, and projects are preserved.`);
 }
 if(i.commandName==="install-library"){
  if(i.guild.ownerId!==i.user.id)return respond(i,"Only the server owner can install Timi libraries.");
  const name=i.options.getString("libraryname");
  if(!name)return respond(i,"Enter a library name in libraryname. Available: Moderation, Support, Foundation, Developer. Use /library-list for details.");
  const result=manager.install(i.guildId,name);if(!result.ok)return respond(i,result.error);
  try {
   await syncGuildCommands(i.guildId);
  } catch(error) {
   logger.error(`Could not publish ${result.library.name} commands for guild ${i.guildId}:`,error);
   return respond(i,`**${result.library.name}** was saved as installed, but Discord did not accept the slash-command update. Check the bot's application permissions and restart Timi to retry the sync.`);
  }
  if(libraries[result.library.name].ready)await libraries[result.library.name].ready(i.guild);
  if(libraries[result.library.name].onInstall)await libraries[result.library.name].onInstall(i.guild);
  return respond(i,`**${result.library.name}** is installed and active in this server. Its slash commands have been published.\n${result.library.description}`);
 }
}
async function handleInteraction(i){
 if(i.isRepliable()&&!opensModal(i))await startWorking(i);
 if(i.isChatInputCommand()){
  if(["install-library","uninstall-library","library-list","timi-plan"].includes(i.commandName))return coreCommand(i);
  const required=commandLibrary(i.commandName);if(!required)return;
  if(!i.memberPermissions?.has(PermissionFlagsBits.Administrator))return respond(i,"Only server administrators can use commands from Timi libraries.");
  if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** library is not installed in this server. Ask the owner to use /install-library.`);
  return libraries[required].handleInteraction(i);
 }
 const id=i.customId||"",required=componentLibrary(id);if(!required)return;
 const publicMemberControls=id==="rolepicker:start"||id==="ticket:wizard-start"||id==="ticket:wizard-continue"||id.startsWith("verify:")||id.startsWith("rolepicker:")||id.startsWith("foundation:poll:");
 const ticketAdminControl=id.startsWith("ticket:edit-")||id==="ticket:priority"||id.startsWith("ticket:settings:")||id==="ticket:publish"||id.startsWith("ticket:priority-select:");
 const administratorControl=id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("embed:")||id.startsWith("tbs:")||id.startsWith("tbm:")||id.startsWith("developer:")||ticketAdminControl;
 if(administratorControl&&!i.memberPermissions?.has(PermissionFlagsBits.Administrator))return respond(i,"Only server administrators can use this control.");
 if(!manager.installed(i.guildId,required))return respond(i,`The **${required}** library is not installed. This control is inactive.`);
 return libraries[required].handleInteraction(i);
}
client.on(Events.GuildCreate,guild=>{
 if(!client.isReady())return;
 syncGuildCommands(guild.id).catch(error=>logger.error(`Command sync failed for new guild ${guild.id}:`,error));
});
client.once(Events.ClientReady,async ready=>{
 logger.info(`Logged in as ${ready.user.tag}`);
 try{await rest.put(Routes.applicationCommands(config.clientId),{body:commandsForLibraries([])});logger.info("Registered core global slash commands.");}catch(error){logger.error("Global command sync failed:",error);}
 for(const guild of ready.guilds.cache.values()){
  try{await syncGuildCommands(guild.id);}catch(error){logger.error(`Command sync failed for guild ${guild.id}:`,error);}
  for(const [name,library] of Object.entries(libraries))if(manager.installed(guild.id,name)&&library.ready)await library.ready(guild);
 }
});
client.on(Events.InteractionCreate,async i=>{
 logger.info(`Interaction received: ${i.type} ${i.commandName||i.customId||"unknown"} (${i.id})`);
 try{
  await handleInteraction(i);
  await finishWorking(i);
  logger.info(`Interaction completed: ${i.id}`);
 }catch(error){
  logger.error(`Interaction ${i.id} failed:`,error);
  if(!i.isRepliable())return;
  const p={content:"Timi could not complete that action. Check bot permissions and try again.",components:[],allowedMentions:{parse:[]}};
  if(i.deferred||i.replied)await i.editReply(p).catch(()=>{});
  else await i.reply({...p,ephemeral:true}).catch(()=>{});
 }
});
client.on(Events.MessageCreate,m=>{if(manager.installed(m.guildId,"Security"))libraries.Security.messageCreate(m).catch(e=>logger.error("Moderation message processing failed:",e));});
client.on(Events.MessageDelete,m=>{if(m.guild&&manager.installed(m.guild.id,"Security"))libraries.Security.messageDelete(m).catch(e=>logger.error("Message delete log failed:",e));});
client.on(Events.MessageUpdate,(oldMessage,newMessage)=>{if(newMessage.guild&&manager.installed(newMessage.guild.id,"Security"))libraries.Security.messageUpdate(oldMessage,newMessage).catch(e=>logger.error("Message edit log failed:",e));});
client.on(Events.GuildMemberUpdate,(oldMember,newMember)=>{if(manager.installed(newMember.guild.id,"Security"))libraries.Security.memberUpdate(oldMember,newMember).catch(e=>logger.error("Member update log failed:",e));});
client.on(Events.GuildBanAdd,ban=>{if(manager.installed(ban.guild.id,"Security"))libraries.Security.ban(ban.guild,ban.user).catch(e=>logger.error("Ban log failed:",e));});
client.on(Events.GuildBanRemove,ban=>{if(manager.installed(ban.guild.id,"Security"))libraries.Security.ban(ban.guild,ban.user,true).catch(e=>logger.error("Unban log failed:",e));});
client.on(Events.GuildAuditLogEntryCreate,(entry,guild)=>{if(manager.installed(guild.id,"Security"))libraries.Security.auditLog(entry,guild).catch(e=>logger.error("Anti-nuke audit processing failed:",e));});
client.on(Events.GuildMemberAdd,m=>{
 if(manager.installed(m.guild.id,"Security"))libraries.Security.guildMemberAdd(m).catch(e=>logger.error("Member join processing failed:",e));
 if(manager.installed(m.guild.id,"Foundation")){
  if(!manager.installed(m.guild.id,"Security")){const r=store.member(m.guild.id,m.id);r.joins++;r.last_join=Date.now();store.save();}
  libraries.Foundation.guildMemberAdd(m).catch(e=>logger.error("Welcome message failed:",e));
 }
});
client.on(Events.GuildMemberRemove,m=>{
 if(manager.installed(m.guild.id,"Foundation")){const r=store.member(m.guild.id,m.id);r.leaves++;store.save();libraries.Foundation.guildMemberRemove(m).catch(e=>logger.error("Goodbye message failed:",e));}
});
client.on(Events.ChannelCreate,c=>{if(c.guild&&manager.installed(c.guild.id,"Security"))libraries.Security.channelCreate(c);});
client.on(Events.ChannelUpdate,(o,c)=>{if(c.guild&&manager.installed(c.guild.id,"Security"))libraries.Security.channelUpdate(o,c);});
client.on(Events.ChannelDelete,c=>{if(c.guild&&manager.installed(c.guild.id,"Security"))libraries.Security.channelDelete(c).catch(e=>logger.error("Recovery failed:",e));});
client.on(Events.Error,e=>logger.error("Discord client error:",e));process.on("unhandledRejection",e=>logger.error("Unhandled rejection:",e));
function shutdown(signal){logger.info(`Received ${signal}; shutting down Timi.`);try{store.save();}catch(e){logger.error("Final save failed:",e);}client.destroy();process.exit(0);}
process.once("SIGINT",()=>shutdown("SIGINT"));process.once("SIGTERM",()=>shutdown("SIGTERM"));
try{await client.login(config.token);}catch(e){logger.error("Timi could not log in. Check DISCORD_TOKEN and application settings:",e);process.exitCode=1;}
