import { randomUUID } from "node:crypto";
import { ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder, ModalBuilder, TextInputBuilder, TextInputStyle, EmbedBuilder, ChannelType, PermissionFlagsBits } from "discord.js";
import { isSafeAssignableRole } from "../permissions.js";

const button=(id,label,style=ButtonStyle.Secondary)=>new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style);
const row=(...items)=>new ActionRowBuilder().addComponents(...items);
const select=(id,placeholder,options)=>new StringSelectMenuBuilder().setCustomId(id).setPlaceholder(placeholder).addOptions(options);
const embed=(title,description)=>new EmbedBuilder().setColor(0x808080).setTitle(title).setDescription(description);
const key=(guild,user)=>guild+":"+user;
const MAX_AUTOMATIONS=25,MAX_ACTIONS=8,MAX_TIMEOUT_MINUTES=40320;
const INVITE=/discord[.]gg[/]|discord(?:app)?[.]com[/]invite[/]/i;
const LINK=/https?:\/\//i;

export function conditionMatches(condition,context){
  if(!condition||condition.type==="always")return true;
  if(condition.type==="account_age_under_days")return Number(context.accountAgeDays)<Number(condition.value);
  if(condition.type==="message_contains")return String(context.message?.content||"").toLowerCase().includes(String(condition.value||"").toLowerCase());
  if(condition.type==="contains_invite")return INVITE.test(String(context.message?.content||""));
  if(condition.type==="contains_link")return LINK.test(String(context.message?.content||""));
  if(condition.type==="channel_is")return context.message?.channelId===condition.value;
  return false;
}

function safeTemplate(template,context){
  const member=context.member,user=member?.user;
  return String(template).replaceAll("{user}",user?"<@"+user.id+">":"")
    .replaceAll("{username}",user?.username||"member")
    .replaceAll("{server}",context.guild?.name||"server")
    .replaceAll("{member_count}",String(context.guild?.memberCount||0))
    .replaceAll("{channel}",context.message?.channel?.name||"");
}

