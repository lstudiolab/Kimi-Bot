import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createModuleArchive, downloadModuleArchive, extractModuleArchive, runModuleChecks } from "../src/package-manager.js";

const [action,...args]=process.argv.slice(2);
const fail=message=>{console.error(message);process.exitCode=1;};
try{
  if(action==="pack"){
    const [source,output]=args;
    if(!source||!output)throw new Error("Usage: node scripts/module-package.js pack <package-directory> <output.kmod>");
    const result=createModuleArchive(path.resolve(source),path.resolve(output));
    console.log(JSON.stringify({created:result.file,bytes:result.bytes,sha256:result.sha256,id:result.manifest.id,kind:result.manifest.kind},null,2));
  }else if(action==="check"){
    const [directory]=args;
    if(!directory)throw new Error("Usage: node scripts/module-package.js check <extracted-package-directory>");
    const result=runModuleChecks(path.resolve(directory));
    console.log(JSON.stringify(result,null,2));
    if(!result.passed)process.exitCode=1;
  }else if(action==="unpack"){
    const [archive,destination]=args;
    if(!archive||!destination)throw new Error("Usage: node scripts/module-package.js unpack <file.kmod> <destination>");
    const result=extractModuleArchive(path.resolve(archive),path.resolve(destination));
    console.log(JSON.stringify({installed:destination,id:result.manifest.id,kind:result.manifest.kind,checks:result.checks,findings:result.findings},null,2));
  }else if(action==="download"){
    const [url,destination]=args;
    if(!url||!destination)throw new Error("Usage: node scripts/module-package.js download <https-url> <install-directory>");
    const temporary=fs.mkdtempSync(path.join(os.tmpdir(),"kimi-module-download-"));
    try{
      const archive=path.join(temporary,"package.kmod");
      const downloaded=await downloadModuleArchive(url,archive);
      const installed=extractModuleArchive(archive,path.resolve(destination));
      console.log(JSON.stringify({downloadedBytes:downloaded.bytes,archiveSha256:downloaded.sha256,installed:destination,id:installed.manifest.id,kind:installed.manifest.kind,checks:installed.checks,findings:installed.findings},null,2));
    }finally{fs.rmSync(temporary,{recursive:true,force:true});}
  }else{
    throw new Error("Actions: pack, download, unpack, check");
  }
}catch(error){fail(error.message);}
