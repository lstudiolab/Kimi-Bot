import { ChannelType, PermissionFlagsBits, ButtonStyle } from "discord.js";
import { DAY, nowMs, snowflakeTime } from "../utils.js";
import { button, row, greyEmbed } from "../ui.js";

const P=PermissionFlagsBits;
export class Protection {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;this.joins=new Map();this.lastAlert=new Map();this.nukeEvents=new Map();this.activeRaids=new Map();}
  async privateChannel(guild){
    const bot=await guild.members.fetchMe();
    const setup=this.store.data.timi_setup?.[guild.id]||{};
    let channel=setup.log_channel_id?await guild.channels.fetch(setup.log_channel_id).catch(()=>null):null;
    if(!channel)channel=guild.channels.cache.find(c=>c.type===ChannelType.GuildText&&(c.name==="timi-log"||c.name==="timi"));
    const permissions=[
      {id:guild.id,deny:[P.ViewChannel]},
      {id:guild.ownerId,allow:[P.ViewChannel,P.SendMessages,P.ReadMessageHistory]},
      {id:bot.id,allow:[P.ViewChannel,P.SendMessages,P.ReadMessageHistory,P.EmbedLinks,P.ManageMessages]}
    ];
    const adminRoles=guild.roles.cache.filter(role=>!role.managed&&role.permissions.has(P.ManageGuild)).first(80);
    permissions.push(...adminRoles.map(role=>({id:role.id,allow:[P.ViewChannel,P.SendMessages,P.ReadMessageHistory]})));
    if(!channel)channel=await guild.channels.create({name:"timi-log",type:ChannelType.GuildText,
      topic:"Private Timi security alerts and bot approval requests. Only the server owner, server managers, and Timi can view this channel.",
      permissionOverwrites:permissions,reason:"Create private Timi security channel"});
    else await channel.permissionOverwrites.set(permissions,"Keep Timi security channel private")
      .catch(error=>this.logger.warn("Could not refresh Timi log permissions:",error.message));
    const current=this.store.data.timi_setup[guild.id]||{};
    if(current.log_channel_id!==channel.id){
      current.log_channel_id=channel.id;this.store.data.timi_setup[guild.id]=current;
      this.store.mods(guild.id).log_channel_id=channel.id;this.store.save();
    }
    return channel;
  }
  async restrictBot(guild,botId,privateId){
    const fetched=await guild.channels.fetch(),result={total:0,restricted:0,failed:0};
    for(const channel of fetched.values()){
      if(!channel.permissionOverwrites||channel.id===privateId||["timi-log","timi-confirmations","timi-settings","timi"].includes(channel.name))continue;
      result.total++;
      try{
        await channel.permissionOverwrites.edit(botId,{ViewChannel:false,SendMessages:false,ReadMessageHistory:false,Connect:false,Speak:false},
          {reason:"Timi temporary bot approval restriction"});
        result.restricted++;
      }catch(error){
        result.failed++;this.logger.warn("Could not restrict bot in channel",channel.id,error.message);
      }
    }
    return result;
  }
  async botJoin(guild,member){
    const log=await this.privateChannel(guild);
    const setup=this.store.data.timi_setup?.[guild.id]||{};
    const confirmation=setup.confirmation_channel_id?await guild.channels.fetch(setup.confirmation_channel_id).catch(()=>null):null;
    const requestChannel=confirmation?.isTextBased()?confirmation:log;
    const msg=await requestChannel.send({
      embeds:[greyEmbed("Bot approval required",`A new bot has joined this server. Review this request before allowing it to access server channels.\\n\\nBot: <@${member.id}> (${member.user.username})\\n\\nTimi will temporarily restrict this bot after this request is posted. Select Approve or Reject below.`)],
      components:[row(button(`botguard:yes:${guild.id}:${member.id}`,"Yes",ButtonStyle.Success),button(`botguard:no:${guild.id}:${member.id}`,"No",ButtonStyle.Danger))],
      allowedMentions:{parse:[]}
    });
    this.store.data.pending_bots[guild.id+":"+member.id]=msg.id;this.store.save();
    try{
      const result=await this.restrictBot(guild,member.id,log.id);
      const status=result.failed
        ? "Restrictions applied in "+result.restricted+" of "+result.total+" channels. "+result.failed+" channel(s) could not be restricted; review those channels manually before approving."
        : "Temporary restrictions applied to "+result.restricted+" channel(s). Review this request before approving the bot.";
      await msg.edit({embeds:[greyEmbed(result.failed?"Bot access review required":"Bot approval required",`Bot: <@${member.id}> (${member.user.username})\\n\\n${status}`)]});
    }catch(error){
      this.logger.error("Could not apply temporary bot restrictions:",error);
      await msg.edit({embeds:[greyEmbed("Bot joined — restriction failed",`Bot: <@${member.id}> (${member.user.username})\\n\\nThe bot is in the server, but Timi could not apply the channel restrictions. Review its access manually.`)]}).catch(()=>{});
    }
  }
  async containRaid(guild, members, log, reason){
    const results={timedOut:0,skipped:0,failed:0};
    for(const member of members){
      if(!member||member.user?.bot||member.id===guild.ownerId||member.permissions?.has(P.Administrator)){
        results.skipped++;continue;
      }
      if(!member.moderatable){results.failed++;continue;}
      try{
        await member.timeout(10*60*1000,"Timi automatic raid containment: "+reason);
        results.timedOut++;
      }catch(error){
        results.failed++;
        this.logger.warn("Automatic raid containment failed for",member.id,error.message);
      }
    }
    return results;
  }
  async memberJoin(member){
    const guild=member.guild,user=member.user;if(!guild||!user)return;
    const record=this.store.member(guild.id,user.id);record.joins++;record.last_join=nowMs();this.store.save();
    if(user.bot)return this.botJoin(guild,member);
    if(user.id===guild.ownerId)return;
    const now=Date.now();
    if(this.joins.size>1000){
      for(const [guildId,items] of this.joins){
        const fresh=items.filter(item=>now-item.at<=10000);
        if(fresh.length)this.joins.set(guildId,fresh);else this.joins.delete(guildId);
      }
    }
    if(this.activeRaids.size>1000)for(const [guildId,until] of this.activeRaids)if(until<=now)this.activeRaids.delete(guildId);
    if(this.lastAlert.size>1000)for(const [guildId,at] of this.lastAlert)if(now-at>60*60*1000)this.lastAlert.delete(guildId);
    const activeUntil=this.activeRaids.get(guild.id)||0;
    if(activeUntil&&activeUntil<=now)this.activeRaids.delete(guild.id);
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
    const recent=(this.joins.get(guild.id)||[]).filter(item=>now-item.at<=10000);
    recent.push({at:now,id:member.id});this.joins.set(guild.id,recent);
    if(activeUntil>now){
      const log=await this.privateChannel(guild);
      const result=await this.containRaid(guild,[member],log,"ongoing join raid");
      await log.send({content:`Raid lockdown is active. New arrival <@${member.id}>: ${result.timedOut} timed out, ${result.failed} could not be contained.`,allowedMentions:{users:[member.id]}});
      return;
    }
    if(recent.length>=8){
      this.activeRaids.set(guild.id,now+60000);
      const log=await this.privateChannel(guild);
      const cohort=[];
      for(const item of recent){
        const joined=await guild.members.fetch(item.id).catch(()=>null);
        if(joined)cohort.push(joined);
      }
      const result=await this.containRaid(guild,cohort,log,"8 or more member joins within 10 seconds");
      await log.send({content:`AUTOMATIC RAID CONTAINMENT ACTIVATED. ${recent.length} members joined within 10 seconds. Timi temporarily timed out ${result.timedOut} recent non-administrator members for 10 minutes. ${result.skipped} owner, administrator, or bot accounts were excluded; ${result.failed} actions failed. New arrivals will be contained for 60 seconds. Review the member list and audit log; remove false positives manually.`});
      return;
    }
    if(recent.length>=6&&now-(this.lastAlert.get(guild.id)||0)>=60000){
      this.lastAlert.set(guild.id,now);const log=await this.privateChannel(guild);
      await log.send({content:`Security alert: ${recent.length} members joined within 10 seconds. Possible raid; automatic containment activates at 8 joins within 10 seconds.`});
    }
  }
  async alertPrivilegeEscalation(entry,guild,actorId){
    const changes=entry.changes||[];
    const sensitive=[P.Administrator,P.ManageGuild,P.ManageRoles,P.ManageChannels,P.ManageWebhooks,P.BanMembers,P.KickMembers];
    if(entry.action===31){
      const permissionChange=changes.find(change=>change.key==="permissions");
      if(!permissionChange)return false;
      const role=await guild.roles.fetch(entry.targetId).catch(()=>null);
      if(!role)return false;
      let before=0n,after=0n;
      try{
        before=BigInt(String(permissionChange.old??"0"));
        after=BigInt(String(permissionChange.new??role.permissions.bitfield));
      }catch{return false;}
      const granted=sensitive.filter(flag=>(after&flag)!==0n&&(before&flag)===0n);
      if(!granted.length)return false;
      const names=[
        [P.Administrator,"Administrator"],[P.ManageGuild,"Manage Server"],[P.ManageRoles,"Manage Roles"],
        [P.ManageChannels,"Manage Channels"],[P.ManageWebhooks,"Manage Webhooks"],
        [P.BanMembers,"Ban Members"],[P.KickMembers,"Kick Members"]
      ].filter(([flag])=>granted.includes(flag)).map(([,name])=>name);
      const log=await this.privateChannel(guild);
      await log.send({content:`PRIVILEGE ESCALATION ALERT: <@${actorId}> changed role **${role.name}** and newly granted: ${names.join(", ")}. Review the role's members and audit history immediately. Timi did not automatically revert the role because that could remove legitimate access.`,allowedMentions:{users:[actorId]}});
      return true;
    }
    if(entry.action===25){
      const added=changes.find(change=>change.key==="$add")?.new||[];
      const dangerous=[];
      for(const item of added){
        const roleId=typeof item==="string"?item:item?.id;
        if(!roleId)continue;
        const role=await guild.roles.fetch(roleId).catch(()=>null);
        if(role&&sensitive.some(flag=>role.permissions.has(flag)))dangerous.push(role);
      }
      if(!dangerous.length)return false;
      const target=entry.targetId?await guild.members.fetch(entry.targetId).catch(()=>null):null;
      const log=await this.privateChannel(guild);
      await log.send({content:`PRIVILEGE ESCALATION ALERT: <@${actorId}> granted ${dangerous.map(role=>`**${role.name}**`).join(", ")} to ${target?'<@'+target.id+'>':"a member"}. These roles carry high-impact permissions. Confirm this assignment was authorized and remove access if it was not.`,allowedMentions:{users:[actorId,...(target?[target.id]:[])]}});
      return true;
    }
    return false;
  }
  async auditLog(entry,guild){
    const destructive=new Set([12,22,32,50,52,92,13,14,15,25,31,51]);
    if(!entry||!guild||!destructive.has(entry.action))return;
    if(entry.action===31&&!(entry.changes||[]).some(change=>change.key==="permissions"))return;
    if(entry.action===25&&!(entry.changes||[]).some(change=>["$add","$remove"].includes(change.key)))return;
    const actorId=entry.executorId||entry.executor?.id;
    if(!actorId||actorId===guild.ownerId||actorId===this.client.user?.id)return;
    let privilegeEscalation=false;
    if([25,31].includes(entry.action)){
      privilegeEscalation=await this.alertPrivilegeEscalation(entry,guild,actorId).catch(error=>{
        this.logger.warn("Privilege escalation alert failed:",error.message);return false;
      });
    }
    const now=Date.now();
    for(const [storedKey,value] of this.nukeEvents){
      if(storedKey.endsWith(":triggered")){
        if(typeof value==="number"&&value<=now)this.nukeEvents.delete(storedKey);
      }else if(Array.isArray(value)){
        const fresh=value.filter(item=>now-item.at<=10000);
        if(fresh.length)this.nukeEvents.set(storedKey,fresh);else this.nukeEvents.delete(storedKey);
      }
    }
    const baseKey=guild.id+":"+actorId,events=(this.nukeEvents.get(baseKey)||[]).filter(v=>now-v.at<=10000);
    const criticalAction=[13,14,15,51].includes(entry.action)||privilegeEscalation;
    events.push({at:now,action:entry.action,critical:criticalAction});this.nukeEvents.set(baseKey,events);
    const threshold=events.some(v=>v.critical)?3:4;
    if(events.length<threshold)return;
    const key=baseKey+":triggered",triggered=this.nukeEvents.get(key)||0;
    if(triggered>now)return;
    this.nukeEvents.set(key,now+60000);
    const log=await this.privateChannel(guild);
    let action="actor flagged for immediate owner review";
    const member=await guild.members.fetch(actorId).catch(()=>null);
    if(member&&member.id!==guild.ownerId&&member.moderatable){
      await member.timeout(60*60*1000,"Timi anti-nuke: destructive audit actions exceeded the safety threshold").then(()=>{action="actor timed out for 60 minutes";}).catch(error=>this.logger.warn("Anti-nuke timeout failed:",error.message));
    }
    const actionNames={12:"channel deletion",22:"member ban",32:"role deletion",50:"webhook creation",52:"webhook deletion",92:"automated integration change",13:"channel permission creation",14:"channel permission change",15:"channel permission deletion",25:"member role change",31:"role permission change",51:"webhook update"};
    const summary=[...new Set(events.map(event=>actionNames[event.action]||"sensitive server change"))].join(", ");
    await log.send({content:"Anti-nuke alert: <@"+actorId+"> performed "+events.length+" sensitive actions within 10 seconds ("+summary+"). "+action+". Timi applied containment where possible. Review the audit log and restore affected resources.",allowedMentions:{users:[actorId]}});
  }
  async scan(guild){
    const risks=[],good=[];
    const everyone=guild.roles.everyone,owner=await guild.fetchOwner().catch(()=>null);
    const me=await guild.members.fetchMe().catch(()=>null);
    if(guild.mfaLevel===1)good.push("Server requires two-factor authentication for moderation actions.");
    else risks.push("Server does not require 2FA for moderation actions. Enable the server's 2FA requirement.");
    const verification=["None","Low","Medium","High","Very High"][guild.verificationLevel]||"Unknown";
    if(guild.verificationLevel<2)risks.push("Membership verification is "+verification+". Set it to at least Medium to slow down drive-by raids.");
    else good.push("Membership verification is "+verification+".");
    const everyoneDanger=[["Administrator",P.Administrator],["Manage Server",P.ManageGuild],["Manage Roles",P.ManageRoles],["Manage Channels",P.ManageChannels],["Manage Webhooks",P.ManageWebhooks],["Mention Everyone",P.MentionEveryone]].filter(([,flag])=>everyone.permissions.has(flag)).map(([name])=>name);
    if(everyoneDanger.length)risks.push("@everyone has dangerous permissions: "+everyoneDanger.join(", ")+". Remove these permissions.");
    else good.push("@everyone has no high-impact administrative permissions.");
    const privileged=guild.roles.cache.filter(role=>role.id!==guild.id&&!role.managed&&[P.Administrator,P.ManageGuild,P.ManageRoles,P.ManageChannels,P.ManageWebhooks,P.BanMembers,P.KickMembers].some(flag=>role.permissions.has(flag)));
    if(privileged.size>8)risks.push(privileged.size+" roles have high-impact permissions. Reduce the number and audit who can assign them.");
    else good.push(privileged.size+" role(s) have high-impact permissions.");
    const botRequired=[["View Audit Log",P.ViewAuditLog],["Manage Channels",P.ManageChannels],["Manage Roles",P.ManageRoles],["Moderate Members",P.ModerateMembers],["Manage Messages",P.ManageMessages],["Ban Members",P.BanMembers],["Kick Members",P.KickMembers]];
    const missing=botRequired.filter(([,flag])=>!me?.permissions.has(flag)).map(([name])=>name);
    if(missing.length)risks.push("Timi is missing permissions needed for full protection: "+missing.join(", ")+". Grant only the permissions required by the features you use.");
    else good.push("Timi has the core permissions used by Security.");
    const setup=this.store.data.timi_setup?.[guild.id]||{};
    const log=setup.log_channel_id?await guild.channels.fetch(setup.log_channel_id).catch(()=>null):null;
    if(!log)risks.push("Timi log channel is not configured or is missing. Run /setup.");
    else good.push("Timi log channel is configured.");
    const botCount=guild.members.cache.filter(member=>member.user.bot).size;
    if(botCount>20)risks.push("This server has "+botCount+" bots. Review each bot's identity, permissions and need to remain installed.");
    const lines=["**Timi Security Audit**","", "**Risks to review ("+risks.length+")**",...(risks.length?risks.map((v,index)=>(index+1)+". "+v):["No common configuration risks were detected."]), "", "**Checks passed ("+good.length+")**",...good.map(v=>"• "+v),"","This is a configuration audit, not a penetration test. It cannot detect compromised accounts, malicious code, leaked tokens or every permission path."];
    return lines.join("\n").slice(0,1900);
  }
  async ready(guild){
    try{await this.privateChannel(guild);}
    catch(error){this.logger.warn("Could not initialize Timi security channel for",guild.id,error.message);}
  }
}