export class AutomationEngine{
  constructor({client,store,logger,services}){this.client=client;this.store=store;this.logger=logger;this.services=services;this.drafts=new Map();this.running=new Set();}
  list(guildId){return this.store.data.automations?.[guildId]||[];}
  async dashboard(i,selectedId=""){
    const items=this.list(i.guildId);
    const lines=items.length?items.slice(0,25).map((a,n)=>`**${n+1}. ${a.name}** — ${a.enabled?"On":"Off"}\nWhen ${String(a.trigger).replaceAll("_"," ")} · ${a.actions.length} step(s)`).join("\n\n"):"No automations yet. Build a flow from a trigger, optional conditions and ordered actions.";
    const components=[row(button("automation:new","Create Automation",ButtonStyle.Primary))];
    if(items.length){
      components.unshift(row(select("automation:select","Choose an automation",items.slice(0,25).map(a=>({label:a.name.slice(0,100),value:a.id,description:(a.trigger+" · "+(a.enabled?"On":"Off")).slice(0,100)})))));
      if(selectedId&&items.some(a=>a.id===selectedId)){
        const a=items.find(x=>x.id===selectedId);
        components.splice(1,0,row(...(a.trigger==="manual"?[button("automation:run:"+a.id,"Run Now",ButtonStyle.Success)]:[]),button("automation:toggle:"+a.id,a.enabled?"Turn Off":"Turn On"),button("automation:delete:"+a.id,"Delete",ButtonStyle.Danger)));
      }
    }
    components.push(row(button("automation:help","How automations work")));
    const payload={embeds:[embed("Kimi Automations",lines)],components};
    if(i.deferred||i.replied)return i.editReply(payload);
    return i.reply({...payload,ephemeral:true});
  }
  async triggerPicker(i){
    const menu=select("automation:trigger","Choose what starts this automation",[
      {label:"Run manually",value:"manual",description:"Start this automation with a Run button"},
      {label:"Member joins",value:"member_join",description:"When someone joins this server"},
      {label:"Member leaves",value:"member_leave",description:"When someone leaves this server"},
      {label:"A message is sent",value:"message_create",description:"When a member sends a message"}
    ]);
    return i.editReply({embeds:[embed("New Automation · Trigger","Choose the event Kimi should watch. This is the first block in your flow.")],components:[row(menu),row(button("automation:cancel","Cancel"))]});
  }
  async conditionPicker(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const options=[{label:"Every time",value:"always",description:"Continue whenever the trigger happens"}];
    if(d.trigger==="member_join"){
      options.push({label:"Account younger than 7 days",value:"age7",description:"Only new or recently created accounts"});
      options.push({label:"Account younger than 30 days",value:"age30",description:"Only accounts under 30 days old"});
    }
    if(d.trigger==="message_create")options.push(
      {label:"Message contains an invite",value:"invite",description:"Detect Discord invite links"},
      {label:"Message contains a web link",value:"link",description:"Detect HTTP or HTTPS links"},
      {label:"Message contains a phrase",value:"phrase",description:"Match text you specify"}
    );
    return i.editReply({embeds:[embed("Add a Condition","Conditions are optional. Kimi continues only when the selected rule matches.")],components:[row(select("automation:condition","Choose a condition",options)),row(button("automation:cancel","Cancel"))]});
  }
  async actionPicker(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const options=[{label:"Send a message",value:"send_message",description:"Post a templated message to a channel"}];
    if(d.trigger==="member_join"||d.trigger==="manual")options.push({label:"Assign a role",value:"assign_role",description:d.trigger==="manual"?"Give the person who runs it a role":"Give the joining member a role"});
    if(d.trigger==="member_join"||d.trigger==="member_leave"||d.trigger==="manual")options.push({label:"Remove a role",value:"remove_role",description:"Remove a role from the member"});
    if(d.trigger==="message_create")options.push(
      {label:"Delete the triggering message",value:"delete_message",description:"Remove the message that matched the flow"},
      {label:"Timeout the message author",value:"timeout_member",description:"Apply a temporary timeout"}
    );
    return i.editReply({embeds:[embed("Add an Action","Actions run from top to bottom. Add up to "+MAX_ACTIONS+" steps to this automation.")],components:[row(select("automation:action","Choose an action",options)),row(button("automation:cancel","Cancel"))]});
  }
  async actionModal(i,action){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const field=(id,label,placeholder,style=TextInputStyle.Short,max=100,required=true)=>new TextInputBuilder().setCustomId(id).setLabel(label).setPlaceholder(placeholder).setStyle(style).setMaxLength(max).setRequired(required);
    const modal=new ModalBuilder().setCustomId("automation:save:"+action).setTitle("Configure automation step");
    modal.addComponents(new ActionRowBuilder().addComponents(field("name","Automation name","e.g. Welcome new members",TextInputStyle.Short,80)));
    if(action==="send_message"){
      modal.addComponents(new ActionRowBuilder().addComponents(field("channel","Channel ID or mention","e.g. #welcome or channel ID")));
      modal.addComponents(new ActionRowBuilder().addComponents(field("message","Message","Use {user}, {username}, {server}, {member_count}",TextInputStyle.Paragraph,1800)));
    }else if(action==="assign_role"||action==="remove_role"){
      modal.addComponents(new ActionRowBuilder().addComponents(field("role","Role ID or mention","Choose a role below Kimi's highest role")));
    }else if(action==="timeout_member"){
      modal.addComponents(new ActionRowBuilder().addComponents(field("duration","Timeout duration in minutes","Example: 10 (maximum 40320)")));
    }
    return i.showModal(modal);
  }
  async review(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const labels={send_message:a=>"Send message to <#"+a.channel_id+">",assign_role:a=>"Assign <@&"+a.role_id+">",remove_role:a=>"Remove <@&"+a.role_id+">",timeout_member:a=>"Timeout author for "+a.duration_minutes+" minute(s)",delete_message:()=>"Delete triggering message"};
    const actions=d.actions.map((a,n)=>(n+1)+". "+(labels[a.type]?.(a)||a.type)).join("\n");
    return i.editReply({embeds:[embed("Review Automation",`**${d.name}**\n\n**When**\n${d.trigger.replaceAll("_"," ")}\n\n**Condition**\n${d.condition.label}\n\n**Actions**\n${actions}\n\nKimi executes each step in order and checks permissions at run time.`)],components:[row(button("automation:add-action","Add Action",ButtonStyle.Primary),button("automation:finish","Turn On Automation",ButtonStyle.Success)),row(button("automation:cancel","Discard"))]});
  }
  async handleInteraction(i){
    if(!i.guild||i.guild.ownerId!==i.user.id){const payload={content:"Only this server's owner can manage automations.",embeds:[],components:[]};if(i.deferred||i.replied)return i.editReply(payload);return i.reply({...payload,ephemeral:true});}
    if(i.isChatInputCommand()&&i.commandName==="automations")return this.dashboard(i);
    const id=i.customId||"";
    if(id==="automation:help")return i.editReply({embeds:[embed("How Automations Work","Build a flow with three block types:\n\n**Trigger** — a server event starts the flow.\n**Condition** — optional rules decide whether it continues.\n**Action** — Kimi performs one or more ordered steps.\n\nKimi validates role hierarchy, channel access and permissions before each action. Failed steps are logged without silently skipping the rest of the flow.")],components:[row(button("automation:new","Create Automation"),button("automation:home","Back"))]});
    if(id==="automation:home")return this.dashboard(i);
    if(id==="automation:new")return this.triggerPicker(i);
    if(id==="automation:cancel"){this.drafts.delete(key(i.guildId,i.user.id));return this.dashboard(i);}
    if(id==="automation:add-action")return this.actionPicker(i);
    if(id.startsWith("automation:trigger")&&i.isStringSelectMenu()){
      this.drafts.set(key(i.guildId,i.user.id),{name:"",trigger:i.values[0],condition:{type:"always",label:"Every time"},actions:[]});
      return this.conditionPicker(i);
    }
    if(id==="automation:condition"&&i.isStringSelectMenu()){
      const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
      const value=i.values[0];
      if(value==="phrase"){
        const modal=new ModalBuilder().setCustomId("automation:condition-phrase").setTitle("Message condition");
        modal.addComponents(new ActionRowBuilder().addComponents(new TextInputBuilder().setCustomId("phrase").setLabel("Phrase to match").setPlaceholder("Enter text to look for").setStyle(TextInputStyle.Short).setMaxLength(100).setRequired(true)));
        return i.showModal(modal);
      }
      if(i.deferred||i.replied){}else await i.deferUpdate();
      d.condition=value==="age7"?{type:"account_age_under_days",value:7,label:"Account younger than 7 days"}:value==="age30"?{type:"account_age_under_days",value:30,label:"Account younger than 30 days"}:value==="invite"?{type:"contains_invite",label:"Message contains a Discord invite"}:value==="link"?{type:"contains_link",label:"Message contains a web link"}:{type:"always",label:"Every time"};
      return this.actionPicker(i);
    }
    if(id==="automation:condition-phrase"&&i.isModalSubmit()){
      const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
      const phrase=i.fields.getTextInputValue("phrase").trim();if(!phrase)return i.editReply({content:"Enter a phrase to match.",components:[],embeds:[]});
      d.condition={type:"message_contains",value:phrase,label:"Message contains: "+phrase.slice(0,70)};
      return this.actionPicker(i);
    }
    if(id==="automation:action"&&i.isStringSelectMenu())return this.actionModal(i,i.values[0]);
    if(id.startsWith("automation:save:")&&i.isModalSubmit()){
      const action=id.split(":")[2],d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return i.editReply({content:"This automation draft expired. Start again with /automations.",components:[],embeds:[]});
      if(d.actions.length>=MAX_ACTIONS)return i.editReply({content:"This automation already has the maximum of "+MAX_ACTIONS+" actions.",components:[],embeds:[]});
      const name=i.fields.getTextInputValue("name").trim();
      if(!name||name.length>80)return i.editReply({content:"Enter an automation name between 1 and 80 characters.",components:[],embeds:[]});
      d.name=name;
      if(action==="send_message"){
        const raw=i.fields.getTextInputValue("channel").trim(),channelId=raw.replace(/[<#>]/g,"");
        if(!/^\d{15,22}$/.test(channelId))return i.editReply({content:"Enter a valid text channel mention or ID.",components:[],embeds:[]});
        const channel=await i.guild.channels.fetch(channelId).catch(()=>null);
        if(!channel||channel.type!==ChannelType.GuildText)return i.editReply({content:"Choose a text channel in this server.",components:[],embeds:[]});
        const bot=await i.guild.members.fetchMe();if(!channel.permissionsFor(bot)?.has([PermissionFlagsBits.ViewChannel,PermissionFlagsBits.SendMessages]))return i.editReply({content:"Kimi needs permission to view and send messages in that channel.",components:[],embeds:[]});
        const message=i.fields.getTextInputValue("message").trim();if(!message||message.length>1800)return i.editReply({content:"Enter a message between 1 and 1800 characters.",components:[],embeds:[]});
        d.actions.push({type:"send_message",channel_id:channelId,message});
      }else if(action==="assign_role"||action==="remove_role"){
        const raw=i.fields.getTextInputValue("role").trim(),roleId=raw.replace(/[<@&>]/g,"");
        if(!/^\d{15,22}$/.test(roleId))return i.editReply({content:"Enter a valid role mention or ID.",components:[],embeds:[]});
        const role=await i.guild.roles.fetch(roleId).catch(()=>null),bot=await i.guild.members.fetchMe();
        if(!role||!isSafeAssignableRole(role,i.guildId)||role.position>=bot.roles.highest.position||!bot.permissions.has(PermissionFlagsBits.ManageRoles))return i.editReply({content:"Choose a normal role below Kimi's highest role. Kimi also needs Manage Roles.",components:[],embeds:[]});
        d.actions.push({type:action,role_id:roleId});
      }else if(action==="timeout_member"){
        const duration=Number(i.fields.getTextInputValue("duration").trim());
        const bot=await i.guild.members.fetchMe();
        if(!Number.isInteger(duration)||duration<1||duration>MAX_TIMEOUT_MINUTES)return i.editReply({content:"Enter a whole number from 1 to 40320 minutes.",components:[],embeds:[]});
        if(!bot.permissions.has(PermissionFlagsBits.ModerateMembers))return i.editReply({content:"Kimi needs the Moderate Members permission for this action.",components:[],embeds:[]});
        d.actions.push({type:action,duration_minutes:duration});
      }else if(action==="delete_message"){
        if(!i.guild.members.me?.permissions.has(PermissionFlagsBits.ManageMessages))return i.editReply({content:"Kimi needs Manage Messages to delete triggering messages.",components:[],embeds:[]});
        d.actions.push({type:action});
      }else return i.editReply({content:"Unknown automation action.",components:[],embeds:[]});
      return this.review(i);
    }
    if(id==="automation:finish"){
      const draft=this.drafts.get(key(i.guildId,i.user.id));if(!draft||!draft.actions.length)return this.dashboard(i);
      const items=this.list(i.guildId);if(items.length>=MAX_AUTOMATIONS)return i.editReply({content:"This server has reached the "+MAX_AUTOMATIONS+" automation limit.",components:[],embeds:[]});
      const automation={id:randomUUID(),name:draft.name,enabled:true,trigger:draft.trigger,condition:draft.condition,actions:draft.actions,created_at:Date.now(),updated_at:Date.now()};
      this.store.data.automations||={};this.store.data.automations[i.guildId]||=[];this.store.data.automations[i.guildId].push(automation);this.store.save();this.drafts.delete(key(i.guildId,i.user.id));
      this.logger.info("Automation created for guild "+i.guildId+": "+automation.id);
      return i.editReply({embeds:[embed("Automation Active",automation.name+" is now enabled. Kimi will run this flow when its trigger and condition match.")],components:[row(button("automation:home","Done"))]});
    }
    if(id.startsWith("automation:run:")){
      const automation=this.list(i.guildId).find(a=>a.id===id.slice("automation:run:".length));
      if(!automation||automation.trigger!=="manual"||!automation.enabled)return i.editReply({content:"This manual automation is unavailable or turned off.",components:[],embeds:[]});
      const member=await i.guild.members.fetch(i.user.id).catch(()=>null);
      if(!member)return i.editReply({content:"Kimi could not load your server member profile.",components:[],embeds:[]});
      const results=await this.run(i.guild,"manual",{guild:i.guild,member,accountAgeDays:Math.floor((Date.now()-i.user.createdTimestamp)/86400000)},"manual:"+randomUUID());
      const failed=results.filter(result=>result.status==="rejected").length;
      return i.editReply({embeds:[embed(failed?"Automation finished with errors":"Automation completed",failed?failed+" background step(s) could not be queued. Check Kimi's logs.":"**"+automation.name+"** finished running.")],components:[row(button("automation:home","Done"))]});
    }
    if(id.startsWith("automation:toggle:")){
      const automation=this.list(i.guildId).find(a=>a.id===id.slice("automation:toggle:".length));if(automation){automation.enabled=!automation.enabled;automation.updated_at=Date.now();this.store.save();}
      return this.dashboard(i,automation?.id||"");
    }
    if(id.startsWith("automation:delete:")){
      const target=id.slice("automation:delete:".length);this.store.data.automations[i.guildId]=this.list(i.guildId).filter(a=>a.id!==target);this.store.save();return this.dashboard(i);
    }
    if(id.startsWith("automation:select")&&i.isStringSelectMenu())return this.dashboard(i,i.values[0]);
  }
  async run(guild,trigger,context,eventId){
    const jobs=this.list(guild.id).filter(a=>a.enabled&&a.trigger===trigger&&conditionMatches(a.condition,context));
    const queued=[];
    for(const automation of jobs){
      const runKey=automation.id+":"+eventId;if(this.running.has(runKey))continue;this.running.add(runKey);
      const task=async()=>{
        try{
          for(const action of automation.actions){
            try{
              if(action.type==="send_message"){
                const channel=await guild.channels.fetch(action.channel_id).catch(()=>null);if(channel?.type!==ChannelType.GuildText)continue;
                const member=context.member,user=member?.user,content=safeTemplate(action.message,{...context,guild});
                await channel.send({content,allowedMentions:{users:user?[user.id]:[]}});
              }else if((action.type==="assign_role"||action.type==="remove_role")&&context.member){
                const role=await guild.roles.fetch(action.role_id).catch(()=>null),bot=await guild.members.fetchMe();
                if(!role||!isSafeAssignableRole(role,guild.id)||role.position>=bot.roles.highest.position||!bot.permissions.has(PermissionFlagsBits.ManageRoles))throw new Error("Role action failed permission or hierarchy validation.");
                if(action.type==="assign_role")await context.member.roles.add(role,"Kimi automation: "+automation.name);
                else await context.member.roles.remove(role,"Kimi automation: "+automation.name);
              }else if(action.type==="timeout_member"&&context.member){
                const bot=await guild.members.fetchMe();if(!bot.permissions.has(PermissionFlagsBits.ModerateMembers))throw new Error("Missing Moderate Members permission.");
                await context.member.timeout(Math.min(MAX_TIMEOUT_MINUTES,Math.max(1,Number(action.duration_minutes)||1))*60000,"Kimi automation: "+automation.name);
              }else if(action.type==="delete_message"&&context.message?.deletable){
                const bot=await guild.members.fetchMe();if(!bot.permissions.has(PermissionFlagsBits.ManageMessages))throw new Error("Missing Manage Messages permission.");
                await context.message.delete();
              }
            }catch(error){this.logger.error("Automation step failed ("+automation.id+", "+action.type+"):",error);}
          }
        }finally{this.running.delete(runKey);}
      };
      if(this.services?.background)queued.push(this.services.background.enqueue("automation:"+runKey,task));
      else queued.push(task());
    }
    return Promise.allSettled(queued);
  }
  async memberJoin(member){const accountAgeDays=Math.floor((Date.now()-member.user.createdTimestamp)/86400000);return this.run(member.guild,"member_join",{member,accountAgeDays},member.id+":"+member.joinedTimestamp);}
  async memberLeave(member){return this.run(member.guild,"member_leave",{member},member.id+":"+Date.now());}
  async messageCreate(message){return this.run(message.guild,"message_create",{message,member:message.member},message.id);}
}
