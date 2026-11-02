import { PLUGINS, normalizePluginName } from "./plugins/index.js";
export class PluginManager{
  constructor(store,logger){this.store=store;this.logger=logger;}
  list(){return Object.values(PLUGINS);}
  get(name){const key=normalizePluginName(name);return key?PLUGINS[key]||Object.values(PLUGINS).find(value=>value.name===key)||null:null;}
  installed(guildId,name){const canonical=normalizePluginName(name);return Boolean(canonical&&(this.store.data.installed_plugins[guildId]||[]).includes(canonical));}
  install(guildId,name){
    const plugin=this.get(name);
    if(!plugin)return {ok:false,error:"App not found. Use /apps to see available apps."};
    const canonical=normalizePluginName(name),installed=this.store.data.installed_plugins[guildId]||=[];
    if(installed.includes(canonical))return {ok:false,error:`${plugin.name} is already added to this server.`};
    installed.push(canonical);this.store.save();
    this.logger.info(`Added ${plugin.name} app for guild ${guildId}.`);
    return {ok:true,plugin};
  }
  uninstall(guildId,name){
    const plugin=this.get(name);
    if(!plugin)return {ok:false,error:"App not found. Use /apps to see available apps."};
    const canonical=normalizePluginName(name),installed=this.store.data.installed_plugins[guildId]||[];
    if(!installed.includes(canonical))return {ok:false,error:`${plugin.name} is not added to this server.`};
    this.store.data.installed_plugins[guildId]=installed.filter(value=>value!==canonical);
    this.store.save();
    this.logger.info(`Removed ${plugin.name} app for guild ${guildId}; saved data was preserved.`);
    return {ok:true,plugin};
  }
}
