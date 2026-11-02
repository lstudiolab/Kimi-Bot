import fs from "node:fs";
import path from "node:path";
import { fillDefaults } from "./utils.js";
import { getGuildStorageBytes, getPlanForData, restoreGuildStorage, PLANS } from "./subscriptions.js";

const defaults=()=>({
  installed_plugins:{},automations:{},modules:{},command_settings:{},languages:{},subscriptions:{},welcome:{},timi_setup:{},tickets:{},moderation:{},verification:{},members:{},channels:{},messages:{},analytics_requests:{},verification_logs:{},guard_state:{},security_events:{},
  role_picker_menus:{},role_picker_drafts:{},embeds:{},moderation_cases:{},moderation_jobs:{},automod_words:{},pending_bots:{},
  customizations:{},library_data:{}
});
function readJson(file){
  try{if(!fs.existsSync(file))return null;const value=JSON.parse(fs.readFileSync(file,"utf8"));
    return value&&typeof value==="object"&&!Array.isArray(value)?value:null;}catch{return null;}
}
function renameFields(value,mapping){
  if(!value||typeof value!=="object")return false;
  let changed=false;
  for(const [oldKey,newKey] of Object.entries(mapping)){
    if(value[newKey]===undefined&&value[oldKey]!==undefined){value[newKey]=value[oldKey];changed=true;}
    if(oldKey!==newKey&&value[oldKey]!==undefined){delete value[oldKey];changed=true;}
  }
  return changed;
}
function normalizePanels(value){
  let changed=renameFields(value,{publishedPanels:"published_panels"});
  for(const panel of value.published_panels||[])if(renameFields(panel,{channelId:"channel_id",messageId:"message_id"}))changed=true;
  return changed;
}
function normalizeData(data){
  let changed=false;
  for(const value of Object.values(data.tickets||{})){
    if(renameFields(value,{panelTitle:"panel_title",panelDescription:"panel_description",openButtonLabel:"open_label",
      ticketMessage:"ticket_message",closeButtonLabel:"close_label",categoryName:"category_name",supportRoleId:"support_role_id",
      transcriptChannelId:"transcript_channel_id",panelChannelId:"panel_channel_id"}))changed=true;
    if(normalizePanels(value))changed=true;
  }
  for(const value of Object.values(data.moderation||{})){
    if(renameFields(value,{timeoutMinutes:"timeout_minutes",logChannelId:"log_channel_id",actionDurationSeconds:"action_duration_seconds",
      maxMessageCount:"max_message_count",blockInvites:"block_invites",blockMassMentions:"block_mass_mentions",
      blockExcessiveCaps:"block_excessive_caps",panelChannelId:"panel_channel_id",panelMessageId:"panel_message_id"}))changed=true;
  }
  for(const value of Object.values(data.verification||{})){
    if(renameFields(value,{roleId:"role_id",requiredRoleId:"required_role_id",reviewChannelId:"review_channel_id",
      minAccountAgeDays:"min_age_days",panelTitle:"panel_title",panelDescription:"panel_description",pointMax:"points"}))changed=true;
    if(normalizePanels(value))changed=true;
  }
  for(const value of Object.values(data.members||{})){
    if(renameFields(value,{verificationAttempts:"attempts",failedChecks:"failed",suspiciousMessages:"suspicious",
      lastJoinAt:"last_join",lastVerifiedAt:"last_verified",lastSuspiciousAt:"last_suspicious",
      lastSuspiciousReason:"last_reason"}))changed=true;
  }
  for(const value of Object.values(data.embeds||{})){
    if(renameFields(value,{guildId:"guild_id",creatorId:"creator_id"}))changed=true;
    for(const p of value.placements||[])if(renameFields(p,{channelId:"channel_id",messageId:"message_id"}))changed=true;
  }
  return changed;
}
function migrateLegacy(data,dir){
  let changed=false;
  for(const [file,key] of [["ticket-settings.json","tickets"],["ticket-config.json","tickets"],["moderation-settings.json","moderation"]]){
    const old=readJson(path.join(dir,file));if(!old)continue;
    for(const [guild,value] of Object.entries(old))if(data[key][guild]===undefined){data[key][guild]=value;changed=true;}
  }
  const verification=readJson(path.join(dir,"verification.json"));
  if(verification){
    for(const [guild,value] of Object.entries(verification.guilds||{}))if(!data.verification[guild]){data.verification[guild]=value;changed=true;}
    for(const [key,value] of Object.entries(verification.members||{}))if(!data.members[key]){data.members[key]=value;changed=true;}
  }
  const recovery=readJson(path.join(dir,"recovery-backup.json"));
  if(recovery?.guilds)for(const [guild,value] of Object.entries(recovery.guilds)){
    for(const [channel,snapshot] of Object.entries(value.channels||{})){
      const key=guild+":"+channel;if(!data.channels[key]){data.channels[key]=snapshot;changed=true;}
    }
    for(const message of value.messages||[]){
      const item={id:String(message.id||""),channel_id:String(message.channelId||message.channel_id||""),
        author_id:String(message.authorId||message.author_id||""),content:message.content||"",
        timestamp_ms:Number(message.createdAt||message.timestamp_ms)||0,attachments:message.attachments||[]};
      data.messages[guild]||=[];
      if(!data.messages[guild].some(old=>old.id===item.id)){data.messages[guild].push(item);changed=true;}
    }
  }
  return changed;
}

