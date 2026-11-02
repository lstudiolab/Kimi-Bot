import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import zlib from "node:zlib";
import { spawnSync } from "node:child_process";

const MAX_ARCHIVE_BYTES=8*1024*1024;
const MAX_UNPACKED_BYTES=24*1024*1024;
const MAX_FILES=250;
const MAX_FILE_BYTES=2*1024*1024;
const NAME=/^[a-z0-9][a-z0-9._-]{1,47}$/;
const ALLOWED_IMPORTS=new Set(["discord.js","node:crypto","node:util"]);
const BLOCKED_PATTERNS=[
  [/\b(?:eval|Function)\s*\(/,"Dynamic code execution"],
  [/\bprocess\s*\./,"Process access"],
  [/\b(?:child_process|worker_threads|cluster)\b/,"Process or worker creation"],
  [/\b(?:exec|execSync|spawn|spawnSync|fork)\s*\(/,"Command execution"],
  [/\b(?:https?|net|tls|dgram)\s*\./,"Direct network access"],
  [/\b(?:writeFile|writeFileSync|appendFile|appendFileSync|rmSync|unlinkSync)\s*\(/,"Filesystem mutation"],
  [/\bcreateRequire\s*\(/,"Unrestricted module loading"],
  [/\bimport\s*\(/,"Dynamic imports"],
  [/\brequire\s*\(/,"CommonJS runtime loading"],
  [/\b(?:TOKEN|BOT_TOKEN|DISCORD_TOKEN)\b\s*[:=]/i,"Possible embedded credential"]
];

function digest(value){return crypto.createHash("sha256").update(value).digest("hex");}
function safeRelative(input){
  if(typeof input!=="string"||!input||input.includes("\\")||input.startsWith("/")||input.includes("\0"))return false;
  const parts=input.split("/");
  return parts.every(part=>part&&part!=="."&&part!==".."&&!part.startsWith(".")||part===".well-known");
}
function readManifest(root){
  const file=path.join(root,"manifest.json");
  if(!fs.existsSync(file))throw new Error("Package manifest.json is missing.");
  const manifest=JSON.parse(fs.readFileSync(file,"utf8"));
  if(!manifest||manifest.schema!==1||!NAME.test(manifest.id||""))throw new Error("Invalid package manifest or package ID.");
  if(!["module","bundle"].includes(manifest.kind))throw new Error("Package kind must be module or bundle.");
  if(typeof manifest.system!=="string"||!manifest.system.trim()||manifest.system.length>80)throw new Error("A package must define exactly one system.");
  if(!Array.isArray(manifest.commands)||manifest.commands.length<1||manifest.commands.length>100)throw new Error("Manifest commands must contain between 1 and 100 commands.");
  if(manifest.kind==="module"&&manifest.commands.length>3)throw new Error("A Module can contain at most 3 commands.");
  if(manifest.kind==="bundle"&&manifest.commands.length<=3)throw new Error("A Module Bundle must contain more than 3 commands.");
  if(new Set(manifest.commands).size!==manifest.commands.length||manifest.commands.some(x=>typeof x!=="string"||!/^[-a-z0-9]{1,32}$/.test(x)))throw new Error("Manifest contains invalid or duplicate command names.");
  if(!Array.isArray(manifest.files)||manifest.files.length>MAX_FILES)throw new Error("Manifest file index is invalid.");
  return manifest;
}
function tarString(value,size){const b=Buffer.alloc(size);Buffer.from(String(value)).copy(b,0,size);return b;}
function octal(value,size){return tarString(Math.max(0,value).toString(8).padStart(size-1,"0")+"\0",size);}
function makeTar(entries){
  const blocks=[];
  for(const [name,data] of entries){
    const header=Buffer.alloc(512);
    tarString(name,100).copy(header,0);octal(0o644,8).copy(header,100);octal(0,8).copy(header,108);octal(0,8).copy(header,116);
    octal(data.length,12).copy(header,124);octal(0,12).copy(header,136);header.fill(32,148,156);header[156]=48;
    tarString("ustar\0",6).copy(header,257);tarString("00",2).copy(header,263);
    const checksum=header.reduce((sum,n)=>sum+n,0);octal(checksum,8).copy(header,148);
    blocks.push(header,data);const pad=(512-data.length%512)%512;if(pad)blocks.push(Buffer.alloc(pad));
  }
  blocks.push(Buffer.alloc(1024));return Buffer.concat(blocks);
}
function parseTar(buffer){
  const files=[];let offset=0,total=0;
  while(offset+512<=buffer.length){
    const header=buffer.subarray(offset,offset+512);offset+=512;
    if(header.every(byte=>byte===0))break;
    const expected=parseInt(header.subarray(148,156).toString().replace(/\0.*$/s,"").trim(),8);
    const actual=header.reduce((sum,byte,index)=>sum+(index>=148&&index<156?32:byte),0);
    if(!Number.isFinite(expected)||expected!==actual)throw new Error("Module archive header checksum failed.");
    const name=header.subarray(0,100).toString().replace(/\0.*$/s,"");
    const prefix=header.subarray(345,500).toString().replace(/\0.*$/s,"");
    const full=prefix?prefix+"/"+name:name;
    const size=parseInt(header.subarray(124,136).toString().replace(/\0.*$/s,"").trim()||"0",8);
    const type=String.fromCharCode(header[156]||48);
    if(type!=="0"&&type!=="\0")throw new Error("Only regular files are allowed in module archives.");
    if(!safeRelative(full)||!Number.isSafeInteger(size)||size<0||size>MAX_FILE_BYTES)throw new Error("Unsafe or oversized file in module archive.");
    if(offset+size>buffer.length)throw new Error("Truncated module archive.");
    const data=Buffer.from(buffer.subarray(offset,offset+size));files.push([full,data]);total+=size;
    if(files.length>MAX_FILES||total>MAX_UNPACKED_BYTES)throw new Error("Module archive exceeds extraction limits.");
    offset+=Math.ceil(size/512)*512;
  }
  if(!files.length)throw new Error("Module archive is empty.");
  return files;
}
function inspectSource(file,source){
  const findings=[];
  if(source.length>MAX_FILE_BYTES)findings.push({severity:"high",file,issue:"Source file exceeds the size limit."});
  for(const [pattern,issue] of BLOCKED_PATTERNS)if(pattern.test(source))findings.push({severity:"high",file,issue});
  const imports=[...source.matchAll(/\bimport\s+(?:[^"'\n]+?\s+from\s+)?["']([^"']+)["']/g)].map(m=>m[1]);
  for(const specifier of imports)if(!specifier.startsWith("./")&&!specifier.startsWith("../")&&!ALLOWED_IMPORTS.has(specifier))findings.push({severity:"high",file,issue:"Unapproved import: "+specifier});
  return findings;
}
export function scanModuleDirectory(root){
  const manifest=readManifest(root),findings=[],indexed=new Map(manifest.files.map(item=>[item.path,item.sha256]));
  if(indexed.size!==manifest.files.length)findings.push({severity:"high",file:"manifest.json",issue:"Duplicate file entries."});
  for(const item of manifest.files){
    if(!item||!safeRelative(item.path)||item.path==="manifest.json"||typeof item.sha256!=="string"||!/^[a-f0-9]{64}$/.test(item.sha256)){
      findings.push({severity:"high",file:"manifest.json",issue:"Invalid file index entry."});continue;
    }
    const full=path.resolve(root,item.path);
    if(!full.startsWith(path.resolve(root)+path.sep)||!fs.existsSync(full)||!fs.statSync(full).isFile()){
      findings.push({severity:"high",file:item.path,issue:"Indexed file is missing or escapes package root."});continue;
    }
    const data=fs.readFileSync(full);
    if(digest(data)!==item.sha256)findings.push({severity:"high",file:item.path,issue:"SHA-256 integrity check failed."});
    if(item.path.endsWith(".js")){
      const source=data.toString("utf8");findings.push(...inspectSource(item.path,source));
      const check=spawnSync(process.execPath,["--check",full],{encoding:"utf8",timeout:5000});
      if(check.status!==0)findings.push({severity:"high",file:item.path,issue:"JavaScript syntax check failed: "+(check.stderr||check.stdout||"unknown error").slice(0,300)});
    }
  }
  const indexedPaths=new Set(manifest.files.map(item=>item.path));
  function findUnindexed(dir,relative=""){
    for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
      const rel=relative?relative+"/"+entry.name:entry.name;
      if(entry.isDirectory())findUnindexed(path.join(dir,entry.name),rel);
      else if(entry.isFile()&&rel!=="manifest.json"&&!indexedPaths.has(rel))findings.push({severity:"medium",file:rel,issue:"Unindexed package file."});
    }
  }
  findUnindexed(root);
  if(manifest.dependencies&&Object.keys(manifest.dependencies).length)findings.push({severity:"high",file:"manifest.json",issue:"Third-party runtime dependencies are not allowed in isolated packages."});
  return {ok:findings.every(item=>item.severity!=="high"),manifest,findings,checks:{manifest:true,integrity:true,syntax:true,staticSecurity:true,dependencies:!manifest.dependencies||Object.keys(manifest.dependencies).length===0}};
}
export function createModuleArchive(sourceDirectory,outputFile){
  const manifest=readManifest(sourceDirectory),entries=[];
  const paths=[];
  function walk(dir,relative=""){
    for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
      if(entry.name==="manifest.json"&&relative==="")continue;
      if(entry.name.startsWith(".")||entry.isSymbolicLink())throw new Error("Hidden files and symbolic links are not allowed in packages.");
      const rel=relative?relative+"/"+entry.name:entry.name,full=path.join(dir,entry.name);
      if(entry.isDirectory())walk(full,rel);
      else if(entry.isFile()){
        if(!safeRelative(rel))throw new Error("Unsafe package path: "+rel);
        const data=fs.readFileSync(full);if(data.length>MAX_FILE_BYTES)throw new Error("Package file is too large: "+rel);
        paths.push({path:rel,sha256:digest(data)});entries.push([rel,data]);
      }
    }
  }
  walk(sourceDirectory);
  manifest.files=paths;
  entries.unshift(["manifest.json",Buffer.from(JSON.stringify(manifest,null,2))]);
  const archive=zlib.gzipSync(makeTar(entries),{level:9});
  if(archive.length>MAX_ARCHIVE_BYTES)throw new Error("Compressed module archive exceeds 8 MB.");
  fs.mkdirSync(path.dirname(outputFile),{recursive:true});fs.writeFileSync(outputFile,archive,{mode:0o600});
  return {file:outputFile,bytes:archive.length,sha256:digest(archive),manifest};
}
export function extractModuleArchive(archiveFile,destination){
  const compressed=fs.readFileSync(archiveFile);
  if(compressed.length>MAX_ARCHIVE_BYTES)throw new Error("Compressed module archive exceeds 8 MB.");
  const tar=zlib.gunzipSync(compressed,{maxOutputLength:MAX_UNPACKED_BYTES});
  const entries=parseTar(tar),parent=path.resolve(destination);
  fs.mkdirSync(path.dirname(parent),{recursive:true});
  const staging=fs.mkdtempSync(path.join(path.dirname(parent),".kmod-stage-"));
  try{
    for(const [name,data] of entries){
      const full=path.resolve(staging,name);if(!full.startsWith(staging+path.sep))throw new Error("Archive path traversal detected.");
      fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,data,{flag:"wx",mode:0o600});
    }
    const report=scanModuleDirectory(staging);
    if(!report.ok)throw new Error("Package security checks failed: "+report.findings.map(x=>x.issue).join("; "));
    fs.rmSync(parent,{recursive:true,force:true});fs.mkdirSync(path.dirname(parent),{recursive:true});fs.renameSync(staging,parent);
    return {...report,archiveSha256:digest(compressed)};
  }catch(error){fs.rmSync(staging,{recursive:true,force:true});throw error;}
}
export async function downloadModuleArchive(url,destination){
  const parsed=new URL(url);
  if(parsed.protocol!=="https:"||parsed.username||parsed.password)throw new Error("Module downloads must use an HTTPS URL without embedded credentials.");
  const response=await fetch(parsed,{redirect:"error",signal:AbortSignal.timeout(20000)});
  if(!response.ok)throw new Error("Module download failed with HTTP "+response.status+".");
  const declared=Number(response.headers.get("content-length")||0);
  if(declared>MAX_ARCHIVE_BYTES)throw new Error("Compressed module archive exceeds 8 MB.");
  const bytes=Buffer.from(await response.arrayBuffer());
  if(bytes.length>MAX_ARCHIVE_BYTES)throw new Error("Compressed module archive exceeds 8 MB.");
  fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,bytes,{mode:0o600});
  return {bytes:bytes.length,sha256:digest(bytes),file:destination};
}
export function runModuleChecks(root){
  const report=scanModuleDirectory(root);
  if(!report.ok)return {...report,passed:false};
  const jsFiles=report.manifest.files.filter(item=>item.path.endsWith(".js"));
  return {...report,passed:true,executed:false,summary:jsFiles.length+" JavaScript files syntax-checked; package code was not executed."};
}
