import crypto from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const runFile=promisify(execFile);
const MAX_IMAGE_BYTES=8*1024*1024;
const MAX_ATTACHMENTS=3;
const MAX_OUTPUT=1700;
const IMAGE_TYPES=new Set(["image/png","image/jpeg","image/jpg","image/gif","image/webp","image/bmp"]);
const EXTENSIONS=new Set([".png",".jpg",".jpeg",".gif",".webp",".bmp"]);
const SHORTENERS=new Set(["bit.ly","tinyurl.com","t.co","is.gd","cutt.ly","rb.gy","rebrand.ly","shorturl.at"]);
const SUSPICIOUS_TERMS=[
  /verify your (?:account|wallet)/i,/claim your (?:prize|reward)/i,/urgent(?:ly)? action required/i,
  /send (?:the )?(?:otp|one.time password|verification code)/i,/seed phrase/i,/recovery phrase/i,
  /connect your wallet/i,/account (?:will be|has been) suspended/i,/free nitro/i,/gift card code/i
];

export function imageSignature(buffer){
  if(!Buffer.isBuffer(buffer))return null;
  if(buffer.length>=8&&buffer.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))return "png";
  if(buffer.length>=3&&buffer[0]===0xff&&buffer[1]===0xd8&&buffer[2]===0xff)return "jpeg";
  if(buffer.length>=6&&["GIF87a","GIF89a"].includes(buffer.toString("ascii",0,6)))return "gif";
  if(buffer.length>=12&&buffer.toString("ascii",0,4)==="RIFF"&&buffer.toString("ascii",8,12)==="WEBP")return "webp";
  if(buffer.length>=2&&buffer.toString("ascii",0,2)==="BM")return "bmp";
  return null;
}
function readU24LE(b,o){return b[o]|(b[o+1]<<8)|(b[o+2]<<16);}
export function imageMetadata(buffer){
  const type=imageSignature(buffer);
  if(!type)return null;
  let width=0,height=0;
  if(type==="png"&&buffer.length>=24){width=buffer.readUInt32BE(16);height=buffer.readUInt32BE(20);}
  else if(type==="gif"&&buffer.length>=10){width=buffer.readUInt16LE(6);height=buffer.readUInt16LE(8);}
  else if(type==="bmp"&&buffer.length>=26){width=Math.abs(buffer.readInt32LE(18));height=Math.abs(buffer.readInt32LE(22));}
  else if(type==="webp"&&buffer.length>=30){
    const chunk=buffer.toString("ascii",12,16);
    if(chunk==="VP8X"){width=1+readU24LE(buffer,24);height=1+readU24LE(buffer,27);}
    else if(chunk==="VP8 "&&buffer.length>=30){width=buffer.readUInt16LE(26)&0x3fff;height=buffer.readUInt16LE(28)&0x3fff;}
    else if(chunk==="VP8L"&&buffer.length>=25){const bits=buffer.readUInt32LE(21);width=(bits&0x3fff)+1;height=((bits>>>14)&0x3fff)+1;}
  }else if(type==="jpeg"){
    let offset=2;
    while(offset+4<buffer.length){
      if(buffer[offset]!==0xff){offset++;continue;}
      const marker=buffer[offset+1];offset+=2;
      if(marker===0xd8||marker===0xd9||marker===0x01||(marker>=0xd0&&marker<=0xd7))continue;
      if(offset+2>buffer.length)break;
      const size=buffer.readUInt16BE(offset);
      if(size<2||offset+size>buffer.length)break;
      if([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)){
        if(size>=7){height=buffer.readUInt16BE(offset+3);width=buffer.readUInt16BE(offset+5);}
        break;
      }
      offset+=size;
    }
  }
  if(!width||!height||width>50000||height>50000)return {type,width:null,height:null,bytes:buffer.length};
  return {type,width,height,bytes:buffer.length};
}
export function extractUrls(text){
  const found=new Set();
  for(const match of String(text||"").matchAll(/(?:https?:\/\/|www\.)[^\s<>()\[\]{}"'\u0000-\u001f]+/gi)){
    const value=match[0].replace(/[.,!?;:]+$/,"");
    try{const url=new URL(value.startsWith("www.")?"https://"+value:value);if(["http:","https:"].includes(url.protocol))found.add(url.href);}catch{}
  }
  return [...found];
}
export function assessImageText(text,urls=[]){
  const flags=[];
  if(SUSPICIOUS_TERMS.some(pattern=>pattern.test(text||"")))flags.push("OCR text contains common account-theft or payment-scam wording");
  for(const value of urls){
    try{
      const url=new URL(value),host=url.hostname.toLowerCase().replace(/^www\./,"");
      if(SHORTENERS.has(host))flags.push("Link uses a URL-shortening service: "+host);
      if(url.protocol!=="https:")flags.push("Link does not use HTTPS: "+host);
      if(host.startsWith("xn--")||host.split(".").some(part=>part.startsWith("xn--")))flags.push("Link uses an internationalized/punycode hostname: "+host);
      if(/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host))flags.push("Link uses a raw IP address instead of a domain");
      if(/discord(?:-gift|nitro|app)?\.(?:gift|support|com\.)/i.test(host))flags.push("Link resembles a Discord impersonation domain");
    }catch{}
  }
  return [...new Set(flags)];
}
function isImageAttachment(attachment){
  const type=(attachment.contentType||"").split(";")[0].toLowerCase();
  return IMAGE_TYPES.has(type)||EXTENSIONS.has(path.extname(attachment.name||"").toLowerCase());
}
async function commandAvailable(command){
  try{await runFile(command,["--version"],{timeout:2500,maxBuffer:32*1024});return true;}catch(error){return error.code!=="ENOENT";}
}
async function runOptional(commands,args,options={}){
  for(const command of commands){
    try{return await runFile(command,args,{timeout:options.timeout||12000,maxBuffer:options.maxBuffer||256*1024,encoding:options.encoding||"utf8"});}
    catch(error){if(error.code==="ENOENT")continue;throw error;}
  }
  return null;
}
async function downloadAttachment(attachment){
  if(attachment.size>MAX_IMAGE_BYTES)throw new Error("Image exceeds the 8 MB processing limit.");
  const response=await fetch(attachment.url,{signal:AbortSignal.timeout(12000),redirect:"error"});
  if(!response.ok)throw new Error("Discord image download failed ("+response.status+").");
  const declared=Number(response.headers.get("content-length")||0);
  if(declared>MAX_IMAGE_BYTES)throw new Error("Image exceeds the 8 MB processing limit.");
  const bytes=Buffer.from(await response.arrayBuffer());
  if(bytes.length>MAX_IMAGE_BYTES)throw new Error("Image exceeds the 8 MB processing limit.");
  if(!imageSignature(bytes))throw new Error("Attachment is not a supported PNG, JPEG, GIF, WEBP, or BMP image.");
  return bytes;
}
async function ocrImage(file){
  const result=await runOptional(["tesseract"],[file,"stdout","-l","eng"],{timeout:15000,maxBuffer:128*1024});
  return result?.stdout?.trim().slice(0,6000)||"";
}
async function decodeQr(file){
  const result=await runOptional(["zbarimg"],["--quiet","--raw",file],{timeout:8000,maxBuffer:32*1024});
  return result?.stdout?.split(/\r?\n/).map(value=>value.trim()).filter(Boolean).slice(0,10)||[];
}
async function differenceHash(file){
  const args=[file,"-resize","9x8!","-colorspace","Gray","-depth","8","gray:-"];
  const result=await runOptional(["magick","convert"],args,{timeout:8000,maxBuffer:1024});
  if(!result?.stdout||result.stdout.length<72)return null;
  const pixels=Buffer.isBuffer(result.stdout)?result.stdout:Buffer.from(result.stdout,"binary");
  if(pixels.length<72)return null;
  let hash="";
  for(let y=0;y<8;y++)for(let x=0;x<8;x++)hash+=pixels[y*9+x]>pixels[y*9+x+1]?"1":"0";
  return BigInt("0b"+hash).toString(16).padStart(16,"0");
}
function hammingDistance(a,b){
  let value=BigInt("0x"+a)^BigInt("0x"+b),count=0;
  while(value){count++;value&=value-1n;}
  return count;
}
export class ImageAnalysis{
  constructor(client,logger){
    this.client=client;this.logger=logger;this.seen=new Map();this.userCooldown=new Map();
  }
  async shouldAnalyze(message){
    if(message.mentions?.users?.has(this.client.user?.id))return true;
    if(!message.reference?.messageId)return false;
    const referenced=await message.channel.messages.fetch(message.reference.messageId).catch(()=>null);
    return referenced?.author?.id===this.client.user?.id;
  }
  remember(guildId,record){
    const now=Date.now(),items=(this.seen.get(guildId)||[]).filter(item=>now-item.at<7*24*60*60*1000);
    const exact=items.find(item=>item.sha===record.sha);
    const similar=record.dhash?items.find(item=>item.dhash&&hammingDistance(item.dhash,record.dhash)<=5):null;
    items.push({...record,at:now});if(items.length>500)items.splice(0,items.length-500);
    this.seen.set(guildId,items);
    return exact?"Exact duplicate image previously analyzed":similar?"Visually similar image previously analyzed":null;
  }
  async analyzeOne(message,attachment){
    const bytes=await downloadAttachment(attachment),meta=imageMetadata(bytes);
    if(!meta)throw new Error("Image format could not be identified.");
    const sha=crypto.createHash("sha256").update(bytes).digest("hex");
    const temp=await fs.mkdtemp(path.join(os.tmpdir(),"timi-image-"));
    const file=path.join(temp,"image."+meta.type);
    try{
      await fs.writeFile(file,bytes,{mode:0o600});
      const [text,qr,dhash]=await Promise.all([
        ocrImage(file).catch(error=>{this.logger.warn("Image OCR unavailable:",error.message);return "";}),
        decodeQr(file).catch(error=>{this.logger.warn("QR decoding unavailable:",error.message);return [];}),
        differenceHash(file).catch(error=>{this.logger.warn("Perceptual hashing unavailable:",error.message);return null;})
      ]);
      const urls=[...new Set([...extractUrls(text),...qr.flatMap(value=>extractUrls(value))])];
      const safety=assessImageText(text,urls);
      const duplicate=this.remember(message.guildId,{sha,dhash,name:attachment.name||"image"});
      return {meta,sha,text,qr,urls,safety,duplicate,hasOcr:await commandAvailable("tesseract"),hasQr:await commandAvailable("zbarimg"),hasHash:!!dhash};
    }finally{await fs.rm(temp,{recursive:true,force:true}).catch(()=>{});}
  }
  async handleMessage(message){
    if(!message.guild||message.author.bot||!message.attachments?.size)return false;
    const attachments=[...message.attachments.values()].filter(isImageAttachment).slice(0,MAX_ATTACHMENTS);
    if(!attachments.length)return false;
    if(!await this.shouldAnalyze(message))return false;
    const now=Date.now(),key=message.guildId+":"+message.author.id;
    if(now-(this.userCooldown.get(key)||0)<10000)return false;
    this.userCooldown.set(key,now);
    const reports=[];
    for(const attachment of attachments){
      try{reports.push(await this.analyzeOne(message,attachment));}
      catch(error){reports.push({error:error.message,name:attachment.name||"image"});}
    }
    const lines=["**Timi Image Check**"];
    for(let index=0;index<reports.length;index++){
      const item=reports[index];lines.push("", "**"+(attachments[index].name||"Image "+(index+1))+"**");
      if(item.error){lines.push("Could not analyze: "+item.error);continue;}
      lines.push("Format: "+item.meta.type.toUpperCase()+" · "+(item.meta.width&&item.meta.height?item.meta.width+" × "+item.meta.height:"dimensions unavailable")+" · "+(item.meta.bytes/1024).toFixed(1)+" KB");
      lines.push("SHA-256: `"+item.sha.slice(0,20)+"…`");
      lines.push("Duplicate check: "+(item.duplicate||"No match in the recent in-memory history."));
      if(item.text)lines.push("**Text detected:** "+item.text.replace(/\s+/g," ").slice(0,420));
      else lines.push("Text detection: "+(item.hasOcr?"No readable text found.":"Unavailable — install Tesseract."));
      if(item.qr.length)lines.push("**QR data:** "+item.qr.slice(0,3).join(" | ").slice(0,350));
      else lines.push("QR scan: "+(item.hasQr?"No QR code found.":"Unavailable — install ZBar."));
      if(item.urls.length)lines.push("**Links found:** "+item.urls.slice(0,5).join(" | ").slice(0,450));
      if(item.safety.length)lines.push("**Safety flags:** "+item.safety.join("; "));
      else lines.push("Safety checks: No known scam wording or obvious suspicious-link pattern detected.");
      if(!item.hasHash)lines.push("Perceptual duplicate matching unavailable — install ImageMagick.");
    }
    lines.push("","These are lightweight OCR, QR, metadata and heuristic checks, not AI image understanding or a reliable visual NSFW/violence classifier. No image was stored after processing.");
    await message.reply({content:lines.join("\n").slice(0,MAX_OUTPUT),allowedMentions:{parse:[]}}).catch(error=>this.logger.warn("Could not send image analysis reply:",error.message));
    return true;
  }
}
