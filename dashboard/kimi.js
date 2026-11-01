(() => {
"use strict";
const $=s=>document.querySelector(s);
const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const catalog=[
{id:"welcome",name:"Welcome & Goodbye",version:"1.0.0",category:"Community",description:"Join and leave messages, automatic roles and member onboarding.",language:"Cling",builtin:true},
{id:"roles",name:"Role Picker",version:"1.0.0",category:"Community",description:"Self-service role panels, buttons and select menus.",language:"Cling",builtin:true},
{id:"security",name:"Moderation & Security",version:"1.0.0",category:"Protection",description:"AutoMod, verification, anti-raid, anti-nuke and recovery tools.",language:"Rust",builtin:true},
{id:"tickets",name:"Ticket System",version:"1.0.0",category:"Support",description:"Private support channels, staff access and transcripts.",language:"Cling",builtin:true},
{id:"embeds",name:"Embed Builder",version:"1.0.0",category:"Utilities",description:"Create, save and publish reusable Discord embeds.",language:"Cling",builtin:true},
{id:"developer",name:"Developer Kit",version:"1.0.0",category:"Developer",description:"Cling projects, templates, validation and module tools.",language:"Cling",builtin:true},
{id:"audit",name:"Server Audit",version:"1.0.0",category:"Protection",description:"Review risky permissions and server configuration.",language:"Rust",builtin:false},
{id:"automations",name:"Automations",version:"1.0.0",category:"Utilities",description:"Build event-based server workflows with Cling.",language:"Cling",builtin:false},
{id:"backups",name:"Backup Manager",version:"1.0.0",category:"Utilities",description:"Manage bounded configuration and message snapshots.",language:"Rust",builtin:false}
];
const KEY="kimi-dashboard",defaults={installed:["welcome","roles","security","tickets","embeds","developer"],language:"Cling",locale:"en-US",apiUrl:"",serverName:"Your server"};
let state;try{state={...defaults,...JSON.parse(localStorage.getItem(KEY)||"{}")}}catch{state={...defaults}}
const save=()=>localStorage.setItem(KEY,JSON.stringify(state));
const names={modules:"Module manager","module-library":"Module library",logs:"Activity logs",language:"Language & runtime",connection:"Bot connection"};
const toast=m=>{const r=$("#toast-region");if(!r)return;const n=document.createElement("div");n.className="toast";n.textContent=m;r.append(n);setTimeout(()=>n.remove(),3000)};
function moduleCard(m,installed){
return '<article class="kimi-module-card"><div class="kimi-module-top"><span class="kimi-module-icon">'+esc(m.name.slice(0,1))+'</span><span class="kimi-tag">'+esc(m.category)+'</span></div><div class="kimi-module-title">'+esc(m.name)+'</div><p>'+esc(m.description)+'</p><div class="kimi-module-meta"><span>v'+esc(m.version)+'</span><span>'+esc(m.language)+'</span>'+(m.builtin?'<span>Core</span>':'')+'</div><div class="kimi-module-actions">'+(installed?'<span class="kimi-installed"><i></i> Installed</span><button class="button secondary small" data-kimi-action="uninstall" data-module="'+m.id+'">Uninstall</button>':'<button class="button small" data-kimi-action="install" data-module="'+m.id+'">Install module</button>')+'<button class="button secondary small" data-kimi-action="download" data-module="'+m.id+'">Download</button></div></article>';
}
function shell(page,body,eyebrow){
const intro={modules:"Manage the modules installed in your Kimi bot.","module-library":"Browse available modules and add capabilities to your bot.",language:"Choose the language used to build and configure bot modules.",connection:"Connect this dashboard to the Kimi process running in Termux."};
$("#page-content").innerHTML='<div class="page-heading"><div><div class="eyebrow">'+(eyebrow||"Kimi control")+'</div><h1>'+names[page]+'</h1><p>'+intro[page]+'</p></div></div>'+body;
document.querySelectorAll(".nav-item").forEach(a=>a.classList.toggle("active",a.dataset.page===page));
if($("#crumb-current"))$("#crumb-current").textContent=names[page];
if($("#server-name"))$("#server-name").textContent=state.serverName||"Your server";
}
function renderModules(page){
const installed=state.installed||[],list=catalog.filter(m=>page==="modules"?installed.includes(m.id):!installed.includes(m.id));
const body='<div class="kimi-summary-row"><div><strong>'+installed.length+' installed</strong><small>Module state saved in this browser preview</small></div><a class="button secondary small" href="#module-library">Browse library</a></div><div class="kimi-module-grid">'+(list.length?list.map(m=>moduleCard(m,installed.includes(m.id))).join(""):'<div class="card kimi-empty"><strong>No modules here</strong><p>All available modules are installed.</p></div>')+'</div><div class="notice info kimi-footnote">Module actions currently update the dashboard preview and export package manifests. Installing or removing code from the live Rust bot requires the authenticated Kimi API bridge.</div>';
shell(page,body,page==="modules"?"Installed modules":"Module catalogue");
}
function renderLanguage(){
const body='<div class="grid section-grid"><div><section class="card"><div class="card-header"><div><h2 class="card-title">Module language</h2><div class="card-subtitle">Choose how custom bot features are authored.</div></div></div><div class="field"><label for="kimi-language">Preferred language</label><select id="kimi-language"><option value="Cling" '+(state.language==="Cling"?"selected":"")+'>Cling — recommended</option><option value="Rust" '+(state.language==="Rust"?"selected":"")+'>Rust — native extensions</option><option value="JSON" '+(state.language==="JSON"?"selected":"")+'>JSON — configuration only</option></select><small class="field-help">This preference applies to new modules and project templates.</small></div><div class="field"><label for="kimi-locale">Dashboard language</label><select id="kimi-locale"><option value="en-US" '+(state.locale==="en-US"?"selected":"")+'>English (US)</option><option value="en-GB" '+(state.locale==="en-GB"?"selected":"")+'>English (UK)</option><option value="fil" '+(state.locale==="fil"?"selected":"")+'>Filipino</option></select></div><button class="button" data-kimi-action="save-language">Save preferences</button></section><section class="card"><h2 class="card-title">Runtime</h2><div class="kimi-runtime"><span class="kimi-runtime-mark">R</span><div><strong>Rust</strong><small>Kimi core bot runtime</small></div><span class="kimi-tag">Fixed</span></div><p class="empty-note">The bot core remains Rust. Changing the module language does not convert or rebuild the running bot. Rust extensions require a rebuild; Cling modules require Kimi&#39;s module engine.</p></section></div><div><section class="card"><h2 class="card-title">Language guide</h2><div class="kimi-language-option"><strong>Cling</strong><p>Readable, restricted syntax for panels, commands, events and bot workflows.</p><span class="kimi-tag">Recommended for modules</span></div><div class="divider"></div><div class="kimi-language-option"><strong>Rust</strong><p>Native performance and direct access to supported bot internals. Requires compilation and restart.</p></div><div class="divider"></div><div class="kimi-language-option"><strong>JSON</strong><p>Declarative settings and data files. Does not execute custom logic.</p></div></section></div></div>';
shell("language",body,"Preferences");
}
function renderConnection(){
const body='<div class="grid section-grid"><div><section class="card"><div class="card-header"><div><h2 class="card-title">Local bot connection</h2><div class="card-subtitle">Connect the dashboard to Kimi running on your device.</div></div><span class="status off">Not connected</span></div><div class="notice info">The frontend is hosted separately from your Termux bot. A secure API bridge must be implemented in Kimi before settings can be synchronized.</div><div class="field"><label for="kimi-server-name">Server label</label><input id="kimi-server-name" value="'+esc(state.serverName)+'" placeholder="My Discord server"></div><div class="field"><label for="kimi-api-url">Bot API address</label><input id="kimi-api-url" type="url" value="'+esc(state.apiUrl)+'" placeholder="http://127.0.0.1:8787"><small class="field-help">Use the HTTPS address of your secure tunnel when accessing the dashboard outside your phone.</small></div><button class="button" data-kimi-action="save-connection">Save connection details</button></section></div><div><section class="card"><h2 class="card-title">Connection requirements</h2><div class="system-list"><div class="system-row"><div class="system-copy"><strong>Authenticated API</strong><small>Owner identity and per-server authorization</small></div><span class="status off">Required</span></div><div class="system-row"><div class="system-copy"><strong>HTTPS transport</strong><small>Encrypted dashboard-to-bot requests</small></div><span class="status off">Required</span></div><div class="system-row"><div class="system-copy"><strong>Module manager endpoints</strong><small>Install, remove, list and export modules</small></div><span class="status off">Pending</span></div></div></section></div></div>';
shell("connection",body,"System");
}

function readLogs(){try{return JSON.parse(localStorage.getItem("kimi-dashboard-logs")||"[]")}catch{return []}}
function addLog(level,source,message){
const rows=readLogs();rows.unshift({id:Date.now()+"-"+Math.random().toString(16).slice(2,7),time:new Date().toISOString(),level,source,message});
localStorage.setItem("kimi-dashboard-logs",JSON.stringify(rows.slice(0,500)));
}
function renderLogs(){
const rows=readLogs();
const body='<div class="kimi-log-toolbar"><div class="kimi-log-filters"><input id="kimi-log-search" type="search" placeholder="Search logs..."><select id="kimi-log-level"><option value="all">All levels</option><option value="error">Error</option><option value="warn">Warning</option><option value="info">Info</option></select><select id="kimi-log-source"><option value="all">All sources</option><option value="dashboard">Dashboard</option><option value="modules">Modules</option><option value="settings">Settings</option><option value="bot">Bot</option></select></div><div class="kimi-log-actions"><button class="button secondary small" data-kimi-action="refresh-logs">Refresh</button><button class="button secondary small" data-kimi-action="export-logs">Export</button><button class="button secondary small" data-kimi-action="clear-logs">Clear</button></div></div><div class="kimi-log-summary"><span><strong>'+rows.length+'</strong> stored events</span><span>Newest first · maximum 500 dashboard events</span></div><div class="card kimi-log-card"><div class="kimi-log-table-wrap"><table class="kimi-log-table"><thead><tr><th>Time</th><th>Level</th><th>Source</th><th>Event</th></tr></thead><tbody id="kimi-log-rows">'+(rows.length?rows.map(logRow).join(""):'<tr><td colspan="4" class="kimi-log-empty">No dashboard events yet. Changes made in this dashboard will appear here.</td></tr>')+'</tbody></table></div></div><div class="notice info kimi-footnote">These are dashboard activity logs stored in this browser. Live Discord events, moderation actions and Rust process output will appear here after the authenticated bot logs API is connected.</div>';
shell("logs",body,"Monitoring");
}
function logRow(row){
const d=new Date(row.time),stamp=isNaN(d.getTime())?row.time:d.toLocaleString();
return '<tr><td class="kimi-log-time">'+esc(stamp)+'</td><td><span class="kimi-log-level '+esc(row.level)+'">'+esc(row.level.toUpperCase())+'</span></td><td>'+esc(row.source)+'</td><td class="kimi-log-message">'+esc(row.message)+'</td></tr>';
}
function filterLogs(){
const q=($("#kimi-log-search")?.value||"").toLowerCase(),level=$("#kimi-log-level")?.value||"all",source=$("#kimi-log-source")?.value||"all";
const rows=readLogs().filter(r=>(level==="all"||r.level===level)&&(source==="all"||r.source===source)&&(!q||(r.message+" "+r.source+" "+r.level).toLowerCase().includes(q)));
$("#kimi-log-rows").innerHTML=rows.length?rows.map(logRow).join(""):'<tr><td colspan="4" class="kimi-log-empty">No matching events.</td></tr>';
}

function render(){const p=location.hash.slice(1);if(p==="modules"||p==="module-library")renderModules(p);else if(p==="logs")renderLogs();else if(p==="language")renderLanguage();else if(p==="connection")renderConnection()}
document.addEventListener("click",e=>{
const b=e.target.closest("[data-kimi-action]");if(!b)return;const a=b.dataset.kimiAction,id=b.dataset.module;
if(a==="install"||a==="uninstall"){const m=catalog.find(x=>x.id===id);if(!m)return;if(a==="uninstall"&&id==="security"){toast("The security core cannot be removed from the dashboard.");return}state.installed=state.installed||[];state.installed=a==="install"?Array.from(new Set([...state.installed,id])):state.installed.filter(x=>x!==id);save();addLog("info","modules",(a==="install"?"Installed ":"Uninstalled ")+m.name+" (dashboard preview)");renderModules(location.hash.slice(1));toast(a==="install"?"Added to dashboard preview.":"Removed from dashboard preview.");return}
if(a==="download"){const m=catalog.find(x=>x.id===id);if(!m)return;const manifest={format:"kimi-module",schemaVersion:1,id:m.id,name:m.name,version:m.version,language:m.language,description:m.description,entrypoint:"module.cling",note:"Manifest template only. Executable module source is not included."};const blob=new Blob([JSON.stringify(manifest,null,2)],{type:"application/json"});const url=URL.createObjectURL(blob),link=document.createElement("a");link.href=url;link.download=m.id+".kimi-module.json";link.click();URL.revokeObjectURL(url);addLog("info","modules","Downloaded manifest for "+m.name);toast("Module manifest downloaded.");return}
if(a==="refresh-logs"){renderLogs();toast("Dashboard logs refreshed.");return}
if(a==="export-logs"){const blob=new Blob([JSON.stringify(readLogs(),null,2)],{type:"application/json"}),url=URL.createObjectURL(blob),link=document.createElement("a");link.href=url;link.download="kimi-dashboard-logs.json";link.click();URL.revokeObjectURL(url);return}
if(a==="clear-logs"){if(!confirm("Clear all locally stored dashboard logs?"))return;localStorage.removeItem("kimi-dashboard-logs");renderLogs();toast("Dashboard logs cleared.");return}
if(a==="save-language"){state.language=$("#kimi-language").value;state.locale=$("#kimi-locale").value;save();addLog("info","settings","Updated language preferences: "+state.language+", "+state.locale);toast("Language preferences saved in this browser.");return}
if(a==="save-connection"){state.serverName=$("#kimi-server-name").value.trim()||"Your server";state.apiUrl=$("#kimi-api-url").value.trim();save();addLog("info","settings","Updated bot connection details (stored locally)");toast("Connection details saved locally. Bot is not connected yet.");return}
});
document.addEventListener("input",e=>{if(e.target.id==="kimi-log-search")filterLogs()});
document.addEventListener("change",e=>{if(e.target.id==="kimi-log-level"||e.target.id==="kimi-log-source")filterLogs()});
window.addEventListener("hashchange",render);render();
})();