import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createModuleArchive, extractModuleArchive, runModuleChecks, scanModuleDirectory } from "../src/package-manager.js";

function fixture(kind="module",commands=["greet","greet-config"]){
  const root=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-kmod-"));
  fs.writeFileSync(path.join(root,"manifest.json"),JSON.stringify({schema:1,id:"sample-pack",name:"Sample Pack",version:"1.0.0",kind,system:"Greeting",commands,files:[]}));
  fs.writeFileSync(path.join(root,"index.js"),"export function run(){ return 'ok'; }\n");
  return root;
}
test("module package creates, compresses, extracts and validates",()=>{
  const root=fixture(),out=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-archive-"));
  try{
    const archive=path.join(out,"sample.kmod"),destination=path.join(out,"installed","sample-pack");
    const packed=createModuleArchive(root,archive);
    assert.ok(packed.bytes>0);
    const installed=extractModuleArchive(archive,destination);
    assert.equal(installed.ok,true);
    assert.equal(installed.manifest.kind,"module");
    assert.equal(runModuleChecks(destination).passed,true);
  }finally{fs.rmSync(root,{recursive:true,force:true});fs.rmSync(out,{recursive:true,force:true});}
});
test("modules are limited to three commands",()=>{
  const root=fixture("module",["one","two","three","four"]);
  try{assert.throws(()=>scanModuleDirectory(root),/at most 3 commands/);}
  finally{fs.rmSync(root,{recursive:true,force:true});}
});
test("module bundles require more than three commands",()=>{
  const root=fixture("bundle",["one","two","three"]);
  try{assert.throws(()=>scanModuleDirectory(root),/more than 3 commands/);}
  finally{fs.rmSync(root,{recursive:true,force:true});}
});
test("static scanner rejects dangerous process access",()=>{
  const root=fixture();
  try{
    fs.writeFileSync(path.join(root,"index.js"),"export function run(){ return process.env.DISCORD_TOKEN; }\n");
    const archive=path.join(root,"../bad.kmod");
    createModuleArchive(root,archive);
    const result=runModuleChecks(root);
    assert.equal(result.passed,false);
    assert.ok(result.findings.some(item=>item.issue==="Process access"));
    fs.rmSync(archive,{force:true});
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test("failed security scan does not replace an existing installation",()=>{
  const root=fixture(),out=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-safe-"));
  try{
    const archive=path.join(out,"unsafe.kmod"),destination=path.join(out,"installed","sample-pack");
    fs.writeFileSync(path.join(root,"index.js"),"export function run(){ return process.env.DISCORD_TOKEN; }\\n");
    createModuleArchive(root,archive);
    fs.mkdirSync(destination,{recursive:true});fs.writeFileSync(path.join(destination,"keep.txt"),"keep");
    assert.throws(()=>extractModuleArchive(archive,destination),/security checks failed/i);
    assert.equal(fs.readFileSync(path.join(destination,"keep.txt"),"utf8"),"keep");
  }finally{fs.rmSync(root,{recursive:true,force:true});fs.rmSync(out,{recursive:true,force:true});}
});
