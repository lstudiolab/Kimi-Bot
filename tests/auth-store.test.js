import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { AuthStore } from "../src/auth-store.js";

test("Kimi accounts, sessions and Discord links persist in local JSON files", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "kimi-auth-"));
  try {
    const auth = new AuthStore(root);
    const created = auth.createAccount({
      email: "Owner@Example.com",
      password: "correct horse battery staple",
      displayName: "Owner"
    });
    assert.ok(created.account);
    assert.equal(created.account.email, "owner@example.com");
    assert.equal(auth.createAccount({ email: "owner@example.com", password: "another secure password" }).error !== undefined, true);
    assert.ok(auth.authenticate("OWNER@example.com", "correct horse battery staple"));
    assert.equal(auth.authenticate("owner@example.com", "incorrect password"), null);

    const token = auth.createSession(created.account.id);
    const persisted = new AuthStore(root);
    assert.equal(persisted.getSession(token).account.id, created.account.id);
    const sessionsFile = fs.readFileSync(path.join(root, "auth", "sessions.json"), "utf8");
    assert.equal(sessionsFile.includes(token), false);

    const link = persisted.createLinkCode(created.account.id);
    const linked = persisted.completeLinkCode(link.code, {
      id: "123456789012345678",
      username: "discord-user",
      globalName: "Discord User",
      avatar: null
    });
    assert.equal(linked.account.discord.id, "123456789012345678");
    assert.equal(persisted.completeLinkCode(link.code, { id: "123456789012345678", username: "discord-user" }).error !== undefined, true);

    const restored = new AuthStore(root);
    assert.equal(restored.getSession(token).discord.id, "123456789012345678");
    assert.ok(fs.existsSync(path.join(root, "auth", "accounts.json")));
    assert.ok(fs.existsSync(path.join(root, "auth", "sessions.json")));
    assert.ok(fs.existsSync(path.join(root, "auth", "link-codes.json")));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("dashboard session and one-time link-code state stays bounded per account",()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-auth-bounds-"));
  try{
    const auth=new AuthStore(root);
    const {account}=auth.createAccount({email:"limits@example.com",password:"a sufficiently long password"});
    const tokens=Array.from({length:12},()=>auth.createSession(account.id));
    assert.equal(Object.keys(auth.sessions).length,10);
    assert.equal(auth.getSession(tokens[0]),null);
    assert.ok(auth.getSession(tokens[tokens.length-1]));
    const first=auth.createLinkCode(account.id);
    const second=auth.createLinkCode(account.id);
    assert.equal(auth.links[first.code],undefined);
    assert.ok(auth.links[second.code]);
    assert.equal(Object.keys(auth.links).filter(code=>auth.links[code].accountId===account.id).length,1);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test("server-link tokens are capped per account during the validity window",()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-web-token-bounds-"));
 try{
  const auth=new AuthStore(root);
  const {account}=auth.createAccount({email:"web-token@example.com",password:"a sufficiently long password"});
  for(let index=0;index<5;index++){
   const token=auth.createWebToken(account.id);
   assert.ok(token.token);
   const linked=auth.completeWebToken(token.token,{id:String(123456789012345670+index),name:"Server "+index},{id:"223456789012345678"});
   assert.ok(linked.guild);
  }
  assert.match(auth.createWebToken(account.id).error,/Too many server-link tokens/);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

test("auth storage ignores malformed account records and bounds link failure state",()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-auth-sanitize-"));
 try{
  fs.mkdirSync(path.join(root,"auth"),{recursive:true});
  fs.writeFileSync(path.join(root,"auth","accounts.json"),JSON.stringify({accounts:[null,{id:"broken",email:"bad@example.com",passwordSalt:"x",passwordHash:"x"}]}));
  const auth=new AuthStore(root);
  assert.equal(auth.accounts.accounts.length,0);
  for(let index=0;index<5005;index++)auth.completeLinkCode("not-a-code",{id:String(100000000000000000+index)});
  assert.ok(auth.linkFailures.size<=5000);
  assert.equal(auth.completeLinkCode("not-a-code",{id:"invalid"}).error!==undefined,true);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
