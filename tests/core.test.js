import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { isSnowflake, normalizeMessage, jaccard, cleanChannelName, snowflakeTime, renderTemplate, TEMPLATE_PLACEHOLDERS, isHttpsUrlTemplate, chunkText } from "../src/utils.js";
import { loadConfig } from "../src/config.js";
import { Store } from "../src/store.js";

const quiet={debug(){},info(){},warn(){},error(){}};

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
    fs.writeFileSync(path.join(dir,"ticket-settings.json"),JSON.stringify({"123456789012345678":{panelTitle:"Legacy Support"}}));
    const store=new Store(dir,quiet);
    assert.equal(store.ticket("123456789012345678").panel_title,"Legacy Support");
    const reloaded=new Store(dir,quiet);
    assert.equal(reloaded.ticket("123456789012345678").panel_title,"Legacy Support");
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

import { LibraryManager } from "../src/module-manager.js";
import { LIBRARIES, normalizeLibraryName } from "../src/libraries/index.js";

test("Timi exposes four focused first-party libraries",()=>{
  assert.deepEqual(Object.keys(LIBRARIES),["Foundation","Security","Support","Scratch"]);
  for(const library of Object.values(LIBRARIES)){
    assert.equal(typeof library.create,"function");
    assert.ok(library.systems.length>0);
    assert.ok(library.description.length>20);
  }
  assert.equal(normalizeLibraryName(" moderation "),"Security");
  assert.equal(normalizeLibraryName("Developer"),"Scratch");
  assert.equal(normalizeLibraryName("Support"),"Support");
  assert.equal(normalizeLibraryName("Unknown"),null);
});
test("library installation is isolated per server and preserves data",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-libraries-"));
  try{
    const store=new Store(dir,quiet),manager=new LibraryManager(store,quiet);
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

import { commandData, libraryCommandsForLibraries, libraryForCommand } from "../src/commands.js";
test("library management commands are registered with the intended option behavior",()=>{
  const install=commandData.find(command=>command.name==="install");
  const uninstall=commandData.find(command=>command.name==="uninstall");
  const list=commandData.find(command=>command.name==="libraries");
  assert.ok(install&&uninstall&&list);
  assert.equal(install.options[0].name,"library");
  assert.equal(install.options[0].required,true);
  assert.equal(uninstall.options[0].required,true);
  assert.ok(commandData.some(command=>command.name==="filter"));
  assert.ok(commandData.some(command=>command.name==="security"));
  for(const name of ["plan","libraries","install","script","script-edit","script-template","script-help","script-check","script-run","script-stop","script-undo","script-redo","script-import","script-export"]) {
    assert.ok(commandData.some(command=>command.name===name),"missing slash command: "+name);
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

import { parseTbScript, compileTbScript, autoFixTbScript, renderTbScript } from "../src/tbscript.js";
import { PLANS, getGuildPlan, getStorageReport, canStoreGuildState } from "../src/subscriptions.js";

test("TbScript keeps the nested brace-block syntax and transpiles each instruction",()=>{
  const source=[
    "{",
    '   {title:"Welcome"}',
    '   {description:"Hello, {user}!"}',
    '   {addbutton:true:"Verify":"":false}',
    '   {onclick(button):giverole:"Member"}',
    '   {ephemeral:true}',
    "}"
  ].join("\n");
  const parsed=parseTbScript(source);
  assert.equal(parsed.ok,true);
  assert.equal(parsed.ast.children.length,5);
  const compiled=compileTbScript(source);
  assert.equal(compiled.ok,true);
  assert.equal(compiled.output.title,"Welcome");
  assert.equal(compiled.output.ephemeral,true);
  assert.equal(compiled.output.buttons[0].action.type,"giverole");
  assert.equal(compiled.output.buttons[0].action.role,"Member");
  assert.equal(compiled.instructions.length,5);
});

test("TbScript parses nested modal input blocks and renders components",()=>{
  const source=[
    "{",
    '   {title:"Contact"}',
    '   {modal:"Contact form"',
    '      {input:"Subject":"Your subject"}',
    '      {input:"Details":"More details":true}',
    "   }",
    "}"
  ].join("\n");
  const compiled=compileTbScript(source);
  assert.equal(compiled.ok,true);
  assert.equal(compiled.output.modal.inputs.length,2);
  const rendered=renderTbScript(compiled,{scope:"test"});
  assert.equal(rendered.embeds[0].data.title,"Contact");
  assert.equal(rendered.components.length,1);
});

test("TbScript reports invalid syntax and does not accept statement semicolons",()=>{
  assert.equal(compileTbScript('{\n  {title:"valid"};\n}').ok,false);
  const invalid=compileTbScript('{\n  {unknown:"value"}\n}');
  assert.equal(invalid.ok,false);
  assert.match(invalid.errors[0],/Unknown TbScript keyword/);
});

test("TbScript structural auto-fix only adds missing closing braces",()=>{
  const source='{\n  {title:"Fixed"}';
  const fixed=autoFixTbScript(source);
  assert.equal((fixed.match(/}/g)||[]).length,2);
  assert.equal(compileTbScript(fixed).ok,true);
});

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

test("storage allocation is fixed at 5 MB for every server",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-storage-"));
  try{
    const store=new Store(dir,quiet);
    const source="x".repeat(5*1024*1024+1024);
    const projects={...(store.data.developer_projects||{}),["guild-free"]:{large:{source}}};
    const report=canStoreGuildState(store,"guild-free",{developer_projects:projects});
    assert.equal(report.ok,false);
    assert.equal(report.limit,5*1024*1024);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("Scratch library installs on the free plan and exposes its project commands",()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),"timi-developer-lib-"));
  try{
    const store=new Store(dir,quiet),manager=new LibraryManager(store,quiet);
    assert.equal(manager.install("guild-dev","Scratch").ok,true);
    assert.equal(manager.installed("guild-dev","Scratch"),true);
    assert.ok(manager.list().some(library=>library.name==="Scratch"));
    const developerCommands=libraryCommandsForLibraries(["Scratch"]).map(command=>command.name);
    for(const name of ["script","script-edit","script-kit","script-run","script-template","script-help"])assert.ok(developerCommands.includes(name));
    assert.equal(manager.install("guild-dev","Scratch").ok,false);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test("Foundation publishes only its requested member systems",()=>{const names=libraryCommandsForLibraries(["Foundation"]).map(command=>command.name);for(const name of ["setup","welcome","autorole","roles","embed-new","embed-edit","embed-post"])assert.ok(names.includes(name),"missing Foundation command: "+name);for(const name of ["server-backup","poll","reminder","calculator"])assert.ok(!names.includes(name),"unexpected general utility command: "+name);});

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

test("compact commands are unique and route to their canonical libraries",()=>{
  const names=commandData.map(command=>command.name);
  assert.equal(new Set(names).size,names.length);
  for(const [name,library] of [
    ["welcome","Foundation"],["autorole","Foundation"],["roles","Foundation"],["embed-new","Foundation"],
    ["verify","Security"],["verify-settings","Security"],["moderation","Security"],["filter","Security"],["security","Security"],
    ["tickets","Support"],["ticket-panel","Support"],["ticket-settings","Support"],
    ["script","Scratch"],["script-run","Scratch"],["scripts","Scratch"]
  ])assert.equal(libraryForCommand(name),library);
  for(const name of ["plan","libraries","install","uninstall"])assert.equal(libraryForCommand(name),null);
});
test("library commands require Manage Server, not Administrator",()=>{
  for(const command of commandData.filter(command=>libraryForCommand(command.name))){
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
test("every library factory can be instantiated with the shared runtime context",()=>{
  const context={client:{},store:{data:{}},logger:quiet,foundation:{}};
  const foundation=LIBRARIES.Foundation.create(context);
  assert.equal(typeof foundation.ensureSetup,"function","Foundation must expose the shared idempotent setup service");
  const shared={...context,foundation};
  for(const library of Object.values(LIBRARIES)){
    const instance=library.create(shared);
    assert.equal(typeof instance.handleInteraction,"function",library.name+" must expose an interaction handler");
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
