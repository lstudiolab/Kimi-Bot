import test from "node:test";
import assert from "node:assert/strict";
import { PermissionFlagsBits as P } from "discord.js";
import { isSafeAssignableRole } from "../src/permissions.js";

const role=(id,permissions,managed=false)=>({id,managed,permissions:{has:value=>(permissions&value)!==0n}});
test("self-service roles reject every protected permission in the policy",()=>{
 for(const permission of ["Administrator","ManageGuild","ManageRoles","ManageChannels","ManageWebhooks","ManageGuildExpressions","ManageEmojisAndStickers","ManageSoundboard","ManageGuildScheduledEvents","CreateInstantInvite","ManageEvents","ManageThreads","ManageMessages","ManageNicknames","KickMembers","BanMembers","ModerateMembers","ViewAuditLog","MentionEveryone","MuteMembers","DeafenMembers","MoveMembers"]){
  const bit=P[permission];
  if(typeof bit==="bigint")assert.equal(isSafeAssignableRole(role("12345678901234567",bit),"98765432109876543"),false,permission+" must be blocked");
 }
});
test("self-service roles reject the everyone and managed roles",()=>{
 assert.equal(isSafeAssignableRole(role("98765432109876543",0n),"98765432109876543"),false);
 assert.equal(isSafeAssignableRole(role("12345678901234567",0n,true),"98765432109876543"),false);
});
test("ordinary cosmetic roles remain eligible",()=>{
 assert.equal(isSafeAssignableRole(role("12345678901234567",P.SendMessages),"98765432109876543"),true);
});
