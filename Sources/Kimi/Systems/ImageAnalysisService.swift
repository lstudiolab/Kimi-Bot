import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor ImageAnalysisService {
 struct Metadata:Sendable {let type:String;let width:Int?;let height:Int?;let bytes:Int}
 struct Report:Sendable {let metadata:Metadata?;let flags:[String];let urls:[String]}
 private let store:PersistentStore;private let rest:DiscordREST;private let logger:Logger
 private let maxBytes=8*1024*1024
 private let trustedHosts:Set<String>=["cdn.discordapp.com","media.discordapp.net"]
 private let shorteners:Set<String>=["bit.ly","tinyurl.com","t.co","is.gd","cutt.ly","rb.gy","rebrand.ly","shorturl.at"]
 private let suspicious:[String]=["verify your account","verify your wallet","claim your prize","urgent action required","send the otp","verification code","seed phrase","recovery phrase","connect your wallet","account will be suspended","free nitro","gift card code"]
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
 func inspect(guild:String,channel:String,messageID:String,content:String,attachments:[[String:Any]])async{
  let links=urls(in:content);var flags:[String]=[]
  let lower=content.lowercased()
  for term in suspicious where lower.contains(term){flags.append("Message contains common account-theft or payment-scam wording: "+term)}
  for link in links{
   guard let url=URL(string:link),let host=url.host?.lowercased().replacingOccurrences(of:"^www\\.",with:"",options:.regularExpression) else{continue}
   if shorteners.contains(host){flags.append("Link uses URL-shortening service: "+host)}
   if url.scheme != "https"{flags.append("Link does not use HTTPS: "+host)}
   if host.hasPrefix("xn--") || host.split(separator:".").contains(where:{$0.hasPrefix("xn--")}){flags.append("Link uses an internationalized/punycode hostname: "+host)}
   if host.range(of:#"^\d{1,3}(?:\.\d{1,3}){3}$"#,options:.regularExpression) != nil{flags.append("Link uses a raw IP address: "+host)}
   if host.contains("discord-gift") || host.contains("discordnitro") || host.contains("discord-support"){flags.append("Link resembles a Discord impersonation domain: "+host)}
  }
  var imageCount=0
  var extractedText=""
  for item in attachments.prefix(3){
   guard let raw=item["url"] as? String,let url=URL(string:raw),let host=url.host?.lowercased(),trustedHosts.contains(host) else{continue}
   let declared=Int(item["size"] as? Int ?? 0)
   if declared>maxBytes{flags.append("Image attachment exceeds the 8 MB analysis limit.");continue}
   let type=(item["content_type"] as? String ?? "").lowercased()
   let name=(item["filename"] as? String ?? "").lowercased()
   guard type.hasPrefix("image/") || [".png",".jpg",".jpeg",".gif",".webp",".bmp"].contains(where:{name.hasSuffix($0)}) else{continue}
   do{
    var request=URLRequest(url:url);request.timeoutInterval=10
    let (data,response)=try await URLSession.shared.data(for:request)
    guard data.count<=maxBytes,let final=response.url,let finalHost=final.host?.lowercased(),trustedHosts.contains(finalHost) else{throw KimiError.configuration("Attachment redirect or size check failed.")}
    guard let metadata=metadata(data) else{flags.append("Attachment did not contain a recognized image signature.");continue}
    imageCount += 1
    if metadata.width==nil || metadata.height==nil{flags.append("Image dimensions could not be verified.")}
    let ext=metadata.type=="jpeg" ? "jpg":metadata.type
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"."+ext)
    do{
     try data.write(to:temp,options:.atomic)
     extractedText += "\n"+(await runOptionalTool(["/data/data/com.termux/files/usr/bin/tesseract","/usr/bin/tesseract","/usr/local/bin/tesseract"],[temp.path,"stdout","-l","eng"]) ?? "")
     extractedText += "\n"+(await runOptionalTool(["/data/data/com.termux/files/usr/bin/zbarimg","/usr/bin/zbarimg","/usr/local/bin/zbarimg"],["--quiet","--raw",temp.path]) ?? "")
     try? FileManager.default.removeItem(at:temp)
    }catch{await logger.log("WARN","Image OCR preparation failed: "+error.localizedDescription)}
   }catch{await logger.log("WARN","Image inspection failed for message "+messageID+": "+error.localizedDescription)}
  }
  for term in suspicious where extractedText.localizedCaseInsensitiveContains(term){flags.append("Image OCR or QR data contains suspicious wording: "+term)}
  for link in urls(in:extractedText){
   guard let url=URL(string:link),let host=url.host?.lowercased() else{continue}
   if shorteners.contains(host){flags.append("Image QR/OCR link uses a URL shortener: "+host)}
   if url.scheme != "https"{flags.append("Image QR/OCR link is not HTTPS: "+host)}
  }
  let unique=Array(Set(flags)).sorted()
  guard !unique.isEmpty else{return}
  await logger.log("WARN","Kimi Lock image/link risk in guild "+guild+", message "+messageID+": "+unique.joined(separator:"; "))
  let setup=await store.getLegacy("timi_setup",as:[String:[String:String]].self)
  if let log=setup?[guild]?["log_channel_id"]{
   let report="**Kimi Lock · Link and image inspection**\nMessage: https://discord.com/channels/"+guild+"/"+channel+"/"+messageID+"\nImages inspected: "+String(imageCount)+"\n"+unique.map{"• "+$0}.joined(separator:"\n")
   _ = try? await rest.call("POST","channels/"+log+"/messages",body:["content":String(report.prefix(1900)),"allowed_mentions":["parse":[]]])
  }
 }
 private func runOptionalTool(_ paths:[String],_ arguments:[String])async->String?{
  await Task.detached(priority:.utility){
   for path in paths where FileManager.default.isExecutableFile(atPath:path){
    let process=Process(),pipe=Pipe()
    process.executableURL=URL(fileURLWithPath:path);process.arguments=arguments;process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
    do{try process.run()}catch{continue}
    let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
    if process.terminationStatus==0{return String(data:data.prefix(16000),encoding:.utf8)}
   }
   return nil
  }.value
 }

 private func metadata(_ data:Data)->Metadata?{
  let b=[UInt8](data);guard b.count>=12 else{return nil}
  if b.count>=24 && Array(b[0..<8])==[137,80,78,71,13,10,26,10]{
   let w=Int(b[16])<<24|Int(b[17])<<16|Int(b[18])<<8|Int(b[19]);let h=Int(b[20])<<24|Int(b[21])<<16|Int(b[22])<<8|Int(b[23])
   return Metadata(type:"png",width:w>0 ? w:nil,height:h>0 ? h:nil,bytes:b.count)
  }
  if b.count>=10 && (String(bytes:b[0..<6],encoding:.ascii)=="GIF87a" || String(bytes:b[0..<6],encoding:.ascii)=="GIF89a"){
   let w=Int(b[6])|Int(b[7])<<8,h=Int(b[8])|Int(b[9])<<8
   return Metadata(type:"gif",width:w,height:h,bytes:b.count)
  }
  if b.count>=26 && String(bytes:b[0..<2],encoding:.ascii)=="BM"{
   let w=Int(UInt32(b[18])|UInt32(b[19])<<8|UInt32(b[20])<<16|UInt32(b[21])<<24)
   let h=Int(UInt32(b[22])|UInt32(b[23])<<8|UInt32(b[24])<<16|UInt32(b[25])<<24)
   return Metadata(type:"bmp",width:abs(w),height:abs(h),bytes:b.count)
  }
  if b.count>=3 && b[0]==0xff && b[1]==0xd8 && b[2]==0xff{return Metadata(type:"jpeg",width:nil,height:nil,bytes:b.count)}
  if b.count>=30 && String(bytes:b[0..<4],encoding:.ascii)=="RIFF" && String(bytes:b[8..<12],encoding:.ascii)=="WEBP"{
   let chunk=String(bytes:b[12..<16],encoding:.ascii) ?? ""
   if chunk=="VP8X"{let w=1+(Int(b[24]) | (Int(b[25]) << 8) | (Int(b[26]) << 16));let h=1+(Int(b[27]) | (Int(b[28]) << 8) | (Int(b[29]) << 16));return Metadata(type:"webp",width:w,height:h,bytes:b.count)}
   return Metadata(type:"webp",width:nil,height:nil,bytes:b.count)
  }
  return nil
 }
}
