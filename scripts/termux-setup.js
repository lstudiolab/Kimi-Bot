import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root=process.cwd();
if(!fs.existsSync(path.join(root,"package.json"))||!fs.existsSync(path.join(root,"src","index.js"))){
  console.error("Run this script from the Kimi-Bot repository root.");
  process.exit(1);
}
const [major,minor]=process.versions.node.split(".").map(Number);
if(major<24||(major===24&&minor<17)){
  console.error("Kimi requires Node.js 24.17.0 or newer. In Termux, run: pkg install nodejs-lts");
  process.exit(1);
}
const envFile=path.join(root,".env");
if(!fs.existsSync(envFile)){
  fs.copyFileSync(path.join(root,".env.example"),envFile);
  fs.chmodSync(envFile,0o600);
  console.log("Created .env from .env.example. Add DISCORD_TOKEN and CLIENT_ID before starting Kimi.");
}else{
  fs.chmodSync(envFile,0o600);
  console.log("Existing .env preserved.");
}
for(const [command,args] of [["npm",["install"]],["npm",["run","check"]],["npm",["test"]]]){
  const result=spawnSync(command,args,{stdio:"inherit",cwd:root});
  if(result.status!==0)process.exit(result.status??1);
}
console.log("\nKimi is ready. Start the bot and dashboard together with: npm start");
console.log("Dashboard (local): http://127.0.0.1:8787");
console.log("Discord OAuth must be configured before the /verify page can authenticate users.");
