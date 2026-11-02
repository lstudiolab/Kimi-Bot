import { randomUUID } from "node:crypto";
import { ActionRowBuilder, ButtonBuilder, ButtonStyle, StringSelectMenuBuilder, ModalBuilder, TextInputBuilder, TextInputStyle, EmbedBuilder, ChannelType, PermissionFlagsBits } from "discord.js";
import { isSafeAssignableRole } from "../permissions.js";

const button=(id,label,style=ButtonStyle.Secondary)=>new ButtonBuilder().setCustomId(id).setLabel(label).setStyle(style);
const row=(...items)=>new ActionRowBuilder().addComponents(...items);
const select=(id,placeholder,options)=>new StringSelectMenuBuilder().setCustomId(id).setPlaceholder(placeholder).addOptions(options);
const embed=(title,description)=>new EmbedBuilder().setColor(0x808080).setTitle(title).setDescription(description);
const key=(guild,user)=>guild+":"+user;

export function conditionMatches(condition,context){
  if(!condition||condition.type==="always")return true;
  if(condition.type==="account_age_under_days")return Number(context.accountAgeDays)<Number(condition.value);
  if(condition.type==="message_contains")return String(context.message?.content||"").toLowerCase().includes(String(condition.value||"").toLowerCase());
  if(condition.type==="contains_invite")return /discord[.]gg[/]|discord(?:app)?[.]com[/]invite[/]/i.test(String(context.message?.content||""));
  return false;
}

