import { PermissionFlagsBits } from "discord.js";
import { DAY, snowflakeTime, mentionRole, mentionChannel, isPrivateTextChannel } from "../utils.js";
import { button, row, respond, deny, requireOwner, isManager } from "../ui.js";
import { isSafeAssignableRole } from "../permissions.js";

const P=PermissionFlagsBits;
export class Verification {
  constructor(client,store,logger){this.client=client;this.store=store;this.logger=logger;this.reviewing=new Set();}
  async validateRole(guild,role,assignable){
    if(!isSafeAssignableRole(role,guild.id))return [false,"Choose a normal role without administrator, moderation, or channel-management permissions."];
    if(!assignable)return [true];
    const me=await guild.members.fetchMe();
    if(!me.permissions.has(P.ManageRoles))return [false,"Timi needs Manage Roles permission."];
    if(role.position>=me.roles.highest.position)return [false,"Move Timi's highest role above the selected role."];
    return [true];
  }
  recordAudit(guild,member,outcome,checks,action,metadata={}){
    const rows=this.store.data.verification_logs||(this.store.data.verification_logs={});
    const list=rows[guild.id]||(rows[guild.id]=[]);
    const entry={
      timestamp:Date.now(),
      user_id:member.id,
      username:member.user.username,
      display_name:member.displayName||member.user.globalName||member.user.username,
      outcome,
      account_age_days:metadata.accountAgeDays??null,
      minimum_age_days:metadata.minimumAgeDays??null,
      checks,
      action
    };
    list.unshift(entry);
    if(list.length>300)list.length=300;
    this.store.save();
    this.logger.info("Automatic verification "+outcome+" for "+member.user.username+" ("+member.id+") in "+guild.name+": "+action);
    return entry;
  }
  async memberJoin(member){
    const guild=member.guild,user=member.user;
    if(!guild||!user||user.bot)return;
    const settings=this.store.verify(guild.id),record=this.store.member(guild.id,user.id);
    const joinAt=record.last_join||Date.now();
    if(record.last_join_audited===joinAt)return;
    record.last_join_audited=joinAt;
    const ageDays=Math.max(0,(Date.now()-snowflakeTime(user.id))/DAY);
    const minimumAge=Math.max(0,Number(settings.min_age_days)||0);
    const agePass=ageDays>=minimumAge;
    const checks=[
      {name:"Account age",status:agePass?"pass":"review",detail:"Account is "+ageDays.toFixed(1)+" days old; server minimum is "+minimumAge+" days."},
      {name:"Server history",status:"info",detail:record.joins+" recorded joins and "+record.leaves+" leaves."},
      {name:"Previous verification failures",status:"info",detail:record.failed+" previous failed or rejected checks; informational only."},
      {name:"Previously observed behavior",status:"info",detail:record.suspicious+" suspicious events recorded. "+(record.last_reason||"No previous behavior note.")+" This does not affect the decision."},
      {name:"Profile avatar",status:"info",detail:user.avatar?"Custom avatar present.":"Default avatar present; informational only."}
    ];
    let outcome=agePass?"passed":"review";
    let action="";
    const reviewControls=[row(
      button("verify:review:approve:"+guild.id+":"+user.id,"Approve"),
      button("verify:review:reject:"+guild.id+":"+user.id,"Reject")
    )];
    if(record.last_verified>0){
      outcome="already_verified";
      action="This member was verified previously; no second verification was performed.";
      if(settings.role_id&&!member.roles.cache.has(settings.role_id)){
        const role=await guild.roles.fetch(settings.role_id).catch(()=>null);
        const [safe,error]=await this.validateRole(guild,role,true);
        if(safe){
          await member.roles.add(role,"Kimi restored previously verified role");
          action="Previously verified member; verified role restored.";
        }else action+=" Role could not be restored: "+error;
      }
      this.recordAudit(guild,member,outcome,checks,action,{accountAgeDays:ageDays,minimumAgeDays:minimumAge});
      await this.log(guild,settings.review_channel_id,"Previously verified member joined: <@"+user.id+">. "+action);
      return;
    }
    if(agePass&&settings.role_id){
      const role=await guild.roles.fetch(settings.role_id).catch(()=>null);
      const [safe,error]=await this.validateRole(guild,role,true);
      if(safe){
        try{
          await member.roles.add(role,"Kimi automatic join verification passed");
          record.last_verified=Date.now();
          action="Account-age requirement passed. Verified role assigned automatically.";
        }catch(assignError){
          outcome="review";
          action="Account-age requirement passed, but role assignment failed: "+assignError.message;
        }
      }else{
        outcome="review";
        action="Account-age requirement passed, but the verified role is not assignable: "+error;
      }
    }else if(agePass){
      action="Account-age requirement passed. No verified role is configured, so no role was assigned.";
    }else{
      action="Account is younger than the configured minimum. Sent for manual review; no automatic kick or timeout.";
      record.last_reason="Account age below configured minimum";
    }
    this.recordAudit(guild,member,outcome,checks,action,{accountAgeDays:ageDays,minimumAgeDays:minimumAge});
    const detail=checks.map(check=>"**"+check.name+":** "+check.detail).join("\n");
    if(outcome==="review"){
      await this.log(guild,settings.review_channel_id,"**Automatic verification needs review**\nMember: <@"+user.id+">\n"+action+"\n"+detail,reviewControls);
    }else{
      await this.log(guild,settings.review_channel_id,"**Automatic verification passed**\nMember: <@"+user.id+">\n"+action+"\n"+detail);
    }
  }
  async log(guild,channelId,content,components=[]){
    const setup=this.store.data.timi_setup?.[guild.id]||{};
    let ch=channelId?await guild.channels.fetch(channelId).catch(()=>null):null;
    if(!isPrivateTextChannel(ch,guild)){
      const ensured=await this.ensureSetup?.(guild).catch(error=>{
        this.logger.warn("Could not secure Timi log channels for verification:",error.message);return null;
      });
      const id=ensured?.saved?.log_channel_id||setup.log_channel_id;
      ch=id?await guild.channels.fetch(id).catch(()=>null):null;
    }
    if(!isPrivateTextChannel(ch,guild)){
      this.logger.warn("Verification details were not logged because no private Timi channel is available.");return;
    }
    await ch.send({content,components,allowedMentions:{parse:[]}}).catch(error=>this.logger.warn("Verification log failed:",error.message));
  }
  settingsText(s){
    return "**Automatic member verification**\nRuns once when a member joins.\nVerified role: "+mentionRole(s.role_id)+"\nMinimum account age: "+s.min_age_days+" days\nManual review channel: "+mentionChannel(s.review_channel_id)+"\nOnly the configured account-age minimum determines pass or review. Avatar, previous joins, failures and behavior are recorded as context only; they are never scored. Members below the age minimum go to manual review. Kimi does not automatically kick or timeout members for verification.";
  }
  async command(i){
    if(!await requireOwner(i))return;
    const guild=i.guild,settings=structuredClone(this.store.verify(guild.id));
    const role=i.options.getRole("role");
    const age=i.options.getInteger("min-age-days");
    const review=i.options.getChannel("review-channel");
    if(!role&&age===null&&!review)return respond(i,this.settingsText(settings));
    if(role){
      const [safe,error]=await this.validateRole(guild,role,true);
      if(!safe)return deny(i,error);
      settings.role_id=role.id;
    }
    if(age!==null)settings.min_age_days=Math.max(0,Math.min(3650,age));
    if(review)settings.review_channel_id=review.id;
    this.store.data.verification[guild.id]=settings;
    this.store.save();
    return respond(i,"Automatic verification settings saved. New members will be checked when they join.");
  }
  async reviewDecision(i){
    const match=i.customId.match(/^verify:review:(approve|reject):(\d{15,22}):(\d{15,22})$/);
    if(!match)return deny(i,"This verification review control is invalid.");
    const [,decision,guildId,userId]=match;
    if(i.guildId!==guildId)return deny(i,"This review belongs to a different server.");
    const guild=i.guild||await this.client.guilds.fetch(guildId);
    if(guild.ownerId!==i.user.id&&!isManager(i))return deny(i,"Only server managers can decide verification reviews.");
    const key=guildId+":"+userId;
    if(this.reviewing.has(key))return deny(i,"A verification decision for this member is already being processed.");
    this.reviewing.add(key);
    try{
      const record=this.store.member(guildId,userId);
      if(record.last_verified>0)return deny(i,"This member has already been approved.");
      const member=await guild.members.fetch(userId).catch(()=>null);
      if(!member)return deny(i,"This member is no longer in the server.");
      if(decision==="approve"){
        const settings=this.store.verify(guildId);
        if(!settings.role_id)return deny(i,"Configure the verified role with /verify-config before approving members.");
        const role=await guild.roles.fetch(settings.role_id).catch(()=>null);
        const [safe,error]=await this.validateRole(guild,role,true);
        if(!safe)return deny(i,"The verified role cannot be assigned. "+error);
        await member.roles.add(role,"Timi manual verification approval");
        record.last_verified=Date.now();
        record.last_reason="Manual verification approval";
        this.store.save();
      }else{
        await member.kick("Timi verification manually rejected");
        record.failed++;
        record.last_reason="Manual verification rejection";
        this.store.save();
      }
      const auditMember=member;
      this.recordAudit(guild,auditMember,decision==="approve"?"manually_approved":"manually_rejected",[],decision==="approve"?"Moderator approved the member and assigned the verified role.":"Moderator rejected the member and removed them from the server.");
      await i.message.edit({components:[]}).catch(error=>this.logger.warn("Could not close verification review controls:",error.message));
      return respond(i,decision==="approve"?"Member approved and verified role assigned.":"Member rejected and removed from the server.");
    }finally{this.reviewing.delete(key);}
  }
  async botDecision(i){
    const match=i.customId.match(/^botguard:(yes|no):(\d+):(\d+)$/);
    if(!match)return deny(i,"This bot approval control is invalid.");
    const [,decision,guildId,botId]=match,guild=await this.client.guilds.fetch(guildId);
    if(guild.ownerId!==i.user.id&&!isManager(i))return deny(i,"Only the server owner or a member with Manage Server can decide.");
    const key=guildId+":"+botId,pending=this.store.data.pending_bots[key];
    if(pending!==i.message.id)return deny(i,"This request is no longer pending.");
    if(decision==="no"){
      await guild.members.kick(botId,"Bot rejected by server owner");
      delete this.store.data.pending_bots[key];this.store.save();
      return respond(i,"Bot rejected and removed from the server.");
    }
    const channels=await guild.channels.fetch();let failures=0;
    for(const channel of channels.values()){
      if(channel.permissionOverwrites?.cache?.has(botId)&&!["timi","timi-log","timi-logs","timi-confirmations","timi-settings"].includes(channel.name)){
        await channel.permissionOverwrites.delete(botId).catch(error=>{
          failures++;this.logger.warn("Could not remove a temporary bot restriction from "+channel.id+":",error.message);
        });
      }
    }
    if(failures)return respond(i,"Bot approval could not be completed: Timi failed to remove restrictions in "+failures+" channel(s). The request remains available so you can retry after checking permissions.");
    delete this.store.data.pending_bots[key];this.store.save();
    return respond(i,"Bot approved. Temporary channel restrictions were removed; private Timi channels remain inaccessible.");
  }
  async handle(i){
    if(i.isChatInputCommand()&&i.commandName==="verify-config")return this.command(i);
    if(i.isButton()&&i.customId.startsWith("verify:review:"))return this.reviewDecision(i);
    if(i.isButton()&&i.customId.startsWith("botguard:"))return this.botDecision(i);
  }
}
