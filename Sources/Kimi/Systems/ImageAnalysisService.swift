import Foundation
import Dispatch
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

private final class ImageNoRedirectDelegate:NSObject,URLSessionTaskDelegate {
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
}
private enum ImageProcess {
 static func resolve(_ command:String)->String?{
  let paths=(ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator:":").map(String.init)
  return paths.map{$0+"/"+command}.first{FileManager.default.isExecutableFile(atPath:$0)}
 }
 static func run(_ command:String,_ arguments:[String],timeout:Double=15,limit:Int=262144)->Data?{
  guard let executable=resolve(command) else{return nil}
  let process=Process(),pipe=Pipe()
  process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
  process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
  do{try process.run()}catch{return nil}
  DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+timeout){if process.isRunning{process.terminate()}}
  let output=pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus==0 else{return nil}
  return Data(output.prefix(limit))
 }
 static func first(_ commands:[String],_ arguments:[String],timeout:Double=15,limit:Int=262144)->Data?{
  for command in commands{if let value=run(command,arguments,timeout:timeout,limit:limit){return value}}
  return nil
 }
}

actor ImageAnalysisService {
 struct Metadata:Sendable {let type:String;let width:Int?;let height:Int?;let bytes:Int}
 private struct Seen:Sendable {let sha:String;let differenceHash:UInt64?;let name:String;let at:Date}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 private let maxBytes=8*1024*1024
 private let maxAttachments=3
 private let trustedHosts:Set<String>=["cdn.discordapp.com","media.discordapp.net"]
 private let shorteners:Set<String>=["bit.ly","tinyurl.com","t.co","is.gd","cutt.ly","rb.gy","rebrand.ly","shorturl.at"]
 private let suspiciousTerms=["verify your account","verify your wallet","claim your prize","claim your reward","urgent action required","urgently action required","send the otp","send otp","verification code","one-time password","seed phrase","recovery phrase","connect your wallet","account will be suspended","account has been suspended","free nitro","gift card code"]
 private var botID:String?
 private var seen:[String:[Seen]]=[:]
 private var userCooldown:[String:Date]=[:]
 init(store:PersistentStore,rest:DiscordREST,logger:Logger){self.store=store;self.rest=rest;self.logger=logger}
 func urls(in text:String)->[String]{
  guard let regex=try? NSRegularExpression(pattern:#"(?:https?://|www\.)[^\s<>()\[\]{}\"']+"#,options:.caseInsensitive) else{return []}
  let ns=text as NSString;var result=Set<String>()
  for match in regex.matches(in:text,range:NSRange(location:0,length:ns.length)){
   var raw=ns.substring(with:match.range).trimmingCharacters(in:CharacterSet(charactersIn:".,!?;:"))
   if raw.hasPrefix("www."){raw="https://"+raw}
   if let url=URL(string:raw),["http","https"].contains(url.scheme?.lowercased() ?? ""){result.insert(url.absoluteString)}
  }
  return result.sorted()
 }
 func inspect(guild:String,channel:String,messageID:String,content:String,attachments:[[String:Any]],userID:String="",mentionedUserIDs:[String]=[],referenceMessageID:String?=nil)async{
  guard !attachments.isEmpty else{return}
  guard await shouldAnalyze(channel:channel,mentionedUserIDs:mentionedUserIDs,referenceMessageID:referenceMessageID) else{return}
  let now=Date(),cooldownKey=guild+":"+userID
  if let last=userCooldown[cooldownKey],now.timeIntervalSince(last)<10{return}
  userCooldown[cooldownKey]=now
  if userCooldown.count>10000{userCooldown=userCooldown.filter{now.timeIntervalSince($0.value)<600}}
  let links=urls(in:content);var flags=assess(text:content,urls:links)
  var reports:[String]=[]
  for attachment in attachments.prefix(maxAttachments){
   do{
    let data=try await download(attachment)
    guard let metadata=metadata(data) else{throw KimiError.configuration("Image signature is not supported.")}
    if let width=metadata.width,let height=metadata.height,(width>12000 || height>12000 || width*height>40_000_000){throw KimiError.configuration("Image dimensions exceed the 40-megapixel processing limit.")}
    let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("kimi-image-"+UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:temporary)}
    let file=temporary.appendingPathComponent("image."+metadata.type)
    try data.write(to:file,options:.atomic)
    let sha=sha256(data,file:file.path)
    let ocr=ocrText(file.path)
    let qr=qrValues(file.path)
    let extracted=Array(Set(urls(in:ocr)+qr.flatMap{urls(in:$0)}))
    flags += assess(text:ocr,urls:extracted)
    let hash=perceptualHash(file.path)
    let duplicate=remember(guild:guild,sha:sha,differenceHash:hash,name:attachment["filename"] as? String ?? "image",now:now)
    let name=attachment["filename"] as? String ?? "image"
    var lines=[name+": "+metadata.type.uppercased()+" · "+(metadata.width != nil && metadata.height != nil ? String(metadata.width!)+" × "+String(metadata.height!):"dimensions unavailable")+" · "+String(format:"%.1f",Double(metadata.bytes)/1024)+" KB","SHA-256: "+String(sha.prefix(20))+"…","Duplicate check: "+(duplicate ?? "No match in recent in-memory history.")]
    if !ocr.isEmpty{lines.append("Text detected: "+String(ocr.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).prefix(320)))}
    else{lines.append("Text detection: "+(ImageProcess.resolve("tesseract") != nil ? "No readable text found.":"Unavailable; install Tesseract for OCR."))}
    if !qr.isEmpty{lines.append("QR data: "+String(qr.prefix(3).joined(separator:" | ").prefix(260)))}
    else{lines.append("QR scan: "+(ImageProcess.resolve("zbarimg") != nil ? "No QR code found.":"Unavailable; install ZBar for QR decoding."))}
    if !extracted.isEmpty{lines.append("Links found: "+String(extracted.prefix(4).joined(separator:" | ").prefix(320)))}
    if hash==nil{lines.append("Perceptual duplicate matching unavailable; install ImageMagick.")}
    reports.append(contentsOf:lines)
   }catch{reports.append((attachment["filename"] as? String ?? "image")+": analysis failed: "+error.localizedDescription);await logger.log("WARN","Image analysis failed in guild "+guild+": "+error.localizedDescription)}
  }
  let unique=Array(Set(flags)).sorted()
  let header="**Kimi Lock · Image Check**\n"
  var body=header+reports.joined(separator:"\n")
  if !unique.isEmpty{body+="\nSafety flags: "+unique.joined(separator:"; ")}
  else{body+="\nSafety checks: no known scam wording or obvious suspicious-link pattern detected."}
  body+="\nChecks use optional OCR, QR decoding, metadata and heuristics; this is not AI image understanding or a reliable NSFW/violence classifier. Images are removed from temporary storage after analysis."
  let response=String(body.prefix(1750))
  _ = try? await rest.call("POST","channels/"+channel+"/messages",body:["content":response,"message_reference":["message_id":messageID,"fail_if_not_exists":false],"allowed_mentions":["parse":[]]])
  await logger.log("INFO","Image check completed for message "+messageID+" in guild "+guild)
  let setup=await store.getLegacy("timi_setup",as:[String:[String:String]].self)
  if let log=setup?[guild]?["log_channel_id"],!unique.isEmpty{
   _ = try? await rest.call("POST","channels/"+log+"/messages",body:["content":"Kimi Lock image/link risk in <#"+channel+"> for message "+messageID+": "+unique.joined(separator:"; "),"allowed_mentions":["parse":[]]])
  }
 }
 private func shouldAnalyze(channel:String,mentionedUserIDs:[String],referenceMessageID:String?)async->Bool{
  if botID==nil{botID=(try? await rest.call("GET","users/@me") as? [String:Any])?["id"] as? String}
  if let botID,mentionedUserIDs.contains(botID){return true}
  guard let referenceMessageID,let botID else{return false}
  let referenced=(try? await rest.call("GET","channels/"+channel+"/messages/"+referenceMessageID)) as? [String:Any] ?? [:]
  let author=(referenced["author"] as? [String:Any])?["id"] as? String
  return author==botID
 }
 private func download(_ attachment:[String:Any])async throws->Data{
  guard let raw=attachment["url"] as? String,let url=URL(string:raw),let host=url.host?.lowercased(),url.scheme=="https",trustedHosts.contains(host),url.user==nil,url.password==nil else{throw KimiError.configuration("Image must use an official Discord attachment URL.")}
  if let size=attachment["size"] as? Int,size>maxBytes{throw KimiError.configuration("Image exceeds the 8 MB processing limit.")}
  let delegate=ImageNoRedirectDelegate(),session=URLSession(configuration:.ephemeral,delegate:delegate,delegateQueue:nil)
  defer{session.finishTasksAndInvalidate()}
  var request=URLRequest(url:url);request.timeoutInterval=12
  let (data,response)=try await session.data(for:request)
  guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),let final=response.url,final.host?.lowercased()==host else{throw KimiError.configuration("Discord image download or redirect validation failed.")}
  guard data.count<=maxBytes else{throw KimiError.configuration("Image exceeds the 8 MB processing limit.")}
  let type=(http.value(forHTTPHeaderField:"content-type") ?? "").lowercased()
  guard type.isEmpty || type.hasPrefix("image/") || type=="application/octet-stream" else{throw KimiError.configuration("Attachment response is not an image.")}
  guard signature(data) != nil else{throw KimiError.configuration("Attachment is not a supported image format.")}
  return data
 }
 private func assess(text:String,urls:[String])->[String]{
  let lower=text.lowercased();var flags:[String]=[]
  for term in suspiciousTerms where lower.contains(term){flags.append("Text contains common account-theft or payment-scam wording: "+term)}
  for value in urls{
   guard let url=URL(string:value),let rawHost=url.host?.lowercased() else{continue}
   let host=rawHost.replacingOccurrences(of:"^www\\.",with:"",options:.regularExpression)
   if shorteners.contains(host){flags.append("Link uses URL-shortening service: "+host)}
   if url.scheme != "https"{flags.append("Link does not use HTTPS: "+host)}
   if host.hasPrefix("xn--") || host.split(separator:".").contains(where:{$0.hasPrefix("xn--")}){flags.append("Link uses an internationalized/punycode hostname: "+host)}
   if host.range(of:#"^\d{1,3}(?:\.\d{1,3}){3}$"#,options:.regularExpression) != nil{flags.append("Link uses a raw IP address: "+host)}
   if host.contains("discord-gift") || host.contains("discordnitro") || host.contains("discord-support"){flags.append("Link resembles a Discord impersonation domain: "+host)}
  }
  return Array(Set(flags))
 }
 private func signature(_ data:Data)->String?{
  let b=[UInt8](data);guard b.count>=12 else{return nil}
  if b.count>=8 && Array(b[0..<8])==[137,80,78,71,13,10,26,10]{return "png"}
  if b.count>=3 && b[0]==0xff && b[1]==0xd8 && b[2]==0xff{return "jpeg"}
  if b.count>=6 && (String(bytes:b[0..<6],encoding:.ascii)=="GIF87a" || String(bytes:b[0..<6],encoding:.ascii)=="GIF89a"){return "gif"}
  if b.count>=12 && String(bytes:b[0..<4],encoding:.ascii)=="RIFF" && String(bytes:b[8..<12],encoding:.ascii)=="WEBP"{return "webp"}
  if b.count>=2 && String(bytes:b[0..<2],encoding:.ascii)=="BM"{return "bmp"}
  return nil
 }
 private func metadata(_ data:Data)->Metadata?{
  guard let type=signature(data) else{return nil};let b=[UInt8](data);var width:Int?=nil,height:Int?=nil
  if type=="png",b.count>=24{let w=Int(b[16])<<24|Int(b[17])<<16|Int(b[18])<<8|Int(b[19]);let h=Int(b[20])<<24|Int(b[21])<<16|Int(b[22])<<8|Int(b[23]);width=w;height=h}
  else if type=="gif",b.count>=10{width=Int(b[6])|Int(b[7])<<8;height=Int(b[8])|Int(b[9])<<8}
  else if type=="bmp",b.count>=26{let w=Int(UInt32(b[18])|UInt32(b[19])<<8|UInt32(b[20])<<16|UInt32(b[21])<<24);let h=Int(UInt32(b[22])|UInt32(b[23])<<8|UInt32(b[24])<<16|UInt32(b[25])<<24);width=abs(w);height=abs(h)}
  else if type=="webp",b.count>=30{
   let chunk=String(bytes:b[12..<16],encoding:.ascii) ?? ""
   if chunk=="VP8X"{width=1+(Int(b[24])|Int(b[25])<<8|Int(b[26])<<16);height=1+(Int(b[27])|Int(b[28])<<8|Int(b[29])<<16)}
   else if chunk=="VP8 ",b.count>=30{width=(Int(b[26])|Int(b[27])<<8)&0x3fff;height=(Int(b[28])|Int(b[29])<<8)&0x3fff}
   else if chunk=="VP8L",b.count>=25{let bits=UInt32(b[21])|UInt32(b[22])<<8|UInt32(b[23])<<16|UInt32(b[24])<<24;width=Int(bits&0x3fff)+1;height=Int((bits>>14)&0x3fff)+1}
  }else if type=="jpeg"{
   var offset=2
   while offset+4<b.count{
    if b[offset] != 0xff{offset+=1;continue}
    let marker=b[offset+1];offset+=2
    if marker==0xd8 || marker==0xd9 || marker==0x01 || (marker>=0xd0 && marker<=0xd7){continue}
    let size=Int(b[offset])<<8|Int(b[offset+1])
    if size<2 || offset+size>b.count{break}
    if [0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].contains(marker),size>=7{
     height=Int(b[offset+3])<<8|Int(b[offset+4]);width=Int(b[offset+5])<<8|Int(b[offset+6]);break
    }
    offset+=size
   }
  }
  if let width,let height,width<=0 || height<=0 || width>50000 || height>50000{return Metadata(type:type,width:nil,height:nil,bytes:b.count)}
  return Metadata(type:type,width:width,height:height,bytes:b.count)
 }
 private func sha256(_ data:Data,file:String)->String{
  #if canImport(CryptoKit)
  return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
  #else
  if let output=ImageProcess.first(["sha256sum","shasum"],[file],timeout:3,limit:512),let text=String(data:output,encoding:.utf8),let first=text.split(separator:" ").first{return String(first)}
  return "unavailable"
  #endif
 }
 private func ocrText(_ file:String)->String{
  guard let data=ImageProcess.run("tesseract",[file,"stdout","-l","eng"],timeout:15,limit:128000) else{return ""}
  return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).prefix(6000).description
 }
 private func qrValues(_ file:String)->[String]{
  guard let data=ImageProcess.run("zbarimg",["--quiet","--raw",file],timeout:8,limit:32768) else{return []}
  return String(decoding:data,as:UTF8.self).components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}.prefix(10).map{$0}
 }
 private func perceptualHash(_ file:String)->UInt64?{
  guard let data=ImageProcess.first(["magick","convert"],[file,"-resize","9x8!","-colorspace","Gray","-depth","8","gray:-"],timeout:8,limit:1024),data.count>=72 else{return nil}
  let pixels=[UInt8](data);var hash:UInt64=0
  for y in 0..<8{for x in 0..<8{hash=hash<<1;if pixels[y*9+x]>pixels[y*9+x+1]{hash |= 1}}}
  return hash
 }
 private func remember(guild:String,sha:String,differenceHash:UInt64?,name:String,now:Date)->String?{
  var items=(seen[guild] ?? []).filter{now.timeIntervalSince($0.at)<7*86400}
  let exact=items.first(where:{$0.sha==sha})
  let similar=differenceHash.flatMap{hash in items.first(where:{$0.differenceHash.map{($0 ^ hash).nonzeroBitCount<=5} ?? false})}
  items.append(Seen(sha:sha,differenceHash:differenceHash,name:name,at:now))
  if items.count>500{items.removeFirst(items.count-500)}
  seen[guild]=items
  if seen.count>1000{seen.removeValue(forKey:seen.keys.first ?? guild)}
  if let exact{return "Exact duplicate previously analyzed: "+exact.name}
  if let similar{return "Visually similar image previously analyzed: "+similar.name}
  return nil
 }
}