export class Store{
  constructor(dataDir,logger){
    this.dataDir=dataDir;fs.mkdirSync(dataDir,{recursive:true,mode:0o700});try{fs.chmodSync(dataDir,0o700);}catch{}this.file=path.join(dataDir,"timi.json");this.backup=path.join(dataDir,"timi.json.bak");
    this.logger=logger;this.data=defaults();
    const hasMain=fs.existsSync(this.file),hasBackup=fs.existsSync(this.backup);
    if(hasMain){
      const primary=readJson(this.file);
      if(primary)this.data=fillDefaults(primary,defaults());
      else if(hasBackup){
        const recovered=readJson(this.backup);
        if(!recovered)throw new Error("Both data/timi.json and its backup are invalid; refusing to reset bot data.");
        const corrupt=this.file+".corrupt-"+Date.now();fs.renameSync(this.file,corrupt);
        this.data=fillDefaults(recovered,defaults());this.logger.warn("Recovered bot data from backup; preserved invalid file at",corrupt);
      }else throw new Error("data/timi.json is invalid and no backup exists; refusing to reset bot data.");
    }else if(hasBackup){
      const recovered=readJson(this.backup);if(!recovered)throw new Error("data/timi.json is missing and backup is invalid.");
      this.data=fillDefaults(recovered,defaults());
    }
    let changed=migrateLegacy(this.data,dataDir);
    if(this.data.installed_libraries){for(const [guild,plugins] of Object.entries(this.data.installed_libraries)){this.data.installed_plugins[guild]||=plugins;}delete this.data.installed_libraries;changed=true;}
    for(const [guild,installed] of Object.entries(this.data.installed_plugins||{})){
      const migrated=[...new Set((installed||[]).flatMap(name=>name==="Foundation"?["Welcome","Auto Role","Role Picker","Embeds"]:["Moderation","Security","Shield"].includes(name)?["Kimi Lock"]:name==="Core"?["Welcome","Auto Role","Role Picker","Embeds"]:[name]).filter(name=>["Welcome","Auto Role","Role Picker","Embeds","Kimi Lock","Support"].includes(name)))];
      if(JSON.stringify(migrated)!==JSON.stringify(installed)){this.data.installed_plugins[guild]=migrated;changed=true;}
    }
    for(const key of ["developer_projects","developer_history","developer_redo","developer_active","panel_scripts"])if(this.data[key]!==undefined){delete this.data[key];changed=true;}
    if(normalizeData(this.data))changed=true;
    if(!this.data.members||typeof this.data.members!=="object"||Array.isArray(this.data.members))this.data.members={};
    this.memberCount=Object.keys(this.data.members).length;
    this.persistedData=null;
    if(changed){this.save();this.logger.info("Imported or normalized legacy Timi settings and recovery data.");}
    else this.persistedData=structuredClone(this.data);
  }
  save(){
    const previous=this.persistedData,baseline=previous||defaults();
    const rejected=[],guildIds=new Set();
    const collections=["installed_plugins","automations","welcome","tickets","moderation","verification","verification_logs","role_picker_menus","role_picker_drafts","customizations","library_data","timi_setup","automod_words","moderation_cases","moderation_jobs","pending_bots","guard_state","security_events","analytics_requests","messages"];
    for(const collection of collections){
      for(const id of Object.keys(this.data[collection]||{}))guildIds.add(id);
      for(const id of Object.keys(baseline[collection]||{}))guildIds.add(id);
    }
    for(const collection of ["pending_bots","embeds","members","channels"]){
      for(const key of Object.keys(this.data[collection]||{}))guildIds.add(key.split(":")[0]);
      for(const key of Object.keys(baseline[collection]||{}))guildIds.add(key.split(":")[0]);
    }
    for(const collection of ["role_picker_menus","role_picker_drafts"]){
      for(const value of Object.values(this.data[collection]||{}))if(value?.guild_id)guildIds.add(value.guild_id);
      for(const value of Object.values(baseline[collection]||{}))if(value?.guild_id)guildIds.add(value.guild_id);
    }
    for(const guildId of guildIds){
      const currentBytes=getGuildStorageBytes(this.data,guildId);
      const previousBytes=getGuildStorageBytes(baseline,guildId);
      const tier=getPlanForData(this.data,guildId),limit=PLANS[tier].storageBytes;
      if(currentBytes>limit&&currentBytes>previousBytes){
        restoreGuildStorage(this.data,baseline,guildId);
        rejected.push({guildId,currentBytes,previousBytes,limit});
      }
    }
    const temp=this.file+".tmp";
    if(previous&&fs.existsSync(this.file)){fs.copyFileSync(this.file,this.backup);try{fs.chmodSync(this.backup,0o600);}catch{}}
    fs.writeFileSync(temp,JSON.stringify(this.data,null,2),{mode:0o600});
    fs.renameSync(temp,this.file);try{fs.chmodSync(this.file,0o600);}catch{}
    this.persistedData=structuredClone(this.data);
    if(rejected.length){
      for(const item of rejected)this.logger.warn("Storage quota rejected a guild data increase:",item.guildId,item.currentBytes,"/",item.limit);
      throw new Error("Storage quota reached for one or more servers. Changes above the plan limit were discarded; remove saved content.");
    }
  }
  queueSave(){
    if(this.pendingSave)return;
    this.pendingSave=setTimeout(()=>{this.pendingSave=null;try{this.save();}catch(error){this.logger.error("Deferred data save failed:",error);}},750);
    this.pendingSave.unref?.();
  }
  ticket(guild){
    this.data.tickets[guild]||={};
    return fillDefaults(this.data.tickets[guild],{
      panel_title:"Support Tickets",panel_description:"Need help? Open a ticket and our team will assist you.",
      open_label:"Open Ticket",ticket_message:"Please describe what you need help with. A member of the support team will be with you shortly.",
      close_label:"Close Ticket",category_name:"ticket",support_role_id:"",transcript_channel_id:"",panel_channel_id:"",published_panels:[]
    });
  }
  mods(guild){
    this.data.moderation[guild]||={};
    return fillDefaults(this.data.moderation[guild],{enabled:true,sanction:"timeout",timeout_minutes:10,log_channel_id:"",
      action_duration_seconds:3,max_message_count:20,block_invites:true,block_mass_mentions:true,block_excessive_caps:true,
      panel_channel_id:"",panel_message_id:""});
  }
  verify(guild){
    this.data.verification[guild]||={};
    const value=fillDefaults(this.data.verification[guild],{
      role_id:"",review_channel_id:"",min_age_days:7
    });
    return value;
  }
  member(guild,user){
    if(!this.data.members||typeof this.data.members!=="object"||Array.isArray(this.data.members)){this.data.members={};this.memberCount=0;}
    if(!Number.isSafeInteger(this.memberCount)||this.memberCount<0)this.memberCount=Object.keys(this.data.members).length;
    const key=guild+":"+user;
    if(!Object.hasOwn(this.data.members,key)){
      if(this.memberCount>=100000){
        const oldest=Object.keys(this.data.members)[0];
        if(oldest!==undefined){delete this.data.members[oldest];this.memberCount--;}
      }
      this.data.members[key]={};this.memberCount++;
    }
    if(!this.data.members[key]||typeof this.data.members[key]!=="object"||Array.isArray(this.data.members[key]))this.data.members[key]={};
    const record=fillDefaults(this.data.members[key],{joins:0,leaves:0,attempts:[],failed:0,suspicious:0,last_join:0,
      last_verified:0,last_suspicious:0,last_reason:"",last_join_audited:0});
    for(const field of ["joins","leaves","failed","suspicious","last_join","last_verified","last_suspicious","last_join_audited"]){
      if(!Number.isFinite(record[field])||record[field]<0)record[field]=0;
    }
    if(!Array.isArray(record.attempts))record.attempts=[];
    else if(record.attempts.length>50)record.attempts=record.attempts.slice(-50);
    if(typeof record.last_reason!=="string")record.last_reason="";
    else record.last_reason=record.last_reason.slice(0,500);
    return record;
  }
  embed(guild,name){
    const value=this.data.embeds[guild+":"+name];if(!value)return null;
    return fillDefaults(value,{guild_id:guild,name,creator_id:"",title:"",description:"",color:8421504,author:"",
      footer:"",thumbnail:"",image:"",url:"",fields:[],placements:[]});
  }
  saveEmbed(value){this.data.embeds[value.guild_id+":"+value.name]=value;this.save();}
}
