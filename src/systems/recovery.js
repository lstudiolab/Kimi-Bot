import { AuditLogEvent, ChannelType, PermissionFlagsBits } from "discord.js";
import { nowMs, DAY, chunkText, isPrivateTextChannel } from "../utils.js";

const WEEK=7*DAY,MAX_MESSAGES=25000,MAX_ARCHIVE_BYTES=4*1024*1024;
export class Recovery {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;this.deletions=new Map();this.recovering=new Set();this.archiveBytes=new Map();}
  snapshot(channel) {
    if(!channel.guild||!channel.id)return;
    const permissions=channel.permissionOverwrites?.cache?.map(o=>({
      id:o.id,type:o.type,allow:o.allow.bitfield.toString(),deny:o.deny.bitfield.toString()
    }))||[];
    this.store.data.channels[channel.guild.id+":"+channel.id]={
      id:channel.id,name:channel.name,type:channel.type,topic:channel.topic??null,
      parent_id:channel.parentId??null,position:channel.position??0,nsfw:channel.nsfw??false,
      rate_limit_per_user:channel.rateLimitPerUser??0,bitrate:channel.bitrate??null,
      user_limit:channel.userLimit??null,permission_overwrites:permissions
    };
    this.store.queueSave();
  }
  cacheArchiveBytes(guildId,bytes){
    if(!this.archiveBytes.has(guildId)&&this.archiveBytes.size>=2000)this.archiveBytes.delete(this.archiveBytes.keys().next().value);
    this.archiveBytes.set(guildId,Math.max(0,bytes));
  }
  prune(guildId){
    const list=this.store.data.messages[guildId]||[];
    const cutoff=nowMs()-WEEK,sizeOf=value=>Buffer.byteLength(JSON.stringify(value),"utf8");
    const retained=list.filter(item=>(item.timestamp_ms||0)>=cutoff)
      .sort((a,b)=>(a.timestamp_ms||0)-(b.timestamp_ms||0));
    let bytes=retained.reduce((total,item)=>total+sizeOf(item),0);
    while(retained.length&&(retained.length>MAX_MESSAGES||bytes>MAX_ARCHIVE_BYTES))bytes-=sizeOf(retained.shift());
    const changed=retained.length!==list.length||retained.some((item,index)=>item!==list[index]);
    if(changed){this.store.data.messages[guildId]=retained;this.store.queueSave();}
    this.cacheArchiveBytes(guildId,bytes);
    return {removed:list.length-retained.length,bytes:Math.max(0,bytes),messages:retained.length};
  }
  backupMessage(message) {
    if(!message.guild||message.author.bot||(!message.content&&message.attachments.size===0))return;
    const guild=message.guild.id;
    const list=this.store.data.messages[guild]||[];this.store.data.messages[guild]=list;
    const sizeOf=value=>Buffer.byteLength(JSON.stringify(value),"utf8");
    let bytes=this.archiveBytes.get(guild);
    if(bytes===undefined){
      list.sort((a,b)=>(a.timestamp_ms||0)-(b.timestamp_ms||0));
      bytes=list.reduce((total,item)=>total+sizeOf(item),0);
    }
    const cutoff=nowMs()-WEEK;
    while(list.length&&(list[0].timestamp_ms||0)<cutoff)bytes-=sizeOf(list.shift());
    const record={
      id:message.id,channel_id:message.channelId,author_id:message.author.id,author_tag:message.author.tag,
      content:(message.content||"").slice(0,4000),timestamp_ms:message.createdTimestamp,
      attachments:[...message.attachments.values()].slice(0,10).map(a=>({name:a.name,url:a.url,content_type:a.contentType,size:a.size}))
    };
    list.push(record);bytes+=sizeOf(record);
    while(list.length&&(list.length>MAX_MESSAGES||bytes>MAX_ARCHIVE_BYTES))bytes-=sizeOf(list.shift());
    this.cacheArchiveBytes(guild,bytes);
    this.store.queueSave();
  }
  async updateMessage(message){
    if(message.partial)message=await message.fetch().catch(()=>null);
    if(!message?.guild||message.author?.bot)return false;
    const list=this.store.data.messages[message.guild.id]||[];
    const index=list.findIndex(item=>item.id===message.id);
    if(index<0)return false;
    const sizeOf=value=>Buffer.byteLength(JSON.stringify(value),"utf8");
    if(!this.archiveBytes.has(message.guild.id)){
      list.sort((a,b)=>(a.timestamp_ms||0)-(b.timestamp_ms||0));
      this.cacheArchiveBytes(message.guild.id,list.reduce((total,item)=>total+sizeOf(item),0));
    }
    const previous=sizeOf(list[index]);
    list[index]={
      ...list[index],author_tag:message.author.tag,
      content:(message.content||"").slice(0,4000),
      attachments:[...message.attachments.values()].slice(0,10).map(a=>({name:a.name,url:a.url,content_type:a.contentType,size:a.size}))
    };
    let bytes=this.archiveBytes.get(message.guild.id)-previous+sizeOf(list[index]);
    while(list.length&&(list.length>MAX_MESSAGES||bytes>MAX_ARCHIVE_BYTES))bytes-=sizeOf(list.shift());
    this.cacheArchiveBytes(message.guild.id,bytes);
    this.store.queueSave();
    return true;
  }
  async findLogChannel(guild) {
    if(this.protection)return this.protection.privateChannel(guild);
    const configured=this.store.data.timi_setup?.[guild.id]?.log_channel_id;
    const channel=configured?await guild.channels.fetch(configured).catch(()=>null):null;
    if(isPrivateTextChannel(channel,guild))return channel;
    return guild.channels.cache.find(c=>c.type===ChannelType.GuildText&&["timi-log","timi-logs","timi"].includes(c.name)&&isPrivateTextChannel(c,guild))||null;
  }
  async onChannelDelete(channel) {
    if(!channel.guild)return;
    const guild=channel.guild,id=channel.id;
    await new Promise(resolve=>setTimeout(resolve,1200));
    const audit=await guild.fetchAuditLogs({type:AuditLogEvent.ChannelDelete,limit:8}).catch(()=>null);
    const entry=audit?.entries.find(e=>e.target?.id===id&&Date.now()-e.createdTimestamp<=15000);
    const actor=entry?.executor;
    if(!actor||actor.id===guild.ownerId||actor.id===this.client.user.id||actor.bot)return;
    const key=guild.id+":"+actor.id,now=Date.now();
    for(const [storedKey,items] of this.deletions)if(!items.length||now-items[items.length-1].at>60000)this.deletions.delete(storedKey);
    if(!this.deletions.has(key)&&this.deletions.size>=2000){
      let oldestKey=null,oldestAt=Infinity;
      for(const [storedKey,items] of this.deletions){const at=items.at(-1)?.at||0;if(at<oldestAt){oldestAt=at;oldestKey=storedKey;}}
      if(oldestKey!==null)this.deletions.delete(oldestKey);
    }
    const entries=(this.deletions.get(key)||[]).filter(item=>now-item.at<=60000);
    entries.push({at:now,id});
    this.deletions.set(key,entries);
    const log=await this.findLogChannel(guild);
    if(log)await log.send({content:`Security alert: a moderator or member deleted #${channel.name||"unknown"} (${id}). ${entries.length} channel deletion(s) in 60 seconds.`});
    if(entries.length<3||this.recovering.has(key))return;
    this.recovering.add(key);
    const recoveryStartedAt=Date.now();
    try{
    let restored=0;
    const restoredChannelIds=new Map();
    const orderedEntries=entries.slice().sort((left,right)=>{
      const a=this.store.data.channels[guild.id+":"+left.id],b=this.store.data.channels[guild.id+":"+right.id];
      const aCategory=a?.type===ChannelType.GuildCategory?0:1,bCategory=b?.type===ChannelType.GuildCategory?0:1;
      return aCategory-bCategory||(a?.position||0)-(b?.position||0);
    });
    for(const item of orderedEntries) {
      const snapshot=this.store.data.channels[guild.id+":"+item.id];
      if(snapshot?.deletedAt)continue;
      if(!snapshot) {
        if(log)await log.send({content:`Recovery incomplete: no saved channel configuration exists for deleted channel ID ${item.id}.`});
        continue;
      }
      const allowedTypes=new Set([ChannelType.GuildText,ChannelType.GuildVoice,ChannelType.GuildCategory,ChannelType.GuildAnnouncement,ChannelType.GuildStageVoice,ChannelType.GuildForum]);
      const rawOverwrites=snapshot.permission_overwrites;
      const validSnapshot=allowedTypes.has(snapshot.type)&&typeof snapshot.name==="string"&&snapshot.name.length>0&&snapshot.name.length<=100&&
        Array.isArray(rawOverwrites)&&rawOverwrites.length<=100&&rawOverwrites.every(o=>/^\d{15,22}$/.test(String(o.id||""))&&[0,1].includes(o.type)&&/^\d{1,25}$/.test(String(o.allow??"0"))&&/^\d{1,25}$/.test(String(o.deny??"0")));
      if(!validSnapshot){
        if(log)await log.send({content:"Recovery skipped deleted channel "+item.id+" because its saved configuration failed safety validation."});
        continue;
      }
      const overwrites=rawOverwrites.map(o=>({
        id:o.id,allow:BigInt(o.allow||"0"),deny:BigInt(o.deny||"0"),type:o.type
      }));
      let parentId=snapshot.parent_id?restoredChannelIds.get(snapshot.parent_id)||null:null;
      if(snapshot.parent_id&&!parentId){
        const parent=await guild.channels.fetch(snapshot.parent_id).catch(()=>null);
        if(parent?.type===ChannelType.GuildCategory)parentId=parent.id;
      }
      const options={
        name:snapshot.name,type:snapshot.type,topic:snapshot.topic??undefined,
        position:snapshot.position,nsfw:snapshot.nsfw,rateLimitPerUser:snapshot.rate_limit_per_user,
        permissionOverwrites:overwrites,reason:"Timi anti-nuke channel recovery"
      };
      if(parentId)options.parent=parentId;
      if(snapshot.type===ChannelType.GuildVoice){options.bitrate=snapshot.bitrate;options.userLimit=snapshot.user_limit;}
      try {
        const created=await guild.channels.create(options);restored++;restoredChannelIds.set(item.id,created.id);
        const archive=(this.store.data.messages[guild.id]||[])
          .filter(m=>m.channel_id===item.id&&m.timestamp_ms>=nowMs()-WEEK)
          .sort((a,b)=>a.timestamp_ms-b.timestamp_ms);
        for(const message of archive) {
          const attachments=(message.attachments||[]).map(f=>`${f.name||"attachment"}: ${f.url||""}`).join(" | ");
          const text=`[Recovered archive • original message ${message.id} • <t:${Math.floor(message.timestamp_ms/1000)}:F>]\nAuthor ID: ${message.author_id}\n${message.content||"(no text content)"}${attachments?"\nAttachments: "+attachments:""}`;
          for(const part of chunkText(text,1900))await created.send({content:part,allowedMentions:{parse:[]} }).catch(()=>{});
        }
        snapshot.deletedAt=nowMs();this.store.queueSave();
      } catch(error) { this.logger.error("Could not restore deleted channel",item.id,error); }
    }

    const actorMember=await guild.members.fetch(actor.id).catch(()=>null);
    const botMember=await guild.members.fetchMe();
    if(!actorMember||actorMember.user.bot)return;
    const botTop=botMember.roles.highest.position,actorTop=actorMember.roles.highest.position;
    const hierarchyAllows=actorTop<botTop;
    const canModerate=(botMember.permissions.has(P.ModerateMembers)||botMember.permissions.has(P.Administrator))
      &&hierarchyAllows&&actorMember.moderatable;
    const canManage=(botMember.permissions.has(P.ManageRoles)||botMember.permissions.has(P.Administrator))
      &&hierarchyAllows;
    let timeoutStatus="not attempted (missing Moderate Members permission or role hierarchy)";
    if(canModerate){
      try{await actorMember.timeout(60*60*1000,"Timi anti-nuke: deleted multiple channels within 60 seconds");timeoutStatus="timed out for 60 minutes";}
      catch(error){timeoutStatus="timeout failed: "+error.message.slice(0,120);}
    }
    let removed=0,roleFailures=0;
    if(canManage){
      for(const role of actorMember.roles.cache.values()){
        if(role.id===guild.id||role.managed||role.position>=botTop)continue;
        if(await actorMember.roles.remove(role).then(()=>true).catch(()=>false))removed++;
        else roleFailures++;
      }
    }
    if(log)await log.send({content:`Anti-nuke recovery finished: recreated ${restored} of ${entries.length} deleted channel(s). <@${actor.id}>: ${timeoutStatus}; removed ${removed} manageable role(s)${roleFailures?"; "+roleFailures+" role removal(s) failed":""}. Reposted archives are copies with new message IDs; attachment source links may expire.`});
    }finally{
      const pending=(this.deletions.get(key)||[]).filter(item=>item.at>recoveryStartedAt);
      if(pending.length)this.deletions.set(key,pending);else this.deletions.delete(key);
      this.recovering.delete(key);
    }
  }
}
