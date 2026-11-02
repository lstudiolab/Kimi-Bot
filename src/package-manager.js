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
  return parts.every(part=>part&&part!=="."&&part!==".."&&!part.startsWith("."));
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
  return findings;
}

