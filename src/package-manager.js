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

function digest(value){return crypto.createHash("sha256").update(value).digest("hex");}
function safeRelative(input){
  if(typeof input!=="string"||!input||input.includes("\\\\")||input.startsWith("/")||input.includes("\\0"))return false;
  return input.split("/").every(part=>part&&part!=="."&&part!==".."&&!part.startsWith("."));
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
export function scanModuleDirectory(root){
  const manifest=readManifest(root),entries=[],findings=[],files=[];
  function walk(dir){
    for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
      const absolute=path.join(dir,entry.name),relative=path.relative(root,absolute).split(path.sep).join("/");
      if(entry.isSymbolicLink())throw new Error("Symbolic links are not allowed in module packages.");
      if(entry.isDirectory()){walk(absolute);continue;}
      if(!entry.isFile()||!safeRelative(relative))throw new Error("Unsafe module package path: "+relative);
      const data=fs.readFileSync(absolute);
      if(data.length>MAX_FILE_BYTES)throw new Error("Module file exceeds the 2 MB limit: "+relative);
      entries.push([relative,data]);files.push({path:relative,size:data.length,sha256:digest(data)});
      if(relative.endsWith(".js"))findings.push(...inspectSource(relative,data.toString("utf8")));
    }
  }
  walk(root);
  if(entries.length>MAX_FILES)throw new Error("Module package contains too many files.");
  const total=entries.reduce((sum,item)=>sum+item[1].length,0);
  if(total>MAX_UNPACKED_BYTES)throw new Error("Module package exceeds the unpacked size limit.");
  if(!entries.some(([name])=>name==="index.js"))throw new Error("Module package must include index.js.");
  manifest.files=files.filter(file=>file.path!=="manifest.json");
  return {manifest,entries,findings};
}
function tarString(value,size){const b=Buffer.alloc(size);Buffer.from(String(value)).copy(b,0,size);return b;}
function octal(value,size){return tarString(Math.max(0,value).toString(8).padStart(size-1,"0")+"\\0",size);}
function makeTar(entries){
  const blocks=[];
  for(const [name,data] of entries){
    const header=Buffer.alloc(512);
    tarString(name,100).copy(header,0);octal(0o644,8).copy(header,100);octal(0,8).copy(header,108);octal(0,8).copy(header,116);
    octal(data.length,12).copy(header,124);octal(0,12).copy(header,136);header.fill(32,148,156);header[156]=48;
    tarString("ustar\\0",6).copy(header,257);tarString("00",2).copy(header,263);
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
    const expected=parseInt(header.subarray(148,156).toString().replace(/\\0.*$/s,"").trim(),8);
    const actual=header.reduce((sum,byte,index)=>sum+(index>=148&&index<156?32:byte),0);
    if(!Number.isFinite(expected)||expected!==actual)throw new Error("Module archive header checksum failed.");
    const name=header.subarray(0,100).toString().replace(/\\0.*$/s,"");
    const prefix=header.subarray(345,500).toString().replace(/\\0.*$/s,"");
    const full=prefix?prefix+"/"+name:name;
    const size=parseInt(header.subarray(124,136).toString().replace(/\\0.*$/s,"").trim()||"0",8);
    const type=String.fromCharCode(header[156]||48);
    if(type!=="0"&&type!=="\\0")throw new Error("Only regular files are allowed in module archives.");
    if(!safeRelative(full)||!Number.isSafeInteger(size)||size<0||size>MAX_FILE_BYTES)throw new Error("Unsafe or oversized file in module archive.");
    if(offset+size>buffer.length)throw new Error("Truncated module archive.");
    files.push([full,Buffer.from(buffer.subarray(offset,offset+size))]);total+=size;
    if(files.length>MAX_FILES||total>MAX_UNPACKED_BYTES)throw new Error("Module archive exceeds extraction limits.");
    offset+=Math.ceil(size/512)*512;
  }
  if(!files.length)throw new Error("Module archive is empty.");
  return files;
}
function inspectSource(file,source){
  const findings=[];
  if(source.length>MAX_FILE_BYTES)findings.push({severity:"high",file,issue:"Source file exceeds the size limit."});
  return findings;
}

export function createModuleArchive(root,output){
  const scanned=scanModuleDirectory(root);
  const manifest=Buffer.from(JSON.stringify(scanned.manifest,null,2)+"\\n");
  const entries=scanned.entries.filter(([name])=>name!=="manifest.json");
  entries.unshift(["manifest.json",manifest]);
  const archive=zlib.gzipSync(makeTar(entries),{level:9});
  if(archive.length>MAX_ARCHIVE_BYTES)throw new Error("Compressed module archive exceeds 8 MB.");
  fs.mkdirSync(path.dirname(output),{recursive:true});
  fs.writeFileSync(output,archive,{mode:0o600});
  return {bytes:archive.length,sha256:digest(archive),manifest:scanned.manifest,findings:scanned.findings};
}
export function extractModuleArchive(archivePath,destination){
  const compressed=fs.readFileSync(archivePath);
  if(compressed.length>MAX_ARCHIVE_BYTES)throw new Error("Module archive exceeds 8 MB.");
  const tar=zlib.gunzipSync(compressed,{maxOutputLength:MAX_UNPACKED_BYTES+MAX_FILES*512+4096});
  const files=parseTar(tar),manifestEntry=files.find(([name])=>name==="manifest.json");
  if(!manifestEntry)throw new Error("Module archive manifest is missing.");
  const manifest=JSON.parse(manifestEntry[1].toString("utf8"));
  if(!manifest||manifest.schema!==1||!NAME.test(manifest.id||""))throw new Error("Invalid module manifest.");
  const listed=new Map((manifest.files||[]).map(file=>[file.path,file]));
  for(const [name,data] of files){
    if(name==="manifest.json")continue;
    if(!listed.has(name))throw new Error("Archive contains an unlisted file: "+name);
    const expected=listed.get(name);
    if(expected.size!==data.length||expected.sha256!==digest(data))throw new Error("Module file integrity check failed: "+name);
  }
  if(listed.size!==files.length-1)throw new Error("Module archive is missing indexed files.");
  const temp=destination+".installing-"+process.pid;
  fs.rmSync(temp,{recursive:true,force:true});fs.mkdirSync(temp,{recursive:true});
  try{
    for(const [name,data] of files){const target=path.resolve(temp,name);if(!target.startsWith(path.resolve(temp)+path.sep))throw new Error("Unsafe module archive path.");fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,data,{mode:0o600});}
    const checked=scanModuleDirectory(temp);
    fs.rmSync(destination,{recursive:true,force:true});fs.mkdirSync(path.dirname(destination),{recursive:true});fs.renameSync(temp,destination);
    return {ok:true,manifest:checked.manifest};
  }catch(error){fs.rmSync(temp,{recursive:true,force:true});throw error;}
}
export function runModuleChecks(root){
  const scanned=scanModuleDirectory(root),syntax=[];
  for(const [file,data] of scanned.entries){
    if(!file.endsWith(".js"))continue;
    const result=spawnSync(process.execPath,["--check",path.join(root,file)],{encoding:"utf8",timeout:5000});
    if(result.status!==0)syntax.push({file,error:(result.stderr||result.stdout||"Syntax check failed").trim()});
  }
  const high=scanned.findings.filter(item=>item.severity==="high");
  return {passed:syntax.length===0&&high.length===0,syntax,findings:scanned.findings,
    vulnerabilityCheck:{simulated:true,details:"Static checks only; no vulnerability analysis or runtime sandbox is provided."}};
}