export class AutomationEngine{
  constructor({client,store,logger,services}){this.client=client;this.store=store;this.logger=logger;this.services=services;this.drafts=new Map();this.running=new Set();}
  list(guildId){return this.store.data.automations?.[guildId]||[];}
  save(guildId){this.store.queueSave();}
  async open(i){return this.dashboard(i);}
  async dashboard(i,selectedId=""){
    const items=this.list(i.guildId);
    const lines=items.length?items.map((a,n)=>`**${n+1}. ${a.name}** — ${a.enabled?"On":"Off"}\nWhen ${a.trigger.replaceAll("_"," ")} · ${a.actions.length} action(s)`).join("\n\n"):"No automations yet. Create one to make Kimi handle repetitive server tasks automatically.";
    const components=[row(button("automation:new","Create Automation",ButtonStyle.Primary))];
    if(items.length){
      components.unshift(row(select("automation:select","Choose an automation",items.slice(0,25).map(a=>({label:a.name.slice(0,100),value:a.id,description:(a.trigger+" · "+(a.enabled?"On":"Off")).slice(0,100)})))));
      if(selectedId&&items.some(a=>a.id===selectedId)){
        const a=items.find(x=>x.id===selectedId);
        components.splice(1,0,row(button("automation:toggle:"+a.id,a.enabled?"Turn Off":"Turn On"),button("automation:delete:"+a.id,"Delete",ButtonStyle.Danger)));
      }
    }
    components.push(row(button("automation:help","How automations work")));
    const payload={embeds:[embed("Kimi Automations",lines)],components};
    if(i.deferred||i.replied)return i.editReply(payload);
    return i.reply({...payload,ephemeral:true});
  }
  async triggerPicker(i){
    const menu=select("automation:trigger","Choose what starts this automation",[
      {label:"Member joins",value:"member_join",description:"When someone joins this server"},
      {label:"Member leaves",value:"member_leave",description:"When someone leaves this server"},
      {label:"A message is sent",value:"message_create",description:"When a member sends a message"}
    ]);
    return i.editReply({embeds:[embed("New Automation · Trigger","Every automation starts with an event. Choose what Kimi should watch for.")],components:[row(menu),row(button("automation:cancel","Cancel"))]});
  }
  async conditionPicker(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const options=[{label:"Every time",value:"always",description:"Run whenever the trigger happens"}];
    if(d.trigger==="member_join"){
      options.push({label:"Account younger than 7 days",value:"age7",description:"Only run for newer Discord accounts"});
      options.push({label:"Account younger than 30 days",value:"age30",description:"Only run for accounts under 30 days"});
    }
    if(d.trigger==="message_create")options.push({label:"Message contains an invite",value:"invite",description:"Only run when a Discord invite is present"});
    return i.editReply({embeds:[embed("New Automation · Condition","Add a condition to decide when the automation should continue. This step is optional.")],components:[row(select("automation:condition","Choose a condition",options)),row(button("automation:cancel","Cancel"))]});
  }
  async actionPicker(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const options=[{label:"Send a message",value:"send_message",description:"Send a message to a channel"}];
    if(d.trigger==="member_join")options.push({label:"Assign a role",value:"assign_role",description:"Give the new member a server role"});
    return i.editReply({embeds:[embed("New Automation · Action","Choose what Kimi should do when the trigger and condition match.")],components:[row(select("automation:action","Choose an action",options)),row(button("automation:cancel","Cancel"))]});
  }
  async actionModal(i,action){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const field=(id,label,placeholder,style=TextInputStyle.Short,max=100,required=true)=>new TextInputBuilder().setCustomId(id).setLabel(label).setPlaceholder(placeholder).setStyle(style).setMaxLength(max).setRequired(required);
    const modal=new ModalBuilder().setCustomId("automation:save:"+action).setTitle(action==="send_message"?"Add message action":"Add role action");
    if(d.name)modal.addComponents(new ActionRowBuilder().addComponents(field("name","Automation name","e.g. Welcome new members",TextInputStyle.Short,80)));
    else modal.addComponents(new ActionRowBuilder().addComponents(field("name","Automation name","e.g. Welcome new members",TextInputStyle.Short,80)));
    if(action==="send_message"){
      modal.addComponents(new ActionRowBuilder().addComponents(field("channel","Channel ID or mention","e.g. #welcome or channel ID")));
      modal.addComponents(new ActionRowBuilder().addComponents(field("message","Message","Use {user}, {username}, {server}, {member_count}",TextInputStyle.Paragraph,1800)));
    }else{
      modal.addComponents(new ActionRowBuilder().addComponents(field("role","Role ID or mention","Choose a role below Kimi's highest role")));
    }
    return i.showModal(modal);
  }
  async review(i){
    const d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return this.dashboard(i);
    const actions=d.actions.map((a,n)=>a.type==="send_message"?(n+1)+". Send message to <#"+a.channel_id+">":(n+1)+". Assign <@&"+a.role_id+">").join("\n");
    return i.editReply({embeds:[embed("Review Automation",`**${d.name}**\nWhen: ${d.trigger.replaceAll("_"," ")}\nCondition: ${d.condition.type==="always"?"Every time":d.condition.label}\n\n**Actions**\n${actions}\n\nAdd more actions or finish to activate this automation.`)],components:[row(button("automation:add-action","Add Action",ButtonStyle.Primary),button("automation:finish","Finish"))]});
  }
  async handleInteraction(i){
    if(!i.guild||i.guild.ownerId!==i.user.id){const payload={content:"Only this server owner can manage automations.",embeds:[],components:[]};if(i.deferred||i.replied)return i.editReply(payload);return i.reply({...payload,ephemeral:true});}
    if(i.isChatInputCommand()&&i.commandName==="automations")return this.dashboard(i);
    const id=i.customId||"";
    if(id==="automation:help")return i.editReply({embeds:[embed("How Automations Work","**Trigger** — an event such as a member joining.\n**Condition** — an optional rule that must match.\n**Action** — something Kimi does, such as sending a message or assigning a role.\n\nAutomations run in order. Kimi checks permissions and validates each action before execution.")],components:[row(button("automation:new","Create Automation"),button("automation:home","Back"))]});
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
      d.condition=value==="age7"?{type:"account_age_under_days",value:7,label:"Account younger than 7 days"}:value==="age30"?{type:"account_age_under_days",value:30,label:"Account younger than 30 days"}:value==="invite"?{type:"contains_invite",value:"",label:"Message contains a Discord invite"}:{type:"always",label:"Every time"};
      return this.actionPicker(i);
    }
    if(id==="automation:action"&&i.isStringSelectMenu())return this.actionModal(i,i.values[0]);
    if(id.startsWith("automation:save:")&&i.isModalSubmit()){
      const action=id.split(":")[2],d=this.drafts.get(key(i.guildId,i.user.id));if(!d)return i.editReply({content:"This automation draft expired. Start again with /automations.",components:[],embeds:[]});
      const name=i.fields.getTextInputValue("name").trim();
      if(!name||name.length>80)return i.editReply({content:"Enter an automation name between 1 and 80 characters.",components:[],embeds:[]});
      d.name=name;
      if(action==="send_message"){
        const raw=i.fields.getTextInputValue("channel").trim(),channelId=raw.replace(/[<#>]/g,"");
        if(!/^\d{15,22}$/.test(channelId))return i.editReply({content:"Enter a valid text channel mention or ID.",components:[],embeds:[]});
        const channel=await i.guild.channels.fetch(channelId).catch(()=>null);
        if(!channel||channel.type!==ChannelType.GuildText)return i.editReply({content:"Choose a text channel in this server.",components:[],embeds:[]});
        const message=i.fields.getTextInputValue("message").trim();
        if(!message||message.length>1800)return i.editReply({content:"Enter a message between 1 and 1800 characters.",components:[],embeds:[]});
        d.actions.push({type:"send_message",channel_id:channelId,message});
      }else if(action==="assign_role"){
        const raw=i.fields.getTextInputValue("role").trim(),roleId=raw.replace(/[<@&>]/g,"");
        if(!/^\d{15,22}$/.test(roleId))return i.editReply({content:"Enter a valid role mention or ID.",components:[],embeds:[]});
        const role=await i.guild.roles.fetch(roleId).catch(()=>null),bot=await i.guild.members.fetchMe();
        if(!role||!isSafeAssignableRole(role,i.guildId)||role.position>=bot.roles.highest.position||!bot.permissions.has(PermissionFlagsBits.ManageRoles))return i.editReply({content:"Choose a normal role below Kimi's highest role. Kimi also needs Manage Roles.",components:[],embeds:[]});
        d.actions.push({type:"assign_role",role_id:roleId});
      }else return i.editReply({content:"Unknown automation action.",components:[],embeds:[]});
      return this.review(i);
    }
    if(id==="automation:finish"){
      const draft=this.drafts.get(key(i.guildId,i.user.id));if(!draft||!draft.actions.length)return this.dashboard(i);
      const automation={id:randomUUID(),name:draft.name,enabled:true,trigger:draft.trigger,condition:draft.condition,actions:draft.actions,created_at:Date.now(),updated_at:Date.now()};
      this.store.data.automations||={};this.store.data.automations[i.guildId]||=[];this.store.data.automations[i.guildId].push(automation);this.store.save();this.drafts.delete(key(i.guildId,i.user.id));
      this.logger.info("Automation created for guild "+i.guildId+": "+automation.id);
      return i.editReply({embeds:[embed("Automation Active",automation.name+" is now enabled. Kimi will run it when its trigger and condition match.")],components:[row(button("automation:home","Done"))]});
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
    for(const automation of jobs){
      const key=automation.id+":"+eventId;if(this.running.has(key))continue;this.running.add(key);
      const task=async()=>{try{for(const action of automation.actions){if(action.type==="send_message"){const channel=await guild.channels.fetch(action.channel_id).catch(()=>null);if(channel?.type!==ChannelType.GuildText)continue;const member=context.member,user=member?.user;const content=String(action.message).replaceAll("{user}",user?"<@"+user.id+">":"").replaceAll("{username}",user?.username||"member").replaceAll("{server}",guild.name).replaceAll("{member_count}",String(guild.memberCount||0));await channel.send({content,allowedMentions:{users:user?[user.id]:[]}});}else if(action.type==="assign_role"&&context.member){const role=await guild.roles.fetch(action.role_id).catch(()=>null),bot=await guild.members.fetchMe();if(role&&isSafeAssignableRole(role,guild.id)&&role.position<bot.roles.highest.position&&bot.permissions.has(PermissionFlagsBits.ManageRoles))await context.member.roles.add(role,"Kimi automation: "+automation.name);}}}catch(error){this.logger.error("Automation failed ("+automation.id+"):",error);}finally{this.running.delete(key);}};
      if(this.services?.background)this.services.background.enqueue("automation:"+key,task).catch(error=>{this.running.delete(key);this.logger.warn("Automation queue rejected work:",error.message);});
      else await task();
    }
  }
  async memberJoin(member){const accountAgeDays=Math.floor((Date.now()-member.user.createdTimestamp)/86400000);return this.run(member.guild,"member_join",{member,accountAgeDays},member.id+":"+member.joinedTimestamp);}
  async memberLeave(member){return this.run(member.guild,"member_leave",{member},member.id+":"+Date.now());}
  async messageCreate(message){return this.run(message.guild,"message_create",{message,member:message.member},message.id);}
}
