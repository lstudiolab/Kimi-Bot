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
    const list=Array.isArray(rows[guild.id])?rows[guild.id]:(rows[guild.id]=[]);
    const entry={
      timestamp:Date.now(),
      user_id:member.id,
      username:member.user?.username||member.username||"Unknown member",
      display_name:member.displayName||member.user?.globalName||member.user?.username||member.username||"Unknown member",
      outcome,
      account_age_days:metadata.accountAgeDays??null,
      minimum_age_days:metadata.minimumAgeDays??null,
      checks,
      action
    };
    list.unshift(entry);
    if(list.length>300)list.length=300;
    this.store.save();
    this.logger.info("Button verification "+outcome+" for "+(member.user?.username||member.username||member.id)+" ("+member.id+") in "+guild.name+": "+action);
    return entry;
  }
  async memberJoin(member){
    const guild=member.guild,user=member.user;
    if(!guild||!user||user.bot)return;
    const settings=this.store.verify(guild.id),record=this.store.member(guild.id,user.id);
    if(record.last_verified>0)return;
    const channelId=settings.channel_id||guild.systemChannelId;
    const channel=channelId?await guild.channels.fetch(channelId).catch(()=>null):null;
    if(!channel?.isTextBased()||!channel.permissionsFor(guild.members.me)?.has([P.ViewChannel,P.SendMessages])){
      this.logger.warn("Verification prompt was not posted in "+guild.name+": configure a visible verification channel with /verify-config.");
      return;
    }
    await channel.send({
      content:"<@"+user.id+"> Please verify to access this server.",
      components:[row(button("verify:start","Verify",))],
      allowedMentions:{users:[user.id]}
    }).catch(error=>this.logger.warn("Could not post verification prompt:",error.message));
  }
  async startVerification(i){
    const guild=i.guild,member=i.member,user=i.user;
    if(!guild||!member||user.bot)return deny(i,"This verification button is not available here.");
    const record=this.store.member(guild.id,user.id),settings=this.store.verify(guild.id);
    if(record.last_verified>0)return respond(i,"You have already been verified.");
    const key=guild.id+":"+user.id;
    if(this.reviewing.has(key))return deny(i,"Your verification is already being processed.");
    this.reviewing.add(key);
    try{
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
      if(!agePass){
        record.last_reason="Account age below configured minimum";
        this.recordAudit(guild,member,"review",checks,"Member requested verification but account age is below the configured minimum; sent for manual review.",{accountAgeDays:ageDays,minimumAgeDays:minimumAge});
        const controls=[row(button("verify:review:approve:"+guild.id+":"+user.id,"Approve"),button("verify:review:reject:"+guild.id+":"+user.id,"Reject"))];
        await this.log(guild,settings.review_channel_id,"**Verification review required**\nMember: <@"+user.id+">\n"+checks.map(check=>"**"+check.name+":** "+check.detail).join("\n"),controls);
        return respond(i,"Your account does not meet the server's minimum age requirement. Your verification has been sent for moderator review.");
      }
      if(settings.role_id){
        const role=await guild.roles.fetch(settings.role_id).catch(()=>null);
        const [safe,error]=await this.validateRole(guild,role,true);
        if(!safe)return deny(i,"Verification cannot be completed. "+error);
        await member.roles.add(role,"Member completed Kimi verification");
      }
      record.last_verified=Date.now();record.last_reason="Member completed button verification";
      this.store.save();
      this.recordAudit(guild,member,"passed",checks,settings.role_id?"Member clicked Verify and received the verified role.":"Member clicked Verify; no verified role is configured.",{accountAgeDays:ageDays,minimumAgeDays:minimumAge});
      await i.message.edit({components:[]}).catch(()=>{});
      return respond(i,"Verification complete. You now have access to the server.");
    }finally{this.reviewing.delete(key);}
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
    return "**Member verification**\nMembers must click the Verify button after joining.\nVerification channel: "+mentionChannel(s.channel_id)+"\n\nVerified role: "+mentionRole(s.role_id)+"\nMinimum account age: "+s.min_age_days+" days\nManual review channel: "+mentionChannel(s.review_channel_id)+"\nOnly the configured account-age minimum determines pass or review. Avatar, previous joins, failures and behavior are recorded as context only; they are never scored. Members below the age minimum go to manual review. Kimi does not automatically kick or timeout members for verification.";
  }
  async command(i){
    if(!await requireOwner(i))return;
    const guild=i.guild,settings=structuredClone(this.store.verify(guild.id));
    const role=i.options.getRole("role");
    const age=i.options.getInteger("min-age-days");
    const review=i.options.getChannel("review-channel");
    const channel=i.options.getChannel("channel");
    if(!role&&age===null&&!review&&!channel)return respond(i,this.settingsText(settings));
    if(role){
      const [safe,error]=await this.validateRole(guild,role,true);
      if(!safe)return deny(i,error);
      settings.role_id=role.id;
    }
    if(age!==null)settings.min_age_days=Math.max(0,Math.min(3650,age));
    if(review)settings.review_channel_id=review.id;
    if(channel)settings.channel_id=channel.id;
    this.store.data.verification[guild.id]=settings;
    this.store.save();
    return respond(i,"Verification settings saved. New members must click the Verify button to complete verification.");
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
    const [,decision,guildId,botId]=match;
    if(i.guildId!==guildId)return deny(i,"This approval request belongs to a different server.");
    const guild=i.guild||await this.client.guilds.fetch(guildId);
    if(guild.ownerId!==i.user.id)return deny(i,"Only the server owner can approve or reject another bot.");
    const botMember=await guild.members.fetch(botId).catch(()=>null);
    if(!botMember?.user.bot)return deny(i,"The bot is no longer in this server or is not a bot account.");
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
    if(i.isChatInputCommand()&&["verify","verify-config"].includes(i.commandName))return this.command(i);
    if(i.isButton()&&i.customId==="verify:start")return this.startVerification(i);
    if(i.isButton()&&i.customId.startsWith("verify:review:"))return this.reviewDecision(i);
    if(i.isButton()&&i.customId.startsWith("botguard:"))return this.botDecision(i);
  }
}
