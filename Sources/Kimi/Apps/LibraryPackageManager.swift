import Foundation

actor LibraryPackageManager {
 struct Manifest:Codable,Sendable {
  let schema:Int;let id:String;let name:String;let version:String;let kind:String;let system:String;let commands:[String];let files:[String];let permissions:[String]
 }
 struct Installed:Codable,Sendable {let id:String;let name:String;let version:String;let kind:String;let system:String;let commands:[String];let installedAt:Date;let requiresBuild:Bool}
 struct Validation:Sendable {let manifest:Manifest;let fileCount:Int;let unpackedBytes:Int;let warnings:[String]}
 private let store:PersistentStore;private let root:URL
 private let maxArchive=8*1024*1024,maxUnpacked=24*1024*1024,maxFiles=250,maxFile=2*1024*1024
 private let namePattern=#"^[a-z0-9][a-z0-9._-]{1,47}$"#
 private let permissionSet:Set<String>=["read_messages","send_messages","manage_messages","manage_roles","manage_channels","moderate_members"]
 init(store:PersistentStore,directory:URL){self.store=store;root=directory.appendingPathComponent("libraries",isDirectory:true)}
 func validate(manifestData:Data,files:[String:Data],archiveBytes:Int)throws->Validation{
  guard archiveBytes<=maxArchive else{throw KimiError.configuration("Package archive exceeds 8 MB.")}
  let manifest=try JSONDecoder().decode(Manifest.self,from:manifestData)
  guard manifest.schema==1,manifest.id.range(of:namePattern,options:.regularExpression) != nil else{throw KimiError.configuration("Invalid package manifest or ID.")}
  guard ["module","bundle"].contains(manifest.kind) else{throw KimiError.configuration("Package kind must be module or bundle.")}
  guard !manifest.system.trimmingCharacters(in:.whitespaces).isEmpty,manifest.system.count<=80 else{throw KimiError.configuration("A package must define exactly one system.")}
  guard (1...100).contains(manifest.commands.count) else{throw KimiError.configuration("Packages require between 1 and 100 commands.")}
  if manifest.kind=="module" && manifest.commands.count>3{throw KimiError.configuration("A Module can contain at most three commands.")}
  if manifest.kind=="bundle" && manifest.commands.count<=3{throw KimiError.configuration("A Module Bundle must contain more than three commands.")}
  guard Set(manifest.commands).count==manifest.commands.count,manifest.commands.allSatisfy({$0.range(of:#"^[-a-z0-9]{1,32}$"#,options:.regularExpression) != nil}) else{throw KimiError.configuration("Manifest command names are invalid or duplicated.")}
  guard manifest.files.count<=maxFiles,Set(manifest.files).count==manifest.files.count,Set(manifest.files)==Set(files.keys) else{throw KimiError.configuration("Manifest file index does not match package contents.")}
  guard manifest.permissions.allSatisfy({permissionSet.contains($0)}) else{throw KimiError.configuration("Package requests an unsupported permission.")}
  var total=0,warnings:[String]=[]
  for (path,data) in files{
   guard safeRelative(path),data.count<=maxFile else{throw KimiError.configuration("Unsafe path or file exceeds 2 MB: "+path)}
   total+=data.count
   let ext=(path as NSString).pathExtension.lowercased()
   guard ["swift","json","md","txt","png","jpg","jpeg","webp","svg"].contains(ext) else{throw KimiError.configuration("Unsupported package file type: "+path)}
   if ext=="swift"{
    let source=String(data:data,encoding:.utf8) ?? ""
    for token in ["Process(","dlopen(","dlsym(","@_silgen_name","system(","fork(","execve("] where source.contains(token){warnings.append("Review restricted system API in "+path+": "+token)}
   }
  }
  guard total<=maxUnpacked else{throw KimiError.configuration("Unpacked package exceeds 24 MB.")}
  guard files.keys.contains(where:{$0.hasSuffix(".swift")}) else{throw KimiError.configuration("Swift libraries must contain at least one .swift source file.")}
  return Validation(manifest:manifest,fileCount:files.count,unpackedBytes:total,warnings:Array(Set(warnings)).sorted())
 }
 func install(_ validation:Validation,files:[String:Data])async throws->Installed{
  let manifest=validation.manifest
  var packages=await store.get("libraries.installed",as:[String:Installed].self) ?? [:]
  let target=root.appendingPathComponent(manifest.id,isDirectory:true)
  if FileManager.default.fileExists(atPath:target.path){throw KimiError.configuration("This library is already installed.")}
  try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true)
  do{
   for (relative,data) in files{
    guard safeRelative(relative) else{throw KimiError.configuration("Unsafe package path.")}
    let destination=target.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
    try data.write(to:destination,options:.atomic)
   }
   let value=Installed(id:manifest.id,name:manifest.name,version:manifest.version,kind:manifest.kind,system:manifest.system,commands:manifest.commands,installedAt:Date(),requiresBuild:true)
   packages[manifest.id]=value;try await store.set(packages,key:"libraries.installed")
   return value
  }catch{try? FileManager.default.removeItem(at:target);throw error}
 }
 func uninstall(_ id:String)async throws->Bool{
  var packages=await store.get("libraries.installed",as:[String:Installed].self) ?? [:]
  guard packages.removeValue(forKey:id) != nil else{return false}
  try await store.set(packages,key:"libraries.installed")
  let target=root.appendingPathComponent(id,isDirectory:true)
  try? FileManager.default.removeItem(at:target)
  return true
 }
 func installed()async->[Installed]{Array((await store.get("libraries.installed",as:[String:Installed].self) ?? [:]).values).sorted{$0.name<$1.name}}
 private func safeRelative(_ path:String)->Bool{
  guard !path.isEmpty,!path.hasPrefix("/"),!path.contains("\\"),!path.contains("\0") else{return false}
  let components=path.split(separator:"/",omittingEmptySubsequences:false)
  return components.allSatisfy{!$0.isEmpty && $0 != "." && $0 != ".."}
 }
}
