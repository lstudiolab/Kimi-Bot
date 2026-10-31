import { ChannelType, PermissionFlagsBits, ButtonStyle } from "discord.js";
import { DAY, nowMs, snowflakeTime } from "../utils.js";
import { button, row, greyEmbed } from "../ui.js";

const P=PermissionFlagsBits;
export class Protection {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;this.joins=new Map();this.lastAlert=new Map();this.nukeEvents=new Map();}
  async privateChannel(guild){
    const bot=await guild.members.fetchMe();
    let channel=guild.channels.cache.find(c=>c.type===ChannelType.GuildText&&c.name==="timi");
    const permissions=[
      {id:guild.id,deny:[P.ViewChannel]},
      {id:guild.ownerId,allow:[P.ViewChannel,P.SendMessages,P.ReadMessageHistory]},
      {id:bot.id,allow:[P.ViewChannel,P.SendMessages,P.ReadMessageHistory,P.EmbedLinks,P.ManageMessages]}
    ];
    if(channel){await channel.permissionOverwrites.set(permissions,"Keep Timi security channel private").catch(()=>{});return channel;}
    return guild.channels.create({name:"timi",type:ChannelType.GuildText,
      topic:"Private Timi security alerts and bot approval requests. Only the server owner and Timi can view this channel.",
      permissionOverwrites:permissions,reason:"Create private Timi security channel"});
  }
  async restrictBot(guild,botId,privateId){
    for(const channel of guild.channels.cache.values()){
      if(!channel.permissionOverwrites||channel.id===privateId)continue;
      await channel.permissionOverwrites.edit(botId,{ViewChannel:false,SendMessages:false,ReadMessageHistory:false,Connect:false,Speak:false},
        {reason:"Timi temporary bot approval restriction"}).catch(error=>this.logger.warn("Could not restrict bot in channel",channel.id,error.message));
    }
  }
  async botJoin(guild,member){
    const log=await this.privateChannel(guild);
    await this.restrictBot(guild,member.id,log.id);
    const msg=await log.send({
      embeds:[greyEmbed("Bot approval required",`Do you agree on giving this bot permission to serve this server?\n\nBot: <@${member.id}> (${member.user.username})\n\nAccess is temporarily restricted while approval is pending.`)],
      components:[row(button(`botguard:yes:${guild.id}:${member.id}`,"Yes",ButtonStyle.Success),button(`botguard:no:${guild.id}:${member.id}`,"No",ButtonStyle.Danger))],
      allowedMentions:{parse:[]}
    });
    this.store.data.pending_bots[guild.id+":"+member.id]=msg.id;this.store.save();
  }
  async memberJoin(member){
    const guild=member.guild,user=member.user;if(!guild||!user)return;
    const record=this.store.member(guild.id,user.id);record.joins++;record.last_join=nowMs();this.store.save();
    if(user.bot)return this.botJoin(guild,member);
    if(user.id===guild.ownerId)return;
    const age=nowMs()-snowflakeTime(user.id);
    if(age<7*DAY){
      const log=await this.privateChannel(guild);let action="flagged for moderator review";
      if(age<3*DAY){
        try{await member.timeout(10*60*1000,"Timi new-account safety timeout");action="temporarily timed out for 10 minutes";}
        catch{action="flagged; timeout could not be applied";}
      }
      await log.send({content:`New-account alert: <@${user.id}> joined with an account ${Math.floor(age/DAY)} day(s) old. Action: ${action}.`,
        allowedMentions:{users:[user.id]}});
    }
    const now=Date.now(),list=(this.joins.get(guild.id)||[]).filter(stamp=>now-stamp<=10000);
    list.push(now);this.joins.set(guild.id,list);
    if(list.length>=6&&now-(this.lastAlert.get(guild.id)||0)>=60000){
      this.lastAlert.set(guild.id,now);const log=await this.privateChannel(guild);
      await log.send({content:`Security alert: ${list.length} members joined within 10 seconds. Possible raid; review the server. No automatic raid punishment was applied.`});
    }
  }
  async auditLog(entry,guild){
    const destructive=new Set([12,22,32,50,52,92]);
    if(!entry||!guild||!destructive.has(entry.action))return;
    const actorId=entry.executorId||entry.executor?.id;
    if(!actorId||actorId===guild.ownerId||actorId===this.client.user?.id)return;
    const now=Date.now(),events=(this.nukeEvents.get(guild.id+":"+actorId)||[]).filter(v=>now-v.at<=10000);
    events.push({at:now,action:entry.action});this.nukeEvents.set(guild.id+":"+actorId,events);
    if(events.length<4||events.length===4&&events.some(v=>v.at<now-10000))return;
    const key=guild.id+":"+actorId+":triggered",triggered=this.nukeEvents.get(key);
    if(triggered)return;
    this.nukeEvents.set(key,true);
    const log=await this.privateChannel(guild);
    let action="actor flagged for immediate owner review";
    const member=await guild.members.fetch(actorId).catch(()=>null);
    if(member&&member.id!==guild.ownerId&&member.moderatable){
      await member.timeout(60*60*1000,"Timi anti-nuke: destructive audit actions exceeded the safety threshold").then(()=>{action="actor timed out for 60 minutes";}).catch(error=>this.logger.warn("Anti-nuke timeout failed:",error.message));
    }
    await log.send({content:"Anti-nuke alert: <@"+actorId+"> performed "+events.length+" destructive server actions within 10 seconds. "+action+". Review the audit log and restore affected resources where possible.",allowedMentions:{users:[actorId]}});
  }
  async ready(guild){
    try{await this.privateChannel(guild);}
    catch(error){this.logger.warn("Could not initialize Timi security channel for",guild.id,error.message);}
  }
}
