import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { isSnowflake, normalizeMessage, jaccard, cleanChannelName, snowflakeTime, renderTemplate, TEMPLATE_PLACEHOLDERS, isHttpsUrlTemplate, chunkText, matchesBlockedPhrase } from "../src/utils.js";
import { loadConfig } from "../src/config.js";
import { Store } from "../src/store.js";

const quiet={debug(){},info(){},warn(){},error(){}};

test("pre-rename ticket settings filename remains supported",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-legacy-ticket-"));
  try{
    fs.writeFileSync(path.join(dir,"ticket-settings.json"),JSON.stringify({"guild-old":{panelTitle:"Old Support"}}));
    const store=new Store(dir,quiet);
    assert.equal(store.ticket("guild-old").panel_title,"Old Support");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("Snowflake validation accepts Discord IDs only",()=>{
  assert.equal(isSnowflake("123456789012345678"),true);
  assert.equal(isSnowflake("not-an-id"),false);
  assert.equal(isSnowflake("123"),false);
});
test("message normalization removes invite and mention formatting",()=>{
  assert.equal(normalizeMessage("HELLO!!! https://example.com <@123456789012345678>"),"hello url mention");
});
test("Jaccard similarity handles repeated and unrelated messages",()=>{
  assert.equal(jaccard("same same","same"),1);
  assert.equal(jaccard("one two","three four"),0);
});
test("channel names are normalized and bounded",()=>{
  assert.equal(cleanChannelName("Hello World!!"),"hello-world");
  assert.ok(cleanChannelName("a".repeat(150)).length<=90);
});
test("Snowflake timestamps are positive",()=>{
  assert.ok(snowflakeTime("123456789012345678")>0);
});
test(".env loader reads credentials and creates its data directory",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-config-"));
  const keys=["DISCORD_TOKEN","CLIENT_ID","GUILD_ID","DATA_DIR","LOG_LEVEL"];
  const previous=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
  try{
    for(const key of keys)delete process.env[key];
    fs.writeFileSync(path.join(dir,".env"),"DISCORD_TOKEN=test-token\r\nCLIENT_ID=123456789012345678\r\nGUILD_ID=\r\nDATA_DIR=state\r\n");
    const config=loadConfig(dir);
    assert.equal(config.token,"test-token");
    assert.equal(config.clientId,"123456789012345678");
    assert.equal(config.guildId,null);
    assert.equal(config.dataDir,path.join(dir,"state"));
    assert.ok(fs.existsSync(config.dataDir));
  }finally{
    for(const key of keys){if(previous[key]===undefined)delete process.env[key];else process.env[key]=previous[key];}
    fs.rmSync(dir,{recursive:true,force:true});
  }
});
test("persistent store saves defaults and reloads settings",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-store-"));
  try{
    const store=new Store(dir,quiet),settings=store.ticket("123456789012345678");
    settings.panel_title="Help Desk";store.save();
    const reloaded=new Store(dir,quiet);
    assert.equal(reloaded.ticket("123456789012345678").panel_title,"Help Desk");
    assert.ok(fs.existsSync(path.join(dir,"timi.json")));
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test("pending moderation jobs survive a bot restart",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-moderation-jobs-"));
  try{
    const store=new Store(dir,quiet);
    store.data.moderation_jobs["guild-a"]=[{
      id:"automod:guild-a:message-a",type:"automod-sanction",status:"pending",
      guild_id:"guild-a",user_id:"user-a",channel_id:"channel-a",message_ids:["message-a"],
      reason:"message burst",steps:{deleted:true,sanction:false,logged:false},attempts:1
    }];
    store.save();
    const restarted=new Store(dir,quiet);
    const [job]=restarted.data.moderation_jobs["guild-a"];
    assert.equal(job.status,"pending");
    assert.equal(job.steps.deleted,true);
    assert.equal(job.steps.sanction,false);
    assert.equal(job.id,"automod:guild-a:message-a");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("legacy configuration files are imported without overwriting new data",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-legacy-"));
  try{
    fs.writeFileSync(path.join(dir,"ticket-config.json"),JSON.stringify({"123456789012345678":{panelTitle:"Legacy Support"}}));
    const store=new Store(dir,quiet);
    assert.equal(store.ticket("123456789012345678").panel_title,"Legacy Support");
    const reloaded=new Store(dir,quiet);
    assert.equal(reloaded.ticket("123456789012345678").panel_title,"Legacy Support");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

import { PluginManager } from "../src/plugin-manager.js";
import { PLUGINS, normalizePluginName } from "../src/plugins/index.js";

test("Kimi exposes three focused first-party plugins",()=>{
  assert.deepEqual(Object.keys(PLUGINS),["Foundation","Kimi Lock","Support"]);
  for(const plugin of Object.values(PLUGINS)){
    assert.equal(typeof plugin.create,"function");
    assert.ok(plugin.systems.length>0);
    assert.ok(plugin.description.length>20);
  }
  assert.equal(normalizePluginName(" moderation "),"Kimi Lock");
  assert.equal(normalizePluginName("Security"),"Kimi Lock");
  assert.equal(normalizePluginName("Developer"),null);
  assert.equal(normalizePluginName("Support"),"Support");
  assert.equal(normalizePluginName("Unknown"),null);
});
test("plugin installation is isolated per server and preserves data",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-plugins-"));
  try{
    const store=new Store(dir,quiet),manager=new PluginManager(store,quiet);
    store.ticket("guild-a").panel_title="Saved support";store.save();
    assert.equal(manager.install("guild-a","Support").ok,true);
    assert.equal(manager.installed("guild-a","Support"),true);
    assert.equal(manager.installed("guild-b","Support"),false);
    assert.equal(manager.install("guild-a","Support").ok,false);
    assert.equal(manager.uninstall("guild-a","Support").ok,true);
    assert.equal(manager.installed("guild-a","Support"),false);
    assert.equal(new Store(dir,quiet).ticket("guild-a").panel_title,"Saved support");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

import { commandData, coreCommandData, pluginCommandsForPlugins, pluginForCommand } from "../src/commands.js";
test("app management commands are registered with the intended option behavior",()=>{
  const install=commandData.find(command=>command.name==="install");
  const uninstall=commandData.find(command=>command.name==="uninstall");
  const list=commandData.find(command=>command.name==="apps");
  assert.ok(install&&uninstall&&list);
  assert.equal(install.options[0].name,"app");
  assert.equal(install.options[0].required,true);
  assert.equal(uninstall.options[0].required,true);
  assert.ok(commandData.some(command=>command.name==="filter"));
  assert.ok(commandData.some(command=>command.name==="security"));
  for(const name of ["plan","apps","app-store","install","uninstall"]) {
    assert.ok(commandData.some(command=>command.name===name),"missing slash command: "+name);
    assert.ok(coreCommandData.some(command=>command.name===name),"missing core app command: "+name);
  }
});


test("pending moderation jobs survive a process restart",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-moderation-jobs-"));
  try{
    const first=new Store(dir,quiet);
    first.data.moderation_jobs["guild-a"]=[{
      id:"automod:guild-a:message-a",type:"automod-sanction",status:"pending",
      guild_id:"guild-a",user_id:"user-a",channel_id:"channel-a",message_ids:["message-a"],
      reason:"message burst",warning_id:1,action:"timeout",timeout_minutes:10,
      action_duration_seconds:3,steps:{deleted:false,sanction:false,logged:false},attempts:0
    }];
    first.save();
    const restarted=new Store(dir,quiet);
    const [job]=restarted.data.moderation_jobs["guild-a"];
    assert.equal(job.status,"pending");
    assert.equal(job.user_id,"user-a");
    assert.deepEqual(job.steps,{deleted:false,sanction:false,logged:false});
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

import { PLANS, getGuildPlan, getStorageReport, canStoreGuildState, getGuildStorageBytes } from "../src/subscriptions.js";

test("Timi has one free plan with a 5 MB per-server storage limit",()=>{
  assert.equal(PLANS.free.storageBytes,5*1024*1024);
  assert.equal(PLANS.free.priceMonthly,0);
  assert.equal(PLANS.pro,undefined);
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-plans-"));
  try{
    const store=new Store(dir,quiet);
    assert.equal(getGuildPlan(store,"guild-plan"),"free");
    assert.equal(getStorageReport(store,"guild-plan").limit,5*1024*1024);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("first save enforces the 5 MB quota before a data file exists",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-first-save-quota-"));
  try{
    const store=new Store(dir,quiet);
    store.data.customizations["first-guild"]={payload:"x".repeat(5*1024*1024)};
    assert.throws(()=>store.save(),/Storage quota reached/);
    assert.equal(getGuildStorageBytes(store.data,"first-guild"),getGuildStorageBytes({}, "first-guild"));
    const persisted=JSON.parse(fs.readFileSync(path.join(dir,"timi.json"),"utf8"));
    assert.equal(getGuildStorageBytes(persisted,"first-guild"),getGuildStorageBytes({}, "first-guild"));
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("storage allocation is fixed at 5 MB for every server",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-storage-"));
  try{
    const store=new Store(dir,quiet);
    const source="x".repeat(5*1024*1024+1024);
    const customizations={...(store.data.customizations||{}),["guild-free"]:{payload:source}};
    const report=canStoreGuildState(store,"guild-free",{customizations});
    assert.equal(report.ok,false);
    assert.equal(report.limit,5*1024*1024);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("Foundation publishes only its requested member systems",()=>{const names=pluginCommandsForPlugins(["Foundation"]).map(command=>command.name);for(const name of ["setup","welcome","autorole","roles","embed-new","embed-edit","embed-post"])assert.ok(names.includes(name),"missing Foundation command: "+name);for(const name of ["server-backup","poll","reminder","calculator"])assert.ok(!names.includes(name),"unexpected general utility command: "+name);});

test("greeting placeholders resolve aliases, hyphens, and context values",()=>{
  const user={id:"111111111111111111",username:"Example",globalName:"Example User",tag:"Example#1234",
    displayAvatarURL:()=> "https://cdn.example/avatar.png"};
  const guild={id:"222222222222222222",name:"Test Server",memberCount:42,ownerId:"333333333333333333",
    iconURL:()=> "https://cdn.example/server.png"};
  const channel={id:"444444444444444444",name:"welcome"};
  const client={user:{id:"555555555555555555",username:"Timi",displayAvatarURL:()=> "https://cdn.example/bot.png"}};
  const result=renderTemplate(
    "{user}|{member}|{user-mention}|{username}|{member-name}|{user-name}|{user_tag}|{user_id}|{member-id}|{user-avatar}|{server}|{server-name}|{server_id}|{server-icon}|{member_count}|{member-count}|{channel}|{channel-mention}|{channel_name}|{channel-name}|{owner}|{server-owner}|{owner_id}|{server-owner-id}|{bot}|{bot-mention}|{bot_name}|{bot-avatar}|{date}|{time}|{timestamp}",
    {guild,member:{guild,user},user,channel,client}
  );
  for(const value of [
    "<@111111111111111111>","Example","Example User","Example#1234","111111111111111111",
    "https://cdn.example/avatar.png","Test Server","222222222222222222",
    "https://cdn.example/server.png","42","<#444444444444444444>","welcome",
    "<@333333333333333333>","333333333333333333","<@555555555555555555>","Timi",
    "https://cdn.example/bot.png"
  ]) assert.ok(result.includes(value), "missing rendered value: "+value);
  assert.ok(!result.includes("{"),"known placeholders should not remain unresolved");
  assert.ok(TEMPLATE_PLACEHOLDERS.includes("{user-avatar}"));
  assert.ok(TEMPLATE_PLACEHOLDERS.includes("{member-count}"));
});
test("unknown template placeholders remain visible for correction",()=>{
  assert.equal(renderTemplate("Hello {unknown-value}"),"Hello {unknown-value}");
});

test("embed image URL validation accepts supported dynamic image placeholders",()=>{
  for(const value of ["{user-avatar}","{user_avatar}","{server-icon}","{bot-avatar}",
    "https://cdn.example/{user-avatar}?size=256","https://cdn.example/image.png"])
    assert.equal(isHttpsUrlTemplate(value),true,value);
  for(const value of ["http://cdn.example/image.png","javascript:alert(1)",
    "{unknown-placeholder}","https://cdn.example/{unknown-placeholder}","not-a-url"])
    assert.equal(isHttpsUrlTemplate(value),false,value);
  assert.equal(isHttpsUrlTemplate(""),true);
});

import { imageSignature, imageMetadata, extractUrls, assessImageText, isTrustedDiscordAttachmentUrl } from "../src/systems/image-analysis.js";

test("image signature and PNG metadata are read without external packages",()=>{
  const png=Buffer.alloc(24);
  Buffer.from([137,80,78,71,13,10,26,10]).copy(png,0);
  png.writeUInt32BE(640,16);png.writeUInt32BE(480,20);
  assert.equal(imageSignature(png),"png");
  assert.deepEqual(imageMetadata(png),{type:"png",width:640,height:480,bytes:24});
  assert.equal(imageSignature(Buffer.from("not an image")),null);
  assert.equal(imageMetadata(Buffer.from("not an image")),null);
});

test("image OCR link extraction and safety heuristics identify common phishing indicators",()=>{
  const urls=extractUrls("Please visit https://bit.ly/fake and http://192.0.2.10/login.");
  assert.equal(urls.length,2);
  const flags=assessImageText("Verify your account urgently and claim your reward",urls);
  assert.ok(flags.some(flag=>flag.includes("account-theft")));
  assert.ok(flags.some(flag=>flag.includes("shortening")));
  assert.ok(flags.some(flag=>flag.includes("HTTPS")));
  assert.ok(flags.some(flag=>flag.includes("IP address")));
});

test("compact commands are unique and route to their canonical plugins",()=>{
  const names=commandData.map(command=>command.name);
  assert.equal(new Set(names).size,names.length);
  for(const [name,plugin] of [
    ["welcome","Foundation"],["autorole","Foundation"],["roles","Foundation"],["embed-new","Foundation"],
    ["verify","Kimi Lock"],["verify-config","Kimi Lock"],["moderation","Kimi Lock"],["filter","Kimi Lock"],["security","Kimi Lock"],
    ["tickets","Support"],["ticket-panel","Support"],["ticket-config","Support"],
  ])assert.equal(pluginForCommand(name),plugin);
  for(const name of ["plan","plugins","install","uninstall"])assert.equal(pluginForCommand(name),null);
});
test("plugin commands require Manage Server, not Administrator",()=>{
  for(const command of commandData.filter(command=>pluginForCommand(command.name))){
    assert.equal(command.default_member_permissions,"32");
  }
});

test("transcript chunking preserves every character of oversized lines",()=>{
  const source="A".repeat(2500)+"\n"+"B".repeat(2300)+"\nshort";
  const chunks=chunkText(source,1900);
  assert.ok(chunks.length>2);
  assert.ok(chunks.every(chunk=>chunk.length<=1900));
  assert.equal(chunks.join("").replace(/\n/g,""),source.replace(/\n/g,""));
});
test("every plugin factory can be instantiated with the shared runtime context",()=>{
  const context={client:{},store:{data:{}},logger:quiet,foundation:{}};
  const foundation=PLUGINS.Welcome.create(context);
  assert.equal(typeof foundation.ensureSetup,"function","Foundation must expose the shared idempotent setup service");
  const shared={...context,foundation};
  for(const plugin of Object.values(PLUGINS)){
    const instance=plugin.create(shared);
    assert.equal(typeof instance.handleInteraction,"function",plugin.name+" must expose an interaction handler");
  }
});

test("image downloads accept only HTTPS Discord attachment CDN URLs",()=>{
  for(const url of [
    "https://cdn.discordapp.com/attachments/123/456/image.png",
    "https://media.discordapp.net/attachments/123/456/image.webp"
  ])assert.equal(isTrustedDiscordAttachmentUrl(url),true,url);
  for(const url of [
    "http://cdn.discordapp.com/attachments/image.png",
    "https://cdn.discordapp.com.evil.example/image.png",
    "https://example.com/image.png",
    "https://user:pass@cdn.discordapp.com/image.png",
    "file:///etc/passwd",
    "not a url"
  ])assert.equal(isTrustedDiscordAttachmentUrl(url),false,url);
});

import { RolePicker } from "../src/systems/role-picker.js";
import { Embeds } from "../src/systems/embeds.js";

test("renamed Foundation slash commands reach their system handlers",async()=>{
  let roleCalled=false,embedCalls=[];
  const rolePicker=new RolePicker({}, {}, quiet);
  rolePicker.command=async()=>{roleCalled=true;};
  await rolePicker.handle({isChatInputCommand:()=>true,commandName:"roles"});
  assert.equal(roleCalled,true,"/roles must reach the role picker setup handler");
  const embeds=new Embeds({}, {}, quiet);
  embeds.command=async interaction=>{embedCalls.push(interaction.commandName);};
  for(const commandName of ["embed-new","embed-edit","embed-post"])
    await embeds.handle({isChatInputCommand:()=>true,commandName});
  assert.deepEqual(embedCalls,["embed-new","embed-edit","embed-post"]);
});

test("published role pickers revalidate role safety before assigning",async()=>{
  let added=false,response=null;
  const store={data:{role_picker_menus:{menu:{guild_id:"guild",channel_id:"channel",message_id:"message",roles:[{id:"12345678901234567"}],selections:{}}}},save(){}};
  const picker=new RolePicker({user:{id:"kimi"}},store,quiet,{validateRole:async()=>[false,"role has privileged permissions"]});
  const interaction={
    customId:"rolepicker:menu:menu",guildId:"guild",channelId:"channel",message:{id:"message",author:{id:"kimi"}},values:["12345678901234567"],user:{id:"member"},
    guild:{roles:{fetch:async()=>({id:"12345678901234567"})},members:{fetch:async()=>({user:{bot:false},roles:{add:async()=>{added=true;},remove:async()=>{}}})}},
    member:{roles:{add:async()=>{added=true;},remove:async()=>{}}},
    deferred:true,replied:false,editReply:async payload=>{response=payload;}
  };
  await picker.menu(interaction);
  assert.equal(added,false,"a role that became privileged after publication must not be assigned");
  assert.match(response.content,/can no longer be self-assigned/);
});

import { isSafeAssignableRole, SELF_SERVICE_BLOCKED_PERMISSIONS } from "../src/permissions.js";

test("self-service role validation blocks every privileged permission",()=>{
  const role={id:"role",managed:false,permissions:{has:()=>false}};
  assert.equal(isSafeAssignableRole(role,"guild"),true);
  assert.equal(isSafeAssignableRole(null,"guild"),false);
  assert.equal(isSafeAssignableRole({...role,id:"guild"},"guild"),false);
  assert.equal(isSafeAssignableRole({...role,managed:true},"guild"),false);
  for(const permission of SELF_SERVICE_BLOCKED_PERMISSIONS){
    assert.equal(isSafeAssignableRole({...role,permissions:{has:value=>value===permission}},"guild"),false,
      "privileged permission "+permission+" must not be self-assignable");
  }
});

test("Timi storage accounting includes setup channels and AutoMod phrases",()=>{
  const empty=getGuildStorageBytes({}, "guild-storage");
  const populated=getGuildStorageBytes({
    timi_setup:{"guild-storage":{log_channel_id:"123456789012345678"}},
    automod_words:{"guild-storage":["blocked phrase"]},
    pending_bots:{"guild-storage:bot-id":{message_id:"message-id"}}
  },"guild-storage");
  assert.ok(populated>empty);
  const otherGuild=getGuildStorageBytes({
    automod_words:{"another-guild":["x".repeat(1000)]}
  },"guild-storage");
  assert.equal(otherGuild,empty,"another server's data must not count against this server");
});

import { Recovery } from "../src/systems/recovery.js";

test("storage accounting includes Guard incidents and recovery channel snapshots",()=>{
  const empty=getGuildStorageBytes({},"guard-storage");
  const populated=getGuildStorageBytes({
    guard_state:{"guard-storage":{users:{u:{tokens:0}},bots:{b:{tokens:0}},incidents:{b:{status:"restricted",reason:"activity limit"}}}},
    channels:{"guard-storage:123456789012345678":{name:"general",permission_overwrites:[{id:"role",allow:"0",deny:"1024"}]}},
    messages:{"guard-storage":[{id:"message",content:"recovery archive"}]}
  },"guard-storage");
  assert.ok(populated>empty);
  assert.equal(getGuildStorageBytes({guard_state:{"other-guild":{incidents:{b:{reason:"x".repeat(1000)}}}}},"guard-storage"),empty);
});

test("recovery message archives stay below four megabytes per server",()=>{
  const store={data:{messages:{}},queueSave(){}};
  const recovery=new Recovery({user:{id:"bot"}},store,quiet);
  const content="x".repeat(4000),attachments={size:0,values:()=>[]};
  for(let index=0;index<1100;index++){
    recovery.backupMessage({
      guild:{id:"archive-guild"},author:{id:"member",tag:"member",bot:false},
      id:String(index),channelId:"channel",content,createdTimestamp:Date.now(),attachments
    });
  }
  const archived=store.data.messages["archive-guild"];
  assert.ok(archived.length<1100,"oldest messages should be pruned when the byte cap is reached");
  assert.ok(Buffer.byteLength(JSON.stringify(archived),"utf8")<=4*1024*1024);
  assert.equal(store.data.messages["other-guild"],undefined);
});

test("recovery startup pruning removes messages older than seven days",()=>{
  const now=Date.now(),store={data:{messages:{guild:[
    {id:"old",timestamp_ms:now-8*24*60*60*1000,content:"old"},
    {id:"recent",timestamp_ms:now-1000,content:"recent"}
  ]}},queueSave(){this.queued=true;}};
  const recovery=new Recovery({user:{id:"bot"}},store,quiet);
  const result=recovery.prune("guild");
  assert.equal(result.removed,1);
  assert.deepEqual(store.data.messages.guild.map(message=>message.id),["recent"]);
  assert.equal(store.queued,true);
});

test("AutoMod blocked phrases match whole words without false substrings",()=>{
  assert.equal(matchesBlockedPhrase("You are an ASS!","ass"),true);
  assert.equal(matchesBlockedPhrase("bad    word detected","bad word"),true);
  assert.equal(matchesBlockedPhrase("class assignment","ass"),false);
  assert.equal(matchesBlockedPhrase("passage","ass"),false);
  assert.equal(matchesBlockedPhrase("nothing suspicious",""),false);
  assert.equal(matchesBlockedPhrase("élève suspect","élève"),true);
  assert.equal(matchesBlockedPhrase("𐐨ass","ass"),false,"supplementary Unicode letters must count as word characters");
  assert.equal(matchesBlockedPhrase("ass𐐨","ass"),false,"supplementary Unicode letters after a phrase must count as word characters");
  assert.equal(matchesBlockedPhrase("💩ass!","ass"),true,"symbols remain valid word boundaries");
});


test("recovery archives track message edits before a later deletion",async()=>{
  const store={data:{messages:{guild:[{id:"message",channel_id:"channel",author_id:"member",author_tag:"member",content:"before",timestamp_ms:Date.now(),attachments:[]}]}},queueSave(){this.queued=true;}};
  const recovery=new Recovery({user:{id:"bot"}},store,quiet);
  const updated={
    id:"message",guild:{id:"guild"},author:{id:"member",tag:"member",bot:false},
    content:"after edit",attachments:{values:()=>[]}
  };
  assert.equal(await recovery.updateMessage(updated),true);
  assert.equal(store.data.messages.guild[0].content,"after edit");
  assert.equal(store.queued,true);
});

test("recovery alerts prefer the configured private Timi log channel",async()=>{
  const configured={id:"configured-log",guildId:"guild",type:0,isTextBased:()=>true,permissionsFor:()=>({has:()=>false})};
  const fallback={id:"fallback-log",guildId:"guild",type:0,name:"timi-log",isTextBased:()=>true,permissionsFor:()=>({has:()=>false})};
  const store={data:{timi_setup:{guild:{log_channel_id:"configured-log"}}}};
  const recovery=new Recovery({},store,quiet);
  const guild={id:"guild",roles:{everyone:{id:"everyone"}},channels:{fetch:async id=>id==="configured-log"?configured:null,cache:{find(predicate){return predicate(fallback)?fallback:undefined;}}}};
  assert.equal(await recovery.findLogChannel(guild),configured);
  store.data.timi_setup.guild.log_channel_id="missing";
  assert.equal(await recovery.findLogChannel(guild),fallback);
});

test("embed editor previews respect Discord's aggregate character limit",()=>{
  const embeds=new Embeds({user:{displayAvatarURL:()=>"https://cdn.example/bot.png"}},{data:{customizations:{}}},quiet);
  const value={title:"T".repeat(256),description:"D".repeat(4096),author:"A".repeat(256),footer:"F".repeat(2048),
    thumbnail:"",image:"",url:"",fields:Array.from({length:25},()=>({name:"N".repeat(256),value:"V".repeat(1024),inline:false}))};
  const preview=embeds.editorPreview(value).toJSON();
  const total=(preview.title||"").length+(preview.description||"").length+(preview.author?.name||"").length+
    (preview.footer?.text||"").length+(preview.fields||[]).reduce((sum,field)=>sum+field.name.length+field.value.length,0);
  assert.ok(total<=6000);
});

import { Protection } from "../src/systems/protection.js";

test("ordinary member role assignments do not use the critical anti-nuke threshold",async()=>{
  const protection=new Protection({user:{id:"timi"}},{},quiet);
  protection.alertPrivilegeEscalation=async()=>false;
  protection.privateChannel=async()=>({send:async()=>{}});
  const guild={id:"security-guild",ownerId:"owner",members:{fetch:async()=>null}};
  for(let index=0;index<3;index++)await protection.auditLog({
    action:25,executorId:"moderator",changes:[{key:"$add",new:[{id:"ordinary-role"}]}]
  },guild);
  assert.equal(protection.nukeEvents.has("security-guild:moderator:triggered"),false);
  assert.equal(protection.nukeEvents.get("security-guild:moderator").length,3);
});

test("critical channel permission changes still trigger anti-nuke containment at three events",async()=>{
  const protection=new Protection({user:{id:"timi"}},{},quiet);
  protection.privateChannel=async()=>({send:async()=>{}});
  const guild={id:"security-guild",ownerId:"owner",members:{fetch:async()=>null}};
  for(let index=0;index<3;index++)await protection.auditLog({
    action:13,executorId:"moderator",changes:[]
  },guild);
  assert.ok(protection.nukeEvents.get("security-guild:moderator:triggered")>Date.now());
});

import { getTicketStaffRoles } from "../src/systems/tickets.js";
import { PermissionFlagsBits } from "discord.js";

test("private ticket access includes configured support and server manager roles",()=>{
  const role=(id,manager=false)=>({id,managed:false,permissions:{has:flag=>manager&&flag===PermissionFlagsBits.ManageGuild}});
  const support=role("support"),manager=role("manager",true),ordinary=role("ordinary");
  const guild={id:"everyone",roles:{cache:new Map([
    ["everyone",role("everyone",true)],["support",support],["manager",manager],["ordinary",ordinary]
  ])}};
  const selected=getTicketStaffRoles(guild,support);
  assert.deepEqual(selected.map(value=>value.id),["support","manager"]);
});

import { Verification } from "../src/systems/verification.js";

test("verification review approval assigns the verified role and closes the review controls",async()=>{
  let added=0,edited=false,response=null;
  const records={};
  const store={
    data:{verification:{},members:{}},
    member(guildId,userId){return records[userId]||=( {last_verified:0,failed:0,last_reason:"",pending_review_message_id:"review-message",pending_review_channel_id:"review-channel"} );},
    verify(){return {role_id:"verified-role"};},
    save(){}
  };
  const member={roles:{add:async role=>{assert.equal(role.id,"verified-role");added++;}},kick:async()=>{}};
  const role={id:"verified-role"};
  const guild={
    id:"123456789012345678",ownerId:"111111111111111111",
    members:{fetch:async()=>member},roles:{fetch:async()=>role}
  };
  const verification=new Verification({user:{id:"kimi"},guilds:{fetch:async()=>guild}},store,quiet);
  verification.validateRole=async()=>[true];
  const interaction={
    customId:"verify:review:approve:123456789012345678:234567890123456789",
    guildId:guild.id,channelId:"review-channel",guild,user:{id:"333333333333333333"},
    isChatInputCommand:()=>false,memberPermissions:{has:()=>true},isButton:()=>true,deferred:true,replied:false,
    message:{id:"review-message",author:{id:"kimi"},edit:async payload=>{edited=payload.components.length===0;}},
    editReply:async payload=>{response=payload;}
  };
  await verification.handle(interaction);
  assert.equal(added,1);
  assert.ok(records["234567890123456789"].last_verified>0);
  assert.equal(edited,true);
  assert.match(response.content,/approved and verified role assigned/);
});

import { Moderation } from "../src/systems/moderation.js";

test("failed AutoMod message deletion remains pending for retry",async()=>{
  const job={id:"job-1",status:"pending",guild_id:"guild",channel_id:"123456789012345678",user_id:"223456789012345678",
    message_ids:["323456789012345678"],action:"timeout",timeout_minutes:5,reason:"spam",steps:{deleted:false,sanction:false,logged:false}};
  const store={data:{moderation_jobs:{guild:[job]}},mods:()=>({log_channel_id:""}),save(){}};
  const moderation=new Moderation({},store,quiet);
  moderation.scheduleJobs=()=>{};
  const channel={
    isTextBased:()=>true,
    messages:{fetch:async()=>({delete:async()=>{throw new Error("Missing Manage Messages");}})}
  };
  const guild={id:"guild",members:{fetch:async()=>null},channels:{fetch:async()=>channel}};
  await moderation.processJob(guild,job);
  assert.equal(job.status,"pending");
  assert.equal(job.steps.deleted,false);
  assert.equal(job.steps.sanction,false);
  assert.equal(job.attempts,1);
});

test("queued AutoMod cancels if a target becomes privileged before enforcement",async()=>{
  const job={id:"job-privileged",status:"pending",guild_id:"guild",channel_id:"123456789012345678",user_id:"223456789012345678",
    message_ids:["323456789012345678"],action:"ban",timeout_minutes:5,reason:"spam",steps:{deleted:false,sanction:false,logged:false}};
  const store={data:{moderation_jobs:{guild:[job]}},mods:()=>({log_channel_id:""}),save(){}};
  const moderation=new Moderation({},store,quiet);
  let channelFetches=0;
  const guild={id:"guild",ownerId:"999999999999999999",
    members:{fetch:async()=>({id:job.user_id,user:{bot:false},permissions:{has:permission=>permission===PermissionFlagsBits.ManageMessages}})},
    channels:{fetch:async()=>{channelFetches++;throw new Error("must not fetch channels");}}
  };
  await moderation.processJob(guild,job);
  assert.equal(job.status,"cancelled");
  assert.equal(channelFetches,0);
});

test("automatic moderation warning history is capped per server",async()=>{
  const warnings=Array.from({length:5000},(_,index)=>({
    id:index+1,type:"warning",user_id:"member",created_at:Date.now(),automatic:true
  }));
  const store={data:{moderation_cases:{guild:warnings}},save(){}};
  const moderation=new Moderation({},store,quiet);
  const id=await moderation.warn("guild","member","spam");
  assert.equal(id,5001);
  assert.equal(store.data.moderation_cases.guild.length,5000);
  assert.equal(store.data.moderation_cases.guild[0].id,2);
  assert.equal(store.data.moderation_cases.guild.at(-1).id,5001);
});

test("blocked-phrase AutoMod does not sanction when message deletion fails",async()=>{
  let warnings=0,logs=0;
  const store={data:{automod_words:{guild:["blocked"]}},mods:()=>({enabled:true}),member(){throw new Error("should not record a warning");}};
  const moderation=new Moderation({},store,quiet);
  moderation.warn=async()=>{warnings++;return 1;};
  moderation.log=async()=>{logs++;};
  const message={
    guild:{id:"guild",ownerId:"owner"},guildId:"guild",author:{id:"member",bot:false},
    member:{permissions:{has:()=>false}},content:"this is blocked",channelId:"channel",
    delete:async()=>{throw new Error("Missing Manage Messages");}
  };
  await moderation.onMessage(message);
  assert.equal(warnings,0);
  assert.equal(logs,1);
});

import { startWorking, respond, finishWorking } from "../src/ui.js";

test("Discord interactions are acknowledged once and use the deferred response",async()=>{
  let deferred=0,edits=0,last=null;
  const interaction={
    deferred:false,replied:false,
    async deferReply(options){deferred++;this.deferred=true;assert.equal(options.ephemeral,true);},
    async editReply(payload){edits++;last=payload;this.replied=true;return payload;}
  };
  await startWorking(interaction);
  await startWorking(interaction);
  await respond(interaction,"Completed.");
  assert.equal(deferred,1);
  assert.equal(edits,1);
  assert.equal(last.content,"Completed.");
});

test("unanswered interactions get one fallback, while deleted ticket replies are skipped",async()=>{
  let edits=0;
  const pending={deferred:true,replied:false,async editReply(){edits++;}};
  assert.equal(await finishWorking(pending),true);
  assert.equal(edits,1);
  const deleted={deferred:true,replied:false,__timiDeletedReply:true,async editReply(){edits++;}};
  assert.equal(await finishWorking(deleted),false);
  assert.equal(edits,1);
});

test("Kimi Lock refuses to write private logs when channel permissions cannot be secured",async()=>{
  const channel={type:0,permissionOverwrites:{set:async()=>{throw new Error("Missing Manage Channels");}}};
  const store={data:{timi_setup:{guild:{log_channel_id:"log"}}},mods:()=>({}),save(){}};
  const protection=new Protection({user:{id:"timi"}},store,quiet);
  const guild={
    id:"guild",ownerId:"owner",members:{fetchMe:async()=>({id:"timi"})},
    roles:{cache:{filter:()=>({first:()=>[]})}},
    channels:{fetch:async()=>channel,cache:{find:()=>channel}}
  };
  await assert.rejects(protection.privateChannel(guild),/refused to send private security logs/);
});

import { isPrivateTextChannel } from "../src/utils.js";

test("private-channel checks reject public and non-text destinations",()=>{
  const guild={roles:{everyone:{id:"everyone"}}};
  const channel=visible=>({isTextBased:()=>true,permissionsFor:()=>({has:flag=>flag==="ViewChannel"?visible:false})});
  assert.equal(isPrivateTextChannel(channel(false),guild),true);
  assert.equal(isPrivateTextChannel(channel(true),guild),false);
  assert.equal(isPrivateTextChannel({isTextBased:()=>false},guild),false);
  assert.equal(isPrivateTextChannel(null,guild),false);
});

import { pluginForComponent } from "../src/component-routing.js";

test("all persistent component prefixes route to their installed plugin",()=>{
  for(const [id,plugin] of [
    ["ticket:close","Support"],["modpanel:enable","Kimi Lock"],["botguard:yes:123","Kimi Lock"],
    ["verify:start","Kimi Lock"],["rolepicker:start","Roles"],["embed:save","Embeds"],
    
  ])assert.equal(pluginForComponent(id),plugin,id);
  assert.equal(pluginForComponent("unknown:component"),null);
});

test("legacy installed library data migrates to plugin storage without losing enabled plugins",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-plugin-migration-"));
  try{
    fs.writeFileSync(path.join(dir,"timi.json"),JSON.stringify({installed_libraries:{"guild-a":["Foundation","Security","Moderation","Support"]}}));
    const store=new Store(dir,quiet);
    assert.deepEqual(store.data.installed_plugins["guild-a"],["Welcome","Roles","Embeds","Kimi Lock","Support"]);
    assert.equal(store.data.installed_libraries,undefined);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("member security records remain bounded under join floods",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-member-cap-"));
  try{
    const store=new Store(dir,quiet);
    store.data.members={};
    for(let index=0;index<100000;index++)store.data.members["guild:user-"+index]={joins:1};
    store.memberCount=100000;
    store.member("guild","223456789012345678");
    assert.equal(Object.keys(store.data.members).length,100000);
    assert.equal(Object.hasOwn(store.data.members,"guild:user-0"),false);
    assert.equal(store.member("guild","223456789012345678").joins,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("malformed member counters and verification history are repaired",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-member-sanitize-"));
  try{
    const store=new Store(dir,quiet);
    store.data.members["guild:user"]={joins:"many",leaves:-1,failed:NaN,suspicious:{},last_join:"yesterday",attempts:"invalid",last_reason:42};
    const record=store.member("guild","user");
    for(const field of ["joins","leaves","failed","suspicious","last_join"])assert.equal(record[field],0);
    assert.deepEqual(record.attempts,[]);
    assert.equal(record.last_reason,"");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
