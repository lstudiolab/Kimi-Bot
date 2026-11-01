import { LIBRARIES, normalizeLibraryName } from "./libraries/index.js";
export class LibraryManager{
  constructor(store,logger){this.store=store;this.logger=logger;}
  list(){return Object.values(LIBRARIES);}
  get(name){const key=normalizeLibraryName(name);return key?LIBRARIES[key]||Object.values(LIBRARIES).find(value=>value.name===key)||null:null;}
  installed(guildId,name){const canonical=normalizeLibraryName(name);return Boolean(canonical&&(this.store.data.installed_libraries[guildId]||[]).includes(canonical));}
  install(guildId,name){
    const library=this.get(name);
    if(!library)return {ok:false,error:"Library not found. Use /libraries to see available libraries."};
    const canonical=normalizeLibraryName(name),installed=this.store.data.installed_libraries[guildId]||=[];
    if(installed.includes(canonical))return {ok:false,error:`${library.name} is already installed in this server.`};
    installed.push(canonical);this.store.save();
    this.logger.info(`Installed ${library.name} for guild ${guildId}.`);
    return {ok:true,library};
  }
  uninstall(guildId,name){
    const library=this.get(name);
    if(!library)return {ok:false,error:"Library not found. Use /libraries to see available libraries."};
    const canonical=normalizeLibraryName(name),installed=this.store.data.installed_libraries[guildId]||[];
    if(!installed.includes(canonical))return {ok:false,error:`${library.name} is not installed in this server.`};
    this.store.data.installed_libraries[guildId]=installed.filter(value=>value!==canonical);
    this.store.save();
    this.logger.info(`Uninstalled ${library.name} for guild ${guildId}; saved data was preserved.`);
    return {ok:true,library};
  }
}
